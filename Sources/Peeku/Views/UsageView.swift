import PeekuKit
import SwiftUI

/// The manager's third tab: how much of each agent's rate limits is used, and when they reset,
/// plus the alerts that say when one gets close. Peeku asks each agent every few minutes, and the
/// status line and session logs fill in between, so each agent says how old its numbers are.
struct UsageView: View {
    let machine: PhaseMachine
    /// Opens with the new-alert editor showing, and a typed percentage, for snapshots.
    var adding = false
    var custom = ""

    var body: some View {
        SnapshotSafeScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(machine.usage) { usage in
                    AgentUsageSection(usage: usage) { machine.onSetUpUsage?(usage.agent) }
                }
                UsageAlertsSection(machine: machine, adding: adding, custom: custom)
            }
            .padding(EdgeInsets(top: 4, leading: 8, bottom: 10, trailing: 8))
        }
    }
}

private struct AgentUsageSection: View {
    @Environment(\.palette) private var palette
    let usage: AgentUsage
    let onSetUp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(EdgeInsets(top: 14, leading: 12, bottom: 6, trailing: 12))
            if let report = usage.report {
                ForEach(report.windows) { WindowRow(window: $0) }
            } else {
                Text(emptyText)
                    .font(.peeku(12))
                    .foregroundStyle(palette.label(0.45))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.vertical, 6)
            }
            if usage.source == .needsSetup {
                Button("Set Up…", action: onSetUp)
                    .buttonStyle(PrimaryPillStyle(fontSize: 11.5, padding: EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)))
                    .padding(.horizontal, 12).padding(.vertical, 6)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            AgentMark(agent: usage.agent, size: 11)
                .foregroundStyle(palette.label(0.6))
            SectionLabel(title: usage.agent.productName.uppercased())
            if let plan = usage.report?.plan {
                Text(plan.capitalized)
                    .font(.peeku(10))
                    .foregroundStyle(palette.label(0.55))
                    .padding(.vertical, 1).padding(.horizontal, 5)
                    .background(RoundedRectangle(cornerRadius: 4).fill(palette.fill(0.08)))
            }
            Spacer()
            if let report = usage.report {
                LiveText { "Updated \(RelativeTime.ago(since: report.observedAt, now: $0))" }
                    .font(.peeku(10.5))
                    .foregroundStyle(palette.label(0.38))
            }
        }
    }

    private var emptyText: String {
        switch (usage.agent, usage.source) {
        case (.claude, .needsSetup): "Couldn't ask Claude Code for your limits. Peeku can also read them from its status line."
        case (.claude, .unavailable): "Claude Code says this account has no rate limits to report."
        case (.claude, .waitingForStatusLine):
            "Waiting for Claude Code to run its status line. Only Claude Code in a terminal has one: start or restart a session in iTerm or Terminal. The VS Code extension and the Claude app don't."
        case (.claude, _):
            "Claude Code runs Peeku's status line but hasn't included usage. It shares usage only on Pro and Max plans, and only after a session's first reply."
        case (.codex, _): "Codex didn't answer. Its limits show up after your next Codex message."
        }
    }
}

/// The user's usage alerts: one row each, and an inline editor to add another. Buttons and a text
/// field only, since menus and pickers open windows of their own that the notch panel reads as a
/// click outside.
private struct UsageAlertsSection: View {
    @Environment(\.palette) private var palette
    let machine: PhaseMachine
    @State private var adding: Bool
    @State private var scope = UsageAlertRule.Scope.both
    @State private var preset = 90
    /// A typed percentage. While it has text, it's the threshold instead of the preset.
    @State private var custom: String
    @FocusState private var customFocused: Bool

    init(machine: PhaseMachine, adding: Bool = false, custom: String = "") {
        self.machine = machine
        _adding = State(initialValue: adding)
        _custom = State(initialValue: custom)
    }

    /// The chosen threshold, or nil while the typed one isn't 1 to 100.
    private var threshold: Int? {
        guard !custom.isEmpty else { return preset }
        return Int(custom).flatMap { UsageAlertRule.validThresholds.contains($0) ? $0 : nil }
    }

    /// Codex choices only make sense once Codex is installed.
    private var hasCodex: Bool { machine.usage.contains { $0.agent == .codex } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel(title: "ALERTS")
                Spacer()
                if !adding {
                    Button("Add Alert") { startAdding() }
                        .buttonStyle(LinkTextStyle())
                }
            }
            .padding(EdgeInsets(top: 18, leading: 12, bottom: 6, trailing: 12))

