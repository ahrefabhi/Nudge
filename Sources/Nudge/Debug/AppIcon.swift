import AppKit
import NudgeKit
import SwiftUI

/// The app icon: Nudge hanging from a small black notch on a dark tile, like onboarding's hero.
/// Drawn on Apple's 1024pt icon grid (an 824pt rounded tile with a soft shadow).
struct AppIconView: View {
    static let canvas: CGFloat = 1024
    private static let tile: CGFloat = 824

    var body: some View {
        let tile = Self.tile
        let shape = RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous)
        ZStack(alignment: .top) {
            RadialGradient(colors: [Color(hex: 0x2a2c36), Color(hex: 0x0b0b0d)],
                           center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: tile * 0.62)
            NudgeView(mood: .working, size: tile * 0.52, extras: false, still: true)
                .padding(.top, tile * 0.19)
            UnevenRoundedRectangle(bottomLeadingRadius: tile * 0.06, bottomTrailingRadius: tile * 0.06)
                .fill(Color.black)
                .frame(width: tile * 0.56, height: tile * 0.15)
        }
        .frame(width: tile, height: tile)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 2))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 10)
        .frame(width: Self.canvas, height: Self.canvas)
    }

    /// Writes an `.iconset` folder: every size `iconutil` needs to build AppIcon.icns.
    static func writeIconset(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = CGFloat(points * scale)
                let renderer = ImageRenderer(content: AppIconView().environment(\.nudgeStill, true))
                renderer.scale = pixels / canvas
                guard let image = renderer.cgImage,
                      let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                else { throw CocoaError(.fileWriteUnknown) }
                let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
                try data.write(to: directory.appending(path: name))
            }
        }
    }
}
