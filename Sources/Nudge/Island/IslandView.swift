import AppKit
import NudgeKit
import SwiftUI

/// The whole notch UI: one black island that springs between phases, anchored top-center.
struct IslandView: View {
    let machine: PhaseMachine
    let notch: NotchGeometry
    var presence: PresenceMonitor?
    /// Where the light panel measured itself, for the pointer hit area.
    var hitArea: IslandHitArea?
    /// Snapshots pin the appearance; the app follows the setting.
    var forceLight: Bool?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var systemScheme
    @AppStorage(PanelAppearance.defaultsKey) private var appearance = PanelAppearance.automatic.rawValue

    private var isLight: Bool {
        forceLight ?? (PanelAppearance(rawValue: appearance) ?? .automatic).isLight(systemIsDark: systemScheme == .dark)
    }

    var body: some View {
        let metrics = IslandMetrics.make(for: machine, notch: notch, minimal: presence?.state.minimal ?? false)
        let panel = isLight && !metrics.glow ? LightPanelLayout.make(for: machine, notch: notch) : nil
        Group {
            if metrics.glow {
                GlowStrip(metrics: metrics, color: machine.focused?.kind.accent ?? Tokens.Accent.permission) { machine.tapIsland() }
            } else {
                ZStack(alignment: .top) {
                    if let panel {
                        lightPanel(panel).transition(.lightPanel(reduceMotion: reduceMotion))
                    }
                    // In light mode the island shrinks back to the plain notch while the panel shows.
                    island(panel == nil ? metrics : IslandMetrics.make(for: machine, notch: notch, asNotch: true), showsContent: panel == nil)
                }
                .animation(reduceMotion ? Motion.reduced : Motion.islandSpring, value: panel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func island(_ metrics: IslandMetrics, showsContent: Bool) -> some View {
        let expanded = metrics.expanded
        let shape = IslandShape(bottomRadius: metrics.radius, shoulder: metrics.shoulder)

        ZStack(alignment: .top) {
            shape
                .fill(Tokens.island)
                .overlay(shape.stroke(Color.white.opacity(expanded ? 0.06 : 0), lineWidth: 0.5))
                .shadow(color: Tokens.expandedShadow.opacity(expanded ? 1 : 0), radius: 30, y: 24)

            if showsContent {
                content(wing: (metrics.width - notch.width) / 2, expanded: metrics.expanded)
                    .frame(width: metrics.width, height: metrics.height, alignment: .top)
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: metrics.radius, bottomTrailingRadius: metrics.radius))
                    .animation(reduceMotion ? Motion.reduced : .default, value: contentKey)
            }
        }
        .frame(width: metrics.outerWidth, height: metrics.height, alignment: .top)
        .contentShape(shape)
        .onTapGesture { machine.tapIsland() }
        .animation(Motion.island(expanding: machine.expanding, reduceMotion: reduceMotion), value: metrics)
        .environment(\.colorScheme, .dark)
    }

    /// The light panel below the notch, with Nudge hanging between them.
    private func lightPanel(_ layout: LightPanelLayout) -> some View {
        ZStack(alignment: .top) {
            LightPanel(fitsContent: layout.fitsContent) {
                content(wing: 0, expanded: true)
                    .animation(reduceMotion ? Motion.reduced : .default, value: contentKey)
            }
            .frame(width: layout.width, height: layout.fitsContent ? nil : layout.height)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { hitArea?.lightPanelHeight = $0 }
            .padding(.top, layout.top)

            NudgeView(mood: layout.nudgeMood, size: layout.nudgeSize, extras: layout.count > 1, count: layout.count, lifted: true)
                .modifier(DropIn(size: layout.nudgeSize))
                .padding(.top, layout.nudgeTop)
                .id(layout.nudgeMood)
        }
    }

    /// Changes whenever the island shows different content, so the old content fades out.
    private var contentKey: String {
        switch machine.phase {
        case .alert: machine.queue.count > 1 ? "alert-multi" : "alert-\(machine.focused?.attentionKey ?? "")"
        case .idle, .working: machine.celebrating == nil ? "wings" : "wings-celebrating"
        default: machine.phase.rawValue
        }
    }

    @ViewBuilder
    private func content(wing: CGFloat, expanded: Bool) -> some View {
        let bar = notch.barHeight
        let transition = AnyTransition.islandContent(delay: expanded ? 0.17 : 0.15, reduceMotion: reduceMotion)

        ZStack(alignment: .top) {
            switch machine.phase {
            // These have nothing to click, and their animations (Nudge's eyes, the spinner) redraw
            // every frame, which can swallow a click. Leave taps to the island.
            case .working, .idle:
                if machine.phase == .working || machine.celebrating != nil {
                    WorkingWings(count: machine.working.count, celebrating: machine.celebrating != nil, wing: wing, bar: bar)
                        .allowsHitTesting(false)
                }
            case .peek:
                PeekView(mood: machine.focused?.kind.mood ?? .permission)
                    .allowsHitTesting(false)
            case .pill:
                PillView(mood: pillMood, count: machine.queue.count,
                         accent: machine.focused?.kind.accent ?? Tokens.Accent.permission, wing: wing, bar: bar)
                    .allowsHitTesting(false)
            case .alert:
                if machine.queue.count > 1 {
                    MultiAlertView(queue: machine.queue, cursor: machine.cursorMoved ? machine.cursor : nil, bar: bar) { machine.open($0.id) }
                } else if let session = machine.focused {
                    AlertCardView(session: session, bar: bar,
                                  onOpen: { machine.open(session.id) },
                                  onLater: { machine.later() },
                                  onAllAgents: { machine.toggleManager() })
                }
            case .manager:
                ManagerView(machine: machine, bar: bar)
            case .opening:
                EmptyView()
            }
        }
        .id(contentKey)
        // Nudge's drop is its own entrance; everything else uses the content-in transition.
        .transition(machine.phase == .peek ? .asymmetric(insertion: .identity, removal: .opacity.animation(.easeIn(duration: 0.1))) : transition)
    }

    private var pillMood: NudgeMood {
        machine.queue.count > 1 ? .multiple : machine.focused?.kind.mood ?? .permission
    }
}

/// Minimal mode's 4px accent glow on the top edge. Clicking it opens the waiting alert.
private struct GlowStrip: View {
    let metrics: IslandMetrics
    let color: Color
    let onTap: () -> Void

    var body: some View {
        UnevenRoundedRectangle(bottomLeadingRadius: metrics.radius, bottomTrailingRadius: metrics.radius)
            .fill(color)
            .frame(width: metrics.width, height: 4)
            .shadow(color: color.opacity(0.8), radius: 6)
            .frame(width: metrics.width, height: metrics.height, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .opacity(metrics.width > 0 ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: metrics.width)
            .accessibilityElement()
            .accessibilityLabel("An agent needs you")
            .accessibilityAddTraits(.isButton)
    }
}

/// The light panel: frosted, 18pt corners, a hairline and a soft shadow, with light content.
private struct LightPanel<Content: View>: View {
    var fitsContent: Bool
    @ViewBuilder let content: Content
    @Environment(\.nudgeStill) private var still

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        Group {
            if fitsContent {
                content.fixedSize(horizontal: false, vertical: true)
            } else {
                content.frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .clipShape(shape)
        .background {
            ZStack {
                // The shadow lives outside the panel only: the frosted fill is see-through, and a
                // shadow under it would show as a grey box behind the content.
                shape
                    .fill(Color.black)
                    .shadow(color: Color(.sRGB, red: 20 / 255, green: 24 / 255, blue: 40 / 255, opacity: 0.2), radius: 22, y: 18)
                    .overlay(shape.fill(Color.black).blendMode(.destinationOut))
                    .compositingGroup()
                // ImageRenderer can't draw the AppKit blur, so snapshots use a solid fill.
                if !still { FrostedBackground().clipShape(shape) }
                shape.fill(Color(hex: 0xfafafc, opacity: still ? 0.97 : 0.62))
            }
        }
        .overlay(shape.strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5))
        .environment(\.palette, .light)
        .environment(\.colorScheme, .light)
    }
}

/// Shared with the notch controller, which needs the light panel's real height to know where clicks land.
@Observable
final class IslandHitArea {
    var lightPanelHeight: CGFloat?
}

/// `backdrop-filter: blur(30px) saturate(1.8)`: blurs whatever is behind the window.
private struct FrostedBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .aqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension AnyTransition {
    /// The panel settles in from just under the notch and fades out going away.
    static func lightPanel(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity).combined(with: .offset(y: -8)),
            removal: .opacity.animation(.easeIn(duration: 0.15))
        )
    }
}
