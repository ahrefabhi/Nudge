import PipKit
import SwiftUI

/// Every session, dropped from the notch. Rows that need you carry an Open button; every other
/// row is one quiet line that still opens its session when clicked.
struct ManagerView: View {
    @Environment(\.palette) private var palette
    enum Tab { case now, history }

    let machine: PhaseMachine
    let bar: CGFloat
    @State private var tab: Tab

    init(machine: PhaseMachine, bar: CGFloat, initialTab: Tab = .now) {
        self.machine = machine
        self.bar = bar
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        let need = machine.queue.filter(\.needsYou)
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    // The light panel has Pip hanging above it instead.
                    if !palette.isLight { PipView(mood: headerMood(need), size: 22, flat: true, extras: false) }
                    Text(need.isEmpty ? "All clear" : "\(need.count) need\(need.count == 1 ? "s" : "") you")
                        .font(.pip(12, .semibold))
                        .foregroundStyle(need.isEmpty ? palette.label(0.86) : palette.accent(.permission))
                        .lineLimit(1)
                }
                Spacer()
                segmented
            }
            .padding(.horizontal, 18)
            .frame(height: bar)

            if tab == .history {
                HistoryView(machine: machine)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                nowList(need)
            }

            footer
        }
    }

    private func nowList(_ need: [PipSession]) -> some View {
        SnapshotSafeScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !need.isEmpty {
                    SectionLabel(title: "NEEDS YOU").padding(EdgeInsets(top: 6, leading: 12, bottom: 4, trailing: 12))
                    ForEach(need) { NeedsYouRow(session: $0, onOpen: open) }
                }
                if !machine.working.isEmpty {
                    SectionLabel(title: "WORKING").padding(EdgeInsets(top: 12, leading: 12, bottom: 4, trailing: 12))
                    ForEach(machine.working) { session in
                        QuietRow(session: session, detail: session.activity ?? session.task, onOpen: open) {
                            Spinner(track: .fill(0.18), head: palette.accent(.finished), period: 1.1)
                        }
                    }
                }
                if !machine.finished.isEmpty {
                    SectionLabel(title: "FINISHED").padding(EdgeInsets(top: 12, leading: 12, bottom: 4, trailing: 12))
                    ForEach(machine.finished) { session in
                        QuietRow(session: session, detail: session.task, dimmed: true, onOpen: open) { mark("✓", session) }
                    }
                }
                if !machine.idle.isEmpty {
                    SectionLabel(title: "IDLE").padding(EdgeInsets(top: 12, leading: 12, bottom: 4, trailing: 12))
                    ForEach(machine.idle) { session in
                        QuietRow(session: session, detail: session.task, dimmed: true, onOpen: open) { mark("·", session) }
                    }
                }
            }
            .padding(.top, 10)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private func open(_ session: PipSession) { machine.open(session.id) }

    private func mark(_ symbol: String, _ session: PipSession) -> some View {
        Text(symbol).font(.pip(11)).foregroundStyle(palette.accent(session.kind))
    }

    private func headerMood(_ need: [PipSession]) -> PipMood {
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
        }
        .font(.pip(11))
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(palette.fill(0.07)))
    }

    private func segment(_ title: String, _ value: Tab) -> some View {
        Button(title) { tab = value }
            .buttonStyle(.plain)
            .padding(.vertical, 2).padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 5).fill(palette.fill(tab == value ? 0.14 : 0)))
            .foregroundStyle(tab == value ? palette.primary : palette.label(0.5))
            .contentShape(Rectangle())
            .accessibilityAddTraits(tab == value ? .isSelected : [])
    }

    private var footer: some View {
        let hosts = HostApp.allCases.filter { host in machine.sessions.contains { $0.host == host } }
        let count = machine.sessions.count
        return HStack {
            Text("\(count) agent\(count == 1 ? "" : "s")" + (hosts.isEmpty ? "" : " · " + hosts.map(\.displayName).joined(separator: ", ")))
            Spacer()
            Text("⌥⌘.").font(.pipMono(11))
        }
        .font(.pip(11))
        .foregroundStyle(palette.label(0.4))
        .padding(.horizontal, 20)
        .frame(height: 40)
        .overlay(alignment: .top) { Rectangle().fill(palette.hairline).frame(height: 1) }
    }
}

private struct NeedsYouRow: View {
    @Environment(\.palette) private var palette
    let session: PipSession
    let onOpen: (PipSession) -> Void

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
                            .font(.pip(13, .semibold))
                            .foregroundStyle(palette.primary)
                        Text(session.host.displayName)
                            .font(.pip(10.5))
                            .foregroundStyle(palette.label(0.65))
                            .padding(.vertical, 1).padding(.horizontal, 6)
                            .background(RoundedRectangle(cornerRadius: 5).fill(palette.fill(0.08)))
                    }
                    (Text(session.kind.tag).foregroundStyle(accent) + Text(" · \(session.task)"))
                        .font(.pip(12))
                        .foregroundStyle(palette.label(0.55))
                        .lineLimit(1)
                    if let quote = session.quote {
                        Text(quote)
                            .font(.pipMono(11))
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
                        .font(.pip(11))
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
    let session: PipSession
    let detail: String
    var dimmed = false
    let onOpen: (PipSession) -> Void
    @ViewBuilder let mark: Mark
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            mark.frame(width: 16)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(session.project)
                    .font(.pip(13, .semibold))
                    .foregroundStyle(dimmed ? palette.label(0.75) : palette.primary)
                    .layoutPriority(1)
                Text(detail)
                    .font(.pip(12))
                    .foregroundStyle(palette.label(dimmed ? 0.45 : 0.55))
                    .truncationMode(.tail)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            LiveText { "\(session.host.displayName) · \(RelativeTime.short(since: session.since, now: $0))" }
                .font(.pip(11))
                .foregroundStyle(palette.label(0.38))
                .lineLimit(1)
                .fixedSize()
                .opacity(hovering ? 0 : 1)
                // Drawn over the label, so the row keeps its one-line height.
                .overlay(alignment: .trailing) {
                    if hovering {
                        Button("Open") { onOpen(session) }
                            .buttonStyle(RowOpenStyle())
                            .fixedSize()
                    }
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
