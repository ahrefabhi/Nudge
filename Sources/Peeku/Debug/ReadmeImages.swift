import AppKit
import PeekuKit
import SwiftUI

/// `Peeku --readme-images <dir>` renders the pictures in the README from the real views,
/// on the design's desktop gradient, at 2×.
enum ReadmeImages {
    static func render(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let notch = NotchGeometry.fallback
        let settings = SettingsModel(setup: onboardingModel(.permissions))
        settings.setup.accessibility = true
        settings.setup.claudeUsage = .installed

        func island(_ scenario: String, light: Bool = false, height: CGFloat) -> some View {
            let clock = ManualScheduler(start: Date())
            let machine = PhaseMachine(scheduler: clock)
            machine.update(sessions: MockSessions.calm(now: clock.now))
            Snapshots.scenarios.first { $0.0 == scenario }?.1(machine, clock)
            machine.history = MockSessions.history()
            return IslandView(machine: machine, notch: notch, settings: settings, forceLight: light)
                .frame(width: 760, height: height)
                .background(alignment: .top) { MenuBarStrip(light: light) }
                .background(light ? AnyView(LightDesktop()) : AnyView(Desktop()))
        }

        try write(island("alert-permission", height: 300), "alert")
        try write(island("alert-multi", height: 330), "multiple")
        try write(island("manager", height: 670), "manager")
        try write(island("alert-permission", light: true, height: 320), "light")
        try write(island("alert-usage", height: 300), "usage-alert")
        try write(island("alert-command", height: 300), "command-alert")
        try write(island("alert-command-input", height: 300), "command-input")

        let tabs = PhaseMachine(scheduler: ManualScheduler(start: Date()))
        tabs.update(sessions: MockSessions.calm())
        tabs.history = MockSessions.history()
        tabs.usage = MockSessions.usage()
        tabs.spend = MockSessions.spend()
        tabs.setUsageAlertRules([UsageAlertRule(scope: .claude, threshold: 75)] + UsageAlertRule.defaults)
        let commandsRoot = FileManager.default.temporaryDirectory.appending(path: "peeku-readme-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: commandsRoot) }
        let commands = MockSessions.commands(root: commandsRoot)
        func manager(_ tab: ManagerTab) -> some View {
            tabs.managerTab = tab
            return ManagerView(machine: tabs, bar: 32, commands: commands, settings: settings)
                .frame(width: 460, height: 580 + IslandMetrics.managerTabRow)
                .background(Color.black)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30))
                .shadow(color: .black.opacity(0.55), radius: 30, y: 24)
                .environment(\.colorScheme, .dark)
                .frame(width: 760, height: 670, alignment: .top)
                .background(Desktop())
        }
        try write(manager(.history), "history")
        try write(manager(.usage), "usage")
        try write(manager(.commands), "commands")
        // The docs preview asking about its port, answered from the output window.
        // cacheDisplay leaves out the window's own background, so give the view one.
        try Snapshots.writeWindowed(CommandLogView(runner: commands, id: commands.commands[2].id)
                                        .background(Color(nsColor: .windowBackgroundColor)),
                                    size: CGSize(width: 720, height: 380),
                                    appearance: .darkAqua, to: directory.appending(path: "command-output.png"))

        try write(NotchStates().background(Desktop()), "notch")
        try write(MenuBarStates().background(Desktop()), "menu-bar")
        try write(MenuBarAlert().background(Desktop()), "menu-bar-alert")
        try write(SocialPreview(), "social-preview")
        try write(CharacterSheet(), "states")

