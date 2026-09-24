import AppKit

/// The hardware notch Nudge hides in, or the 190×32 pill used on screens without one.
struct NotchGeometry: Equatable {
    var hasNotch: Bool
    var width: CGFloat
    /// Height of the top row that sits beside the camera.
    var barHeight: CGFloat

    static let fallback = NotchGeometry(hasNotch: false, width: 190, barHeight: 32)

    init(hasNotch: Bool, width: CGFloat, barHeight: CGFloat) {
        self.hasNotch = hasNotch
        self.width = width
        self.barHeight = barHeight
    }

    init(screen: NSScreen) {
        let top = screen.safeAreaInsets.top
        guard top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else {
            self = .fallback
            return
        }
        self.init(hasNotch: true, width: screen.frame.width - left.width - right.width, barHeight: top)
    }

    /// The built-in display when it has a notch, otherwise the main screen.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }
}
