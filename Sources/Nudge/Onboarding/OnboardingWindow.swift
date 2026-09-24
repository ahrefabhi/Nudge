import AppKit
import SwiftUI

/// The small dark onboarding window. Closing it any way counts as finishing;
/// "Set Up Nudge…" in the menu reopens it.
final class OnboardingWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let model: OnboardingModel
    private let onClose: () -> Void

    init(model: OnboardingModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: HookSetup.availableTargets.contains(.codex) ? 476 : 420),
                          styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Welcome to Nudge"
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingView(model: model))
        window.delegate = self
        model.onFinish = { [weak self] in self?.window.close() }
    }

    func show() {
        model.start()
        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.stop()
        onClose()
    }
}
