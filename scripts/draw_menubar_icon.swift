import AppKit
// Template menu-bar icon: outlined speech bubble with a bold A, black on transparent.
let S: CGFloat = 512
let out = CommandLine.arguments[1]
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let stroke: CGFloat = 34
// bubble body leaves room for the tail at bottom-left
let rect = NSRect(x: 40, y: 120, width: 432, height: 340)
let bubble = NSBezierPath(roundedRect: rect, xRadius: 110, yRadius: 110)
// smooth curled tail
let tail = NSBezierPath()
let bx = rect.minX + 92
tail.move(to: NSPoint(x: bx, y: rect.minY + 40))
tail.curve(to: NSPoint(x: bx - 52, y: rect.minY - 72),
    controlPoint1: NSPoint(x: bx - 4, y: rect.minY - 12),
    controlPoint2: NSPoint(x: bx - 22, y: rect.minY - 50))
tail.curve(to: NSPoint(x: bx + 116, y: rect.minY + 6),
    controlPoint1: NSPoint(x: bx + 12, y: rect.minY - 36),
    controlPoint2: NSPoint(x: bx + 60, y: rect.minY - 10))
tail.close()
bubble.append(tail)
NSColor.black.setStroke()
bubble.lineWidth = stroke
bubble.lineJoinStyle = .round
bubble.stroke()
// letter A
let font = NSFont.systemFont(ofSize: 230, weight: .bold)
let str = NSAttributedString(string: "A", attributes: [.font: font, .foregroundColor: NSColor.black])
let sz = str.size()
str.draw(at: NSPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2 + 6))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("written")
