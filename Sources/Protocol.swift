// SPDX-License-Identifier: MIT
import Foundation
import CryptoKit
import Security
import Darwin
import CoreGraphics
import ImageIO

enum ScanFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

func pageSummary(_ count: Int) -> String { "\(count) \(count == 1 ? "page" : "pages")" }

struct AppSettings: Codable, Equatable {
    // Use the conservative Scan-to-PC display-name limit documented by Brother.
    static let maxDisplayNameLength = 15
    static let displayNameGuidance = "Use 1–15 ASCII letters, digits, spaces, hyphens, or underscores, with no leading or trailing spaces."
    var printerHost = ""
    var printerName = ""
    var printerUUID = ""
    var certificatePin = ""
    var displayName = AppSettings.defaultName()
    var outputPath = NSHomeDirectory() + "/Scans/Scan Connector"
    var dpi = 300
    var source = "auto"
    var receiveEnabled = false
    var automaticReception = true
    var colorMode = ScanColorMode.color
    var documentEnhancement = true
    var density = 0
    var contrast = 0
    var textThreshold = 180
    init() {}
    enum CodingKeys: String, CodingKey {
        case printerHost, printerName, printerUUID, certificatePin, displayName, outputPath, dpi, source, receiveEnabled
        case automaticReception, colorMode, documentEnhancement, density, contrast, textThreshold
    }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        printerHost = try c.decodeIfPresent(String.self, forKey: .printerHost) ?? printerHost
        printerName = try c.decodeIfPresent(String.self, forKey: .printerName) ?? printerName
        printerUUID = try c.decodeIfPresent(String.self, forKey: .printerUUID) ?? printerUUID
        certificatePin = try c.decodeIfPresent(String.self, forKey: .certificatePin) ?? certificatePin
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? displayName
        outputPath = try c.decodeIfPresent(String.self, forKey: .outputPath) ?? outputPath
        dpi = try c.decodeIfPresent(Int.self, forKey: .dpi) ?? dpi
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? source
        receiveEnabled = try c.decodeIfPresent(Bool.self, forKey: .receiveEnabled) ?? receiveEnabled
        automaticReception = try c.decodeIfPresent(Bool.self, forKey: .automaticReception) ?? automaticReception
        colorMode = try c.decodeIfPresent(ScanColorMode.self, forKey: .colorMode) ?? colorMode
        documentEnhancement = try c.decodeIfPresent(Bool.self, forKey: .documentEnhancement) ?? documentEnhancement
        density = min(50, max(-50, try c.decodeIfPresent(Int.self, forKey: .density) ?? density))
        contrast = min(50, max(-50, try c.decodeIfPresent(Int.self, forKey: .contrast) ?? contrast))
        textThreshold = min(240, max(64, try c.decodeIfPresent(Int.self, forKey: .textThreshold) ?? textThreshold))
    }
    var appearance: ScanAppearance { ScanAppearance(mode:colorMode,enhance:documentEnhancement,density:density,contrast:contrast,textThreshold:textThreshold) }
    mutating func prepareForLaunch() { receiveEnabled = automaticReception && !printerHost.isEmpty }
    static func defaultName() -> String {
        let name = Host.current().localizedName ?? "Mac Native"
        let ascii = name.applyingTransform(.toLatin, reverse: false)?.applyingTransform(.stripDiacritics, reverse: false) ?? name
        let clean = ascii.map { $0.isASCII && ($0.isLetter || $0.isNumber || " _-".contains($0)) ? $0 : "-" }
        let shortName = String(String(clean).prefix(maxDisplayNameLength)).trimmingCharacters(in: .whitespaces)
        return shortName.isEmpty ? "Mac Native" : shortName
    }
    static func isValidDisplayName(_ name: String) -> Bool {
        !name.isEmpty && name == name.trimmingCharacters(in: .whitespaces) && name.utf8.count <= maxDisplayNameLength &&
        name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || " _-".contains($0)) }
    }
    var nameIsValid: Bool { Self.isValidDisplayName(displayName) }
    static var storageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mac Native Scan", isDirectory: true).appendingPathComponent("Settings.json")
    }
    static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: storageURL), let value = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return value
    }
    func save() throws {
        try FileManager.default.createDirectory(at: Self.storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Self.storageURL, options: .atomic)
    }
}

