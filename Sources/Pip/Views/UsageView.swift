import PipKit
import SwiftUI

/// The manager's third tab: how much of each agent's rate limits is used, and when they reset.
/// Readings only update while a session runs, so each agent says how old its numbers are.
struct UsageView: View {
    let machine: PhaseMachine

    var body: some View {
        SnapshotSafeScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(machine.usage) { usage in
                    AgentUsageSection(usage: usage) { machine.onSetUpUsage?(usage.agent) }
                }
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
                    .font(.pip(12))
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
                    .font(.pip(10))
                    .foregroundStyle(palette.label(0.55))
                    .padding(.vertical, 1).padding(.horizontal, 5)
                    .background(RoundedRectangle(cornerRadius: 4).fill(palette.fill(0.08)))
            }
            Spacer()
            if let report = usage.report {
                LiveText { "Updated \(RelativeTime.ago(since: report.observedAt, now: $0))" }
                    .font(.pip(10.5))
                    .foregroundStyle(palette.label(0.38))
            }
        }
    }

    private var emptyText: String {
        switch (usage.agent, usage.source) {
        case (.claude, .needsSetup): "Claude Code shares your 5-hour and weekly limits only with its status line. Pip can read them from there."
        case (.claude, .waitingForStatusLine):
            "Waiting for Claude Code to run its status line. Only Claude Code in a terminal has one: start or restart a session in iTerm or Terminal. The VS Code extension and the Claude app don't."
        case (.claude, _):
            "Claude Code runs Pip's status line but hasn't included usage. It shares usage only on Pro and Max plans, and only after a session's first reply."
        case (.codex, _): "Shows up after your next Codex message."
        }
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
                        .font(.pip(13, .semibold))
                        .foregroundStyle(palette.primary)
                    Spacer()
                    Text(reset ? "—" : "\(Int(window.usedPercent.rounded()))%")
                        .font(.pipMono(12))
                        .foregroundStyle(reset ? palette.label(0.4) : palette.primary)
                }
                Bar(fraction: reset ? 0 : window.usedPercent / 100, color: color)
                Text(Self.resetText(window.resetsAt, reset: reset, now: context.date))
                    .font(.pip(11))
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
