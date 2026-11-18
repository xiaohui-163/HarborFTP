import AppKit
import SwiftUI

/// Only the main window participates; panels and menu-bar windows are unaffected.
struct MainWindowLifecycle: NSViewRepresentable {
    func makeNSView(context: Context) -> MainWindowAnchor { MainWindowAnchor() }
    func updateNSView(_ nsView: MainWindowAnchor, context: Context) {}
}
final class MainWindowAnchor: NSView {
    private var closeObserver: NSObjectProtocol?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer = closeObserver { NotificationCenter.default.removeObserver(observer) }
        closeObserver = nil
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        NSApplication.shared.setActivationPolicy(.regular)
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            // MenuBarExtra and the shared service model remain alive.
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
    deinit {
        if let observer = closeObserver { NotificationCenter.default.removeObserver(observer) }
    }
}

final class HarborAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