struct PrinterInfo: Equatable {
    let model: String
    let uuid: String
    let state: String
    let adfLoaded: Bool
}

final class XMLValues: NSObject, XMLParserDelegate {
    private var current = ""
    private var buffer = ""
    private(set) var values: [String: String] = [:]
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        current = elementName.components(separatedBy: ":").last ?? elementName; buffer = ""
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { buffer += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let key = elementName.components(separatedBy: ":").last ?? elementName
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if key == current && !value.isEmpty { values[key] = value }
        buffer = ""
    }
    static func parse(_ data: Data) throws -> [String: String] {
        let delegate = XMLValues(); let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false; parser.delegate = delegate
        guard parser.parse() else { throw ScanFailure.message("The printer returned an unreadable status. Try reconnecting.") }
        return delegate.values
    }
}

func resolveIPv4(_ host: String) throws -> String {
    var hints = addrinfo(); hints.ai_family = AF_INET; hints.ai_socktype = SOCK_STREAM
    var list: UnsafeMutablePointer<addrinfo>?
    let result = getaddrinfo(host, nil, &hints, &list)
    guard result == 0, let first = list else { throw ScanFailure.message("Printer not found. Check Wi-Fi or enter the printer IP address.") }
    defer { freeaddrinfo(list) }
    var address = first.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
    var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
    guard inet_ntop(AF_INET, &address, &text, socklen_t(INET_ADDRSTRLEN)) != nil else { throw ScanFailure.message("Could not read the printer address.") }
    return String(cString: text)
}

func localIPv4(for printerIP: String) throws -> String {
    let fd = socket(AF_INET, SOCK_DGRAM, 0)
    guard fd >= 0 else { throw ScanFailure.message("Could not create a local network connection.") }
    defer { close(fd) }
    var destination = sockaddr_in(); destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    destination.sin_family = sa_family_t(AF_INET); destination.sin_port = UInt16(443).bigEndian
    inet_pton(AF_INET, printerIP, &destination.sin_addr)
    let status = withUnsafePointer(to: &destination) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    guard status == 0 else { throw ScanFailure.message("Cannot connect to the printer's local network.") }
    var local = sockaddr_in(); var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let result = withUnsafeMutablePointer(to: &local) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
    guard result == 0 else { throw ScanFailure.message("Could not read this Mac's local network address.") }
    var address = local.sin_addr; var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
    inet_ntop(AF_INET, &address, &text, socklen_t(INET_ADDRSTRLEN))
    return String(cString: text)
}

