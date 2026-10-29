// SPDX-License-Identifier: MIT
import Foundation
import Darwin

final class ButtonReceiver: @unchecked Sendable {
    private let lock = NSLock()
    private var running = true
    private var descriptor: Int32 = -1
    private let queue = DispatchQueue(label: "local.mac-native-scan.buttons", qos: .utility)
    let localIP: String
    let printerIP: String
    let name: String
    private(set) var port: UInt16
    let callback: @Sendable (ScanButtonEvent) -> Void
    let failure: @Sendable (String) -> Void
    init(localIP: String, printerIP: String, name: String, port: UInt16 = 54925, callback: @escaping @Sendable (ScanButtonEvent) -> Void, failure: @escaping @Sendable (String) -> Void) throws {
        self.localIP = localIP; self.printerIP = printerIP; self.name = name; self.port = port; self.callback = callback; self.failure = failure
        descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { throw ScanFailure.message("Could not start the scan receiver.") }
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET); address.sin_port = port.bigEndian
        inet_pton(AF_INET, localIP, &address.sin_addr)
        let result = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard result == 0 else { close(descriptor); descriptor = -1; throw ScanFailure.message("Another scan service is using the receiving port. Stop that service and reconnect.") }
        if port == 0 {
            var bound = sockaddr_in(); var size = socklen_t(MemoryLayout<sockaddr_in>.size)
            withUnsafeMutablePointer(to:&bound) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) { _ = getsockname(descriptor,$0,&size) } }
            self.port = UInt16(bigEndian:bound.sin_port)
        }
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }
    deinit { stop() }
    func start() { queue.async { [self] in receiveLoop() } }
    func stop() { lock.lock(); running = false; lock.unlock() }
    private var shouldRun: Bool { lock.lock(); defer { lock.unlock() }; return running }
    private func receiveLoop() {
        let fd = descriptor
        defer { close(fd); lock.lock(); descriptor = -1; lock.unlock() }
        var seen: [String:Date] = [:]
        while shouldRun {
            var bytes = [UInt8](repeating: 0, count: 4097)
            var peer = sockaddr_in(); var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &peer) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &bytes, bytes.count, 0, $0, &length) } }
            if count < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR { continue }
                failure("The receiver connection was interrupted. Reconnect the printer."); break
            }
            var address = peer.sin_addr; var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &address, &text, socklen_t(INET_ADDRSTRLEN))
            guard String(cString: text) == printerIP else { continue }
            let data = Data(bytes.prefix(count))
            guard let event = ScanButtonEvent.parse(data, expectedName: name, expectedHost: "\(localIP):\(port)") else { continue }
            _ = data.withUnsafeBytes { raw in withUnsafePointer(to: &peer) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(fd, raw.baseAddress, data.count, 0, $0, length) } } }
            let now = Date(); seen = seen.filter { $0.value > now }
            let key = "\(event.registration)/\(event.sequence)/\(event.function)"
            guard seen[key] == nil else { continue }
            seen[key] = now.addingTimeInterval(120); callback(event)
        }
    }
}

struct FoundPrinter: Identifiable, Equatable {
    var id: String { host }
    let name: String
    let host: String
}

@MainActor final class PrinterDiscovery: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    @Published var printers: [FoundPrinter] = []
    @Published var searching = false
    private var browsers: [NetServiceBrowser] = []
    private var services: [NetService] = []
    func start() {
        browsers.forEach { $0.stop() }; browsers.removeAll(); services.forEach { $0.stop() }; services.removeAll()
        printers.removeAll(); searching = true
        for type in ["_uscan._tcp.", "_uscans._tcp."] {
            let browser = NetServiceBrowser(); browser.delegate = self; browsers.append(browser)
            browser.searchForServices(ofType: type, inDomain: "local.")
        }
        DispatchQueue.main.asyncAfter(deadline: .now()+7) { [weak self] in self?.searching = false }
    }
    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        Task { @MainActor in
            guard service.name.lowercased().contains("brother") else { return }
            services.append(service); service.delegate = self; service.resolve(withTimeout: 5)
        }
    }
    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        Task { @MainActor in
            guard let host = sender.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")) else { return }
            let found = FoundPrinter(name: sender.name, host: host)
            if !printers.contains(where: { $0.host == host }) { printers.append(found) }
            searching = false
        }
    }
    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String:NSNumber]) {
        Task { @MainActor in searching = false }
    }
}
