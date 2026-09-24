import PipKit
import SwiftUI

/// The manager's second tab: moments when an agent needed you or finished, grouped by day.
/// Rows reopen their session while it's still running.
struct HistoryView: View {
    @Environment(\.palette) private var palette
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", neededYou = "Needed you", errors = "Errors", finished = "Finished"
        var id: Self { self }

        func includes(_ entry: HistoryEntry) -> Bool {
            switch self {
            case .all: true
            case .neededYou: entry.kind.neededYou
            case .errors: entry.kind == .error
            case .finished: entry.kind == .finished
            }
        }
    }

    let machine: PhaseMachine
    @State private var filter: Filter = .all

    var body: some View {
        let entries = machine.history.filter(filter.includes)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach(Filter.allCases) { option in
                    Button(option.rawValue) { filter = option }
                        .buttonStyle(ChipStyle(selected: option == filter))
                }
            }
            .padding(EdgeInsets(top: 12, leading: 20, bottom: 4, trailing: 20))

            if entries.isEmpty {
                Text(filter == .all ? "Nothing yet. Moments when an agent needs you or finishes show up here." : "Nothing here this week.")
                    .font(.pip(12))
                    .foregroundStyle(palette.label(0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SnapshotSafeScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Self.days(entries), id: \.label) { day in
                            SectionLabel(title: day.label.uppercased())
                                .padding(EdgeInsets(top: 14, leading: 12, bottom: 6, trailing: 12))
                            ForEach(day.entries) { entry in
                                HistoryRow(entry: entry, alive: machine.sessions.contains { $0.id == entry.sessionID }) {
                                    machine.open(entry.sessionID)
                                }
                            }
                        }
                    }
                    .padding(EdgeInsets(top: 4, leading: 8, bottom: 10, trailing: 8))
                }
            }
        }
    }

    /// "Today", "Yesterday", then "Mon 22 Sep".
    static func days(_ entries: [HistoryEntry], now: Date = Date(), calendar: Calendar = .current) -> [(label: String, entries: [HistoryEntry])] {
        var groups: [(label: String, entries: [HistoryEntry])] = []
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        for entry in entries {
            let label = calendar.isDateInToday(entry.at) ? "Today"
                : calendar.isDateInYesterday(entry.at) ? "Yesterday"
                : formatter.string(from: entry.at)
            if groups.last?.label == label { groups[groups.count - 1].entries.append(entry) } else { groups.append((label, [entry])) }
        }
        return groups
    }
}

private struct HistoryRow: View {
    @Environment(\.palette) private var palette
    let entry: HistoryEntry
    /// Only a session that's still running can be reopened.
    let alive: Bool
    let onOpen: () -> Void
    @State private var hovering = false

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Self.time.string(from: entry.at))
                .font(.pipMono(11))
                .foregroundStyle(palette.label(0.4))
                .frame(width: 40, alignment: .leading)
            Dot(color: entry.kind.color(palette), size: 6)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
                .frame(width: 10)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.project)
                        .font(.pip(13, .semibold))
                        .foregroundStyle(palette.primary)
                    Text(entry.kind.label)
                        .font(.pip(12))
                        .foregroundStyle(entry.kind.color(palette))
                }
                .lineLimit(1)
                if !entry.summary.isEmpty {
                    Text(entry.summary)
                        .font(.pip(12))
                        .foregroundStyle(palette.label(0.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                AgentMark(agent: entry.agent ?? .claude, size: 10)
                Text(entry.host.displayName)
            }
                .font(.pip(11))
                .foregroundStyle(palette.label(0.38))
                .fixedSize()
                .opacity(hovering && alive ? 0 : 1)
                .overlay(alignment: .trailing) {
                    if hovering && alive {
                        Button("Open", action: onOpen).buttonStyle(RowOpenStyle()).fixedSize()
                    }
                }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(palette.fill(hovering && alive ? 0.055 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if alive { onOpen() } }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(alive ? .isButton : [])
    }
}

/// Filter chip: 4×10 capsule, `.14` when selected.
private struct ChipStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Chip(label: configuration.label, selected: selected, pressed: configuration.isPressed)
    }

    private struct Chip<Label: View>: View {
        let label: Label
        let selected: Bool
        let pressed: Bool
        @Environment(\.palette) private var palette

        var body: some View {
            label
                .font(.pip(11.5))
                .foregroundStyle(selected ? palette.primary : palette.label(0.6))
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background(Capsule().fill(palette.fill(selected ? 0.14 : pressed ? 0.09 : 0.05)))
        }
    }
}

extension HistoryEntry.Kind {
    var label: String {
        switch self {
        case .started: "Started"
        case .permission: "Permission"
        case .question: "Question"
        case .waiting: "Waiting"
        case .error: "Blocked"
        case .finished: "Finished"
        }
    }

    /// The session kind whose color this entry uses; `nil` for Started, which stays grey.
    var sessionKind: SessionKind? {
        switch self {
        case .started: nil
        case .permission: .permission
        case .question: .question
        case .waiting: .waiting
        case .error: .error
        case .finished: .finished
        }
    }
}

extension HistoryEntry.Kind {
    func color(_ palette: Palette) -> Color {
        sessionKind.map(palette.accent) ?? palette.label(0.35)
    }
}