final class PinnedDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    let host: String
    let expectedPin: String
    private let lock = NSLock()
    private var observed = ""
    var fingerprint: String { lock.lock(); defer { lock.unlock() }; return observed }
    init(host: String, pin: String) { self.host = host; self.expectedPin = pin }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        guard space.host == host else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        if space.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = space.serverTrust {
            guard let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let certificate = certificates.first else { completionHandler(.cancelAuthenticationChallenge, nil); return }
            let data = SecCertificateCopyData(certificate) as Data
            let pin = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard expectedPin.isEmpty || pin == expectedPin else { completionHandler(.cancelAuthenticationChallenge, nil); return }
            lock.lock(); observed = pin; lock.unlock()
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else { completionHandler(.performDefaultHandling, nil) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            urlSession(session, didReceive: challenge, completionHandler: completionHandler); return
        }
        if challenge.protectionSpace.host == host && challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPDigest && challenge.previousFailureCount == 0 && task.originalRequest?.url?.path == "/phoenix/mib" && !expectedPin.isEmpty {
            completionHandler(.useCredential, URLCredential(user: "Public", password: "0000", persistence: .forSession))
        } else { completionHandler(.cancelAuthenticationChallenge, nil) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class PrinterClient: @unchecked Sendable {
    let ip: String
    let delegate: PinnedDelegate
    let session: URLSession
    init(ip: String, pin: String) {
        self.ip = ip; delegate = PinnedDelegate(host: ip, pin: pin)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 7; config.timeoutIntervalForResource = 12
        config.httpShouldSetCookies = false; config.urlCache = nil
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    func request(_ path: String, secure: Bool = false, method: String = "GET", body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: "\(secure ? "https" : "http")://\(ip)\(path)") else { throw ScanFailure.message("The printer address is invalid.") }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ScanFailure.message("The printer did not return a valid response.") }
        return (data, http)
    }
    func info() async throws -> PrinterInfo {
        let (caps, capsResponse) = try await request("/eSCL/ScannerCapabilities")
        guard capsResponse.statusCode == 200 else { throw ScanFailure.message("This device does not provide a scan interface.") }
        let values = try XMLValues.parse(caps)
        let status = try await statusValues()
        return PrinterInfo(model: values["MakeAndModel"] ?? "Brother", uuid: values["UUID"] ?? "", state: status["State"] ?? "Unknown", adfLoaded: status["AdfState"] == "ScannerAdfLoaded")
    }
    func statusValues() async throws -> [String: String] {
        let (data, response) = try await request("/eSCL/ScannerStatus")
        guard response.statusCode == 200 else { throw ScanFailure.message("Could not read scan status (\(response.statusCode)).") }
        return try XMLValues.parse(data)
    }
    func readCertificate() async throws -> String {
        let (_, response) = try await request("/eSCL/ScannerStatus", secure: true)
        guard response.statusCode == 200 && delegate.fingerprint.count == 64 else { throw ScanFailure.message("Could not verify this printer's certificate.") }
        return delegate.fingerprint
    }
    func register(name: String, localIP: String, port: UInt16, duration: Int = 360) async throws {
        guard AppSettings.isValidDisplayName(name) else { throw ScanFailure.message(AppSettings.displayNameGuidance) }
        guard !delegate.expectedPin.isEmpty else { throw ScanFailure.message("Connect and verify the printer first.") }
        let entries = [("FILE",5),("IMAGE",1)].map { function, appnum in
            ["key": "1.3.6.1.4.1.2435.2.3.9.2.11.1.1.0", "string_value": "TYPE=BR;BUTTON=SCAN;DURATION=\(duration);CC=1;HOST=\(localIP):\(port);USER=\"\(name)\";FUNC=\(function);APPNUM=\(appnum);"]
        }
        let body = try JSONSerialization.data(withJSONObject: ["request":entries])
        let (data, response) = try await request("/phoenix/mib", secure: true, method: "POST", body: body)
        guard response.statusCode == 200 else { throw ScanFailure.message("Destination registration failed (\(response.statusCode)). Reconnect the printer.") }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String:Any], let rows = root["response"] as? [[String:Any]], rows.count == 2, rows.allSatisfy({ ($0["status"] as? Int) == 0 }) else { throw ScanFailure.message("The printer rejected this destination name. Try another name.") }
    }
}

struct ScanButtonEvent: Equatable {
    let function: String
    let sequence: String
    let registration: String
    static func parse(_ data: Data, expectedName: String, expectedHost: String) -> ScanButtonEvent? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 && bytes.count <= 4096 && bytes[0] == 2 && bytes[3] == 0x30, let text = String(data: data.dropFirst(4), encoding: .ascii) else { return nil }
        var fields: [String:String] = [:]
        for part in text.split(separator: ";") { let items = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false); if items.count == 2 { fields[String(items[0])] = String(items[1]) } }
        guard fields["TYPE"] == "BR", fields["BUTTON"] == "SCAN", fields["HOST"] == expectedHost, fields["USER"]?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) == expectedName,
              let function = fields["FUNC"], let expectedApp = ["FILE":"5","IMAGE":"1"][function], expectedApp == fields["APPNUM"], let sequence = fields["SEQ"], !sequence.isEmpty else { return nil }
        return ScanButtonEvent(function: function, sequence: sequence, registration: fields["REGID"] ?? "")
    }
}

