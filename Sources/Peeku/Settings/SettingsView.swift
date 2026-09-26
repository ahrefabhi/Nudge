import PeekuKit
import SwiftUI

/// Peeku's settings, inside the manager: the gear at its top right swaps the panel to this view.
/// Drawn with the panel's own palette, so it matches the island in dark and the light panel.
struct SettingsView: View {
    @Environment(\.palette) private var palette
    @Environment(\.peekuStill) private var still
    let model: SettingsModel

    var body: some View {
        SnapshotSafeScrollView {
            VStack(alignment: .leading, spacing: 0) {
                general
                notifications
                utilities
                environments
                agents
                shortcuts
                uninstall
            }
            .padding(EdgeInsets(top: 4, leading: 8, bottom: 12, trailing: 8))
        }
        // Snapshots keep the apps and hooks they were given instead of reading this Mac's.
        .onAppear { if !still { model.start() } }
        .onDisappear { if !still { model.stop() } }
    }

    // MARK: Sections

    @AppStorage(PanelAppearance.defaultsKey) private var appearance = PanelAppearance.automatic.rawValue
    @AppStorage(SpendFormat.showCostKey) private var showCost = true

    private var general: some View {
        SettingsSection("GENERAL") {
            SettingsRow("Appearance", "Alerts and the session manager. The notch itself is always black.") {
                HStack(spacing: 0) {
                    ForEach(PanelAppearance.allCases) { option in
                        SettingsSegment(title: option.shortTitle, selected: appearance == option.rawValue) { appearance = option.rawValue }
                    }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 7).fill(palette.fill(0.07)))
            }
            SettingsRow("Show Peeku in", "Macs without a notch always use the menu bar. There, Peeku lives in its icon and hangs from it when an agent needs you.") {
                HStack(spacing: 0) {
                    SettingsSegment(title: "Notch", selected: !model.prefersMenuBar) { model.setPrefersMenuBar(false) }
                    SettingsSegment(title: "Menu Bar", selected: model.prefersMenuBar) { model.setPrefersMenuBar(true) }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 7).fill(palette.fill(0.07)))
            }
            SettingsRow("Open Peeku at login", loginDetail) {
                SettingsSwitch(isOn: model.loginItem == .on || model.loginItem == .needsApproval) { model.setLaunchAtLogin($0) }
                    .disabled(model.loginItem == .unavailable)
            }
            if model.loginItem == .needsApproval {
                SettingsRow("Needs approval", "Allow Peeku in Login Items to finish turning this on.") {
                    SettingsButton("Open Login Items…") { model.presentingDialog { LoginItem.openSettings() } }
                }
            }
            SettingsRow("Check for updates automatically", updateDetail) {
                HStack(spacing: 8) {
                    SettingsButton("Check Now") { model.presentingDialog { model.updater?.checkForUpdates() } }
                        .disabled(!(model.updater?.canCheck ?? false))
                    SettingsSwitch(isOn: model.checksForUpdates) { model.setChecksForUpdates($0) }
                        .disabled(!(model.updater?.isAvailable ?? false))
                }
            }
        }
    }

    private var notifications: some View {
        SettingsSection("NOTIFICATIONS") {
            SettingsRow("Fold alerts after 8 seconds", "An unanswered alert shrinks to a small pill in the notch.") {
                SettingsSwitch(isOn: model.autoCollapse) { model.setAutoCollapse($0) }
            }
            SettingsRow("Pop up when a session finishes", "Otherwise Peeku gives a 3-second wink in the notch.") {
                SettingsSwitch(isOn: model.popUpOnFinish) { model.setPopUpOnFinish($0) }
            }
            SettingsRow("Stay quiet for the session in front", "No pop-up or sound when its tab or window is the one you're using.") {
                SettingsSwitch(isOn: model.quietInView) { model.setQuietInView($0) }
            }
            SettingsRow("Usage alerts", usageAlertsDetail) {
                SettingsButton("Edit in Usage") { model.onEditUsageAlerts?() }
            }
            SettingsRow("Show costs", "Dollars at API prices in Usage and beside each session. Off shows tokens only.") {
                SettingsSwitch(isOn: showCost) { showCost = $0 }
            }
            SettingsRow("Play sounds", "When a session starts waiting or finishes, or usage is high. Silent during Quiet.") {
                SettingsSwitch(isOn: model.soundsEnabled) { model.setSoundsEnabled($0) }
            }
            if model.soundsEnabled {
                ForEach(Chime.allCases, id: \.self) { chime in
                    SettingsRow(chime.title, nil, indented: true) {
                        SettingsMenu(title: model.sounds[chime].flatMap { $0 } ?? "None") {
                            Button("None") { model.setSound(nil, for: chime) }
                            Divider()
                            ForEach(Sounds.names, id: \.self) { name in
                                Button(name) { model.setSound(name, for: chime) }
                            }
                        }
                    }
                }
            }
            SettingsRow("Quiet", quietDetail) {
                if model.quietUntil != nil {
                    SettingsButton("Resume") { model.setQuiet(for: nil) }
                } else {
                    SettingsMenu(title: "Quiet…") {
                        Button("For 1 Hour") { model.setQuiet(for: 3600) }
                        Button("For 3 Hours") { model.setQuiet(for: 3 * 3600) }
                    }
                }
            }
        }
    }

    private var utilities: some View {
        SettingsSection("UTILITIES", footer: "Utilities sit in the footer dock, never in the tabs at the top.") {
            SettingsRow("Commands", "Save commands like npm run dev, then run, restart and stop them from the dock.") {
                SettingsSwitch(isOn: model.commandsEnabled) { model.setCommandsEnabled($0) }
            }
        }
    }

    private var environments: some View {
        SettingsSection("WATCH SESSIONS IN") {
            ForEach(model.setup.environments) { environment in
                SettingsRow(environment.name, environment.detail) {
                    SettingsSwitch(isOn: environment.enabled) { _ in model.setup.toggle(environment.id) }
                }
            }
        }
    }

    private var agents: some View {
        SettingsSection(model.setup.codexHooks == nil ? "CLAUDE CODE" : "AGENTS",
                        footer: "Peeku only reads session state. It never types into your terminal or approves anything on your behalf.") {
            SettingsRow("Claude Code hooks", hooksDetail, agent: .claude) {
                switch model.setup.hooks {
                case .installed: SettingsButton("Remove…") { model.presentingDialog { model.setup.removeHooks() } }
                case .incomplete: SettingsButton("Update") { model.setup.installHooks() }
                case .notInstalled: SettingsButton("Install", primary: true) { model.setup.installHooks() }
                }
            }
            if let codex = model.setup.codexHooks {
                SettingsRow("Codex hooks", codexDetail(codex), agent: .codex) {
                    switch codex {
                    case .installed: SettingsButton("Remove…") { model.presentingDialog { model.setup.removeHooks(.codex) } }
                    case .incomplete: SettingsButton("Update") { model.setup.installHooks(.codex) }
                    case .notInstalled: SettingsButton("Install", primary: true) { model.setup.installHooks(.codex) }
                    }
                }
            }
            SettingsRow("Claude usage", claudeUsageDetail, agent: .claude) {
                switch model.setup.claudeUsage {
                case .installed: SettingsButton("Remove…") { model.presentingDialog { model.setup.removeClaudeUsage() } }
                case .incomplete: SettingsButton("Update") { model.presentingDialog { model.setup.setUpClaudeUsage() } }
                case .notInstalled: SettingsButton("Set Up…") { model.presentingDialog { model.setup.setUpClaudeUsage() } }
                }
            }
            SettingsRow("Accessibility", model.setup.accessibility
                        ? "Raises the exact window and draws the focus ring."
                        : "Already on in System Settings but not working? That entry is for an older Peeku: Reset clears it and asks again.") {
                if model.setup.accessibility {
                    AllowedLabel()
                } else {
                    HStack(spacing: 6) {
                        SettingsButton("Reset…") { model.presentingDialog { model.setup.resetPermissions() } }
                        SettingsButton("Allow…", primary: true) { model.presentingDialog { model.setup.allowAccessibility() } }
                    }
                }
            }
            SettingsRow("Automation", "Switches iTerm and Terminal tabs.") {
                switch model.setup.automation {
                case .granted: AllowedLabel()
                case .needsAsk: SettingsButton("Allow…", primary: true) { model.presentingDialog { model.setup.allowAutomation() } }
                case .denied: SettingsButton("Open Settings…") { model.presentingDialog { model.setup.allowAutomation() } }
                case .asksOnFirstUse:
                    Text("Asks on first use").font(.peeku(11.5)).foregroundStyle(palette.label(0.45))
                }
            }
        }
    }

    private var shortcuts: some View {
        SettingsSection("SHORTCUTS", footer: "↵, Esc and the rest work once the notch has focus: click it, or use ⌥⌘. or ⌥⌘↓.") {
            shortcut("Agents", "⌥⌘.")
            shortcut("Now, History or Usage", "⌥⌘. then 1–3")
            shortcut("Commands", "⌥⌘,")
            shortcut("Next waiting agent", "⌥⌘↓")
            shortcut("Open the focused session", "↵")
            shortcut("Fold the alert, or back to Agents", "Esc")
            shortcut("Open row 1–9", "⌘1–9")
        }
    }

    private var uninstall: some View {
        SettingsSection(nil) {
            SettingsRow("Uninstall Peeku", "Removes its hooks, history, data and login item, then moves Peeku to the Trash.") {
                SettingsButton("Uninstall…", destructive: true) { model.presentingDialog { Uninstaller.confirmAndUninstall() } }
            }
        }
    }

    // MARK: Pieces

    private var loginDetail: String? {
        if let error = model.loginError { return error }
        if model.loginItem == .unavailable { return "Available when Peeku runs as an app, not from swift run." }
        return nil
    }

    private var updateDetail: String {
        guard model.updater?.isAvailable == true else { return "Available when Peeku runs as an app." }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        guard let last = model.lastUpdateCheck else { return "Peeku \(version). Updates come from GitHub releases." }
        return "Peeku \(version). Last checked \(last.formatted(.relative(presentation: .named)))."
    }

    /// "Claude at 75% · Claude and Codex at 90%", or how to add one.
    private var usageAlertsDetail: String {
        guard !model.usageAlertRules.isEmpty else { return "None. Add one to hear when a Claude or Codex limit gets close." }
        return model.usageAlertRules.map { "\($0.scope.title) at \($0.threshold)%" }.joined(separator: " · ")
    }

    private var quietDetail: String {
        guard let until = model.quietUntil else { return "Also automatic in full screen and while Zoom shares your screen." }
        let time = until.formatted(date: Calendar.current.isDateInToday(until) ? .omitted : .abbreviated, time: .shortened)
        return "No pop-ups until \(time). The count still updates."
    }

    private var hooksDetail: String {
        switch model.setup.hooks {
        case .installed: "Installed in \(model.setup.settingsPath). Peeku sees why sessions wait."
        case .incomplete: "Some hooks are missing or out of date."
        case .notInstalled: "Without them Peeku lists sessions but can't say why they wait."
        }
    }

    private func codexDetail(_ status: HookInstaller.Status) -> String {
        switch status {
        case .installed: "Installed in \(model.setup.settingsPath(.codex)). In Codex, trust them once with /hooks."
        case .incomplete: "Some hooks are missing or out of date."
        case .notInstalled: "Lets Peeku see Codex sessions and why they wait."
        }
    }

    private var claudeUsageDetail: String {
        model.setup.claudeUsage == .notInstalled
            ? "Shows your 5-hour and weekly limits in Usage. Reads them through Claude Code's status line."
            : "Read through Claude Code's status line. Your own status line, if you had one, still runs."
    }

    private func shortcut(_ title: String, _ keys: String) -> some View {
        SettingsRow(title, nil) {
            Text(keys).font(.peekuMono(11)).foregroundStyle(palette.label(0.5))
        }
    }
}

