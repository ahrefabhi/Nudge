import PeekuKit
import SwiftUI

/// Every session, dropped from the notch. Rows that need you carry an Open button; every other
/// row is one quiet line that still opens its session when clicked.
struct ManagerView: View {
    @Environment(\.palette) private var palette
    @Environment(\.peekuHangsAbove) private var hangsAbove
    let machine: PhaseMachine
    let bar: CGFloat
    var commands: CommandRunner?
    var skills: SkillManager?
    /// Nil in snapshots, which show the agent tabs only.
    var settings: SettingsModel?
    /// The machine owns the tab, so opening a usage alert can switch to Usage.
    private var tab: ManagerTab { machine.managerTab }

    var body: some View {
        let need = machine.queue.filter(\.needsYou)
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    // Hidden when Peeku hangs above the panel and when empty (the empty state has its own Peeku).
                    if !hangsAbove && !machine.sessions.isEmpty {
                        PeekuView(mood: headerMood(need), size: 22, flat: true, extras: false)
                    }
                    Text(need.isEmpty ? "Peeku" : "\(need.count) need\(need.count == 1 ? "s" : "") you")
                        .font(.peeku(12, .semibold))
                        .foregroundStyle(need.isEmpty ? palette.label(0.86) : palette.accent(.permission))
                        .lineLimit(1)
                }
                Spacer()
                if settings != nil {
                    SettingsGear(selected: tab == .settings) {
                        tab == .settings ? machine.showAgents() : machine.showSettings()
                    }
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 12)
            .frame(height: bar)

