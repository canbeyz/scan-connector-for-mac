// SPDX-License-Identifier: MIT
import Foundation
import SwiftUI
import AppKit
import PDFKit
import ServiceManagement
import ImageIO

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let model = AppModel()
    private(set) var window: NSWindow?
    var statusItem: NSStatusItem!
    func settingsWindow(rememberFrame: Bool = true) -> NSWindow {
        if let window { return window }
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:940,height:800),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        // The menu-bar receiver outlives a closed window. Keep ownership in Swift.
        window.isReleasedWhenClosed = false
        window.title = "Scan Connector for Mac"; window.minSize = NSSize(width:880,height:650)
        window.contentView = NSHostingView(rootView:RootView(model:model)); window.delegate = self
        window.center()
        if rememberFrame { window.setFrameAutosaveName("MacNativeScanMainWindow") }
        self.window = window
        return window
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenus()
        _ = settingsWindow()
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName:"scanner",accessibilityDescription:"Scan Connector for Mac")
        let menu = NSMenu(); menu.delegate = self; statusItem.menu = menu
        let launchedAtLogin = NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword:0x6c676974)?.booleanValue ?? false
        if !launchedAtLogin || model.settings.printerHost.isEmpty { showWindow() }
        model.launch()
    }
    func configureMenus() {
        let bar = NSMenu(); let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle:"About Scan Connector for Mac",action:#selector(NSApplication.orderFrontStandardAboutPanel(_:)),keyEquivalent:"")
        appMenu.addItem(.separator()); appMenu.addItem(withTitle:"Quit Scan Connector for Mac",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        appItem.submenu = appMenu; bar.addItem(appItem)
        let fileItem = NSMenuItem(); let fileMenu = NSMenu(title:"File")
        let open = NSMenuItem(title:"Open Scan Folder",action:#selector(openFolder),keyEquivalent:"o"); open.target = self; fileMenu.addItem(open)
        let scan = NSMenuItem(title:"Scan Now",action:#selector(scanNow),keyEquivalent:"s"); scan.target = self; fileMenu.addItem(scan)
        fileItem.submenu = fileMenu; bar.addItem(fileItem)
        let editItem = NSMenuItem(); let editMenu = NSMenu(title:"Edit")
        for (title,selector,key) in [("Undo",Selector(("undo:")),"z"),("Cut",#selector(NSText.cut(_:)),"x"),("Copy",#selector(NSText.copy(_:)),"c"),("Paste",#selector(NSText.paste(_:)),"v"),("Select All",#selector(NSText.selectAll(_:)),"a")] { editMenu.addItem(withTitle:title,action:selector,keyEquivalent:key) }
        editItem.submenu = editMenu; bar.addItem(editItem); NSApp.mainMenu = bar
    }
    func menuWillOpen(_ menu:NSMenu) {
        menu.removeAllItems(); let status = menu.addItem(withTitle:model.statusTitle,action:nil,keyEquivalent:""); status.isEnabled = false
        menu.addItem(.separator())
        for (title,action) in [("Open Settings",#selector(showWindow)),("Open Scan Folder",#selector(openFolder)),(model.registered ? "Pause Receiving" : "Start Receiving",#selector(toggleReception))] {
            let item = menu.addItem(withTitle:title,action:action,keyEquivalent:""); item.target = self
        }
        menu.addItem(.separator()); menu.addItem(withTitle:"Quit",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
    }
    @objc func showWindow() { settingsWindow().makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true) }
    @objc func openFolder() { model.showFolder() }
    @objc func scanNow() { model.performScan() }
    @objc func toggleReception() { if model.registered { model.pauseReceiving() } else { model.startReceiving() } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool) -> Bool { showWindow(); return true }
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply {
        if model.scanning {
            let alert = NSAlert(); alert.messageText = "A scan is in progress. Quit anyway?"; alert.informativeText = "Quitting will cancel this scan."; alert.addButton(withTitle:"Keep Scanning"); alert.addButton(withTitle:"Quit")
            if alert.runModal() == .alertFirstButtonReturn { return .terminateCancel }
            model.cancelScan()
            Task { @MainActor in
                while model.scanning { try? await Task.sleep(nanoseconds:100_000_000) }
                model.shutdown(); NSApp.reply(toApplicationShouldTerminate:true)
            }
            return .terminateLater
        }
        model.shutdown(); return .terminateNow
    }
}

func argument(_ key:String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of:key), i+1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i+1]
}

func requiredHost() -> String {
    guard let host = argument("--host"), !host.isEmpty else {
        fputs("This diagnostic command requires --host <printer IP or hostname>.\n",stderr)
        exit(2)
    }
    return host
}

@main @MainActor struct AppEntry {
static func main() {
let arguments = CommandLine.arguments
if arguments.contains("--window-lifecycle-test") {
    let app=NSApplication.shared;app.setActivationPolicy(.accessory)
    let owner=AppDelegate()
    weak var original=owner.settingsWindow(rememberFrame:false)
    original?.setFrameOrigin(NSPoint(x:-100000,y:-100000))
    guard let frame=original?.frame, NSScreen.screens.allSatisfy({ !$0.frame.intersects(frame) }) else {
        fputs("Could not position the regression window offscreen.\n",stderr);exit(1)
    }
    for _ in 0..<50 {
        autoreleasepool {
            let window=owner.settingsWindow(rememberFrame:false)
            window.orderFront(nil); window.close()
        }
        RunLoop.current.run(until:Date().addingTimeInterval(0.01))
        guard let retained=original, owner.settingsWindow(rememberFrame:false) === retained,
              retained.title == "Scan Connector for Mac", retained.contentView != nil else {
            fputs("Window lifetime regression failed after close.\n",stderr);exit(1)
        }
    }
    original=nil
    print("PASS: 50 offscreen close/reuse cycles preserve the settings window");exit(0)
} else if arguments.contains("--enable-auto-reception") {
    do {
        var settings=AppSettings.load();settings.automaticReception=true;settings.prepareForLaunch();try settings.save()
        if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
        print("Automatic reception: enabled. Login item status: \(SMAppService.mainApp.status.rawValue)")
        exit(SMAppService.mainApp.status == .enabled ? 0 : 2)
    } catch { fputs("\(error.localizedDescription)\n",stderr);exit(1) }
} else if arguments.contains("--appearance-test") {
    do {
        guard let input=argument("--input"),let output=argument("--output"),
              let source=CGImageSourceCreateWithURL(URL(fileURLWithPath:input) as CFURL,nil),
              let image=CGImageSourceCreateImageAtIndex(source,0,nil) else { throw ScanFailure.message("--input image and --output PNG are required") }
        let mode=ScanColorMode(rawValue:argument("--mode") ?? "color") ?? .color
        let appearance=ScanAppearance(mode:mode,enhance:!arguments.contains("--original"),density:Int(argument("--density") ?? "0") ?? 0,contrast:Int(argument("--contrast") ?? "0") ?? 0)
        let result=try ScanImageProcessor.process(image,appearance:appearance)
        guard let destination=CGImageDestinationCreateWithURL(URL(fileURLWithPath:output) as CFURL,"public.png" as CFString,1,nil) else { throw ScanFailure.message("Cannot create preview") }
        CGImageDestinationAddImage(destination,result,nil)
        guard CGImageDestinationFinalize(destination) else { throw ScanFailure.message("Cannot write preview") }
        print("Rendered \(mode.title), \(result.bitsPerComponent) bits/component");exit(0)
    } catch { fputs("\(error.localizedDescription)\n",stderr);exit(1) }
} else
if arguments.contains("--self-test") {
    do { try CoreTests.run(); exit(0) } catch { fputs("\(error.localizedDescription)\n",stderr); exit(1) }
} else if arguments.contains("--diagnose") {
    let host = requiredHost()
    Task.detached {
        do {
            let ip = try resolveIPv4(host); let client = PrinterClient(ip:ip,pin:"")
            let info = try await client.info(); let pin = try await client.readCertificate()
            let object:[String:Any] = ["ip":ip,"model":info.model,"uuid":info.uuid,"state":info.state,"adfLoaded":info.adfLoaded,"certificate":pin]
            let data = try JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys]); print(String(decoding:data,as:UTF8.self)); exit(0)
        } catch { fputs("\(error.localizedDescription)\n",stderr); exit(1) }
    }; dispatchMain()
} else if arguments.contains("--discover") {
    let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
    let discovery = PrinterDiscovery(); discovery.start()
    Timer.scheduledTimer(withTimeInterval:8,repeats:false) { _ in
        Task { @MainActor in
            for printer in discovery.printers { print("\(printer.name)\t\(printer.host)") }
            exit(discovery.printers.isEmpty ? 1 : 0)
        }
    }
    RunLoop.current.run()
} else if arguments.contains("--scan-test") {
    do {
        let ip = try resolveIPv4(requiredHost())
        let folder = URL(fileURLWithPath:argument("--output") ?? NSHomeDirectory()+"/Scans/Scan Connector",isDirectory:true)
        let dpi = Int(argument("--dpi") ?? "100") ?? 100
        let appearance=ScanAppearance(mode:ScanColorMode(rawValue:argument("--mode") ?? "color") ?? .color,enhance:!arguments.contains("--original"))
        let result = try DirectScanner.scan(ip:ip,output:folder,dpi:dpi,adf:false,appearance:appearance,cancellation:Cancellation()) { count in print("Received \(count) page(s)") }
        guard let doc = PDFDocument(url:result.url),doc.pageCount == result.pages else { throw ScanFailure.message("PDF verification failed") }
        print("Saved: \(result.url.path)"); exit(0)
    } catch { fputs("\(error.localizedDescription)\n",stderr); exit(1) }
} else if arguments.contains("--register-test") {
    let host = requiredHost()
    Task.detached {
        do {
            let ip = try resolveIPv4(host); let probe = PrinterClient(ip:ip,pin:""); let pin = try await probe.readCertificate()
            let client = PrinterClient(ip:ip,pin:pin)
            try await client.register(name:argument("--name") ?? "Native App Test",localIP:localIPv4(for:ip),port:54926,duration:60)
            print("Destination registration accepted"); exit(0)
        } catch { fputs("\(error.localizedDescription)\n",stderr); exit(1) }
    }; dispatchMain()
} else if arguments.contains("--button-scan-test") {
    let host = requiredHost()
    let name = argument("--name") ?? "Native App Test"
    let folder = URL(fileURLWithPath:argument("--output") ?? NSHomeDirectory()+"/Scans/Scan Connector",isDirectory:true)
    Task.detached {
        do {
            let ip = try resolveIPv4(host); let local = try localIPv4(for:ip)
            let probe = PrinterClient(ip:ip,pin:""); let pin = try await probe.readCertificate()
            let client = PrinterClient(ip:ip,pin:pin); let events = EventTestState()
            let receiver = try ButtonReceiver(localIP:local,printerIP:ip,name:name,port:54926,callback:{ _ in
                events.received(); guard events.events == 1 else { return }
                Task.detached {
                    do {
                        try await Task.sleep(nanoseconds:1_200_000_000)
                        let state = try await client.statusValues()
                        let result = try DirectScanner.scan(ip:ip,output:folder,dpi:300,adf:state["AdfState"] == "ScannerAdfLoaded",cancellation:Cancellation()) { pages in print("Received \(pages) page(s)"); fflush(stdout) }
                        print("Panel scan saved: \(result.url.path)"); fflush(stdout); exit(0)
                    } catch { fputs("\(error.localizedDescription)\n",stderr); exit(1) }
                }
            },failure:{ text in fputs("\(text)\n",stderr); exit(1) })
            receiver.start()
            try await client.register(name:name,localIP:local,port:receiver.port,duration:360)
            print("Ready for panel scan: \(name)"); fflush(stdout)
            while true {
                try await Task.sleep(nanoseconds:60_000_000_000)
                if events.events == 0 { try await client.register(name:name,localIP:local,port:receiver.port,duration:360) }
            }
        } catch { fputs("\(error.localizedDescription)\n",stderr); exit(1) }
    }; dispatchMain()
} else if arguments.contains("--render-preview") {
    let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
    let model = AppModel(); model.model = "Brother MFC-L2820DW"; model.ip = "192.0.2.50"; model.connected = true; model.registered = true
    model.settings.displayName = "Office Mac"; model.settings.printerHost = "BRW-printer.local"; model.settings.printerName = model.model
    model.stateText = "On the printer, choose Scan → to File → Office Mac."
    let view = NSHostingView(rootView:RootView(model:model).environment(\.colorScheme,.light))
    view.frame = NSRect(x:0,y:0,width:940,height:Double(argument("--height") ?? "800") ?? 800)
    let window = NSWindow(contentRect:view.frame,styleMask:[.borderless],backing:.buffered,defer:false)
    window.contentView = view; view.layoutSubtreeIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) else { fatalError("Preview failed") }
    view.cacheDisplay(in:view.bounds,to:bitmap)
    let output = argument("--output") ?? "/tmp/mac-native-scan-preview.png"
    do { try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:output)); print(output); exit(0) }
    catch { fputs("\(error.localizedDescription)\n",stderr); exit(1) }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate(); app.delegate = delegate; app.setActivationPolicy(.regular)
    withExtendedLifetime(delegate) { app.run() }
}
}
}
