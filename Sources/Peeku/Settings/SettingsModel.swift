import AppKit
import Observation
import PeekuKit

/// Settings state. Apps, hooks and permissions come from the same model onboarding uses.
/// Settings show inside the manager; `start` and `stop` follow its Settings view.
@MainActor
@Observable
final class SettingsModel {
    let setup: OnboardingModel
    @ObservationIgnored let updater: Updater?
    private(set) var checksForUpdates = false
    private(set) var lastUpdateCheck: Date?
    private(set) var autoCollapse = Preferences.autoCollapse
    private(set) var popUpOnFinish = Preferences.popUpOnFinish
    private(set) var quietInView = Preferences.quietInView
    private(set) var usageAlertRules = Preferences.usageAlertRules
    private(set) var commandsEnabled = Preferences.commandsEnabled
    private(set) var skillsEnabled = Preferences.skillsEnabled
    private(set) var prefersMenuBar = Preferences.prefersMenuBar
    private(set) var soundsEnabled = Preferences.soundsEnabled
    private(set) var sounds = Dictionary(uniqueKeysWithValues: Chime.allCases.map { ($0, Preferences.sound(for: $0)) })
    private(set) var quietUntil: Date?
    private(set) var loginItem = LoginItem.status
    var loginError: String?

    /// Called after a notification preference changes, so the app can apply it.
    @ObservationIgnored var onPreferencesChanged: (() -> Void)?
    @ObservationIgnored var onQuietChanged: (() -> Void)?
    /// Called when Peeku moves between the notch and the menu bar.
    @ObservationIgnored var onPlacementChanged: (() -> Void)?
    /// Usage alerts are edited in the manager's Usage tab.
    @ObservationIgnored var onEditUsageAlerts: (() -> Void)?
    /// Runs an action that shows a dialog or a system prompt. The notch floats above ordinary
    /// windows, so the app closes the manager first.
    @ObservationIgnored var presentingDialog: (@escaping () -> Void) -> Void = { $0() }
    @ObservationIgnored private var poll: Timer?

    init(setup: OnboardingModel, updater: Updater? = nil) {
        self.setup = setup
        self.updater = updater
    }

    func start() {
        refresh()
        setup.start()
        poll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        poll?.invalidate()
        poll = nil
        setup.stop()
    }

    func refresh() {
        quietUntil = Preferences.quietUntil.flatMap { $0 > Date() ? $0 : nil }
        usageAlertRules = Preferences.usageAlertRules
        loginItem = LoginItem.status
        checksForUpdates = updater?.checksAutomatically ?? false
        lastUpdateCheck = updater?.lastChecked
    }

    func setChecksForUpdates(_ on: Bool) {
        updater?.checksAutomatically = on
        refresh()
    }

    // MARK: Actions

    func setAutoCollapse(_ on: Bool) {
        autoCollapse = on
        Preferences.autoCollapse = on
        onPreferencesChanged?()
    }

    func setPopUpOnFinish(_ on: Bool) {
        popUpOnFinish = on
        Preferences.popUpOnFinish = on
        onPreferencesChanged?()
    }

    func setQuietInView(_ on: Bool) {
        quietInView = on
        Preferences.quietInView = on
    }

    func setPrefersMenuBar(_ on: Bool) {
        prefersMenuBar = on
        Preferences.prefersMenuBar = on
        onPlacementChanged?()
    }

    func setCommandsEnabled(_ on: Bool) {
        commandsEnabled = on
        Preferences.commandsEnabled = on
        onPreferencesChanged?()
    }

    func setSkillsEnabled(_ on: Bool) {
        skillsEnabled = on
        Preferences.skillsEnabled = on
        onPreferencesChanged?()
    }

    func setSoundsEnabled(_ on: Bool) {
        soundsEnabled = on
        Preferences.soundsEnabled = on
    }

    /// Choosing a sound plays it, so the picker doubles as a preview.
    func setSound(_ name: String?, for chime: Chime) {
        sounds[chime] = name
        Preferences.setSound(name, for: chime)
        if let name { Sounds.preview(name) }
    }

    func setQuiet(for duration: TimeInterval?) {
        Preferences.quietUntil = duration.map { Date().addingTimeInterval($0) }
        refresh()
        onQuietChanged?()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            try LoginItem.set(on)
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        refresh()
    }
}
