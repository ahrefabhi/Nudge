import AppKit
import Sparkle

/// Updates through Sparkle. Releases live on GitHub; each one carries an `appcast.xml` whose
/// download is verified against the EdDSA key in Info.plist.
final class Updater {
    private let controller: SPUStandardUpdaterController?

    init() {
        // Only a real Pip.app has a feed URL; `swift run` and snapshots skip Sparkle entirely.
        let bundled = Bundle.main.bundleURL.pathExtension == "app"
            && Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        controller = bundled ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil) : nil
    }

    var isAvailable: Bool { controller != nil }

    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }

    var checksAutomatically: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    var lastChecked: Date? { controller?.updater.lastUpdateCheckDate }

    /// Shows Sparkle's window. Pip has no Dock icon, so bring it forward first.
    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }
}
