import AppKit
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
NSColor(red: 0.05, green: 0.24, blue: 0.20, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()
let track = NSBezierPath()
track.move(to: NSPoint(x: 275, y: -30))
track.line(to: NSPoint(x: 275, y: 365))
track.curve(to: NSPoint(x: 749, y: 680), controlPoint1: NSPoint(x: 275, y: 555), controlPoint2: NSPoint(x: 749, y: 470))
track.line(to: NSPoint(x: 749, y: 1050))
track.lineWidth = 55
NSColor(red: 0.67, green: 0.83, blue: 0.64, alpha: 1).setStroke()
track.stroke()
for point in [NSPoint(x: 275, y: 210), NSPoint(x: 749, y: 830)] {
    NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: point.x-57, y: point.y-57, width: 114, height: 114)).fill()
    NSColor(red: 0.05, green: 0.24, blue: 0.20, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: point.x-28, y: point.y-28, width: 56, height: 56)).fill()
}
NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 356, y: 351, width: 312, height: 312)).fill()
let check = NSBezierPath()
check.move(to: NSPoint(x: 433, y: 506))
check.line(to: NSPoint(x: 491, y: 449))
check.line(to: NSPoint(x: 589, y: 564))
check.lineWidth = 31
check.lineCapStyle = .round
check.lineJoinStyle = .round
NSColor(red: 0.05, green: 0.24, blue: 0.20, alpha: 1).setStroke()
check.stroke()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
