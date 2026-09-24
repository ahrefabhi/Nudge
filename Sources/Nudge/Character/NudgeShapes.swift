import SwiftUI

/// Cubic handle length for a quarter ellipse.
nonisolated private let kappa: CGFloat = 0.5523

/// Nudge's body: CSS `border-radius: 50% 50% 46% 46% / 60% 60% 40% 40%`.
struct NudgeBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let topX = 0.50 * w, topY = 0.60 * h
        let bottomX = 0.46 * w, bottomY = 0.40 * h
        var path = Path()
        path.move(to: CGPoint(x: topX, y: 0))
        path.addCurve(to: CGPoint(x: w, y: topY),
                      control1: CGPoint(x: w - topX + kappa * topX, y: 0),
                      control2: CGPoint(x: w, y: topY - kappa * topY))
        path.addLine(to: CGPoint(x: w, y: h - bottomY))
        path.addCurve(to: CGPoint(x: w - bottomX, y: h),
                      control1: CGPoint(x: w, y: h - bottomY + kappa * bottomY),
                      control2: CGPoint(x: w - bottomX + kappa * bottomX, y: h))
        path.addLine(to: CGPoint(x: bottomX, y: h))
        path.addCurve(to: CGPoint(x: 0, y: h - bottomY),
                      control1: CGPoint(x: bottomX - kappa * bottomX, y: h),
                      control2: CGPoint(x: 0, y: h - bottomY + kappa * bottomY))
        path.addLine(to: CGPoint(x: 0, y: topY))
        path.addCurve(to: CGPoint(x: topX, y: 0),
                      control1: CGPoint(x: 0, y: topY - kappa * topY),
                      control2: CGPoint(x: topX - kappa * topX, y: 0))
        path.closeSubpath()
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// The happy "success" eye: a rounded arch with no bottom, meant to be stroked.
struct ArchShape: Shape {
    var lineWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let inset = lineWidth / 2
        let left = rect.minX + inset, right = rect.maxX - inset
        let radius = (right - left) / 2
        let top = rect.minY + inset
        let shoulder = min(top + radius, rect.maxY)
        let midX = (left + right) / 2
        var path = Path()
        path.move(to: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: left, y: shoulder))
        path.addCurve(to: CGPoint(x: midX, y: top),
                      control1: CGPoint(x: left, y: shoulder - kappa * radius),
                      control2: CGPoint(x: midX - kappa * radius, y: top))
        path.addCurve(to: CGPoint(x: right, y: shoulder),
                      control1: CGPoint(x: midX + kappa * radius, y: top),
                      control2: CGPoint(x: right, y: shoulder - kappa * radius))
        path.addLine(to: CGPoint(x: right, y: rect.maxY))
        return path
    }
}
