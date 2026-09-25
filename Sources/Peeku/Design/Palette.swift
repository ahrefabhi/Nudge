import PeekuKit
import SwiftUI

/// Content colors. The notch is always black, so its own content stays dark; in light mode,
/// the panel that hangs below it uses the light palette.
struct Palette: Sendable {
    let isLight: Bool

    static let dark = Palette(isLight: false)
    static let light = Palette(isLight: true)

    /// `#f5f5f7` on black, `#1d1d1f` on the light panel.
    var primary: Color { isLight ? Color(hex: 0x1d1d1f) : Tokens.textPrimary }
    var context: Color { isLight ? Color(hex: 0x1d1d1f) : Tokens.contextText }

    /// Secondary text. Dark is `rgba(235,235,245,o)`; light is `rgba(60,60,67,…)`, a touch
    /// stronger to read on white (`.5` → `.58`, the design's meta and task lines).
    func label(_ opacity: Double) -> Color {
        isLight ? Color(.sRGB, red: 60 / 255, green: 60 / 255, blue: 67 / 255, opacity: min(1, opacity + 0.08)) : Color.label(opacity)
    }

    /// Hover, chip and box fills: white on black, black on light (`.065` → `.045`).
    func fill(_ opacity: Double) -> Color {
        isLight ? Color.black.opacity(opacity * 0.72) : Color.white.opacity(opacity)
    }

    var hairline: Color { isLight ? Color.black.opacity(0.08) : Tokens.hairline }

    /// The primary button inverts in light mode.
    var buttonBackground: Color { isLight ? Color(hex: 0x1d1d1f) : Tokens.textPrimary }
    var buttonHover: Color { isLight ? Color.black : Color.white }
    var buttonText: Color { isLight ? Color.white : Tokens.buttonText }

    /// Light mode uses the darker accents the design gives for text on white.
    func accent(_ kind: SessionKind) -> Color {
        guard isLight else { return kind.accent }
        switch kind {
        case .permission, .usage: return Color(oklch: 0.56, 0.13, 65)
        case .question, .waiting: return Color(oklch: 0.52, 0.14, 250)
        case .error: return Color(oklch: 0.55, 0.17, 25)
        case .finished, .working: return Color(oklch: 0.52, 0.13, 152)
        case .idle: return label(0.38)
        }
    }
}

extension EnvironmentValues {
    @Entry var palette = Palette.dark
}
