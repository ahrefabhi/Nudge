import PipKit
import SwiftUI

/// Single notification: what happened, where, and one primary action.
struct AlertCardView: View {
    @Environment(\.palette) private var palette
    let session: PipSession
    let bar: CGFloat
    let onOpen: () -> Void
    let onLater: () -> Void
    let onAllAgents: () -> Void

    var body: some View {
        if palette.isLight {
            // In the light panel Pip hangs above, so there's no wing row and no Pip column.
            VStack(alignment: .leading, spacing: 0) {
                tagRow
                details.padding(.top, 8)
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                tagRow.frame(height: bar)
                HStack(alignment: .top, spacing: 14) {
                    PipView(mood: session.kind.mood, size: 50)
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
                    .font(.pip(11, .semibold))
                    .tracking(0.55)
                    .foregroundStyle(accent)
            }
            Spacer(minLength: 12)
            HStack(spacing: 5) {
                AgentMark(agent: session.agent, size: 11)
                Text(session.hostLabel)
            }
            .font(.pip(11))
            .foregroundStyle(palette.label(0.5))
            .lineLimit(1)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(session.kind.alertTitle(for: session.agent))
                .font(.pip(15, .semibold))
                .tracking(-0.15)
                .foregroundStyle(palette.primary)
                .lineLimit(1)
            LiveText { now in
                [session.project, session.branch, RelativeTime.ago(since: session.since, now: now)]
                    .compactMap { $0 }
                    .joined(separator: " · ")
            }
            .font(.pip(12))
            .foregroundStyle(palette.label(0.5))
            .lineLimit(1)
            .padding(.top, 3)

            if session.quote != nil || !session.choices.isEmpty {
                context.padding(.top, 10)
            }

            HStack(spacing: 8) {
                Button(action: onOpen) {
                    HStack(spacing: 8) {
                        Text(session.kind == .usage ? "Show Usage" : "Open Session")
                        Text("↵").font(.pip(11)).opacity(0.45)
                    }
                }
                .buttonStyle(PrimaryPillStyle())
                Button(session.kind == .finished ? "Dismiss" : "Later", action: onLater)
                    .buttonStyle(GhostPillStyle())
                Spacer(minLength: 0)
                Button("All agents", action: onAllAgents)
                    .buttonStyle(LinkTextStyle())
            }
            .padding(.top, 12)
        }
    }

    private var context: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let quote = session.quote {
                Text(session.kind == .permission ? "$ \(quote)" : quote)
                    .font(.pipMono(11.5))
                    .lineSpacing(3.5)
                    .foregroundStyle(palette.context)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !session.choices.isEmpty {
                ForEach(Array(session.choices.prefix(4).enumerated()), id: \.offset) { index, choice in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.pip(10, .semibold))
                            .foregroundStyle(palette.label(0.8))
                            .frame(width: 16, height: 16)
                            .background(RoundedRectangle(cornerRadius: 5).fill(palette.fill(0.1)))
                        Text(choice)
                            .font(.pip(12))
                            .foregroundStyle(palette.context)
                            .lineLimit(1)
                    }
                }
                Text("Answer in \(session.host.displayName)")
                    .font(.pip(11))
                    .foregroundStyle(palette.label(0.45))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(palette.fill(0.065)))
    }
}
