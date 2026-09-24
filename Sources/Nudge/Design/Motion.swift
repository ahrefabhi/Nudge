import SwiftUI

extension EnvironmentValues {
    /// Renders every loop at rest, for snapshots. Reduce Motion does the same for users.
    @Entry var nudgeStill = false
}

enum Motion {
    /// Island size going out.
    static let islandSpring = Animation.spring(response: 0.50, dampingFraction: 0.78)
    /// Island size coming back: ease-in, no overshoot.
    static let collapse = Animation.timingCurve(0.4, 0, 1, 1, duration: 0.28)
    /// Reduce Motion replaces springs and hops with short cross-fades.
    static let reduced = Animation.easeInOut(duration: 0.15)

    static func island(expanding: Bool, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : expanding ? islandSpring : collapse
    }
}

/// CSS `cubic-bezier()`, solved for y at a given x.
struct CubicBezier: Sendable {
    let x1, y1, x2, y2: Double

    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        (self.x1, self.y1, self.x2, self.y2) = (x1, y1, x2, y2)
    }

    static let linear = CubicBezier(0, 0, 1, 1)
    static let ease = CubicBezier(0.25, 0.1, 0.25, 1)
    static let easeInOut = CubicBezier(0.42, 0, 0.58, 1)
    static let easeOut = CubicBezier(0, 0, 0.58, 1)

    func callAsFunction(_ x: Double) -> Double {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        func sample(_ t: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t
        }
        var t = x
        for _ in 0..<8 {
            let error = sample(t, x1, x2) - x
            let slope = 3 * (1 - t) * (1 - t) * x1 + 6 * (1 - t) * t * (x2 - x1) + 3 * t * t * (1 - x2)
            guard abs(error) > 1e-6, abs(slope) > 1e-6 else { break }
            t = min(max(t - error / slope, 0), 1)
        }
        return sample(t, y1, y2)
    }
}

/// One animated property following CSS `@keyframes` stops, with the timing function applied per segment.
struct Keyframes: Sendable {
    let stops: [(at: Double, value: Double)]
    let curve: CubicBezier

    init(_ curve: CubicBezier = .easeInOut, _ stops: [(Double, Double)]) {
        self.curve = curve
        self.stops = stops.map { (at: $0.0, value: $0.1) }
    }

    func value(at progress: Double) -> Double {
        guard let first = stops.first else { return 0 }
        guard progress > first.at else { return first.value }
        for (previous, next) in zip(stops, stops.dropFirst()) where progress <= next.at {
            let span = next.at - previous.at
            let local = span > 0 ? (progress - previous.at) / span : 1
            return previous.value + (next.value - previous.value) * curve(local)
        }
        return stops[stops.count - 1].value
    }

    /// Value for an infinite loop of `duration` seconds at elapsed time `t`.
    func looping(_ t: TimeInterval, duration: TimeInterval, delay: TimeInterval = 0) -> Double {
        let local = max(0, t - delay)
        return value(at: local.truncatingRemainder(dividingBy: duration) / duration)
    }
}