// MARK: Building blocks

/// A section label, its rows on a faint card, and an optional note under it.
private struct SettingsSection<Content: View>: View {
    let title: String?
    var footer: String?
    @ViewBuilder let content: Content
    @Environment(\.palette) private var palette

    init(_ title: String?, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                SectionLabel(title: title).padding(EdgeInsets(top: 14, leading: 12, bottom: 6, trailing: 12))
            } else {
                Spacer().frame(height: 14)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 12).fill(palette.fill(0.045)))
            if let footer {
                Text(footer)
                    .font(.peeku(11))
                    .lineSpacing(2)
                    .foregroundStyle(palette.label(0.4))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(EdgeInsets(top: 6, leading: 12, bottom: 0, trailing: 12))
            }
        }
    }
}

/// A title and its explanation on the left, the control on the right.
private struct SettingsRow<Control: View>: View {
    let title: String
    let detail: String?
    var agent: Agent?
    var indented = false
    @ViewBuilder let control: Control
    @Environment(\.palette) private var palette

    init(_ title: String, _ detail: String?, agent: Agent? = nil, indented: Bool = false, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.agent = agent
        self.indented = indented
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let agent { AgentMark(agent: agent, size: 11) }
                    Text(title)
                        .font(.peeku(12.5, indented ? .regular : .medium))
                        .foregroundStyle(indented ? palette.label(0.7) : palette.primary)
                }
                if let detail {
                    Text(detail)
                        .font(.peeku(11))
                        .lineSpacing(1.5)
                        .foregroundStyle(palette.label(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, indented ? 14 : 0)
            Spacer(minLength: 8)
            control.fixedSize()
                .environment(\.settingsRowTitle, title)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
    }
}

/// A small switch drawn in the panel's colors, since the system one greys out while Peeku
/// isn't the active app.
private struct SettingsSwitch: View {
    let isOn: Bool
    let set: (Bool) -> Void
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.settingsRowTitle) private var title