        try write(
            HStack(spacing: 28) {
                ForEach(OnboardingModel.Step.allCases, id: \.self) { step in
                    OnboardingView(model: onboardingModel(step))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.5), radius: 30, y: 24)
                }
            }
            .padding(48)
            .background(Desktop()),
            "onboarding")

        // Settings open inside the manager. Its pop-up menus are AppKit, so it renders in a window;
        // still, so it shows this picture's apps rather than this Mac's.
        tabs.showSettings()
        let settingsPanel = ManagerView(machine: tabs, bar: 32, commands: commands, settings: settings)
            .frame(width: 460, height: 580 + IslandMetrics.managerTabRow)
            .background(Color.black)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30))
            .environment(\.peekuStill, true)
            .environment(\.colorScheme, .dark)
            .frame(width: 540, height: 690, alignment: .top)
            .background(Desktop())
        try Snapshots.writeWindowed(settingsPanel, size: CGSize(width: 540, height: 690),
                                    appearance: .darkAqua, to: directory.appending(path: "settings.png"))

        try write(AppIconView().frame(width: 1024, height: 1024).scaleEffect(0.25).frame(width: 256, height: 256), "icon")

        func write<V: View>(_ view: V, _ name: String) throws {
            try Snapshots.write(view, to: directory.appending(path: "\(name).png"))
        }
    }

    private static func onboardingModel(_ step: OnboardingModel.Step) -> OnboardingModel {
        let model = OnboardingModel(sessions: { MockSessions.sample() }, hookSetup: nil)
        model.refresh()
        model.step = step
        model.hooks = .installed
        model.codexHooks = .installed
        model.accessibility = false
        model.automation = .needsAsk
        // The picture shouldn't depend on which apps this Mac happens to have installed.
        model.environments = [
            .init(id: .host(.iTerm), detail: "3 sessions found", enabled: true),
            .init(id: .host(.terminal), detail: "1 session found", enabled: true),
            .init(id: .host(.vsCode), detail: "Claude Code extension · 1 session", enabled: true),
            .init(id: .host(.claude), detail: "Not running", enabled: false),
        ]
        return model
    }
}

/// The design's dark desktop.
private struct Desktop: View {
    var body: some View {
        RadialGradient(colors: [Color(hex: 0x2a3142), Color(hex: 0x14161d), Color(hex: 0x0c0d11)],
                       center: UnitPoint(x: 0.25, y: 1.15), startRadius: 0, endRadius: 900)
    }
}

/// The design's light desktop, for light mode.
private struct LightDesktop: View {
    var body: some View {
        RadialGradient(colors: [Color(hex: 0xc6d0e0), Color(hex: 0xeceef3)], center: UnitPoint(x: 0.7, y: 1.3),
                       startRadius: 0, endRadius: 800)
    }
}

/// A plain menu bar behind the notch, so the island reads as sitting at the top of a screen.
private struct MenuBarStrip: View {
    var light = false
    var height: CGFloat = 32
    var body: some View {
        Rectangle().fill(light ? Color.white.opacity(0.45) : Color.black.opacity(0.3)).frame(height: height)
    }
}

/// What lives in the notch: working, a waiting session peeking out, and the folded pill.
private struct NotchStates: View {
    var body: some View {
        VStack(spacing: 18) {
            row("Working", "A spinner and how many agents are busy") { _, _ in }
            row("Needs you", "Peeku drops out of the notch") { machine, clock in
                Snapshots.trigger(.permission, machine, clock)
            }
            row("Folded", "Three waiting, out of the way") { machine, clock in
                Snapshots.trigger(.multiple, machine, clock)
                clock.advance(by: 1)
                machine.later()
            }
        }
        .padding(.vertical, 28)
        .frame(width: 760)
    }

    private func row(_ title: String, _ detail: String, drive: Snapshots.Drive) -> some View {
        let clock = ManualScheduler(start: Date())
        let machine = PhaseMachine(scheduler: clock)
        machine.update(sessions: MockSessions.calm(now: clock.now))
        drive(machine, clock)
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.peeku(13, .semibold)).foregroundStyle(Tokens.textPrimary)
                Text(detail).font(.peeku(12)).foregroundStyle(Color.label(0.55))
            }
            .frame(width: 200, alignment: .leading)
            ZStack(alignment: .top) {
                MenuBarStrip()
                IslandView(machine: machine, notch: .fallback, forceLight: false)
            }
            .frame(width: 440, height: 76, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.08)))
        }
    }
}

/// On a display without a notch: no fake notch. Peeku is the menu bar icon, whose eyes show the
/// state, and it climbs down from the icon when an agent needs you.
private struct MenuBarStates: View {
    static let notch = NotchGeometry(hasNotch: false, width: 190, barHeight: 24)
    /// The icon sits 160pt right of the strip's middle, among the other menu bar items.
    static let iconOffset: CGFloat = 160

    var body: some View {
        VStack(spacing: 18) {
            row("Idle", "Sleepy eyes, nothing else on screen", icon: .init(mood: .idle)) { machine, _ in machine.update(sessions: []) }
            row("Working", "The eyes glance around", icon: .init(mood: .working)) { _, _ in }
            row("Needs you", "Peeku climbs down from the icon", icon: .init(mood: .permission, count: 1)) { machine, clock in
                Snapshots.trigger(.permission, machine, clock)
            }
            row("Folded", "Three waiting, out of the way", icon: .init(mood: .multiple, count: 3)) { machine, clock in
                Snapshots.trigger(.multiple, machine, clock)
                clock.advance(by: 1)
                machine.later()
            }
        }
        .padding(.vertical, 28)
        .frame(width: 760)
    }

