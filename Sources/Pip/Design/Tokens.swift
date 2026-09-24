import PipKit
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: opacity)
    }

    /// CSS `oklch(L C H)` converted to sRGB, so accents match the handoff exactly.
    init(oklch lightness: Double, _ chroma: Double, _ hue: Double, opacity: Double = 1) {
        let radians = hue * .pi / 180
        let a = chroma * cos(radians), b = chroma * sin(radians)
        let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
        func encode(_ linear: Double) -> Double {
            let x = min(max(linear, 0), 1)
            return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
        }
        self.init(.sRGB,
                  red: encode(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                  green: encode(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                  blue: encode(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s),
                  opacity: opacity)
    }

    /// `rgba(235,235,245,opacity)`, the handoff's secondary text family.
    static func label(_ opacity: Double) -> Color {
        Color(.sRGB, red: 235 / 255, green: 235 / 255, blue: 245 / 255, opacity: opacity)
    }

    static func fill(_ opacity: Double) -> Color { Color.white.opacity(opacity) }
}

enum Tokens {
    static let island = Color.black
    static let ink = Color(hex: 0x060607)

    static let textPrimary = Color(hex: 0xf5f5f7)
    static let contextText = Color(hex: 0xe8e8ec)
    static let buttonText = Color(hex: 0x0b0b0c)
    static let badgeText = Color(hex: 0x1b1406)
    static let pillBadgeText = Color(hex: 0x17120a)

    static let hairline = Color.fill(0.07)

    static let eyeIdle = Color(hex: 0xd6d6dc)
    static let eyeWorking = Color(hex: 0xf5f5f7)

    enum Accent {
        static let permission = Color(oklch: 0.83, 0.13, 78)
        static let question = Color(oklch: 0.80, 0.12, 250)
        static let error = Color(oklch: 0.75, 0.15, 25)
        static let success = Color(oklch: 0.82, 0.14, 152)
    }

    static let expandedShadow = Color.black.opacity(0.55)
}

extension PipMood {
    var eyeColor: Color {
        switch self {
        case .idle: Tokens.eyeIdle
        case .working: Tokens.eyeWorking
        case .question: Tokens.Accent.question
        case .permission, .multiple: Tokens.Accent.permission
        case .error: Tokens.Accent.error
        case .success: Tokens.Accent.success
        }
    }
}

extension SessionKind {
    var accent: Color {
        switch self {
        case .permission: Tokens.Accent.permission
        case .question, .waiting: Tokens.Accent.question
        case .error: Tokens.Accent.error
        case .finished, .working: Tokens.Accent.success
        case .idle: Color.label(0.38)
        }
    }

    var tag: String {
        switch self {
        case .permission: "Permission"
        case .question: "Question"
        case .waiting: "Waiting"
        case .error: "Blocked"
        case .finished: "Finished"
        case .working: "Working"
        case .idle: "Idle"
        }
    }

    func alertTitle(for agent: Agent) -> String {
        let name = agent.name
        return switch self {
        case .permission: "\(name) needs your permission"
        case .question: "\(name) has a question"
        case .waiting: "\(name) is waiting for you"
        case .error: "\(name) hit an error"
        case .finished: "\(name) finished"
        case .working: "\(name) is working"
        case .idle: "\(name) is ready"
        }
    }
}

extension Font {
    static func pip(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func pipMono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension PipSession {
    /// Where the session runs, with "· Codex" for Codex so the two agents are easy to tell apart.
    var sourceName: String { agent == .codex ? "\(host.displayName) · Codex" : host.displayName }
}
