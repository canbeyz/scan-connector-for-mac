// SPDX-License-Identifier: MIT
import Foundation
import AppKit
import ServiceManagement

@MainActor final class AppModel: ObservableObject {
    @Published var settings = AppSettings.load()
    @Published var connected = false
    @Published var registered = false
    @Published var connecting = false
    @Published var applying = false
    @Published var registering = false
    @Published var manualAddressExpanded = false
    @Published var scanning = false
    @Published var ip = ""
    @Published var model = "No printer connected"
    @Published var stateText = "Select a printer to get started."
    @Published var errorText = ""
    @Published var lastScan: URL?
    @Published var lastScanText = "No scans yet"
    @Published var pagesReceived = 0
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    let discovery = PrinterDiscovery()
    private var client: PrinterClient?
    private var receiver: ButtonReceiver?
    private var timer: Timer?
    private var lastRegistration = Date.distantPast
    private var scanCancellation: Cancellation?
    private var scanTask: Task<Void,Never>?
    private var healthBusy = false
    private var generation = 0
    private var workspaceObservers: [NSObjectProtocol] = []
    var statusTitle: String {
        if scanning { return "Scanning" }
        if connecting || applying || registering { return "Connecting" }
        if registered { return "Ready to receive" }
        if connected { return "Printer connected" }
        return "Not connected"
    }
    var canReceive: Bool { settings.nameIsValid && !settings.printerHost.isEmpty && !connecting && !applying && !registering && !scanning }
    func launch() {
        settings.prepareForLaunch(); save()
        discovery.start()
        if !settings.printerHost.isEmpty { Task { await connect(startReceiving: settings.receiveEnabled) } }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in Task { @MainActor in await self?.healthCheck() } }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in self?.suspendForSleep() }
        })
        workspaceObservers.append(center.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds:2_000_000_000)
                await self?.healthCheck()
            }
        })
    }
    func suspendForSleep() {
        generation += 1; receiver?.stop(); receiver = nil; registered = false; connected = false
        connecting = false
        scanCancellation?.cancel(); stateText = "Mac is asleep. Connection resumes after wake."
    }
    func save() { do { try settings.save() } catch { showError("Could not save settings: \(error.localizedDescription)") } }
    func showError(_ text: String) { errorText = text }
    func choose(_ printer: FoundPrinter) {
        if settings.printerHost != printer.host { disconnectForSelectionChange() }
        settings.printerHost = printer.host; settings.printerName = printer.name
        save()
    }
    func connect(startReceiving: Bool = false) async {
        guard !connecting && !scanning else { return }
        guard settings.nameIsValid else { showError(AppSettings.displayNameGuidance); return }
        let host = settings.printerHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty && !host.contains("/") && !host.contains(":") else { showError("Enter the printer IP address or local hostname."); return }
        generation += 1; let current = generation
        connecting = true; errorText = ""; stateText = "Checking printer connection…"
        let hadReceiver = receiver != nil
        receiver?.stop(); receiver = nil; registered = false
        if hadReceiver { try? await Task.sleep(nanoseconds:1_100_000_000) }
        do {
            // Socket lookup stays off the main thread.
            let resolved = try await Task.detached { try resolveIPv4(host) }.value
            let pin = settings.certificatePin
            let probe = PrinterClient(ip: resolved, pin: pin)
            let info = try await probe.info()
            guard info.model.contains("MFC-L2820DW") else { throw ScanFailure.message("This version supports MFC-L2820DW. Detected \(info.model).") }
            try await Task.detached { try DirectScanner.checkConnection(ip:resolved) }.value
            let observed = try await probe.readCertificate()
            guard current == generation else { return }
            if !settings.printerUUID.isEmpty && settings.printerUUID != info.uuid { throw ScanFailure.message("The printer at this address has changed. Select the device again.") }
            settings.printerHost = host; settings.printerName = info.model; settings.printerUUID = info.uuid; settings.certificatePin = observed
            ip = resolved; model = info.model; connected = true
            client = PrinterClient(ip: resolved, pin: observed); save()
            stateText = info.state == "Idle" ? "Scan channel connected" : "Printer status: \(info.state)"
            if startReceiving { try await beginReceiving() }
        } catch {
            guard current == generation else { return }
            connected = false; registered = false; client = nil
            errorText = friendly(error); stateText = "Check printer power, Wi-Fi, and local network permission."
        }
        if current == generation { connecting = false }
    }
    func beginReceiving() async throws {
        guard !registering else { return }
        guard settings.nameIsValid, let client else { throw ScanFailure.message("Connect the printer and enter a valid destination name first.") }
        registering = true; defer { registering = false }
        let current = generation
        guard current == generation else { return }
        let local = try localIPv4(for: ip)
        if receiver == nil {
            let newReceiver = try ButtonReceiver(localIP: local, printerIP: ip, name: settings.displayName,
                callback: { [weak self] _ in Task { @MainActor in guard let self, self.generation == current, self.registered else { return }; self.performScan(fromPanel:true) } },
                failure: { [weak self] error in Task { @MainActor in
                    guard let self, self.generation == current else { return }
                    self.receiver?.stop(); self.receiver=nil; self.registered=false; self.errorText=error
                    self.stateText="Receiver interrupted. Reconnecting automatically."
                } })
            receiver = newReceiver; newReceiver.start()
        }
        do { try await client.register(name: settings.displayName, localIP: local, port: 54925) }
        catch { receiver?.stop(); receiver = nil; throw error }
        guard current == generation else { receiver?.stop(); receiver = nil; return }
        registered = true; lastRegistration = Date(); settings.receiveEnabled = true; save()
        stateText = "On the printer, choose Scan → to File → \(settings.displayName)."
    }
    func startReceiving() {
        guard !applying && !connecting && !registering && !scanning else { return }
        settings.receiveEnabled = true; save()
        Task { if connected { do { try await beginReceiving(); errorText = "" } catch { showError(friendly(error)) } } else { await connect(startReceiving: true) } }
    }
    func pauseReceiving() {
        generation += 1; receiver?.stop(); receiver = nil; registered = false
        settings.receiveEnabled = false; save(); stateText = "Paused for this session. Auto receive applies next time the app opens."
    }
    func applySettings() {
        guard !applying && !connecting && !registering && !scanning else { return }
        applying = true
        let wasReceiving = settings.receiveEnabled
        save(); Task {
            receiver?.stop(); receiver = nil; registered = false
            // Wait for the old UDP read to finish and release its port.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await connect(startReceiving: wasReceiving)
            applying = false
        }
    }
    func changePrinterHost(_ host: String) {
        if settings.printerHost != host { disconnectForSelectionChange(); settings.printerName = "" }
        settings.printerHost = host
    }
    func disconnectForSelectionChange() {
        generation += 1; settings.certificatePin = ""; settings.printerUUID = ""
        connecting = false
        receiver?.stop(); receiver = nil; registered = false; connected = false; client = nil
        ip = ""; model = "No printer connected"; stateText = "Click Connect to verify this printer."
    }
    func forgetPrinter() {
        disconnectForSelectionChange(); settings.printerHost = ""; settings.printerName = ""; settings.receiveEnabled = false; errorText = ""; save()
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false; panel.prompt = "Choose Scan Folder"
        panel.directoryURL = URL(fileURLWithPath: settings.outputPath, isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url { settings.outputPath = url.path; save() }
    }
    func showFolder() {
        let url = URL(fileURLWithPath:settings.outputPath,isDirectory:true)
        do { try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true); NSWorkspace.shared.open(url) }
        catch { showError("Could not open the scan folder: \(error.localizedDescription)") }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval { showError("Allow Scan Connector for Mac in System Settings → General → Login Items.") }
        } catch { showError("Could not change login settings: \(error.localizedDescription)") }
    }
    func performScan(fromPanel: Bool = false) {
        guard connected && !scanning, let client else { return }
        scanning = true; errorText = ""; pagesReceived = 0; stateText = "Preparing to scan…"
        let currentSettings = settings; let targetIP = ip; let cancellation = Cancellation(); scanCancellation = cancellation
        scanTask = Task {
            do {
                if fromPanel { try await Task.sleep(nanoseconds: 1_200_000_000) }
                let status = try await client.statusValues()
                let adf = currentSettings.source == "adf" || (currentSettings.source == "auto" && status["AdfState"] == "ScannerAdfLoaded")
                let output = URL(fileURLWithPath: currentSettings.outputPath, isDirectory: true)
                let stateOwner = self
                let result = try await Task.detached(priority: .userInitiated) {
                    try DirectScanner.scan(ip: targetIP, output: output, dpi: currentSettings.dpi, adf: adf, appearance:currentSettings.appearance, cancellation: cancellation) { count in
                        Task { @MainActor in stateOwner.pagesReceived = count; stateOwner.stateText = "Received \(pageSummary(count)). Saving PDF…" }
                    }
                }.value
                lastScan = result.url; lastScanText = "\(pageSummary(result.pages)) · \(Date().formatted(date: .omitted, time: .shortened))"
                stateText = "Saved \(pageSummary(result.pages)) to PDF"
            } catch {
                errorText = cancellation.isCancelled ? "" : friendly(error)
                stateText = cancellation.isCancelled ? "Scan canceled" : "Scan did not finish"
            }
            scanning = false; scanCancellation = nil; scanTask = nil
        }
    }
    func cancelScan() { scanCancellation?.cancel(); stateText = "Canceling scan…" }
    func healthCheck() async {
        guard !connecting && !applying && !registering && !scanning && !healthBusy && !settings.printerHost.isEmpty else { return }
        healthBusy = true; defer { healthBusy = false }
        if !connected { await connect(startReceiving: settings.receiveEnabled); return }
        do {
            let newIP = try await Task.detached { [host = settings.printerHost] in try resolveIPv4(host) }.value
            let interfaceMatches: Bool
            if let receiver { interfaceMatches = try localIPv4(for:ip) == receiver.localIP } else { interfaceMatches = true }
            guard newIP == ip && interfaceMatches else { await connect(startReceiving: settings.receiveEnabled); return }
            guard let client else { return }
            _ = try await client.statusValues()
            if settings.receiveEnabled && (receiver == nil || Date().timeIntervalSince(lastRegistration) > 200) {
                if let receiver {
                    try await client.register(name:receiver.name,localIP:receiver.localIP,port:receiver.port)
                    lastRegistration = Date()
                } else { try await beginReceiving() }
            }
        } catch {
            receiver?.stop(); receiver = nil; connected = false; registered = false
            stateText = "Connection lost. Waiting to reconnect."; errorText = friendly(error)
        }
    }
    func shutdown() {
        timer?.invalidate(); receiver?.stop(); scanCancellation?.cancel()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; workspaceObservers.removeAll()
    }
    func friendly(_ error: Error) -> String {
        if let failure = error as? ScanFailure { return failure.localizedDescription }
        if let urlError = error as? URLError {
            if [.serverCertificateUntrusted, .cancelled, .secureConnectionFailed].contains(urlError.code) && !settings.certificatePin.isEmpty { return "The certificate did not match, or the connection was rejected. Verify the selected printer." }
            if urlError.code == .notConnectedToInternet || urlError.code == .cannotConnectToHost || urlError.code == .timedOut { return "Cannot connect. Use the same local network and allow local network access for the app." }
        }
        return error.localizedDescription
    }
}
