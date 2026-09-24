import NudgeKit
import SwiftUI

/// Nudge's settings, as a native grouped form that follows the system appearance.
struct SettingsView: View {
    let model: SettingsModel

    var body: some View {
        Form {
            general
            notifications
            environments
            claudeCode
            shortcuts
            uninstall
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
    }

    // MARK: Sections

    @AppStorage(PanelAppearance.defaultsKey) private var appearance = PanelAppearance.automatic.rawValue

    private var general: some View {
        Section {
            Picker(selection: $appearance) {
                ForEach(PanelAppearance.allCases) { Text($0.title).tag($0.rawValue) }
            } label: {
                Text("Appearance")
                Text("Alerts and the session manager. The notch itself is always black.")
            }
            Toggle("Open Nudge at login", isOn: Binding(
                get: { model.loginItem == .on || model.loginItem == .needsApproval },
                set: { model.setLaunchAtLogin($0) }
            ))
            .disabled(model.loginItem == .unavailable)
            if model.loginItem == .needsApproval {
                HStack {
                    Text("Allow Nudge in Login Items to finish turning this on.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Login Items…") { LoginItem.openSettings() }
                }
                .font(.callout)
            }
            if model.loginItem == .unavailable {
                Text("Available when Nudge runs as an app, not from `swift run`.").font(.callout).foregroundStyle(.secondary)
            }
            if let error = model.loginError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            LabeledContent {
                Button("Check Now") { model.updater?.checkForUpdates() }
                    .disabled(!(model.updater?.canCheck ?? false))
            } label: {
                Toggle(isOn: Binding(get: { model.checksForUpdates }, set: { model.setChecksForUpdates($0) })) {
                    Text("Check for updates automatically")
                    Text(updateDetail)
                }
                .disabled(!(model.updater?.isAvailable ?? false))
            }
        } header: {
            Text("General")
        }
    }

    private var notifications: some View {
        Section {
            Toggle(isOn: Binding(get: { model.autoCollapse }, set: { model.setAutoCollapse($0) })) {
                Text("Fold alerts after 8 seconds")
                Text("An unanswered alert shrinks to a small pill in the notch.")
            }
            Toggle(isOn: Binding(get: { model.popUpOnFinish }, set: { model.setPopUpOnFinish($0) })) {
                Text("Pop up when a session finishes")
                Text("Otherwise Nudge gives a 3-second wink in the notch.")
            }
            Toggle(isOn: Binding(get: { model.quietInView }, set: { model.setQuietInView($0) })) {
                Text("Stay quiet for the session in front")
                Text("No pop-up or sound when the session's tab or window is the one you're using. The count still updates.")
            }
            LabeledContent {
                Button("Edit in Usage Tab") { model.onEditUsageAlerts?() }
            } label: {
                Text("Usage alerts")
                Text(usageAlertsDetail)
            }
            Toggle(isOn: Binding(get: { model.soundsEnabled }, set: { model.setSoundsEnabled($0) })) {
                Text("Play sounds")
                Text("When a session starts waiting or finishes, or usage is high. Silent during Quiet.")
            }
            if model.soundsEnabled {
                ForEach(Chime.allCases, id: \.self) { chime in
                    Picker(chime.title, selection: Binding(
                        get: { model.sounds[chime] ?? nil },
                        set: { model.setSound($0, for: chime) }
                    )) {
                        Text("None").tag(String?.none)
                        Divider()
                        ForEach(Sounds.names, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                    .padding(.leading, 16)
                }
            }
            LabeledContent {
                if model.quietUntil != nil {
                    Button("Resume") { model.setQuiet(for: nil) }
                } else {
                    Menu("Quiet…") {
                        Button("For 1 Hour") { model.setQuiet(for: 3600) }
                        Button("For 3 Hours") { model.setQuiet(for: 3 * 3600) }
                    }
                    .fixedSize()
                }
            } label: {
                Text("Quiet")
                if let until = model.quietUntil {
                    Text("No pop-ups until \(until.formatted(date: Calendar.current.isDateInToday(until) ? .omitted : .abbreviated, time: .shortened)). The count still updates.")
                } else {
                    Text("Also automatic in full screen and while Zoom shares your screen.")
                }
            }
        } header: {
            Text("Notifications")
        }
    }

    private var environments: some View {
        Section {
            ForEach(model.setup.environments) { environment in
                Toggle(isOn: Binding(get: { environment.enabled }, set: { _ in model.setup.toggle(environment.host) })) {
                    Text(environment.host.onboardingName)
                    Text(environment.detail)
                }
            }
        } header: {
            Text("Watch sessions in")
        }
    }

    private var claudeCode: some View {
        Section {
            LabeledContent {
                switch model.setup.hooks {
                case .installed: Button("Remove…") { model.setup.removeHooks() }
                case .incomplete: Button("Update") { model.setup.installHooks() }
                case .notInstalled: Button("Install") { model.setup.installHooks() }
                }
            } label: {
                Label { Text("Claude Code hooks") } icon: { AgentMark(agent: .claude, size: 13) }
                Text(hooksDetail)
            }
            if let codex = model.setup.codexHooks {
                LabeledContent {
                    switch codex {
                    case .installed: Button("Remove…") { model.setup.removeHooks(.codex) }
                    case .incomplete: Button("Update") { model.setup.installHooks(.codex) }
                    case .notInstalled: Button("Install") { model.setup.installHooks(.codex) }
                    }
                } label: {
                    Label { Text("Codex hooks") } icon: { AgentMark(agent: .codex, size: 13) }
                    Text(codex == .installed
                         ? "Installed in \(model.setup.settingsPath(.codex)). In Codex, trust them once with /hooks."
                         : codex == .incomplete ? "Some hooks are missing or out of date." : "Lets Nudge see Codex sessions and why they wait.")
                }
            }
            LabeledContent {
                switch model.setup.claudeUsage {
                case .installed: Button("Remove…") { model.setup.removeClaudeUsage() }
                case .incomplete: Button("Update") { model.setup.setUpClaudeUsage() }
                case .notInstalled: Button("Set Up…") { model.setup.setUpClaudeUsage() }
                }
            } label: {
                Label { Text("Claude usage") } icon: { AgentMark(agent: .claude, size: 13) }
                Text(model.setup.claudeUsage == .notInstalled
                     ? "Shows your 5-hour and weekly limits in the Usage tab. Reads them through Claude Code's status line."
                     : "Read through Claude Code's status line. Your own status line, if you had one, still runs.")
            }
            LabeledContent {
                if model.setup.accessibility {
                    Label("Allowed", systemImage: "checkmark").foregroundStyle(.secondary)
                } else {
                    HStack {
                        Button("Reset…") { model.setup.resetPermissions() }
                        Button("Allow…") { model.setup.allowAccessibility() }
                    }
                }
            } label: {
                Text("Accessibility")
                Text(model.setup.accessibility
                     ? "Raises the exact window and draws the focus ring."
                     : "Already switched on in System Settings but not working? That entry is for an older Nudge: Reset clears it and asks again.")
            }
            LabeledContent {
                switch model.setup.automation {
                case .granted: Label("Allowed", systemImage: "checkmark").foregroundStyle(.secondary)
                case .needsAsk: Button("Allow…") { model.setup.allowAutomation() }
                case .denied: Button("Open Settings…") { model.setup.allowAutomation() }
                case .asksOnFirstUse: Text("Asks on first use").foregroundStyle(.secondary)
                }
            } label: {
                Text("Automation")
                Text("Switches iTerm and Terminal tabs.")
            }
        } header: {
            Text(model.setup.codexHooks == nil ? "Claude Code" : "Agents")
        } footer: {
            Text("Nudge only reads session state. It never types into your terminal or approves anything on your behalf.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var uninstall: some View {
        Section {
            LabeledContent {
                Button("Uninstall…", role: .destructive) { Uninstaller.confirmAndUninstall() }
            } label: {
                Text("Uninstall Nudge")
                Text("Removes its hooks, history, data and login item, then moves Nudge to the Trash.")
            }
        }
    }

    private var shortcuts: some View {
        Section {
            shortcut("Session manager", "⌥⌘.")
            shortcut("Next waiting agent", "⌥⌘↓")
            shortcut("Open the focused session", "↵")
            shortcut("Fold the alert", "Esc")
            shortcut("Open row 1–9", "⌘1–9")
        } header: {
            Text("Shortcuts")
        } footer: {
            Text("↵, Esc and ⌘1–9 work once the notch has focus: click it, or use ⌥⌘. or ⌥⌘↓.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Pieces

    private var updateDetail: String {
        guard model.updater?.isAvailable == true else { return "Available when Nudge runs as an app." }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        guard let last = model.lastUpdateCheck else { return "Nudge \(version). Updates come from GitHub releases." }
        return "Nudge \(version). Last checked \(last.formatted(.relative(presentation: .named)))."
    }

    /// "Claude at 75% · Claude and Codex at 90%", or how to add one.
    private var usageAlertsDetail: String {
        guard !model.usageAlertRules.isEmpty else { return "None. Add one to hear when a Claude or Codex limit gets close." }
        return model.usageAlertRules.map { "\($0.scope.title) at \($0.threshold)%" }.joined(separator: " · ")
    }

    private var hooksDetail: String {
        switch model.setup.hooks {
        case .installed: "Installed in \(model.setup.settingsPath). Nudge sees why sessions wait."
        case .incomplete: "Some hooks are missing or out of date."
        case .notInstalled: "Without them Nudge lists sessions but can't say why they wait."
        }
    }

    private func shortcut(_ title: String, _ keys: String) -> some View {
        LabeledContent(title) {
            Text(keys).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
        }
    }
}