    private func row(_ title: String, _ detail: String, icon: MenuBarIcon.State, drive: Snapshots.Drive) -> some View {
        let clock = ManualScheduler(start: Date())
        let machine = PhaseMachine(scheduler: clock)
        machine.update(sessions: MockSessions.calm(now: clock.now))
        drive(machine, clock)
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.peeku(13, .semibold)).foregroundStyle(Tokens.textPrimary)
                Text(detail).font(.peeku(12)).foregroundStyle(Color.label(0.55))
            }
            .frame(width: 200, alignment: .leading)
            ZStack(alignment: .top) {
                MenuBarStrip(height: Self.notch.barHeight)
                MenuBarItems(icon: icon, width: 440)
                IslandView(machine: machine, notch: Self.notch, menuBar: MenuBarAnchor(offset: Self.iconOffset), forceLight: false)
            }
            .frame(width: 440, height: 76, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.08)))
        }
    }
}

/// The Apple menu, Peeku's icon and the clock, so the strip reads as a menu bar without a notch.
private struct MenuBarItems: View {
    let icon: MenuBarIcon.State
    let width: CGFloat

    var body: some View {
        let image = MenuBarIcon.image(icon, darkMenuBar: true)
        ZStack {
            HStack {
                Image(systemName: "apple.logo")
                Spacer()
                Text("9:41")
            }
            .padding(.horizontal, 14)
            Image(nsImage: image).renderingMode(icon.isTemplate ? .template : .original)
                .foregroundStyle(Color.label(0.9))
                // Centered on the icon's body; a badge adds width on the right.
                .offset(x: MenuBarStates.iconOffset + (image.size.width - MenuBarIcon.size) / 2)
        }
        .font(.peeku(12))
        .foregroundStyle(Color.label(0.85))
        .frame(width: width, height: MenuBarStates.notch.barHeight)
    }
}

/// An alert on a display without a notch: Peeku hangs from its icon and holds it.
private struct MenuBarAlert: View {
    var body: some View {
        let clock = ManualScheduler(start: Date())
        let machine = PhaseMachine(scheduler: clock)
        machine.update(sessions: MockSessions.calm(now: clock.now))
        Snapshots.scenarios.first { $0.0 == "alert-permission" }?.1(machine, clock)
        return ZStack(alignment: .top) {
            MenuBarStrip(height: MenuBarStates.notch.barHeight)
            MenuBarItems(icon: .init(mood: .permission, count: 1), width: 760)
            IslandView(machine: machine, notch: MenuBarStates.notch, menuBar: MenuBarAnchor(offset: MenuBarStates.iconOffset), forceLight: false)
        }
        .frame(width: 760, height: 330, alignment: .top)
    }
}

/// GitHub's social preview. Laid out at 1280×640 with the real island scaled up to fill its half,
/// then halved so the 2× render comes out 1280×640. Text keeps an 80pt margin for link-card crops.
private struct SocialPreview: View {
    var body: some View {
        let clock = ManualScheduler(start: Date())
        let machine = PhaseMachine(scheduler: clock)
        machine.update(sessions: MockSessions.calm(now: clock.now))
        Snapshots.trigger(.multiple, machine, clock)
        clock.advance(by: 1.5)

        return ZStack(alignment: .top) {
            Desktop()
            MenuBarStrip()

            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 24) {
                        AppIconView().scaleEffect(128 / AppIconView.canvas).frame(width: 128, height: 128)
                        Text("Peeku").font(.peeku(92, .bold)).foregroundStyle(Tokens.textPrimary)
                    }
                    Text("A tiny companion in your notch that tells you when a Claude Code or Codex session needs you.")
                        .font(.peeku(34, .medium))
                        .foregroundStyle(Color.label(0.7))
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("macOS 14+  ·  Swift  ·  MIT")
                        .font(.peekuMono(22, .medium))
                        .foregroundStyle(Color.label(0.45))
                }
                .frame(width: 560, alignment: .leading)
                .padding(.leading, 80)
                .padding(.top, 32)

                IslandView(machine: machine, notch: .fallback, forceLight: false)
                    .scaleEffect(1.3, anchor: .top)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(width: 1280, height: 640)
        .clipped()
        .scaleEffect(0.5)
        .frame(width: 640, height: 320)
    }
}
