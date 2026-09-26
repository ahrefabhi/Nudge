import PeekuKit
import SwiftUI

/// Single notification: what happened, where, and one primary action.
struct AlertCardView: View {
    @Environment(\.palette) private var palette
    @Environment(\.peekuHangsAbove) private var hangsAbove
    let session: PeekuSession
    let bar: CGFloat
    let onOpen: () -> Void
    let onLater: () -> Void
    let onAllAgents: () -> Void
    /// For a failed command, which gets Restart beside Show Output.
    var onRestart: (() -> Void)?
    /// For a command asking yes or no, which gets both as buttons.
    var onAnswer: ((String) -> Void)?

    var body: some View {
        if hangsAbove {
            // In a panel Peeku hangs above, so there's no wing row and no Peeku column.
            VStack(alignment: .leading, spacing: 0) {
                tagRow
                details.padding(.top, 8)
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                tagRow.frame(height: bar)
                HStack(alignment: .top, spacing: 14) {
                    PeekuView(mood: session.kind.mood, size: 50)
                        .frame(width: 58)
                        .padding(.top, 2)
                    details
                }
                .padding(.top, 10)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
    }

    private var tagRow: some View {
        let accent = palette.accent(session.kind)
        return HStack {
            HStack(spacing: 6) {
                Dot(color: accent, size: 6)
                Text(session.kind.tag.uppercased())
                    .font(.peeku(11, .semibold))
                    .tracking(0.55)
                    .foregroundStyle(accent)
            }
            Spacer(minLength: 12)
            HStack(spacing: 5) {
                SourceMark(session: session, size: 11)
                Text(session.hostLabel)
            }
            .font(.peeku(11))
            .foregroundStyle(palette.label(0.5))
            .lineLimit(1)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            // "Dashboard exited with code 1".
            Text(session.kind.isCommand ? "\(session.project) \(session.task)" : session.kind.alertTitle(for: session.agent))
                .font(.peeku(15, .semibold))
                .tracking(-0.15)
                .foregroundStyle(palette.primary)
                .lineLimit(1)
            LiveText { now in
                // A command's name is already in the title.
                let place = session.kind.isCommand ? [] : [session.project, session.branch].compactMap { $0 }
                return (place + [RelativeTime.ago(since: session.since, now: now)]).joined(separator: " · ")
            }
            .font(.peeku(12))
            .foregroundStyle(palette.label(0.5))
            .lineLimit(1)
            .padding(.top, 3)

            if session.quote != nil || !session.choices.isEmpty {
                context.padding(.top, 10)
            }

            HStack(spacing: 8) {
                Button(action: onOpen) {
                    HStack(spacing: 8) {
                        Text(primaryTitle)
                        Text("↵").font(.peeku(11)).opacity(0.45)
                    }
                }
                .buttonStyle(PrimaryPillStyle())
                if let onAnswer {
                    Button("Yes") { onAnswer("y") }
                        .buttonStyle(GhostPillStyle())
                    Button("No") { onAnswer("n") }
                        .buttonStyle(GhostPillStyle())
                    Spacer(minLength: 0)
                    Button("Later", action: onLater)
                        .buttonStyle(LinkTextStyle())
                } else if let onRestart {
                    Button("Restart", action: onRestart)
                        .buttonStyle(GhostPillStyle())
                    Spacer(minLength: 0)
                    Button("Later", action: onLater)
                        .buttonStyle(LinkTextStyle())
                } else {
                    Button(session.kind == .finished ? "Dismiss" : "Later", action: onLater)
                        .buttonStyle(GhostPillStyle())
                    Spacer(minLength: 0)
                    Button("All agents", action: onAllAgents)
                        .buttonStyle(LinkTextStyle())
                }
            }
            .padding(.top, 12)
        }
    }

    private var primaryTitle: String {
        switch session.kind {
        case .usage: "Show Usage"
        case .command, .commandInput: "Show Output"
        default: "Open Session"
        }
    }

    private var context: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let quote = session.quote {
                Text(session.kind == .permission ? "$ \(quote)" : quote)
                    .font(.peekuMono(11.5))
                    .lineSpacing(3.5)
                    .foregroundStyle(palette.context)
                    .lineLimit(2)
                    // A prompt's question and "(Y/n)" are at its end.
                    .truncationMode(session.kind == .commandInput ? .head : .tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !session.choices.isEmpty {
                ForEach(Array(session.choices.prefix(4).enumerated()), id: \.offset) { index, choice in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.peeku(10, .semibold))
                            .foregroundStyle(palette.label(0.8))
                            .frame(width: 16, height: 16)
                            .background(RoundedRectangle(cornerRadius: 5).fill(palette.fill(0.1)))
                        Text(choice)
                            .font(.peeku(12))
                            .foregroundStyle(palette.context)
                            .lineLimit(1)
                    }
                }
                Text("Answer in \(session.hostName)")
                    .font(.peeku(11))
                    .foregroundStyle(palette.label(0.45))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(palette.fill(0.065)))
    }
}
