import AppKit
import SwiftUI

/// Pip's silhouette for the menu bar: ears and body from the character's own shapes, eyes cut
/// out. A template image, so macOS tints it for light, dark and highlighted menu bars.
enum MenuBarIcon {
    static let size: CGFloat = 18

    static func image() -> NSImage {
        let renderer = ImageRenderer(content: Silhouette(size: size))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "eyes", accessibilityDescription: nil) ?? NSImage()
        image.size = NSSize(width: size, height: size)
        image.isTemplate = true
        image.accessibilityDescription = "Pip"
        return image
    }

    private struct Silhouette: View {
        let size: CGFloat

        var body: some View {
            let s = size
            ZStack(alignment: .topLeading) {
                ear(left: true)
                ear(left: false)
                PipBodyShape()
                    .frame(width: s, height: 0.82 * s)
                    .offset(y: 0.14 * s)
                // Slightly larger than the character's eyes so they still read at 18pt.
                eye.offset(x: 0.28 * s, y: 0.43 * s)
                eye.offset(x: s - 0.28 * s - 0.15 * s, y: 0.43 * s)
            }
            .frame(width: s, height: s, alignment: .topLeading)
            .compositingGroup()
            .foregroundStyle(Color.black)
        }

        private func ear(left: Bool) -> some View {
            Ellipse()
                .frame(width: 0.22 * size, height: 0.28 * size)
                .rotationEffect(.degrees(left ? -20 : 20))
                .offset(x: left ? 0.13 * size : size - 0.13 * size - 0.22 * size, y: 0.04 * size)
        }

        private var eye: some View {
            Capsule()
                .frame(width: 0.15 * size, height: 0.27 * size)
                .blendMode(.destinationOut)
        }
    }
}