            // Its own row, below the camera: the tabs are wider than the space beside the notch.
            // Utilities and Settings swap it for their own header with a way back.
            Group {
                switch tab {
                case .commands:
                    UtilityHeader(title: "Commands", onBack: machine.showAgents) {
                        Button { commands?.onEdit?(nil) } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                                Text("New")
                            }
                        }
                        .buttonStyle(ChipStyle(selected: false))
                        .disabled(commands == nil)
                    }
                case .skills:
                    UtilityHeader(title: "Skills", onBack: machine.showAgents) {
                        Button { skills?.refresh() } label: {
                            HStack(spacing: 4) {
                                if skills?.loading == true {
                                    Spinner(size: 9)
                                } else {
                                    Image(systemName: "arrow.clockwise").font(.system(size: 9, weight: .bold))
                                }
                                Text("Refresh")
                            }
                        }
                        .buttonStyle(ChipStyle(selected: false))
                        .disabled(skills == nil || skills?.loading == true)
                    }
                case .settings:
                    UtilityHeader(title: "Settings", onBack: machine.showAgents) { EmptyView() }
                default:
                    segmented.frame(maxWidth: .infinity)
                }
            }
            .frame(height: IslandMetrics.managerTabRow)

            switch tab {
            case .now: nowList(need)
            case .history: HistoryView(machine: machine).frame(maxHeight: .infinity, alignment: .top)
            case .usage: UsageView(machine: machine).frame(maxHeight: .infinity, alignment: .top)
            case .commands: CommandsView(runner: commands).frame(maxHeight: .infinity, alignment: .top)
            case .skills: SkillsView(manager: skills).frame(maxHeight: .infinity, alignment: .top)
            case .settings:
                if let settings { SettingsView(model: settings).frame(maxHeight: .infinity, alignment: .top) }
            }

            if machine.dock.isEmpty { footer } else { dock }
        }
    }

    @ViewBuilder
    private func nowList(_ need: [PeekuSession]) -> some View {
        if machine.sessions.isEmpty {
            EmptyNow { host in
                host.launch()
                machine.tapOutside()
            }
        } else {
            sessionList(need)
        }
    }

    private func sessionList(_ need: [PeekuSession]) -> some View {
        SnapshotSafeScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !need.isEmpty {
                    SectionLabel(title: "NEEDS YOU").padding(EdgeInsets(top: 6, leading: 12, bottom: 4, trailing: 12))
                    ForEach(need) { NeedsYouRow(session: $0, spend: machine.spend.session($0.id), onOpen: open) }
                }
                if !machine.working.isEmpty {
                    SectionLabel(title: "WORKING").padding(EdgeInsets(top: 12, leading: 12, bottom: 4, trailing: 12))
                    ForEach(machine.working) { session in
                        QuietRow(session: session, spend: machine.spend.session(session.id), detail: session.activity ?? session.task, onOpen: open) {
                            Spinner(track: .fill(0.18), head: palette.accent(.finished), period: 1.1)
                        }
                    }
                }
                if !machine.finished.isEmpty {
                    SectionLabel(title: "FINISHED").padding(EdgeInsets(top: 12, leading: 12, bottom: 4, trailing: 12))
                    ForEach(machine.finished) { session in
                        QuietRow(session: session, spend: machine.spend.session(session.id), detail: session.task, dimmed: true, onOpen: open) { mark("✓", session) }
                    }
                }
                if !machine.idle.isEmpty {
                    SectionLabel(title: "IDLE").padding(EdgeInsets(top: 12, leading: 12, bottom: 4, trailing: 12))
                    ForEach(machine.idle) { session in
                        QuietRow(session: session, spend: machine.spend.session(session.id), detail: session.task, dimmed: true, onOpen: open) { mark("·", session) }
                    }
                }
            }
            .padding(.top, 10)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private func open(_ session: PeekuSession) { machine.open(session.id) }

    private func mark(_ symbol: String, _ session: PeekuSession) -> some View {
        Text(symbol).font(.peeku(11)).foregroundStyle(palette.accent(session.kind))
    }

    private func headerMood(_ need: [PeekuSession]) -> PeekuMood {
        switch need.count {
        case 0: .idle
        case 1: need[0].kind.mood
        default: .multiple
        }
    }

    private var segmented: some View {
        HStack(spacing: 0) {
            segment("Now", .now)
            segment("History", .history)
            segment("Usage", .usage)
        }
        .font(.peeku(11))
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(palette.fill(0.07)))
    }

    private func segment(_ title: String, _ value: ManagerTab) -> some View {
        Button(title) { machine.managerTab = value }
            .buttonStyle(.plain)
            .padding(.vertical, 2).padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 5).fill(palette.fill(tab == value ? 0.14 : 0)))
            .foregroundStyle(tab == value ? palette.primary : palette.label(0.5))
            .contentShape(Rectangle())
            .accessibilityAddTraits(tab == value ? .isSelected : [])
    }

    /// The footer as a small dock: Agents plus a button per utility. Clicking one swaps the
    /// whole panel, so the tabs at the top always mean "your agents".
    private var dock: some View {
        let running = commands?.activeCount ?? 0
        return HStack(spacing: 4) {
            DockButton(selected: tab.isAgentTab, label: "Agents", shortcut: .agents) { machine.showAgents() } icon: {
                PeekuView(mood: .working, size: 16, flat: true, extras: false)
            }
            if machine.dock.contains(.commands) {
                DockButton(selected: tab == .commands, label: "Commands", count: running, shortcut: .commands) { machine.managerTab = .commands } icon: {
                    Text(">_").font(.peekuMono(10.5, .semibold))
                }
            }
            if machine.dock.contains(.skills) {
                DockButton(selected: tab == .skills, label: "Skills", shortcut: .skills) { machine.managerTab = .skills } icon: {
                    Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold))
                }
            }
            Spacer()
            Text(Shortcuts.shared.label(.agents) ?? "").font(.peekuMono(11)).foregroundStyle(palette.label(0.4))
                .padding(.trailing, 8)
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 44)
        .overlay(alignment: .top) { Rectangle().fill(palette.hairline).frame(height: 1) }
    }

    private var footer: some View {
        let hosts = machine.sessions.map(\.hostName).reduce(into: [String]()) { names, name in
            if !names.contains(name) { names.append(name) }
        }
        let count = machine.sessions.count
        return HStack {
            Text(count == 0 ? "No agents running"
                 : "\(count) agent\(count == 1 ? "" : "s")" + (hosts.isEmpty ? "" : " · " + hosts.joined(separator: ", ")))
            Spacer()
            Text(Shortcuts.shared.label(.agents) ?? "").font(.peekuMono(11))
        }
        .font(.peeku(11))
        .foregroundStyle(palette.label(0.4))
        .padding(.horizontal, 20)
        .frame(height: 40)
        .overlay(alignment: .top) { Rectangle().fill(palette.hairline).frame(height: 1) }
    }
}

