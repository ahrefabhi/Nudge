import AppKit
import PeekuKit
import SwiftUI

/// Peeku's silhouette for the menu bar: ears and body from the character's own shapes, eyes cut
/// out. Idle and working stay a template image, so macOS tints it for light, dark and highlighted
/// menu bars. On a Mac without a notch the eyes carry the other states too, in their accent color,
/// with a dot or a count when someone waits.
enum MenuBarIcon {
    static let size: CGFloat = 18

    struct State: Equatable {
        var mood: PeekuMood = .idle
        /// Several waiting shows a count; one waiting shows a dot.
        var count = 0
        /// While working the eyes glance: -1 left, 0 middle, 1 right.
        var glance: CGFloat = 0

        var isTemplate: Bool { (mood == .idle || mood == .working) && count == 0 }
    }

    /// `nil` is the plain icon a notched Mac keeps, where the notch shows the state.
    static func image(_ state: State? = nil, darkMenuBar: Bool = true) -> NSImage {
        let state = state ?? State(mood: .working)
        let badge = state.count > 0
        let width = badge ? size + 8 : size
        let fill = state.isTemplate ? Color.black : darkMenuBar ? Color(hex: 0xf5f5f7) : Color(hex: 0x1d1d1f)
        let renderer = ImageRenderer(content: Silhouette(size: size, state: state, fill: fill)
            .frame(width: width, height: size, alignment: .leading))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "eyes", accessibilityDescription: nil) ?? NSImage()
        image.size = NSSize(width: width, height: size)
        image.isTemplate = state.isTemplate
        image.accessibilityDescription = "Peeku"
        return image
    }

    private struct Silhouette: View {
        let size: CGFloat
        let state: State
        let fill: Color

        var body: some View {
            let s = size
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    ear(left: true)
                    ear(left: false)
                    PeekuBodyShape()
                        .frame(width: s, height: 0.82 * s)
                        .offset(y: 0.14 * s)
                    // Cut out even when colored, so the menu bar shows through around the eyes.
                    eyes.blendMode(.destinationOut)
                }
                .foregroundStyle(fill)
                if let accent { eyes.foregroundStyle(accent) }
                if state.count == 1 {
                    Circle().fill(accent ?? .orange)
                        .frame(width: 0.34 * s, height: 0.34 * s)
                        .overlay(Circle().stroke(Color.black, lineWidth: 1.4).blendMode(.destinationOut))
                        .offset(x: s - 0.12 * s, y: 0)
                } else if state.count > 1 {
                    Text("\(min(state.count, 9))")
                        .font(.system(size: 0.44 * s, weight: .bold))
                        .foregroundStyle(Color(hex: 0x17120a))
                        .frame(width: 0.52 * s, height: 0.52 * s)
                        .background(Circle().fill(accent ?? .orange))
                        .overlay(Circle().stroke(Color.black, lineWidth: 1.4).blendMode(.destinationOut))
                        .offset(x: s - 0.1 * s, y: -0.02 * s)
                }
            }
            .frame(width: s, height: s, alignment: .topLeading)
            .compositingGroup()
        }

        private var accent: Color? {
            state.isTemplate ? nil : state.mood.eyeColor
        }

        private func ear(left: Bool) -> some View {
            Ellipse()
                .frame(width: 0.22 * size, height: 0.28 * size)
                .rotationEffect(.degrees(left ? -20 : 20))
                .offset(x: left ? 0.13 * size : size - 0.13 * size - 0.22 * size, y: 0.04 * size)
        }

        /// Slightly larger than the character's eyes so they still read at 18pt.
        private var eyes: some View {
            let s = size
            let shift = state.mood == .working ? state.glance * 0.06 * s : 0
            return ZStack(alignment: .topLeading) {
                eye(left: true).offset(x: 0.28 * s + shift)
                eye(left: false).offset(x: s - 0.28 * s - 0.15 * s + shift)
            }
        }

        @ViewBuilder
        private func eye(left: Bool) -> some View {
            let s = size
            switch state.mood {
            case .idle:
                Capsule().frame(width: 0.15 * s, height: 0.07 * s).offset(y: 0.58 * s)
            case .question:
                let height = (left ? 0.19 : 0.27) * s
                Capsule().frame(width: 0.15 * s, height: height).offset(y: 0.43 * s + 0.27 * s - height)
            case .permission, .multiple:
                Capsule().frame(width: 0.16 * s, height: 0.29 * s).offset(y: 0.41 * s)
            case .error:
                Capsule().frame(width: 0.19 * s, height: 0.08 * s)
                    .rotationEffect(.degrees(left ? -22 : 22))
                    .offset(y: 0.54 * s)
            case .success:
                Arch().stroke(style: StrokeStyle(lineWidth: 0.07 * s, lineCap: .round))
                    .frame(width: 0.16 * s, height: 0.1 * s)
                    .offset(y: 0.52 * s)
            case .working:
                Capsule().frame(width: 0.15 * s, height: 0.27 * s).offset(y: 0.43 * s)
            }
        }
    }

    /// The finished state's happy eyes: the top half of an oval.
    private struct Arch: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height))
            }
        }
    }
}
