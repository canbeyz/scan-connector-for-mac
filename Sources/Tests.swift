// SPDX-License-Identifier: MIT
import Foundation
import AppKit
import Darwin
import CoreGraphics

final class EventTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func received() { lock.lock(); count += 1; lock.unlock() }
    var events: Int { lock.lock(); defer { lock.unlock() }; return count }
}

enum CoreTests {
    static func run() throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ text: String) throws {
            guard condition() else { throw ScanFailure.message("Test failed: \(text)") }; count += 1
        }
        var settings = AppSettings(); settings.displayName = "Office Mac"
        try check(settings.nameIsValid,"valid destination name")
        settings.displayName = "bad;name"; try check(!settings.nameIsValid,"reject protocol injection")
        settings.displayName = String(repeating:"a",count:15); try check(settings.nameIsValid,"allow 15-character panel name")
        settings.displayName = String(repeating:"a",count:16); try check(!settings.nameIsValid,"reject name exceeding panel limit")
        settings.displayName = "Alexs Office Desktop"; try check(!settings.nameIsValid,"reject previously allowed 20-character name")
        settings.displayName = " Office Mac"; try check(!settings.nameIsValid,"reject leading space")
        settings.displayName = "Office Mac "; try check(!settings.nameIsValid,"reject trailing space")
        settings.displayName = ""; try check(!settings.nameIsValid,"reject empty name")
        try check(AppSettings.isValidDisplayName(AppSettings.defaultName()),"default name fits panel limit")
        settings.displayName = "\u{4e66}\u{623f}"; try check(!settings.nameIsValid,"reject unsupported name encoding")
        settings.displayName = "Mac Native"
        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self,from:encoded)
        try check(decoded == settings,"settings roundtrip")
        let legacy=Data("{\"printerHost\":\"printer.local\",\"displayName\":\"Office Mac\",\"dpi\":600,\"outputPath\":\"/tmp/scans\",\"receiveEnabled\":false}".utf8)
        var migrated=try JSONDecoder().decode(AppSettings.self,from:legacy)
        try check(migrated.displayName == "Office Mac" && migrated.dpi == 600 && migrated.outputPath == "/tmp/scans","migrate old settings without losing user choices")
        try check(migrated.automaticReception && migrated.documentEnhancement && migrated.colorMode == .color,"new preferences have upgrade defaults")
        migrated.prepareForLaunch();try check(migrated.receiveEnabled,"relaunch resumes after a temporary pause")
        migrated.automaticReception=false;migrated.prepareForLaunch();try check(!migrated.receiveEnabled,"honor disabled automatic reception")
        var empty=AppSettings();empty.prepareForLaunch();try check(!empty.receiveEnabled,"unconfigured Mac waits for printer selection")
        var pixels=[UInt8](repeating:255,count:26);for index in [0,12,14,24] { pixels[index]=130 }
        let provider=CGDataProvider(data:Data(pixels) as CFData)!
        let image=CGImage(width:13,height:2,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:13,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:0),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        let gray=try ScanImageProcessor.process(image,appearance:ScanAppearance(mode:.grayscale))
        try check(gray.bitsPerComponent == 8 && gray.colorSpace?.model == .monochrome,"true 8-bit grayscale output")
        let grayBytes=gray.dataProvider!.data! as Data
        try check(grayBytes[0] < 16 && grayBytes[1] > 240,"document enhancement restores faint ink while preserving paper")
        let text=try ScanImageProcessor.process(image,appearance:ScanAppearance(mode:.text))
        try check(text.bitsPerComponent == 1 && text.bitsPerPixel == 1,"packed 1-bit text output")
        try check((text.dataProvider!.data! as Data) == Data([0x7f,0xf7,0xbf,0xef]),"text orientation and odd-width row padding")
        var histogram=[Int](repeating:0,count:256);histogram[130]=10;histogram[255]=990
        let neutral=ScanImageProcessor.lookup(histogram:histogram,appearance:.original)
        let darker=ScanImageProcessor.lookup(histogram:histogram,appearance:ScanAppearance(enhance:false,density:20))
        try check(neutral[130] == 130 && darker[130] < neutral[130] && darker[255] == 255,"density darkens ink without turning white paper gray")
        let message = Data([2,0,120,48]) + Data("TYPE=BR;BUTTON=SCAN;USER=\"Office Mac\";FUNC=FILE;HOST=192.0.2.10:54925;APPNUM=5;REGID=1234;SEQ=1;".utf8)
        try check(ScanButtonEvent.parse(message,expectedName:"Office Mac",expectedHost:"192.0.2.10:54925")?.sequence == "1","synthetic scan button frame")
        try check(ScanButtonEvent.parse(message,expectedName:"Wrong Mac",expectedHost:"192.0.2.10:54925") == nil,"reject wrong destination")
        try check(ScanButtonEvent.parse(message,expectedName:"Office Mac",expectedHost:"192.0.2.11:54925") == nil,"reject wrong host")
        try check(ScanButtonEvent.parse(Data(repeating:0,count:5000),expectedName:"Office Mac",expectedHost:"") == nil,"reject oversized packet")
        let unknown = Data([2,0,120,48]) + Data("TYPE=BR;BUTTON=SCAN;USER=\"Office Mac\";FUNC=UNKNOWN;HOST=192.0.2.10:54925;SEQ=2;".utf8)
        try check(ScanButtonEvent.parse(unknown,expectedName:"Office Mac",expectedHost:"192.0.2.10:54925") == nil,"reject unknown scan function")
        let dataFrame = try ScanWire.validateFrame(Data([0,2,1,0,21,0]))
        try check(dataFrame.status == 2 && dataFrame.kind == 21,"decode JPEG band header")
        let endFrame = try ScanWire.validateFrame(Data([0,33,1,0,0,32]))
        try check(endFrame.status & 0x20 == 0x20 && endFrame.kind == 0x2000,"decode final page")
        do { _ = try ScanWire.validateFrame(Data([1,2,1,0,21,0])); throw ScanFailure.message("Test failed: scanner error accepted") }
        catch let error as ScanFailure { if error.localizedDescription.contains("Test failed") { throw error }; count += 1 }
        try check(Data([242,255,0,0]).uint32LE(0) == 65522,"decode observed image-band length")
        let command = ScanWire.settings(dpi:300,adf:false)
        try check(command.prefix(5) == Data([27,83,83,80,10]) && command.last == 128,"scan settings frame")
        try check(String(data:command.dropLast(),encoding:.ascii)?.contains("PSRC=FB\n") == true,"flatbed source")
        try check(String(data:ScanWire.settings(dpi:200,adf:true).dropLast(),encoding:.ascii)?.contains("PSRC=ADF\n") == true,"ADF source")
        let xml = Data("<scan:ScannerStatus xmlns:scan=\"test\" xmlns:pwg=\"pwg\"><pwg:State>Idle</pwg:State><scan:AdfState>ScannerAdfLoaded</scan:AdfState></scan:ScannerStatus>".utf8)
        let values = try XMLValues.parse(xml)
        try check(values["State"] == "Idle" && values["AdfState"] == "ScannerAdfLoaded","parse live scanner status")
        let events = EventTestState()
        let receiver = try ButtonReceiver(localIP:"127.0.0.1",printerIP:"127.0.0.1",name:"Office Mac",port:0,callback:{ _ in events.received() },failure:{ _ in })
        receiver.start(); defer { receiver.stop() }
        let fd = socket(AF_INET,SOCK_DGRAM,0); defer { close(fd) }
        var timeout = timeval(tv_sec:0,tv_usec:300_000)
        setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET); address.sin_port = receiver.port.bigEndian
        inet_pton(AF_INET,"127.0.0.1",&address.sin_addr)
        let packet = Data([2,0,120,48]) + Data("TYPE=BR;BUTTON=SCAN;USER=\"Office Mac\";FUNC=FILE;HOST=127.0.0.1:\(receiver.port);APPNUM=5;REGID=9;SEQ=1;".utf8)
        func sendPacket(_ data:Data) -> Data {
            _ = data.withUnsafeBytes { raw in withUnsafePointer(to:&address) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) { sendto(fd,raw.baseAddress,data.count,0,$0,socklen_t(MemoryLayout<sockaddr_in>.size)) } } }
            var reply = [UInt8](repeating:0,count:4096); let size = recv(fd,&reply,reply.count,0)
            return size > 0 ? Data(reply.prefix(size)) : Data()
        }
        try check(sendPacket(packet) == packet,"acknowledge a UDP button event")
        try check(sendPacket(packet) == packet,"acknowledge duplicate event without rescanning")
        Thread.sleep(forTimeInterval:0.05)
        try check(events.events == 1,"dispatch each button sequence only once")
        let wrongName = Data([2,0,120,48]) + Data("TYPE=BR;BUTTON=SCAN;USER=\"Other Mac\";FUNC=FILE;HOST=127.0.0.1:\(receiver.port);APPNUM=5;REGID=9;SEQ=2;".utf8)
        try check(sendPacket(wrongName).isEmpty && events.events == 1,"ignore a packet for a different Mac")
        print("\(count) core checks passed")
    }
}