final class TCPStream: @unchecked Sendable {
    private var fd: Int32 = -1
    init(ip: String, port: UInt16) throws {
        fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ScanFailure.message("Could not create the scan connection.") }
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET); address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, ip, &address.sin_addr) == 1 else { close(fd); fd = -1; throw ScanFailure.message("The printer IP address is invalid.") }
        let flags = fcntl(fd, F_GETFL); _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        let result = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        if result < 0 {
            var item = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            guard errno == EINPROGRESS && poll(&item, 1, 5000) > 0 else { close(fd); fd = -1; throw ScanFailure.message("The scan connection timed out. Check that the printer is on.") }
            var error: Int32 = 0; var size = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size)
            guard error == 0 else { close(fd); fd = -1; throw ScanFailure.message("The scan channel is temporarily unavailable.") }
        }
        _ = fcntl(fd, F_SETFL, flags)
        var timeout = timeval(tv_sec: 65, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var yes: Int32 = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, 4)
    }
    deinit { if fd >= 0 { close(fd) } }
    func interrupt() { if fd >= 0 { _ = Darwin.shutdown(fd,SHUT_RDWR) } }
    func read(_ count: Int) throws -> Data {
        guard count >= 0 && count <= 16_777_216 else { throw ScanFailure.message("The printer returned an invalid data length.") }
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { raw in
            var done = 0
            while done < count {
                let result = recv(fd, raw.baseAddress!.advanced(by: done), count-done, 0)
                if result < 0 && errno == EINTR { continue }
                guard result > 0 else { throw ScanFailure.message("The scan connection was interrupted. Cancel the job on the printer and try again.") }
                done += result
            }
        }
        return data
    }
    func write(_ data: Data) throws {
        try data.withUnsafeBytes { raw in
            var done = 0
            while done < data.count {
                let count = send(fd, raw.baseAddress!.advanced(by: done), data.count-done, 0)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw ScanFailure.message("Could not send the scan request.") }; done += count
            }
        }
    }
}

extension Data {
    func uint16LE(_ offset: Int) -> UInt16 { UInt16(self[offset]) | (UInt16(self[offset+1]) << 8) }
    func uint32LE(_ offset: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(self[offset+$1]) << UInt32(8*$1) } }
}

enum ScanWire {
    static func settings(dpi: Int, adf: Bool) -> Data {
        let lines = ["OS=MAC","PSRC=\(adf ? "ADF" : "FB")","RESO=\(dpi),\(dpi)","CLR=C24BIT","AREA=FULL","MRGN=0,0,0,0","DPLX=OFF","BRIT=50","CONT=50","COMP=JPEG","JSF=420","IPRC=NORMAL","PTYPE=NORMAL","PAGE=0","LONG=OFF","CARR=OFF","RMGC=OFF","DTDF=OFF","DT4V=OFF","DSKW=OFF","LSMD=OFF","RMBP=OFF","RMMR=OFF","GMMA=OFF","TONE=OFF","QTFD=OFF","ATCN=OFF","ATCRP=OFF"]
        return Data((["\u{1b}SSP"] + lines).joined(separator: "\n").utf8) + Data([10,128])
    }
    static func validateFrame(_ header: Data) throws -> (status: UInt8, kind: UInt16) {
        guard header.count == 6, header[0] == 0, header.uint16LE(2) == 1 else { throw ScanFailure.message("Unsupported scan response. Verify that the printer is an MFC-L2820DW.") }
        return (header[1], header.uint16LE(4))
    }
}

final class Cancellation: @unchecked Sendable {
    private let lock = NSLock(); private var value = false
    private var handler: (@Sendable () -> Void)?
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func onCancel(_ action: (@Sendable () -> Void)?) { lock.lock(); handler = action; let cancelled = value; lock.unlock(); if cancelled { action?() } }
    func cancel() { lock.lock(); value = true; let action = handler; lock.unlock(); action?() }
}

struct ScanResult { let url: URL; let pages: Int }

