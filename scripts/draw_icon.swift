import AppKit
let S: CGFloat = 1024
let out = CommandLine.arguments[1]
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
}
// flat blue, full bleed (system masks its own squircle)
rgba(0.21, 0.26, 0.40).setFill()
NSRect(x: 0, y: 0, width: S, height: S).fill()

// speech bubble with a smooth iMessage-style curled tail at bottom-left
func bubble(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    let p = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let tail = NSBezierPath()
    let bx = rect.minX + radius * 0.55
    tail.move(to: NSPoint(x: bx, y: rect.minY + 70))
    tail.curve(
        to: NSPoint(x: bx - 88, y: rect.minY - 92),
        controlPoint1: NSPoint(x: bx - 6, y: rect.minY - 10),
        controlPoint2: NSPoint(x: bx - 30, y: rect.minY - 62))
    tail.curve(
        to: NSPoint(x: bx + 150, y: rect.minY + 4),
        controlPoint1: NSPoint(x: bx + 10, y: rect.minY - 46),
        controlPoint2: NSPoint(x: bx + 70, y: rect.minY - 12))
    tail.close()
    p.append(tail)
    return p
}
func drawText(_ text: String, center: NSPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    let sz = str.size()
    str.draw(at: NSPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2))
}
func withShadow(_ alpha: CGFloat, _ blur: CGFloat, _ dy: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.current?.saveGraphicsState()
    let s = NSShadow()
    s.shadowColor = NSColor.black.withAlphaComponent(alpha)
    s.shadowOffset = NSSize(width: 0, height: dy)
    s.shadowBlurRadius = blur
    s.set()
    draw()
    NSGraphicsContext.current?.restoreGraphicsState()
}

// white bubble with 文 — main element, centered slightly left/low
let whiteRect = NSRect(x: 140, y: 280, width: 540, height: 470)
let whiteBubble = bubble(whiteRect, radius: 160)
withShadow(0.25, 34, -14) {
    rgba(1, 1, 1).setFill()
    whiteBubble.fill()
}
drawText("文", center: NSPoint(x: whiteRect.midX, y: whiteRect.midY + 10), size: 330, weight: .semibold,
         color: rgba(0.15, 0.19, 0.28))

// amber bubble with A — overlapping the white one from the top-right
let amberRect = NSRect(x: 590, y: 590, width: 300, height: 265)
let amberPath = NSBezierPath(roundedRect: amberRect, xRadius: 92, yRadius: 92)
let amberTail = NSBezierPath()
amberTail.move(to: NSPoint(x: amberRect.minX + 130, y: amberRect.minY + 60))
amberTail.curve(
    to: NSPoint(x: amberRect.minX + 26, y: amberRect.minY - 66),
    controlPoint1: NSPoint(x: amberRect.minX + 90, y: amberRect.minY - 14),
    controlPoint2: NSPoint(x: amberRect.minX + 56, y: amberRect.minY - 46))
amberTail.curve(
    to: NSPoint(x: amberRect.minX + 210, y: amberRect.minY + 6),
    controlPoint1: NSPoint(x: amberRect.minX + 116, y: amberRect.minY - 36),
    controlPoint2: NSPoint(x: amberRect.minX + 160, y: amberRect.minY - 10))
amberTail.close()
amberPath.append(amberTail)
withShadow(0.28, 28, -12) {
    rgba(1.0, 0.71, 0.13).setFill()
    amberPath.fill()
}
drawText("A", center: NSPoint(x: amberRect.midX, y: amberRect.midY + 6), size: 185, weight: .heavy,
         color: .white)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("written")