            if machine.usageAlertRules.isEmpty && !adding {
                Text("No alerts. Add one to hear when Claude or Codex gets close to a limit.")
                    .font(.peeku(12))
                    .foregroundStyle(palette.label(0.45))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.vertical, 4)
            }
            ForEach(machine.usageAlertRules) { rule in
                RuleRow(rule: rule) { machine.removeUsageAlertRule(rule.id) }
            }
            if adding { editor }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasCodex {
                option("Agent") {
                    ForEach(UsageAlertRule.Scope.allCases, id: \.self) { value in
                        Button(value == .both ? "Both" : value.title) { scope = value }
                            .buttonStyle(ChipStyle(selected: scope == value))
                    }
                }
            }
            option("At") {
                ForEach(UsageAlertRule.thresholds, id: \.self) { value in
                    Button("\(value)%") {
                        preset = value
                        custom = ""
                        customFocused = false
                    }
                    .buttonStyle(ChipStyle(selected: custom.isEmpty && preset == value))
                }
                customField
            }
            HStack(spacing: 8) {
                Button("Add", action: add)
                    .buttonStyle(PrimaryPillStyle(fontSize: 11.5, padding: EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12)))
                    .disabled(threshold == nil)
                    .opacity(threshold == nil ? 0.4 : 1)
                Button("Cancel") { adding = false }
                    .buttonStyle(LinkTextStyle())
            }
            Text(threshold == nil ? "Enter a percentage from 1 to 100."
                 : "Alerts once for each limit, like the 5-hour or weekly one, then waits until it resets.")
                .font(.peeku(11))
                .foregroundStyle(threshold == nil ? palette.accent(.error) : palette.label(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(palette.fill(0.05)))
        .padding(.horizontal, 6).padding(.top, 4)
    }

    /// A chip you type into. Digits only, up to three.
    private var customField: some View {
        let active = !custom.isEmpty || customFocused
        return HStack(spacing: 1) {
            TextField("Custom", text: $custom)
                .textFieldStyle(.plain)
                .focused($customFocused)
                .multilineTextAlignment(.trailing)
                .frame(width: custom.isEmpty ? 46 : 24)
                .onChange(of: custom) { _, typed in
                    let digits = String(typed.filter(\.isNumber).prefix(3))
                    if digits != typed { custom = digits }
                }
                .onSubmit { if threshold != nil { add() } }
            if !custom.isEmpty { Text("%") }
        }
        .font(.peeku(11.5))
        .foregroundStyle(active ? palette.primary : palette.label(0.6))
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background(Capsule().fill(palette.fill(active ? 0.14 : 0.05)))
        .accessibilityLabel("Custom percentage")
    }

    private func add() {
        guard let threshold else { return }
        machine.addUsageAlertRule(scope: hasCodex ? scope : .claude, threshold: threshold)
        adding = false
    }

    private func option<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.peeku(11.5))
                .foregroundStyle(palette.label(0.5))
                .frame(width: 40, alignment: .leading)
            content()
        }
    }

    private func startAdding() {
        scope = hasCodex ? .both : .claude
        preset = 90
        custom = ""
        adding = true
    }
}

private struct RuleRow: View {
    @Environment(\.palette) private var palette
    let rule: UsageAlertRule
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                if rule.scope != .codex { AgentMark(agent: .claude, size: 11) }
                if rule.scope != .claude { AgentMark(agent: .codex, size: 11) }
            }
            .foregroundStyle(palette.label(0.6))
            Text("\(rule.scope.title) at \(rule.threshold)%")
                .font(.peeku(12.5))
                .foregroundStyle(palette.primary)
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.label(0.4))
            .accessibilityLabel("Remove alert")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
    }
}

private struct WindowRow: View {
    @Environment(\.palette) private var palette
    let window: UsageWindow

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let reset = window.hasReset(now: context.date)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(window.title)
                        .font(.peeku(13, .semibold))
                        .foregroundStyle(palette.primary)
                    Spacer()
                    Text(reset ? "—" : "\(Int(window.usedPercent.rounded()))%")
                        .font(.peekuMono(12))
                        .foregroundStyle(reset ? palette.label(0.4) : palette.primary)
                }
                Bar(fraction: reset ? 0 : window.usedPercent / 100, color: color)
                Text(Self.resetText(window.resetsAt, reset: reset, now: context.date))
                    .font(.peeku(11))
                    .foregroundStyle(palette.label(0.45))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .accessibilityElement(children: .combine)
        }
    }

    /// Green, then amber from 70%, red from 90%.
    private var color: Color {
        switch window.usedPercent {
        case 90...: palette.accent(.error)
        case 70...: palette.accent(.permission)
        default: palette.accent(.finished)
        }
    }

    /// "Resets in 2h 14m", "Resets Tue 9:00 AM", or, once past, "Reset 12m ago · no reading since".
    static func resetText(_ date: Date?, reset: Bool, now: Date) -> String {
        guard let date else { return "Reset time unknown" }
        if reset { return "Reset \(RelativeTime.ago(since: date, now: now)) · no new reading yet" }
        let minutes = max(1, Int(date.timeIntervalSince(now) / 60))
        switch minutes {
        case ..<60: return "Resets in \(minutes)m"
        case ..<1440: return "Resets in \(minutes / 60)h \(minutes % 60)m"
        default: return "Resets " + date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
    }
}

private struct Bar: View {
    @Environment(\.palette) private var palette
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.fill(0.1))
                Capsule().fill(color).frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 5)
    }
}