enum DirectScanner {
    static func checkConnection(ip: String) throws {
        let socket = try TCPStream(ip:ip,port:54921)
        guard try socket.read(9) == Data("+OK 200\r\n".utf8) else { throw ScanFailure.message("The scan channel is not ready. Finish other scan jobs on the printer.") }
        try socket.write(Data([27,81,10,128]))
        guard try socket.read(75).first == 0xc1 else { throw ScanFailure.message("Could not verify the scan channel. Reconnect the printer.") }
    }
    static func scan(ip: String, output: URL, dpi: Int, adf: Bool, appearance: ScanAppearance = ScanAppearance(), cancellation: Cancellation, progress: @escaping @Sendable (Int) -> Void) throws -> ScanResult {
        guard [100,200,300,600].contains(dpi) else { throw ScanFailure.message("This scan resolution is not supported.") }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        guard FileManager.default.isWritableFile(atPath: output.path) else { throw ScanFailure.message("The output folder is not writable. Choose another folder.") }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let suffix = String(UUID().uuidString.prefix(6))
        let destination = output.appendingPathComponent("Scan_\(stamp)_\(suffix).pdf")
        let temporary = output.appendingPathComponent(".Scan_\(suffix).partial.pdf")
        var published = false
        defer { if !published { try? FileManager.default.removeItem(at: temporary) } }
        guard let consumer = CGDataConsumer(url: temporary as CFURL), let pdf = CGContext(consumer: consumer, mediaBox: nil, [kCGPDFContextTitle: "Scanned document"] as CFDictionary) else { throw ScanFailure.message("Could not create the PDF file.") }
        var pdfClosed = false
        defer { if !pdfClosed { pdf.closePDF() } }
        let socket = try TCPStream(ip: ip, port: 54921)
        cancellation.onCancel { socket.interrupt() }
        defer { cancellation.onCancel(nil) }
        guard try socket.read(9) == Data("+OK 200\r\n".utf8) else { throw ScanFailure.message("The scan channel is not ready. Another scan may be in progress.") }
        // The legacy capability query initializes the MFC-L2820DW scan channel.
        try socket.write(Data([27,81,10,128])); let legacy = try socket.read(75)
        guard legacy.first == 0xc1 else { throw ScanFailure.message("This printer's scan protocol is not supported.") }
        try socket.write(Data([27,81,68,73,10,128])); let capability = try socket.read(8)
        guard capability.prefix(4) == Data([0,81,68,73]), capability.uint32LE(4) <= 65536 else { throw ScanFailure.message("Could not read the printer's scan capabilities.") }
        _ = try socket.read(Int(capability.uint32LE(4)))
        try socket.write(ScanWire.settings(dpi: dpi, adf: adf))
        let settings = try socket.read(8)
        guard settings.prefix(4) == Data([0,83,83,80]), settings.uint32LE(4) <= 65536 else { throw ScanFailure.message("The printer did not accept the scan settings.") }
        _ = try socket.read(Int(settings.uint32LE(4)))
        try socket.write(Data("\u{1b}XSC\nRESO=\(dpi),\(dpi)\nAREA=FULL\nMODE=NORMAL\n".utf8) + Data([128]))
        var imageData = Data(); var pages = 0
        while true {
            if cancellation.isCancelled { throw ScanFailure.message("Scan canceled.") }
            let frame = try ScanWire.validateFrame(socket.read(6))
            if frame.status == 2 {
                guard frame.kind == 0x15 else { throw ScanFailure.message("The printer returned an unsupported image format.") }
                let details = try socket.read(8); let length = Int(details.uint32LE(0))
                guard length > 0 && length <= 16_777_216 && imageData.count + length <= 200_000_000 else { throw ScanFailure.message("The scan page is too large. Lower the resolution and try again.") }
                imageData += try socket.read(length)
            } else if (frame.status & 1) == 1 {
                guard frame.kind == 0x2000, imageData.prefix(2) == Data([255,216]), imageData.suffix(2) == Data([255,217]),
                      let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
                      let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int, let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int,
                      pixelWidth > 0, pixelHeight > 0, pixelWidth <= 20000, pixelHeight <= 30000, pixelWidth * pixelHeight <= 100_000_000,
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ScanFailure.message("The scan image is incomplete or has invalid dimensions. Scan again.") }
                let width = CGFloat(image.width) * 72 / CGFloat(dpi), height = CGFloat(image.height) * 72 / CGFloat(dpi)
                var box = CGRect(x: 0, y: 0, width: width, height: height)
                let boxData = NSData(bytes: &box, length: MemoryLayout<CGRect>.size)
                pdf.beginPDFPage([kCGPDFContextMediaBox: boxData] as CFDictionary)
                let processed = try ScanImageProcessor.process(image,appearance:appearance)
                pdf.draw(processed, in: box); pdf.endPDFPage(); pages += 1; progress(pages)
                imageData.removeAll(keepingCapacity: true)
                guard pages <= 500 else { throw ScanFailure.message("The job exceeds 500 pages. Scan in smaller batches.") }
                if (frame.status & 0x20) == 0x20 { break }
            } else if frame.status == 0x20 && frame.kind == 0x2000 { break }
            else { throw ScanFailure.message("The printer stopped scanning (status \(frame.status)). Check the paper and printer display.") }
        }
        guard pages > 0 else { throw ScanFailure.message("No scan pages were received.") }
        pdf.closePDF(); pdfClosed = true
        try FileManager.default.moveItem(at: temporary, to: destination); published = true
        return ScanResult(url: destination, pages: pages)
    }
}
