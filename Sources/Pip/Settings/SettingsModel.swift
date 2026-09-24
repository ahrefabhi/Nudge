import AppKit
import Observation
import PipKit

/// Settings state. Apps, hooks and permissions come from the same model onboarding uses.
@MainActor
@Observable
final class SettingsModel {
    let setup: OnboardingModel
    private(set) var autoCollapse = Preferences.autoCollapse
    private(set) var popUpOnFinish = Preferences.popUpOnFinish
    private(set) var quietUntil: Date?
    private(set) var loginItem = LoginItem.status
    var loginError: String?

    /// Called after a notification preference changes, so the app can apply it.
    @ObservationIgnored var onPreferencesChanged: (() -> Void)?
    @ObservationIgnored var onQuietChanged: (() -> Void)?
    @ObservationIgnored private var poll: Timer?

    init(setup: OnboardingModel) {
        self.setup = setup
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
        loginItem = LoginItem.status
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
