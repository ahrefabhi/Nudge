import SwiftUI

// MARK: Time

enum RelativeTime {
    /// "now", "12s", "2m", "1h", "3d".
    static func short(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<5: return "now"
        case ..<60: return "\(seconds)s"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86_400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86_400)d"
        }
    }

    /// "just now" or "12s ago".
    static func ago(since date: Date, now: Date = Date()) -> String {
        let value = short(since: date, now: now)
        return value == "now" ? "just now" : "\(value) ago"
    }
}

/// Text that re-renders every second, for "12s" style ages.
struct LiveText: View {
    let make: (Date) -> String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(make(context.date))
        }
    }
}

// MARK: Buttons

/// "Open Session" pill: 12.5/600, pressed scale .96. White on black; inverted on the light panel.
struct PrimaryPillStyle: ButtonStyle {
    var fontSize: CGFloat = 12.5
    var padding = EdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 14)

    func makeBody(configuration: Configuration) -> some View {
        Pill(label: configuration.label, pressed: configuration.isPressed, fontSize: fontSize, padding: padding)
    }

    private struct Pill<Label: View>: View {
        let label: Label
        let pressed: Bool
        let fontSize: CGFloat
        let padding: EdgeInsets
        @Environment(\.palette) private var palette
        @State private var hovering = false

        var body: some View {
            label
                .font(.pip(fontSize, .semibold))
                .foregroundStyle(palette.buttonText)
                .padding(padding)
                .background(Capsule().fill(hovering ? palette.buttonHover : palette.buttonBackground))
                .scaleEffect(pressed ? 0.96 : 1)
                .animation(.easeOut(duration: 0.12), value: pressed)
                .onHover { hovering = $0 }
        }
    }
}

/// Dim "Later" pill.
struct GhostPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Pill(label: configuration.label, pressed: configuration.isPressed)
    }

    private struct Pill<Label: View>: View {
        let label: Label
        let pressed: Bool
        @Environment(\.palette) private var palette
        @State private var hovering = false

        var body: some View {
            label
                .font(.pip(12.5))
                .foregroundStyle(palette.label(0.8))
                .padding(EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12))
                .background(Capsule().fill(palette.fill(hovering ? 0.13 : 0.08)))
                .scaleEffect(pressed ? 0.96 : 1)
                .onHover { hovering = $0 }
        }
    }
}

/// Small queue-row "Open": dim, inverts on hover.
struct RowOpenStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowOpenLabel(label: configuration.label, pressed: configuration.isPressed)
    }

    private struct RowOpenLabel<Label: View>: View {
        let label: Label
        let pressed: Bool
        @Environment(\.palette) private var palette
        @State private var hovering = false

        var body: some View {
            label
                .font(.pip(11.5, .medium))
                .foregroundStyle(hovering ? palette.buttonText : palette.primary)
                .padding(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                .background(Capsule().fill(hovering ? palette.buttonBackground : palette.fill(0.1)))
                .scaleEffect(pressed ? 0.95 : 1)
                .onHover { hovering = $0 }
        }
    }
}

/// Plain text link that brightens on hover.
struct LinkTextStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LinkLabel(label: configuration.label)
    }

    private struct LinkLabel<Label: View>: View {
        let label: Label
        @Environment(\.palette) private var palette
        @State private var hovering = false

        var body: some View {
            label
                .font(.pip(11.5))
                .foregroundStyle(hovering ? palette.primary : palette.label(0.45))
                .onHover { hovering = $0 }
        }
    }
}

/// Row with the handoff's hover fill.
struct HoverRow<Content: View>: View {
    var radius: CGFloat = 12
    var fill: Double = 0.055
    var highlighted = false
    @ViewBuilder let content: Content
    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        content
            .background(RoundedRectangle(cornerRadius: radius).fill(palette.fill(hovering || highlighted ? fill : 0)))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

// MARK: Bits

/// A scroll view, except in snapshots: ImageRenderer can't draw AppKit-backed scroll views.
struct SnapshotSafeScrollView<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.pipStill) private var pipStill

    var body: some View {
        if pipStill {
            content.frame(maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView { content }.scrollIndicators(.never)
        }
    }
}

