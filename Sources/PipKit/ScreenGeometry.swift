import CoreGraphics

public enum ScreenGeometry {
    /// Accessibility and the window server measure from the top-left of the primary display;
    /// AppKit measures from its bottom-left.
    public static func appKitRect(fromTopLeft rect: CGRect, primaryDisplayHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryDisplayHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
