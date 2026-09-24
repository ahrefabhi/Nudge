import CoreGraphics
import Testing
@testable import PipKit

@Suite struct ScreenGeometryTests {
    @Test func flipsATopLeftRectOntoTheAppKitGrid() {
        // A 800×600 window 100pt from the top of a 1329pt-tall display.
        let rect = ScreenGeometry.appKitRect(fromTopLeft: CGRect(x: 40, y: 100, width: 800, height: 600), primaryDisplayHeight: 1329)
        #expect(rect == CGRect(x: 40, y: 629, width: 800, height: 600))
    }

    @Test func handlesDisplaysAboveThePrimaryOne() {
        // Negative y: a display arranged above the primary.
        let rect = ScreenGeometry.appKitRect(fromTopLeft: CGRect(x: 0, y: -900, width: 500, height: 400), primaryDisplayHeight: 1000)
        #expect(rect == CGRect(x: 0, y: 1500, width: 500, height: 400))
    }
}