    var body: some View {
        Button { set(!isOn) } label: {
            Capsule()
                .fill(isOn ? palette.buttonBackground : palette.fill(0.16))
                .frame(width: 28, height: 16)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isOn ? palette.buttonText : palette.isLight ? Color.white : palette.label(0.8))
                        .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                        .padding(2)
                }
                .animation(.easeOut(duration: 0.15), value: isOn)
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// A small pill button. `primary` fills it; `destructive` tints it red.
private struct SettingsButton: View {
    let title: String
    var primary = false
    var destructive = false
    let action: () -> Void
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    init(_ title: String, primary: Bool = false, destructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.primary = primary
        self.destructive = destructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.peeku(11.5, .medium))
                .foregroundStyle(primary ? palette.buttonText : destructive ? palette.accent(.error) : palette.primary)
                .padding(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                .background(Capsule().fill(primary ? (hovering ? palette.buttonHover : palette.buttonBackground)
                                                   : palette.fill(hovering ? 0.14 : 0.09)))
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A pop-up menu that looks like a `SettingsButton` with a chevron.
private struct SettingsMenu<Items: View>: View {
    let title: String
    @ViewBuilder let items: Items
    @Environment(\.palette) private var palette

    var body: some View {
        Menu { items } label: {
            HStack(spacing: 5) {
                Text(title)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .font(.peeku(11.5, .medium))
            .foregroundStyle(palette.primary)
            .padding(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 9))
            .background(Capsule().fill(palette.fill(0.09)))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

/// One option of the appearance control, like the manager's tabs.
private struct SettingsSegment: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.peeku(11))
            .padding(.vertical, 2).padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 5).fill(palette.fill(selected ? 0.14 : 0)))
            .foregroundStyle(selected ? palette.primary : palette.label(0.5))
            .contentShape(Rectangle())
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct AllowedLabel: View {
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark").font(.system(size: 9.5, weight: .bold))
            Text("Allowed")
        }
        .font(.peeku(11.5))
        .foregroundStyle(palette.accent(.finished))
    }
}

extension EnvironmentValues {
    /// The row a control sits in, so VoiceOver can name a switch after it.
    @Entry var settingsRowTitle = ""
}

extension PanelAppearance {
    /// For the three-way control in Settings.
    var shortTitle: String {
        switch self {
        case .automatic: "System"
        case .dark: "Dark"
        case .light: "Light"
        }
    }
}
