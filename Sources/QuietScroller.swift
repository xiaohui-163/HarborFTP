import AppKit
import SwiftUI

/// Retains native scrolling, keyboard access, hit testing and thumb dragging.
final class QuietScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
    override func drawKnob() {
        let knob = rect(for: .knob)
        guard knob.height > 0 else { return }
        let width: CGFloat = 6
        let thumb = NSRect(x: knob.midX - width / 2, y: knob.minY + 2,
                           width: width, height: max(0, knob.height - 4))
        NSColor(calibratedWhite: 1, alpha: 0.13).setFill()
        NSBezierPath(roundedRect: thumb, xRadius: width / 2, yRadius: width / 2).fill()
    }
}

struct QuietScrollStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> ScrollStyleAnchor { ScrollStyleAnchor() }
    func updateNSView(_ nsView: ScrollStyleAnchor, context: Context) { nsView.installSoon() }
}
final class ScrollStyleAnchor: NSView {
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); installSoon() }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); installSoon() }
    func installSoon() {
        DispatchQueue.main.async { [weak self] in
            guard let scroll = self?.enclosingScrollView else { return }
            if !(scroll.verticalScroller is QuietScroller) {
                let scroller = QuietScroller()
                scroller.controlSize = .small
                scroll.verticalScroller = scroller
            }
            scroll.scrollerStyle = .overlay
            scroll.hasHorizontalScroller = false
            scroll.drawsBackground = false
        }
    }
}