/// The gear at the manager's top right. Highlighted while Settings shows; clicking it again goes back.
private struct SettingsGear: View {
    let selected: Bool
    let action: () -> Void
    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected || hovering ? palette.primary : palette.label(0.55))
                .frame(width: 26, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(palette.fill(selected ? 0.14 : hovering ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Settings")
        .accessibilityLabel("Settings")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// "‹ Commands" with the view's primary action on the right, in place of the tabs.
private struct UtilityHeader<Action: View>: View {
    let title: String
    let onBack: () -> Void
    @ViewBuilder let action: Action
    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left").font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(hovering ? palette.primary : palette.label(0.55))
                    Text(title).font(.peeku(13, .semibold)).foregroundStyle(palette.primary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityLabel("Back to Agents")
            .accessibilityValue(title)
            Spacer()
            action
        }
        .padding(.horizontal, 18)
    }
}

/// One dock button: 26pt pill, filled while its view shows, with a green count while commands run.
private struct DockButton<Icon: View>: View {
    let selected: Bool
    let label: String
    var count = 0
    var shortcut: ShortcutAction?
    let action: () -> Void
    @ViewBuilder let icon: Icon
    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                icon
                Text(label).font(.peeku(11.5))
                if count > 0 {
                    Text("\(count)")
                        .font(.peeku(9.5, .bold))
                        .foregroundStyle(Tokens.pillBadgeText)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(Capsule().fill(palette.accent(.finished)))
                }
            }
            .foregroundStyle(selected || hovering ? palette.primary : palette.label(0.55))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(palette.fill(selected ? 0.14 : hovering ? 0.08 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help([label, shortcut.flatMap { Shortcuts.shared.label($0) }].compactMap { $0 }.joined(separator: "  "))
        .accessibilityLabel(count > 0 ? "\(label), \(count) running" : label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct NeedsYouRow: View {
    @Environment(\.palette) private var palette
    let session: PeekuSession
    let spend: SessionSpend?
    let onOpen: (PeekuSession) -> Void

    var body: some View {
        let accent = palette.accent(session.kind)
        HoverRow {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                    .background(Circle().fill(accent.opacity(0.22)).frame(width: 14, height: 14))
                    .frame(width: 16)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(session.project)
                            .font(.peeku(13, .semibold))
                            .foregroundStyle(palette.primary)
                        HStack(spacing: 4) {
                            SourceMark(session: session, size: 10)
                            Text(session.hostName)
                        }
                            .font(.peeku(10.5))
                            .foregroundStyle(palette.label(0.65))
                            .padding(.vertical, 1).padding(.horizontal, 6)
                            .background(RoundedRectangle(cornerRadius: 5).fill(palette.fill(0.08)))
                    }
                    (Text(session.kind.tag).foregroundStyle(accent) + Text(" · \(session.task)"))
                        .font(.peeku(12))
                        .foregroundStyle(palette.label(0.55))
                        .lineLimit(1)
                    if !SessionDetails.isEmpty(session, spend) { SessionDetails(session: session, spend: spend) }
                    if let quote = session.quote {
                        Text(quote)
                            .font(.peekuMono(11))
                            .foregroundStyle(palette.label(0.85))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.vertical, 6).padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 7).fill(palette.fill(0.055)))
                            .padding(.top, 4)
                    }
                }

                VStack(alignment: .trailing, spacing: 8) {
                    LiveText { RelativeTime.short(since: session.since, now: $0) }
                        .font(.peeku(11))
                        .foregroundStyle(palette.label(0.38))
                    Button("Open") { onOpen(session) }
                        .buttonStyle(PrimaryPillStyle(fontSize: 11.5, padding: EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)))
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
        }
    }
}

