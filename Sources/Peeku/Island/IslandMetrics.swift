import PeekuKit
import SwiftUI

/// Island size per phase, from the handoff's table. Widths that hug the notch are measured
/// from the real notch; heights follow the bar when it's taller or shorter than the design's 32pt.
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
        // A plain menu bar (about 24pt) is shorter than the design's camera row, so this can be negative.
        let extra = bar - 32
        let base = notch.width
        let shoulder = IslandShape.slot

        switch machine.phase {
        case .idle, .opening:
            if machine.celebrating != nil { return IslandMetrics(width: base + 62, height: bar, radius: 12, shoulder: shoulder) }
            // On a notch, idle is the hardware notch itself, so no flare shows on the menu bar.
            // Without one, a black pill would cover app menus, so the island tucks away entirely.
            guard notch.hasNotch else { return IslandMetrics(width: base, height: 0, radius: 0, shoulder: 0) }
            return IslandMetrics(width: base, height: bar, radius: 10, shoulder: 0)
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
            return IslandMetrics(width: 460, height: (managerIsEmpty(machine) ? 350 : 580) + managerTabRow + extra, radius: 30, shoulder: shoulder)
        }
    }

    /// The manager's Now · History · Usage · Commands row, under the camera row.
    static let managerTabRow: CGFloat = 30

    static func managerIsEmpty(_ machine: PhaseMachine) -> Bool {
        // Commands and Settings have nothing to do with sessions, so they keep the full height.
        machine.managerTab.isAgentTab && machine.sessions.isEmpty && machine.history.isEmpty
    }

    private static func alertHeight(_ session: PeekuSession?) -> CGFloat {
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

/// Light mode: the notch stays black, Peeku hangs from it, and content sits in a light panel below.
struct LightPanelLayout: Equatable {
    var width: CGFloat
    var height: CGFloat
    /// Distance from the top of the screen to the panel.
    var top: CGFloat
    var peekuSize: CGFloat
    var peekuTop: CGFloat
    var peekuMood: PeekuMood
    /// Shown on Peeku's badge when several agents wait.
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
            // Peeku hangs lower when it wears a count badge, so the badge clears the notch.
            let peekuTop = bar - (multiple ? 2 : 8)
            return LightPanelLayout(width: 400, height: design, top: peekuTop + 46, peekuSize: 40, peekuTop: peekuTop,
                                    peekuMood: multiple ? .multiple : first.kind.mood, count: queue.count, fitsContent: true)
        case .manager:
            let need = machine.queue.filter(\.needsYou)
            let mood: PeekuMood = need.isEmpty ? .idle : need.count == 1 ? need[0].kind.mood : .multiple
            let peekuTop = bar - (need.count > 1 ? 1 : 6)
            return LightPanelLayout(width: 440, height: IslandMetrics.managerIsEmpty(machine) ? 330 : 560, top: peekuTop + 40,
                                    peekuSize: 34, peekuTop: peekuTop,
                                    peekuMood: mood, count: need.count, fitsContent: false)
        default:
            return nil
        }
    }
}

/// Where the menu bar icon sits, relative to the middle of Peeku's window.
struct MenuBarAnchor: Equatable {
    var offset: CGFloat
}

/// No notch: what hangs under the menu bar icon. Quiet phases draw nothing (the icon shows
/// them); Peeku drops out for a peek and holds the alert; the manager is a panel under the icon.
struct MenuBarLayout: Equatable {
    struct Panel: Equatable {
        var width: CGFloat
        var height: CGFloat
        /// Distance from the top of the screen.
        var top: CGFloat
        /// Alerts size to their content; the manager scrolls in a fixed height.
        var fitsContent: Bool
    }

    struct Hanging: Equatable {
        var top: CGFloat
        var mood: PeekuMood
        var count: Int
    }

    var panel: Panel?
    var peeku: Hanging?

    static let peekuSize: CGFloat = 38
    /// The panel's own top row, in place of the camera row.
    static let headerHeight: CGFloat = 40
    /// Widest panel, so the window keeps it on screen near the edges.
    static let maxWidth: CGFloat = 440

    static func make(for machine: PhaseMachine, bar: CGFloat) -> MenuBarLayout {
        // Peeku hangs by its ears from the bottom of the menu bar.
        let peekuTop = bar - 10
        switch machine.phase {
        case .peek:
            return MenuBarLayout(peeku: Hanging(top: peekuTop, mood: machine.focused?.kind.mood ?? .permission, count: 1))
        case .alert:
            let queue = machine.queue
            guard let first = queue.first else { return MenuBarLayout() }
            let multiple = queue.count > 1
            // The dark heights include the 32pt camera row; the panel has a 14pt row plus padding instead.
            let design = IslandMetrics.make(for: machine, notch: .fallback).height
            let top = peekuTop - (multiple ? 6 : 0)
            return MenuBarLayout(panel: Panel(width: 380, height: design, top: top + peekuSize + 4, fitsContent: true),
                                 peeku: Hanging(top: top, mood: multiple ? .multiple : first.kind.mood, count: queue.count))
        case .manager:
            let height: CGFloat = IslandMetrics.managerIsEmpty(machine) ? 340 : 580
            return MenuBarLayout(panel: Panel(width: maxWidth, height: height, top: bar + 6, fitsContent: false))
        case .idle, .working, .pill, .opening:
            return MenuBarLayout()
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
