import AppKit
import PipKit
import SwiftUI

/// All seven states side by side, plus the flat notch variants, for checking against the handoff.
struct CharacterSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Pip's states").font(.pip(15, .semibold)).foregroundStyle(Tokens.textPrimary)
            HStack(spacing: 12) {
                ForEach(PipMood.allCases, id: \.self) { mood in
                    card(mood.rawValue.capitalized) {
                        if mood == .multiple { PipGroup(size: 58, count: 3) } else { PipView(mood: mood, size: 64, showZ: true) }
                    }
                }
            }
            Text("Inside the notch (flat)").font(.pip(12)).foregroundStyle(Color.label(0.55))
            HStack(spacing: 18) {
                ForEach(PipMood.allCases, id: \.self) { mood in
                    PipView(mood: mood, size: 22, flat: true, extras: false)
                        .padding(5)
                        .background(Color.black)
                }
            }
        }
        .padding(28)
        .background(Color(hex: 0x111114))
        .environment(\.colorScheme, .dark)
    }

    private func card<Content: View>(_ name: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 16) {
            content().frame(height: 70, alignment: .bottom)
            Text(name).font(.pip(11.5)).foregroundStyle(Color.label(0.6))
        }
        .frame(width: 118, height: 150)
        .background(RoundedRectangle(cornerRadius: 16).fill(
            RadialGradient(colors: [Color(hex: 0x1d1e25), Color(hex: 0x0b0b0d)], center: UnitPoint(x: 0.5, y: 0.4),
                           startRadius: 0, endRadius: 110)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.fill(0.07)))
    }

    static func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: CharacterSheet()))
        window.title = "Pip character sheet"
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