/// One quiet line for a session that doesn't need you. Clicking anywhere on it jumps to the
/// session; on hover its "host · time" gives way to an Open pill.
private struct QuietRow<Mark: View>: View {
    @Environment(\.palette) private var palette
    let session: PeekuSession
    let spend: SessionSpend?
    let detail: String
    var dimmed = false
    let onOpen: (PeekuSession) -> Void
    @ViewBuilder let mark: Mark
    @State private var hovering = false

    var body: some View {
        // The details run under the whole first line, "host · time" included, so they have room.
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                mark.frame(width: 16)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(session.project)
                        .font(.peeku(13, .semibold))
                        .foregroundStyle(dimmed ? palette.label(0.75) : palette.primary)
                        .layoutPriority(1)
                    Text(detail)
                        .font(.peeku(12))
                        .foregroundStyle(palette.label(dimmed ? 0.45 : 0.55))
                        .truncationMode(.tail)
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    AgentMark(agent: session.agent, size: 10)
                    LiveText { "\(session.hostName) · \(RelativeTime.short(since: session.since, now: $0))" }
                }
                    .font(.peeku(11))
                    .foregroundStyle(palette.label(0.38))
                    .lineLimit(1)
                    .fixedSize()
                    .opacity(hovering ? 0 : 1)
                    // Drawn over the label, so the row keeps its height.
                    .overlay(alignment: .trailing) {
                        if hovering {
                            Button("Open") { onOpen(session) }
                                .buttonStyle(RowOpenStyle())
                                .fixedSize()
                        }
                    }
            }
            if !SessionDetails.isEmpty(session, spend) {
                SessionDetails(session: session, spend: spend)
                    .padding(.leading, 26)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.fill(hovering ? 0.055 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onOpen(session) }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens this session")
        .accessibilityAction { onOpen(session) }
    }
}

/// The Now tab with no Claude Code sessions: a sleepy Peeku, what to do next, and a button for
/// each app Peeku watches that's installed and turned on.
private struct EmptyNow: View {
    let onLaunch: (HostApp) -> Void
    @Environment(\.palette) private var palette
    @Environment(\.peekuHangsAbove) private var hangsAbove

    private var hosts: [HostApp] {
        let hidden = Preferences.disabledHosts
        return Preferences.environments.filter { $0.isInstalled && !hidden.contains($0) }
    }

    var body: some View {
        VStack(spacing: 14) {
            // Peeku may already be hanging above the panel.
            if !hangsAbove {
                PeekuView(mood: .idle, size: 56, showZ: true)
                    .padding(.top, 8)
            }
            VStack(spacing: 6) {
                Text("Nothing running")
                    .font(.peeku(15, .semibold))
                    .tracking(-0.15)
                    .foregroundStyle(palette.primary)
                Text(CodexPaths.isInstalled
                     ? "Start Claude Code or Codex, and I'll let you know when one needs you."
                     : "Start Claude Code in iTerm, Terminal, VS Code or the Claude app, and I'll let you know when it needs you.")
                    .font(.peeku(12))
                    .lineSpacing(3)
                    .foregroundStyle(palette.label(0.55))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            if !hosts.isEmpty {
                HStack(spacing: 8) {
                    ForEach(hosts, id: \.self) { host in
                        LaunchButton(host: host) { onLaunch(host) }
                    }
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// "Open VS Code", with the app's own icon.
private struct LaunchButton: View {
    let host: HostApp
    let action: () -> Void
    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon = host.icon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                }
                Text(host.onboardingName)
                    .font(.peeku(12, .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(palette.primary)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Capsule().fill(palette.fill(hovering ? 0.13 : 0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Open \(host.onboardingName)")
    }
}
