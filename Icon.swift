// SPDX-License-Identifier: MIT
import AppKit

let directory = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
for size in [16,32,64,128,256,512,1024] {
    let image = NSImage(size:NSSize(width:size,height:size))
    image.lockFocus()
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x:CGFloat(size)/1024,y:CGFloat(size)/1024)
    NSColor(calibratedRed:0.09,green:0.41,blue:0.76,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:18,y:18,width:988,height:988),xRadius:211,yRadius:211).fill()
    let paper = NSBezierPath(); paper.move(to:NSPoint(x:330,y:448));paper.line(to:NSPoint(x:330,y:806));paper.curve(to:NSPoint(x:362,y:838),controlPoint1:NSPoint(x:330,y:828),controlPoint2:NSPoint(x:341,y:838));paper.line(to:NSPoint(x:610,y:838));paper.line(to:NSPoint(x:700,y:748));paper.line(to:NSPoint(x:700,y:448));paper.close()
    NSColor.white.setFill();paper.fill()
    let fold = NSBezierPath();fold.move(to:NSPoint(x:610,y:838));fold.line(to:NSPoint(x:610,y:748));fold.line(to:NSPoint(x:700,y:748));NSColor(calibratedRed:0.77,green:0.87,blue:0.98,alpha:1).setFill();fold.fill()
    NSColor(calibratedRed:0.47,green:0.65,blue:0.85,alpha:1).setFill()
    for y in [647,698] { NSBezierPath(roundedRect:NSRect(x:386,y:y,width:224,height:14),xRadius:7,yRadius:7).fill() }
    let shadow = NSShadow();shadow.shadowColor = NSColor.black.withAlphaComponent(0.14);shadow.shadowBlurRadius = 20;shadow.shadowOffset = NSSize(width:0,height:-10);shadow.set()
    NSColor.white.setFill();NSBezierPath(roundedRect:NSRect(x:205,y:240,width:614,height:256),xRadius:48,yRadius:48).fill()
    NSShadow().set()
    NSColor(calibratedRed:0.74,green:0.85,blue:0.97,alpha:1).setFill();NSBezierPath(roundedRect:NSRect(x:271,y:412,width:482,height:31),xRadius:15,yRadius:15).fill()
    NSColor(calibratedRed:0.08,green:0.49,blue:0.41,alpha:1).setFill();NSBezierPath(ovalIn:NSRect(x:702,y:328,width:26,height:26)).fill()
    NSColor(calibratedRed:0.09,green:0.41,blue:0.76,alpha:1).setFill();NSBezierPath(roundedRect:NSRect(x:348,y:286,width:328,height:18),xRadius:9,yRadius:9).fill()
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
    let data = bitmap.representation(using:.png,properties:[:])!
    let names:[String]
    switch size {
    case 16:names=["icon_16x16.png"]
    case 32:names=["icon_16x16@2x.png","icon_32x32.png"]
    case 64:names=["icon_32x32@2x.png"]
    case 128:names=["icon_128x128.png"]
    case 256:names=["icon_128x128@2x.png","icon_256x256.png"]
    case 512:names=["icon_256x256@2x.png","icon_512x512.png"]
    default:names=["icon_512x512@2x.png"]
    }
    for name in names { try data.write(to:directory.appendingPathComponent(name)) }
}
