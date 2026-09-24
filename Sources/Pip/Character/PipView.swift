import PipKit
import SwiftUI

/// Pip, drawn from shapes and scaled from `size`. Inside the island use `flat`, so only the eyes show.
struct PipView: View {
    var mood: PipMood
    var size: CGFloat
    var flat = false
    /// The "!" / count badge, the "?" and the success sparkles.
    var extras = true
    var count = 3
    /// Gap drawn around the badge, in the color behind Pip.
    var ring: Color = .black
    var still = false
    var showZ = false
    var lifted = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pipStill) private var pipStill
    @State private var start = Date()

    var body: some View {
        let animated = !still && !reduceMotion && !pipStill
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !animated)) { context in
            PipFigure(pip: self, t: animated ? context.date.timeIntervalSince(start) : nil)
        }
        .frame(width: size, height: size)
        .onChange(of: mood) { start = Date() }
    }
}

private struct PipFigure: View {
    let pip: PipView
    /// Elapsed time, or nil for the still pose.
    let t: TimeInterval?

    private var s: CGFloat { pip.size }
    private var color: Color { pip.mood.eyeColor }

    var body: some View {
        let pose = t.map { PipMotion.pose(pip.mood, at: $0) } ?? PipMotion.rest(pip.mood)
        ZStack(alignment: .topLeading) {
            ear(left: true)
            ear(left: false)
            bodyShape
            eyes
            if pip.extras { extras }
            if pip.showZ && pip.mood == .idle { sleepyZs }
        }
        .frame(width: s, height: s, alignment: .topLeading)
        .scaleEffect(x: pose.scaleX, y: pose.scaleY, anchor: .bottom)
        .rotationEffect(.degrees(pose.rotation), anchor: .bottom)
        .offset(x: pose.x * s, y: pose.y * s)
    }

    // MARK: Body

    private func ear(left: Bool) -> some View {
        rimmed(Ellipse(), outline: false)
            .frame(width: 0.22 * s, height: 0.28 * s)
            .rotationEffect(.degrees(left ? -20 : 20))
            .offset(x: left ? 0.13 * s : s - 0.13 * s - 0.22 * s, y: 0.04 * s)
    }

    private var bodyShape: some View {
        rimmed(PipBodyShape(), outline: true)
            .frame(width: s, height: 0.82 * s)
            .shadow(color: .black.opacity(pip.lifted ? 0.3 : 0), radius: 9, y: 8)
            .offset(y: 0.14 * s)
    }

    /// Ink fill, plus the rim highlights unless Pip is flat.
    private func rimmed<S: Shape>(_ shape: S, outline: Bool) -> some View {
        shape.fill(Tokens.ink)
            .overlay {
                if !pip.flat {
                    ZStack {
                        shape.fill(LinearGradient(stops: [.init(color: .clear, location: 0.65),
                                                          .init(color: .white.opacity(0.04), location: 1)],
                                                  startPoint: .top, endPoint: .bottom))
                        shape.stroke(LinearGradient(stops: [.init(color: .white.opacity(0.2), location: 0),
                                                            .init(color: .clear, location: 0.2)],
                                                    startPoint: .top, endPoint: .bottom), lineWidth: 2)
                            .clipShape(shape)
                        if outline { shape.stroke(Color.white.opacity(0.1), lineWidth: 0.5) }
                    }
                }
            }
    }

    // MARK: Eyes

    private var eyes: some View {
        let box = CGSize(width: 0.42 * s, height: 0.26 * s)
        let glance = pip.mood == .working ? (t.map { PipMotion.glance.looping($0, duration: 3.4) } ?? 0) : 0
        let blink = PipMotion.blinks(pip.mood) ? (t.map { PipMotion.blink.looping($0, duration: 5.5) } ?? 1) : 1
        return ZStack(alignment: .topLeading) {
            eye(left: true, box: box)
            eye(left: false, box: box)
        }
        .frame(width: box.width, height: box.height, alignment: .topLeading)
        .scaleEffect(x: 1, y: blink, anchor: .center)
        .offset(x: 0.29 * s + glance * box.width, y: 0.44 * s)
    }

