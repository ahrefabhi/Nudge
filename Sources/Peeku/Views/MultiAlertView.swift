import PeekuKit
import SwiftUI

/// Several agents waiting: one Peeku, one queue, most urgent first.
struct MultiAlertView: View {
    @Environment(\.palette) private var palette
    let queue: [PeekuSession]
    /// Highlighted row, once the user cycles with ⌥⌘↓.
    let cursor: Int?
    let bar: CGFloat
    let onOpen: (PeekuSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Dot(color: palette.accent(.permission), size: 6)
                    Text("\(queue.count) waiting".uppercased())
                        .font(.peeku(11, .semibold))
                        .tracking(0.55)
                        .foregroundStyle(palette.accent(.permission))
                }
                Spacer()
                Text("⌥⌘↓ next")
                    .font(.peekuMono(10.5))
                    .foregroundStyle(palette.label(0.4))
            }
            .padding(.horizontal, 4)
            // Beside the camera in the notch; an ordinary row in the light panel.
            .frame(height: palette.isLight ? 28 : bar)

            HStack(spacing: 12) {
                if !palette.isLight { PeekuGroup(size: 42, count: queue.count) }
                VStack(alignment: .leading, spacing: 2) {
                    // Usage and command alerts aren't agents.
                    Text("\(Self.countWord(queue.count)) \(queue.contains { $0.kind == .usage || $0.kind.isCommand } ? "things" : "agents") need you")
                        .font(.peeku(15, .semibold))
                        .tracking(-0.15)
                        .foregroundStyle(palette.primary)
                    Text("Most urgent first")
                        .font(.peeku(12))
                        .foregroundStyle(palette.label(0.5))
                }
            }
            .padding(EdgeInsets(top: 10, leading: 4, bottom: 8, trailing: 4))

            ForEach(Array(queue.prefix(6).enumerated()), id: \.element.id) { index, session in
                row(session, highlighted: index == cursor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, palette.isLight ? 8 : 0)
        .padding(.bottom, 14)
    }

    private func row(_ session: PeekuSession, highlighted: Bool) -> some View {
        HoverRow(radius: 10, fill: 0.06, highlighted: highlighted) {
            HStack(spacing: 10) {
                Dot(color: palette.accent(session.kind), size: 7)
                    .padding(.leading, 3)
                    .frame(width: 14, alignment: .leading)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(session.project)
                        .font(.peeku(12.5, .semibold))
                        .foregroundStyle(palette.primary)
                    Text(session.kind.tag)
                        .font(.peeku(12))
                        .foregroundStyle(palette.accent(session.kind))
                    HStack(spacing: 5) {
                        SourceMark(session: session, size: 10)
                        LiveText { now in "\(session.hostName) · \(RelativeTime.short(since: session.since, now: now))" }
                    }
                    .font(.peeku(11))
                    .foregroundStyle(palette.label(0.38))
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                Button("Open") { onOpen(session) }
                    .buttonStyle(RowOpenStyle())
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
        }
    }

    static func countWord(_ count: Int) -> String {
        let words = ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"]
        return count < words.count ? words[count] : "\(count)"
    }
}
