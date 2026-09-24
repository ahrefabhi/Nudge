import PipKit
import SwiftUI

/// Working: Pip glancing in the left wing, a spinner and the working count in the right.
/// A session that just finished swaps in a happy Pip for its 3s wink.
struct WorkingWings: View {
    let count: Int
    let celebrating: Bool
    let wing: CGFloat
    let bar: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Wing(width: wing, height: bar, edge: .leading) {
                PipView(mood: celebrating ? .success : .working, size: 22, flat: true, extras: false)
            }
            Spacer(minLength: 0)
            Wing(width: wing, height: bar, edge: .trailing) {
                if count > 0 {
                    HStack(spacing: 7) {
                        Spinner()
                        Text("\(count)")
                            .font(.pip(12, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Tokens.textPrimary)
                    }
                }
            }
        }
    }
}

/// Peek: Pip drops out of the notch at the bottom center.
struct PeekView: View {
    let mood: PipMood

    var body: some View {
        PipView(mood: mood, size: 30, flat: true, extras: false)
            .modifier(DropIn(size: 30))
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

/// Pill: the folded alert. Pip in the event's state, and a count badge.
struct PillView: View {
    let mood: PipMood
    let count: Int
    let accent: Color
    let wing: CGFloat
    let bar: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Wing(width: wing, height: bar, edge: .leading) {
                PipView(mood: mood, size: 22, flat: true, extras: false)
            }
            Spacer(minLength: 0)
            Wing(width: wing, height: bar, edge: .trailing) {
                Text("\(count)")
                    .font(.pip(11, .bold))
                    .monospacedDigit()
                    .foregroundStyle(Tokens.pillBadgeText)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Capsule().fill(accent))
            }
        }
    }
}