    @ViewBuilder
    private func eye(left: Bool, box: CGSize) -> some View {
        let mood = pip.mood
        let glow = max(2, 0.14 * s) / 2
        if mood == .success {
            let w = 0.15 * s, h = 0.1 * s
            let line = max(1.5, 0.045 * s)
            ArchShape(lineWidth: line)
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .butt))
                .frame(width: w, height: h)
                .shadow(color: color, radius: 0.035 * s)
                .offset(x: left ? 0 : box.width - w, y: (box.height - h) / 2)
        } else {
            let (w, h, top, opacity, angle) = eyeGeometry(left: left, box: box)
            RoundedRectangle(cornerRadius: min(w, h) / 2)
                .fill(color)
                .frame(width: w, height: h)
                .shadow(color: color, radius: glow)
                .rotationEffect(.degrees(angle))
                .opacity(opacity)
                .offset(x: left ? 0 : box.width - w, y: top)
        }
    }

    private func eyeGeometry(left: Bool, box: CGSize) -> (CGFloat, CGFloat, CGFloat, Double, Double) {
        switch pip.mood {
        case .idle:
            return (0.12 * s, max(1.5, 0.045 * s), box.height * 0.6, 0.7, 0)
        case .permission, .multiple:
            let h = 0.24 * s
            return (0.14 * s, h, (box.height - h) / 2, 1, 0)
        case .question:
            let h = left ? 0.15 * s : 0.23 * s
            return (0.12 * s, h, (box.height - h) / 2, 1, 0)
        case .error:
            let h = 0.065 * s
            return (0.16 * s, h, (box.height - h) / 2, 1, left ? -22 : 22)
        case .working, .success:
            let h = 0.2 * s
            return (0.12 * s, h, (box.height - h) / 2, 1, 0)
        }
    }

    // MARK: Extras

    @ViewBuilder
    private var extras: some View {
        switch pip.mood {
        case .permission, .multiple:
            let b = max(13, 0.32 * s)
            ZStack {
                Circle().fill(pip.ring).frame(width: b + 4, height: b + 4)
                Circle().fill(color).frame(width: b, height: b)
                Text(pip.mood == .multiple ? "\(pip.count)" : "!")
                    .font(.system(size: b * 0.62, weight: .bold))
                    .foregroundStyle(Tokens.badgeText)
            }
            .frame(width: b, height: b)
            .offset(x: s + 0.1 * s - b, y: 0.02 * s)
        case .question:
            let bob = t.map { PipMotion.bob.looping($0, duration: 1.6) } ?? 0
            Text("?")
                .font(.system(size: 0.38 * s, weight: .bold))
                .foregroundStyle(color)
                .shadow(color: color, radius: 0.06 * s)
                .fixedSize()
                .frame(width: 0.24 * s, height: 0.38 * s)
                .offset(x: s + 0.16 * s - 0.24 * s, y: -0.24 * s + bob * 0.38 * s)
        case .success:
            let d = max(3, 0.1 * s)
            sparkle(d, delay: 0).offset(x: -0.1 * s, y: -0.04 * s)
            sparkle(d * 0.8, delay: 0.5).offset(x: s + 0.16 * s - d * 0.8, y: 0.16 * s)
        case .idle, .working, .error:
            EmptyView()
        }
    }

    private func sparkle(_ d: CGFloat, delay: TimeInterval) -> some View {
        // Still sparkles sit at their brightest point.
        let local = t ?? 0.7
        return Rectangle()
            .fill(color)
            .frame(width: d, height: d)
            .scaleEffect(PipMotion.twinkleScale.looping(local, duration: 1.4, delay: delay))
            .rotationEffect(.degrees(45))
            .opacity(PipMotion.twinkle.looping(local, duration: 1.4, delay: delay))
    }

    private var sleepyZs: some View {
        ZStack(alignment: .topLeading) {
            sleepyZ(fontSize: 0.22 * s, delay: 0)
            sleepyZ(fontSize: 0.17 * s, delay: 1.5)
        }
        .offset(x: s + 0.1 * s - 0.14 * s)
    }

    private func sleepyZ(fontSize: CGFloat, delay: TimeInterval) -> some View {
        let local = t ?? 1
        let progress = PipMotion.zProgress.looping(local, duration: 3, delay: delay)
        let visible = t == nil || local >= delay
        return Text("z")
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(Color.label(0.55))
            .fixedSize()
            .scaleEffect(0.6 + 0.4 * progress)
            .offset(x: 7 / 64 * s * progress, y: -16 / 64 * s * progress)
            .opacity(visible ? PipMotion.zOpacity.looping(local, duration: 3, delay: delay) : 0)
    }
}

/// The multiple-waiting character: Pip with a count, the rest of the queue dimmed behind.
struct PipGroup: View {
    var size: CGFloat
    var count: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            PipView(mood: .question, size: size, extras: false, still: true)
                .scaleEffect(0.68, anchor: .bottomLeading)
                .opacity(0.5)
            PipView(mood: .error, size: size, extras: false, still: true)
                .scaleEffect(0.68, anchor: .bottomTrailing)
                .opacity(0.5)
                .offset(x: 0.7 * size)
            PipView(mood: .multiple, size: size, count: count)
                .offset(x: 0.35 * size)
        }
        .frame(width: 1.7 * size, height: size, alignment: .topLeading)
    }
}
