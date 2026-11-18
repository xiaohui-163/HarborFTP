import AppKit
let image = NSImage(size: NSSize(width: 720, height: 460))
image.lockFocus()
let full = NSBezierPath(rect: NSRect(x: 0, y: 0, width: 720, height: 460))
NSGradient(starting: NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.25, alpha: 1), ending: NSColor(calibratedRed: 0.04, green: 0.07, blue: 0.12, alpha: 1))!.draw(in: full, angle: -60)
func text(_ string: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ color: NSColor, _ weight: NSFont.Weight = .regular) {
    (string as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
}
text("HARBOR", 42, 398, 12, NSColor.white.withAlphaComponent(0.55), .semibold)
text("让文件，轻松抵达。", 42, 347, 30, .white, .semibold)
text("将 Harbor 拖入右侧文件夹，即可完成安装", 43, 319, 13, NSColor.white.withAlphaComponent(0.6))
let panel = NSBezierPath(roundedRect: NSRect(x: 42, y: 96, width: 636, height: 191), xRadius: 28, yRadius: 28)
NSGradient(starting: NSColor.white.withAlphaComponent(0.12), ending: NSColor.white.withAlphaComponent(0.035))!.draw(in: panel, angle: -90)
NSColor.white.withAlphaComponent(0.16).setStroke(); panel.lineWidth = 1; panel.stroke()
let arrow = NSBezierPath(); arrow.move(to: NSPoint(x: 312, y: 209)); arrow.line(to: NSPoint(x: 402, y: 209)); arrow.move(to: NSPoint(x: 389, y: 222)); arrow.line(to: NSPoint(x: 402, y: 209)); arrow.line(to: NSPoint(x: 389, y: 196)); arrow.lineWidth = 2.5; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round; NSColor(calibratedRed: 0.64, green: 0.74, blue: 1, alpha: 1).setStroke(); arrow.stroke()
text("01  拖入应用程序", 44, 57, 12, NSColor.white.withAlphaComponent(0.7))
text("02  从启动台打开 Harbor", 250, 57, 12, NSColor.white.withAlphaComponent(0.7))
text("FTP · MINI     /     0.5.5", 44, 25, 10, NSColor.white.withAlphaComponent(0.35))
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
