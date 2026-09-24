import AppKit
import PipKit
import SwiftUI

/// `Pip --snapshot <dir>` renders the character sheet and every island phase to PNGs,
/// driving the real phase machine with a manual clock. Animations render at rest.
enum Snapshots {
    static func render(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write(CharacterSheet(), to: directory.appending(path: "character-sheet.png"))

        for step in OnboardingModel.Step.allCases {
            let model = OnboardingModel(sessions: { MockSessions.sample() }, hookSetup: nil)
            model.refresh()
            model.step = step
            model.hooks = .installed
            model.accessibility = false
            model.automation = .needsAsk
            try write(OnboardingView(model: model), to: directory.appending(path: "onboarding-\(step.rawValue).png"))
        }

        let ring = FocusRingView(color: Tokens.Accent.permission, margin: 24)
            .frame(width: 520, height: 340)
            .background(Color(hex: 0x16161a).padding(24))
        try write(ring, to: directory.appending(path: "focus-ring.png"))

        let historyMachine = PhaseMachine(scheduler: ManualScheduler(start: Date()))
        historyMachine.update(sessions: MockSessions.calm())
        historyMachine.history = MockSessions.history()
        let history = ManagerView(machine: historyMachine, bar: 32, initialTab: .history)
            .frame(width: 460, height: 580)
            .background(Color.black)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30))
            .padding(40)
            .background(Color(hex: 0x1a1d26))
            .environment(\.colorScheme, .dark)
        try write(history, to: directory.appending(path: "manager-history.png"))

        let settings = SettingsModel(setup: OnboardingModel(sessions: { MockSessions.sample() }, hookSetup: nil))
        settings.setup.refresh()
        settings.setup.hooks = .installed
        settings.setup.accessibility = true
        for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            try writeWindowed(SettingsView(model: settings), size: CGSize(width: 480, height: 640), appearance: appearance,
                              to: directory.appending(path: "settings-\(name).png"))
        }

        // The menu bar icon, drawn large on a light and a dark bar to check the cut-out eyes.
        for (name, bar, ink) in [("light", Color(hex: 0xe8e8ec), Color.black), ("dark", Color(hex: 0x2b2b30), Color.white)] {
            let icon = Image(nsImage: MenuBarIcon.image()).renderingMode(.template).resizable()
                .foregroundStyle(ink).frame(width: 72, height: 72)
                .padding(24).background(bar)
            try write(icon, to: directory.appending(path: "menubar-\(name).png"))
        }

        let notch = NotchGeometry.fallback

        // Minimal mode: a full-screen app hides the menu bar, so a waiting session is only a glow.
        let glowClock = ManualScheduler(start: Date())
        let glowMachine = PhaseMachine(scheduler: glowClock)
        glowMachine.update(sessions: MockSessions.calm(now: glowClock.now))
        let presence = PresenceMonitor()
        presence.state.menuBarHidden = true
        glowMachine.muted = true
        glowMachine.update(sessions: MockSessions.apply(.permission, to: glowMachine.sessions, now: glowClock.now))
        let glow = IslandView(machine: glowMachine, notch: notch, presence: presence)
            .frame(width: 600, height: 120)
            .background(Color(hex: 0x2a2d36))
        try write(glow, to: directory.appending(path: "island-glow.png"))

        // Light mode: the same alerts and manager in the light panel under a black notch.
        for name in ["alert-permission", "alert-question", "alert-multi", "manager", "manager-empty"] {
            guard let drive = scenarios.first(where: { $0.0 == name })?.1 else { continue }
            let clock = ManualScheduler(start: Date())
            let machine = PhaseMachine(scheduler: clock)
            machine.update(sessions: MockSessions.calm(now: clock.now))
            drive(machine, clock)
            let view = IslandView(machine: machine, notch: notch, forceLight: true)
                .frame(width: 600, height: 700)
                .background(RadialGradient(colors: [Color(hex: 0xc6d0e0), Color(hex: 0xeceef3)], center: UnitPoint(x: 0.7, y: 1.3),
                                           startRadius: 0, endRadius: 700))
            try write(view, to: directory.appending(path: "light-\(name).png"))
        }

        for (name, drive) in scenarios {
            let clock = ManualScheduler(start: Date())
            let machine = PhaseMachine(scheduler: clock)
            machine.update(sessions: MockSessions.calm(now: clock.now))
            drive(machine, clock)
            let view = IslandView(machine: machine, notch: notch, forceLight: false)
                .frame(width: 600, height: 640)
                .background(LinearGradient(colors: [Color(hex: 0x2a3142), Color(hex: 0x0c0d11)], startPoint: .bottom, endPoint: .top))
            try write(view, to: directory.appending(path: "island-\(name).png"))
        }
    }

    typealias Drive = (PhaseMachine, ManualScheduler) -> Void

    static let scenarios: [(String, Drive)] = [
        ("idle", { machine, _ in machine.update(sessions: []) }),
        ("working", { _, _ in }),
        ("peek", { machine, clock in trigger(.permission, machine, clock) }),
        ("alert-permission", { machine, clock in trigger(.permission, machine, clock); clock.advance(by: 1.5) }),
        ("alert-question", { machine, clock in trigger(.question, machine, clock); clock.advance(by: 1.5) }),
        ("alert-error", { machine, clock in trigger(.error, machine, clock); clock.advance(by: 1.5) }),
        ("alert-multi", { machine, clock in trigger(.multiple, machine, clock); clock.advance(by: 1.5) }),
        ("pill", { machine, clock in trigger(.multiple, machine, clock); clock.advance(by: 1); machine.later() }),
        ("manager", { machine, clock in
            machine.update(sessions: MockSessions.sample(now: clock.now))
            clock.advance(by: 1)
            machine.toggleManager()
        }),
        ("celebrating", { machine, clock in trigger(.success, machine, clock) }),
        ("manager-empty", { machine, _ in
            machine.update(sessions: [])
            machine.toggleManager()
        }),
    ]

    static func trigger(_ event: MockSessions.Event, _ machine: PhaseMachine, _ clock: ManualScheduler) {
        machine.update(sessions: MockSessions.apply(event, to: machine.sessions, now: clock.now, staggered: true))
    }

    /// For views backed by AppKit controls (forms, toggles), which ImageRenderer can't draw:
    /// lays them out in an off-screen window and caches its display.
    static func writeWindowed<V: View>(_ view: V, size: CGSize, appearance: NSAppearance.Name, to url: URL) throws {
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw CocoaError(.fileWriteUnknown) }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        window.orderOut(nil)
        guard let data = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
        print(url.path)
    }

    static func write<V: View>(_ view: V, to url: URL) throws {
        let renderer = ImageRenderer(content: view.environment(\.pipStill, true))
        renderer.scale = 2
        guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
        print(url.path)
    }
}
