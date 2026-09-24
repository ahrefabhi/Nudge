import NudgeKit
import SwiftUI

/// Body transform, with offsets as a fraction of Nudge's size. Scale and rotation pivot at the bottom center.
struct NudgePose {
    var x = 0.0, y = 0.0, scaleX = 1.0, scaleY = 1.0, rotation = 0.0
}

/// The handoff's `@keyframes`, evaluated at elapsed time `t`.
enum NudgeMotion {
    private static let hopCurve = CubicBezier(0.3, 0.7, 0.4, 1)

    private static let breathX = Keyframes(.easeInOut, [(0, 1), (0.5, 1.035), (1, 1)])
    private static let breathY = Keyframes(.easeInOut, [(0, 1), (0.5, 0.965), (1, 1)])

    private static let hopY = Keyframes(hopCurve, [(0, 0), (0.55, 0), (0.65, -0.18), (0.76, 0), (0.84, -0.04), (0.92, 0), (1, 0)])
    private static let hopX = Keyframes(hopCurve, [(0, 1), (0.55, 1), (0.65, 0.96), (0.76, 1.07), (0.84, 1), (1, 1)])
    private static let hopScaleY = Keyframes(hopCurve, [(0, 1), (0.55, 1), (0.65, 1.05), (0.76, 0.92), (0.84, 1), (1, 1)])

    private static let tilt = Keyframes(.easeInOut, [(0, -9), (0.5, -4), (1, -9)])
    private static let tiltY = Keyframes(.easeInOut, [(0, 0), (0.5, -0.04), (1, 0)])

    private static let shakeX = Keyframes(.easeInOut, [(0, 0), (0.70, 0), (0.74, -0.06), (0.78, 0.06), (0.82, -0.03), (0.86, 0.02), (1, 0)])
    private static let shakeRotation = Keyframes(.easeInOut, [(0, 0), (0.70, 0), (0.74, -5), (0.78, 5), (0.82, -2), (0.86, 0), (1, 0)])

    static let blink = Keyframes(.ease, [(0, 1), (0.92, 1), (0.95, 0.08), (1, 1)])
    static let glance = Keyframes(.easeInOut, [(0, 0), (0.12, 0), (0.22, -0.16), (0.40, -0.16), (0.52, 0.16), (0.72, 0.16), (0.82, 0), (1, 0)])
    static let bob = Keyframes(.easeInOut, [(0, 0), (0.5, -0.22), (1, 0)])
    static let twinkle = Keyframes(.easeInOut, [(0, 0.15), (0.5, 1), (1, 0.15)])
    static let twinkleScale = Keyframes(.easeInOut, [(0, 0.5), (0.5, 1), (1, 0.5)])
    static let zOpacity = Keyframes(.easeOut, [(0, 0), (0.3, 0.7), (1, 0)])
    static let zProgress = Keyframes(.easeOut, [(0, 0), (1, 1)])

    /// Success hops only for its first three seconds.
    static let successDuration: TimeInterval = 3

    static func pose(_ mood: NudgeMood, at t: TimeInterval) -> NudgePose {
        switch mood {
        case .idle: breathe(t, 4.5)
        case .working: breathe(t, 2.2)
        case .question:
            NudgePose(y: tiltY.looping(t, duration: 2.8), rotation: tilt.looping(t, duration: 2.8))
        case .permission, .multiple: hop(t, 1.8)
        case .error:
            NudgePose(x: shakeX.looping(t, duration: 2.6), rotation: shakeRotation.looping(t, duration: 2.6))
        case .success: t < successDuration ? hop(t, 1.3) : NudgePose()
        }
    }

    /// The resting pose when nothing animates. Question keeps its head tilt.
    static func rest(_ mood: NudgeMood) -> NudgePose {
        mood == .question ? NudgePose(rotation: -9) : NudgePose()
    }

    static func blinks(_ mood: NudgeMood) -> Bool {
        mood != .idle && mood != .success && mood != .error
    }

    private static func breathe(_ t: TimeInterval, _ duration: TimeInterval) -> NudgePose {
        NudgePose(scaleX: breathX.looping(t, duration: duration), scaleY: breathY.looping(t, duration: duration))
    }

    private static func hop(_ t: TimeInterval, _ duration: TimeInterval) -> NudgePose {
        NudgePose(y: hopY.looping(t, duration: duration),
                scaleX: hopX.looping(t, duration: duration),
                scaleY: hopScaleY.looping(t, duration: duration))
    }
}
