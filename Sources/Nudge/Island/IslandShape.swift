import SwiftUI

nonisolated private let kappa: CGFloat = 0.5523

/// The black island: flush with the bezel on top, rounded at the bottom, with two inverse
/// "shoulder" corners that flare into the top edge. The shape's rect reserves `slot` on each
/// side for the shoulders.
struct IslandShape: Shape {
    static let slot: CGFloat = 10

    var bottomRadius: CGFloat
    var shoulder: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, shoulder) }
        set { (bottomRadius, shoulder) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        let left = rect.minX + Self.slot, right = rect.maxX - Self.slot
        let top = rect.minY, bottom = rect.maxY
        let r = max(0, min(bottomRadius, (right - left) / 2, rect.height))
        let sh = max(0, min(shoulder, Self.slot, rect.height))

        var path = Path()
        path.move(to: CGPoint(x: left - sh, y: top))
        path.addLine(to: CGPoint(x: right + sh, y: top))
        if sh > 0 {
            path.addCurve(to: CGPoint(x: right, y: top + sh),
                          control1: CGPoint(x: right + sh - kappa * sh, y: top),
                          control2: CGPoint(x: right, y: top + sh - kappa * sh))
        }
        path.addLine(to: CGPoint(x: right, y: bottom - r))
        path.addCurve(to: CGPoint(x: right - r, y: bottom),
                      control1: CGPoint(x: right, y: bottom - r + kappa * r),
                      control2: CGPoint(x: right - r + kappa * r, y: bottom))
        path.addLine(to: CGPoint(x: left + r, y: bottom))
        path.addCurve(to: CGPoint(x: left, y: bottom - r),
                      control1: CGPoint(x: left + r - kappa * r, y: bottom),
                      control2: CGPoint(x: left, y: bottom - r + kappa * r))
        path.addLine(to: CGPoint(x: left, y: top + sh))
        if sh > 0 {
            path.addCurve(to: CGPoint(x: left - sh, y: top),
                          control1: CGPoint(x: left, y: top + sh - kappa * sh),
                          control2: CGPoint(x: left - sh + kappa * sh, y: top))
        }
        path.closeSubpath()
        return path
    }
}
