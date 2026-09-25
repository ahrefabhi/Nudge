import AppKit
import PeekuKit
import SwiftUI

/// `Peeku --snapshot <dir>` renders the character sheet and every island phase to PNGs,
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
            model.codexHooks = .installed
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
        historyMachine.spend = MockSessions.spend()
        historyMachine.history = MockSessions.history()
        historyMachine.managerTab = .history
        let history = ManagerView(machine: historyMachine, bar: 32)
            .frame(width: 460, height: 580 + IslandMetrics.managerTabRow)
            .background(Color.black)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30))
            .padding(40)
            .background(Color(hex: 0x1a1d26))
            .environment(\.colorScheme, .dark)
        try write(history, to: directory.appending(path: "manager-history.png"))

        historyMachine.usage = MockSessions.usage()
        historyMachine.setUsageAlertRules([UsageAlertRule(scope: .claude, threshold: 75)] + UsageAlertRule.defaults)
        historyMachine.managerTab = .usage
        let usage = ManagerView(machine: historyMachine, bar: 32)
            .frame(width: 460, height: 580 + IslandMetrics.managerTabRow)
            .background(Color.black)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30))
            .padding(40)
            .background(Color(hex: 0x1a1d26))
            .environment(\.colorScheme, .dark)
        try write(usage, to: directory.appending(path: "manager-usage.png"))

        let editor = UsageView(machine: historyMachine, adding: true, custom: "83")
            .frame(width: 460, height: 720)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        // The custom percentage is a text field, which ImageRenderer can't draw.
        try writeWindowed(editor, size: CGSize(width: 460, height: 720), appearance: .darkAqua,
                          to: directory.appending(path: "usage-alert-editor.png"))

        let commandsRoot = FileManager.default.temporaryDirectory.appending(path: "peeku-snapshot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: commandsRoot) }
        let runner = MockSessions.commands(root: commandsRoot)
        historyMachine.managerTab = .commands
        let commands = ManagerView(machine: historyMachine, bar: 32, commands: runner)
            .frame(width: 460, height: 580 + IslandMetrics.managerTabRow)
            .background(Color.black)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30))
            .padding(40)
            .background(Color(hex: 0x1a1d26))
            .environment(\.colorScheme, .dark)
        try write(commands, to: directory.appending(path: "manager-commands.png"))
        try writeWindowed(CommandLogView(runner: runner, id: runner.commands[2].id), size: CGSize(width: 720, height: 360),
                          appearance: .aqua, to: directory.appending(path: "command-log.png"))
        try writeWindowed(CommandEditorView(original: runner.commands[0], chooseFolder: { _, _ in }, onSave: { _, _ in },
                                            onDelete: {}, onCancel: {}),
                          size: CGSize(width: 460, height: 250), appearance: .aqua, to: directory.appending(path: "command-editor.png"))

        let setupMachine = PhaseMachine(scheduler: ManualScheduler(start: Date()))
        setupMachine.update(sessions: MockSessions.calm())
        setupMachine.usage = [AgentUsage(agent: .claude, source: .needsSetup, report: nil),
                              AgentUsage(agent: .codex, source: .connected, report: nil)]
        setupMachine.managerTab = .usage
        let setup = ManagerView(machine: setupMachine, bar: 32)
            .frame(width: 460, height: 580 + IslandMetrics.managerTabRow)
            .background(Color.black)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30))
            .padding(40)
            .background(Color(hex: 0x1a1d26))
            .environment(\.colorScheme, .dark)
        try write(setup, to: directory.appending(path: "manager-usage-setup.png"))

        let settings = SettingsModel(setup: OnboardingModel(sessions: { MockSessions.sample() }, hookSetup: nil))
        settings.setup.refresh()
        settings.setup.hooks = .installed
        settings.setup.codexHooks = .installed
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
        for name in ["alert-permission", "alert-question", "alert-multi", "alert-usage", "alert-command", "manager", "manager-empty"] {
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
        ("alert-usage", { machine, clock in
            machine.update(usageAlerts: [MockSessions.usageAlert(now: clock.now)])
            clock.advance(by: 1.5)
        }),
        ("alert-command", { machine, clock in
            machine.update(commandAlerts: [MockSessions.commandAlert(now: clock.now)])
            clock.advance(by: 1.5)
        }),
        ("alert-command-input", { machine, clock in
            machine.update(commandAlerts: [MockSessions.commandPrompt(now: clock.now)])
            clock.advance(by: 1.5)
        }),
        ("alert-multi-command", { machine, clock in
            trigger(.error, machine, clock)
            machine.update(commandAlerts: [MockSessions.commandAlert(now: clock.now)])
            clock.advance(by: 1.5)
        }),
        ("alert-multi-usage", { machine, clock in
            trigger(.error, machine, clock)
            machine.update(usageAlerts: [MockSessions.usageAlert(now: clock.now)])
            clock.advance(by: 1.5)
        }),
        ("pill", { machine, clock in trigger(.multiple, machine, clock); clock.advance(by: 1); machine.later() }),
        ("manager", { machine, clock in
            machine.update(sessions: MockSessions.sample(now: clock.now))
            machine.spend = MockSessions.spend(now: clock.now)
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
        let renderer = ImageRenderer(content: view.environment(\.peekuStill, true))
        renderer.scale = 2
        guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
        print(url.path)
    }
}