struct Spinner: View {
    var size: CGFloat = 10
    /// Defaults: a faint ring with a primary-color head.
    var track: Color?
    var head: Color?
    var period: TimeInterval = 0.9
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pipStill) private var pipStill

    var body: some View {
        let still = reduceMotion || pipStill
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: still)) { context in
            let angle = still ? 0 : context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: period) / period * 360
            ZStack {
                Circle().stroke(track ?? palette.fill(0.2), lineWidth: 1.5)
                // CSS border-top: the top quarter of the ring.
                Circle().trim(from: 0.625, to: 0.875).stroke(head ?? palette.primary, lineWidth: 1.5)
            }
            .padding(0.75)
            .rotationEffect(.degrees(angle))
        }
        .frame(width: size, height: size)
    }
}

struct Dot: View {
    var color: Color
    var size: CGFloat
    var body: some View { Circle().fill(color).frame(width: size, height: size) }
}

struct SectionLabel: View {
    let title: String
    @Environment(\.palette) private var palette

    var body: some View {
        Text(title)
            .font(.pip(10.5, .semibold))
            .tracking(0.84)
            .foregroundStyle(palette.label(0.38))
    }
}

/// Places content in one wing of the top row, beside the camera. Narrow wings center it
/// so nothing slides under the hardware notch.
struct Wing<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    let edge: HorizontalEdge
    @ViewBuilder let content: Content

    var body: some View {
        let roomy = width >= 50
        content
            .padding(edge == .leading ? .leading : .trailing, roomy ? 14 : 0)
            .frame(width: max(0, width), height: height,
                   alignment: roomy ? (edge == .leading ? .leading : .trailing) : .center)
    }
}

// MARK: Motion helpers

/// Content in: translateY 8→0, scale .98→1, blur 5→0.
private struct ContentInModifier: ViewModifier {
    let progress: Double
    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(0.98 + 0.02 * progress, anchor: .top)
            .offset(y: 8 * (1 - progress))
            .blur(radius: 5 * (1 - progress))
    }
}

extension AnyTransition {
    static func islandContent(delay: TimeInterval = 0.17, reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity.animation(Motion.reduced) }
        return .asymmetric(
            insertion: .modifier(active: ContentInModifier(progress: 0), identity: ContentInModifier(progress: 1))
                .animation(.easeOut(duration: 0.38).delay(delay)),
            removal: .opacity.animation(.easeIn(duration: 0.1))
        )
    }
}

/// Pip dropping out of the notch: from −130% and stretched, a squash, a small rebound, rest.
struct DropIn: ViewModifier {
    let size: CGFloat
    @State private var start = Date()
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pipStill) private var pipStill

    private static let duration: TimeInterval = 0.52
    private static let curve = CubicBezier(0.3, 1.2, 0.45, 1)
    private static let y = Keyframes(curve, [(0, -1.3), (0.58, 0.10), (0.78, -0.04), (1, 0)])
    private static let scaleX = Keyframes(curve, [(0, 1), (0.58, 1.1), (0.78, 0.97), (1, 1)])
    private static let scaleY = Keyframes(curve, [(0, 1.3), (0.58, 0.88), (0.78, 1.03), (1, 1)])

    func body(content: Content) -> some View {
        let done = finished || reduceMotion || pipStill
        TimelineView(.animation(paused: done)) { context in
            let p = done ? 1 : min(1, context.date.timeIntervalSince(start) / Self.duration)
            content
                .scaleEffect(x: Self.scaleX.value(at: p), y: Self.scaleY.value(at: p), anchor: .bottom)
                .offset(y: Self.y.value(at: p) * size)
        }
        .task {
            try? await Task.sleep(for: .seconds(Self.duration))
            finished = true
        }
    }
}
