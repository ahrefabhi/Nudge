import PipKit
import SwiftUI

/// Island size per phase, from the handoff's table. Widths that hug the notch are measured
/// from the real notch; heights grow when the notch is taller than the design's 32pt.
struct IslandMetrics: Equatable {
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat
    var shoulder: CGFloat

    /// Minimal mode: a 4px accent strip on the top edge instead of the island.
    var glow = false

    var outerWidth: CGFloat { width + 2 * IslandShape.slot }
    var expanded: Bool { width > 320 }

    /// The strip's hit area is taller than what's drawn, so it's easy to click.
    static let glowHitHeight: CGFloat = 10

    /// `minimal`: the menu bar is hidden, so quiet phases shrink to the glow, and to nothing
    /// when no one is waiting. Anything the user opened (alert, manager) still shows in full.
    /// The island as the plain hardware notch, for when content lives in the light panel.
    static func make(for machine: PhaseMachine, notch: NotchGeometry, asNotch: Bool) -> IslandMetrics {
        IslandMetrics(width: notch.width, height: notch.barHeight, radius: 10, shoulder: notch.hasNotch ? 0 : IslandShape.slot)
    }

    static func make(for machine: PhaseMachine, notch: NotchGeometry, minimal: Bool = false) -> IslandMetrics {
        if minimal, [.idle, .working, .pill, .opening].contains(machine.phase) {
            guard !machine.queue.isEmpty else { return IslandMetrics(width: 0, height: 0, radius: 0, shoulder: 0, glow: true) }
            return IslandMetrics(width: notch.width + 40, height: glowHitHeight, radius: 2, shoulder: 0, glow: true)
        }
        let bar = notch.barHeight
        let extra = max(0, bar - 32)
        let base = notch.width
        let shoulder = IslandShape.slot

        switch machine.phase {
        case .idle, .opening:
            if machine.celebrating != nil { return IslandMetrics(width: base + 62, height: bar, radius: 12, shoulder: shoulder) }
            // On a notch, idle is the hardware notch itself, so no flare shows on the menu bar.
            return IslandMetrics(width: base, height: bar, radius: 10, shoulder: notch.hasNotch ? 0 : shoulder)
        case .working:
            return IslandMetrics(width: base + 62, height: bar, radius: 12, shoulder: shoulder)
        case .peek:
            return IslandMetrics(width: base + 16, height: 60 + extra, radius: 28, shoulder: shoulder)
        case .pill:
            return IslandMetrics(width: base + 110, height: bar, radius: 14, shoulder: shoulder)
        case .alert:
            let queue = machine.queue
            if queue.count > 1 {
                let rows = min(queue.count, 6)
                return IslandMetrics(width: 420, height: 268 + CGFloat(rows - 3) * 35 + extra, radius: 30, shoulder: shoulder)
            }
            return IslandMetrics(width: 420, height: alertHeight(machine.focused) + extra, radius: 30, shoulder: shoulder)
        case .manager:
            // With nothing running and no history there's only the empty state to show.
            return IslandMetrics(width: 460, height: (managerIsEmpty(machine) ? 350 : 580) + extra, radius: 30, shoulder: shoulder)
        }
    }

    static func managerIsEmpty(_ machine: PhaseMachine) -> Bool {
        machine.sessions.isEmpty && machine.history.isEmpty
    }

    private static func alertHeight(_ session: PipSession?) -> CGFloat {
        guard let session else { return 208 }
        switch session.kind {
        case .question, .waiting:
            let choices = min(session.choices.count, 4)
            return choices == 0 ? 226 : 226 + CGFloat(choices) * 24 + 22
        default:
            return 208
        }
    }
}

/// Light mode: the notch stays black, Pip hangs from it, and content sits in a light panel below.
struct LightPanelLayout: Equatable {
    var width: CGFloat
    var height: CGFloat
    /// Distance from the top of the screen to the panel.
    var top: CGFloat
    var pipSize: CGFloat
    var pipTop: CGFloat
    var pipMood: PipMood
    /// Shown on Pip's badge when several agents wait.
    var count: Int
    /// Alerts size to their content, like the design's panel; the manager scrolls in a fixed height.
    var fitsContent: Bool

    /// The light panel is for content the user reads: alerts and the manager. Everything that
    /// lives in the notch (working, peek, pill) stays black.
    static func make(for machine: PhaseMachine, notch: NotchGeometry) -> LightPanelLayout? {
        let bar = notch.barHeight
        // The dark heights include a 32pt camera row; in the panel that's a 14pt row plus padding.
        let design = IslandMetrics.make(for: machine, notch: .fallback).height
        switch machine.phase {
        case .alert:
            let queue = machine.queue
            guard let first = queue.first else { return nil }
            let multiple = queue.count > 1
            // Pip hangs lower when it wears a count badge, so the badge clears the notch.
            let pipTop = bar - (multiple ? 2 : 8)
            return LightPanelLayout(width: 400, height: design, top: pipTop + 46, pipSize: 40, pipTop: pipTop,
                                    pipMood: multiple ? .multiple : first.kind.mood, count: queue.count, fitsContent: true)
        case .manager:
            let need = machine.queue.filter(\.needsYou)
            let mood: PipMood = need.isEmpty ? .idle : need.count == 1 ? need[0].kind.mood : .multiple
            let pipTop = bar - (need.count > 1 ? 1 : 6)
            return LightPanelLayout(width: 440, height: IslandMetrics.managerIsEmpty(machine) ? 330 : 560, top: pipTop + 40,
                                    pipSize: 34, pipTop: pipTop,
                                    pipMood: mood, count: need.count, fitsContent: false)
        default:
            return nil
        }
    }
}

/// Automatic follows the system; the notch itself is black either way.
enum PanelAppearance: String, CaseIterable, Identifiable {
    case automatic, dark, light
    var id: Self { self }

    static let defaultsKey = "panelAppearance"

    static var stored: PanelAppearance {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(PanelAppearance.init(rawValue:)) ?? .automatic
    }

    func isLight(systemIsDark: Bool) -> Bool {
        switch self {
        case .automatic: !systemIsDark
        case .dark: false
        case .light: true
        }
    }

    var title: String {
        switch self {
        case .automatic: "Match System"
        case .dark: "Dark"
        case .light: "Light"
        }
    }
}
