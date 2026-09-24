import AppKit

/// The hardware notch Nudge hides in, or a 190pt pill the height of the menu bar on screens without one.
struct NotchGeometry: Equatable {
    var hasNotch: Bool
    var width: CGFloat
    /// Height of the top row that sits beside the camera, or of the menu bar without a notch.
    var barHeight: CGFloat

    /// The design's 190×32 stand-in, used before a screen is measured and for snapshots.
    static let fallback = NotchGeometry(hasNotch: false, width: 190, barHeight: 32)

    init(hasNotch: Bool, width: CGFloat, barHeight: CGFloat) {
        self.hasNotch = hasNotch
        self.width = width
        self.barHeight = barHeight
    }

    init(screen: NSScreen) {
        let top = screen.safeAreaInsets.top
        guard top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else {
            self.init(hasNotch: false, width: Self.fallback.width, barHeight: Self.menuBarHeight(on: screen))
            return
        }
        self.init(hasNotch: true, width: screen.frame.width - left.width - right.width, barHeight: top)
    }

    /// The built-in display when it has a notch, otherwise the primary display, which holds the menu bar.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }

    /// Sits flush with the menu bar rather than hanging below it. An auto-hiding menu bar
    /// leaves no gap in the visible frame, so fall back to the status bar's thickness.
    private static func menuBarHeight(on screen: NSScreen) -> CGFloat {
        let gap = screen.frame.maxY - screen.visibleFrame.maxY
        return gap > 0 ? gap : NSStatusBar.system.thickness
    }
}
