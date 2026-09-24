import AppKit
import SwiftUI

final class SettingsWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let model: SettingsModel

    init(model: SettingsModel) {
        self.model = model
        window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
        super.init()
        window.title = "Nudge Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
    }

    func show() {
        model.start()
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.stop()
    }
}
