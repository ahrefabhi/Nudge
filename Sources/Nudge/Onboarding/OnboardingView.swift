import NudgeKit
import SwiftUI

/// Three steps in one 420×420 window: hello, where agents run, permissions. With Codex the
/// window is one row taller, for its hooks row in the last step.
struct OnboardingView: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            // The window's own traffic lights sit in this strip.
            Color.clear.frame(height: 36)
            Group {
                switch model.step {
                case .hello: HelloStep()
                case .environments: EnvironmentsStep(model: model)
                case .permissions: PermissionsStep(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .id(model.step)
            .transition(.opacity.animation(.easeOut(duration: 0.18)))
            footer
        }
        .frame(width: 420, height: model.codexHooks == nil ? 420 : 476)
        .background(Color(hex: 0x1c1c1f, opacity: 0.96))
        .foregroundStyle(Tokens.textPrimary)
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.18), value: model.step)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text("\(model.step.rawValue) / \(OnboardingModel.Step.allCases.count)")
                .font(.nudgeMono(11))
                .foregroundStyle(Color.label(0.35))
            Spacer()
            if model.step == .permissions, model.needsSystemSettings {
                Button("Done") { model.finish() }
                    .buttonStyle(LinkTextStyle())
                Button("Open System Settings") { model.openSystemSettings() }
                    .buttonStyle(OnboardingPrimaryStyle())
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(model.step == .permissions ? "Finish" : "Continue") { model.advance() }
                    .buttonStyle(OnboardingPrimaryStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .overlay(alignment: .top) { Rectangle().fill(Color.fill(0.06)).frame(height: 1) }
    }
}

// MARK: Steps

private struct HelloStep: View {
    var body: some View {
        VStack(spacing: 22) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(RadialGradient(colors: [Color(hex: 0x23242c), Color(hex: 0x0b0b0d)],
                                         center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 80))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.fill(0.06)))
                NudgeView(mood: .working, size: 76)
                    .padding(.top, 22)
                UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                    .fill(Color.black)
                    .overlay(UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8).stroke(Color.fill(0.08), lineWidth: 0.5))
                    .frame(width: 84, height: 18)
            }
            .frame(width: 150, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(spacing: 8) {
                Text("Hi, I'm Nudge.")
                    .font(.nudge(20, .semibold))
                    .tracking(-0.2)
                Text("I live in your notch and watch your coding agents. I'll only come out when one of them needs you.")
                    .font(.nudge(13))
                    .lineSpacing(4)
                    .foregroundStyle(Color.label(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 44)
        .frame(maxHeight: .infinity)
    }
}

private struct EnvironmentsStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Where do your agents run?")
                    .font(.nudge(18, .semibold))
                    .tracking(-0.18)
                Text("I found these. Change them any time from the menu bar.")
                    .font(.nudge(13))
                    .foregroundStyle(Color.label(0.55))
            }
            OnboardingList(rows: model.environments) { environment in
                HStack(spacing: 12) {
                    RowText(title: environment.host.onboardingName, detail: environment.detail)
                    NudgeToggle(isOn: environment.enabled) { model.toggle(environment.host) }
                }
                .padding(.vertical, 11)
                .padding(.horizontal, 14)
            }
        }
        .padding(EdgeInsets(top: 6, leading: 28, bottom: 0, trailing: 28))
    }
}

private struct PermissionsStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                NudgeView(mood: .success, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Let me open sessions for you")
                        .font(.nudge(18, .semibold))
                        .tracking(-0.18)
                    Text("So Open Session lands on the exact tab.")
                        .font(.nudge(13))
                        .foregroundStyle(Color.label(0.55))
                }
            }
            OnboardingList(rows: rows) { row in
                HStack(spacing: 12) {
                    if let agent = row.agent { AgentMark(agent: agent, size: 16) }
                    RowText(title: row.title, detail: row.detail)
                    switch row.status {
                    case .done(let label):
                        Text("✓ \(label)")
                            .font(.nudge(12))
                            .foregroundStyle(Tokens.Accent.success)
                    case .action(let label, let perform):
                        Button(label, action: perform)
                            .buttonStyle(OnboardingSmallStyle())
                    case .note(let label):
                        Text(label)
                            .font(.nudge(12))
                            .foregroundStyle(Color.label(0.45))
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
            }
            if model.suggestsReset {
                HStack(spacing: 6) {
                    Text("Already on in System Settings?")
                        .foregroundStyle(Color.label(0.55))
                    Button("Reset and ask again") { model.resetPermissions() }
                        .buttonStyle(LinkTextStyle())
                }
                .font(.nudge(11.5))
            }
            Text("Nudge only reads session state. It never types into your terminal or approves anything on your behalf.")
                .font(.nudge(11.5))
                .lineSpacing(3)
                .foregroundStyle(Color.label(0.4))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(EdgeInsets(top: 6, leading: 28, bottom: 0, trailing: 28))
    }

    private struct Row: Identifiable {
        enum Status {
            case done(String)
            case action(String, () -> Void)
            case note(String)
        }
        let title: String
        let detail: String
        let status: Status
        var agent: Agent? = nil
        var id: String { title }
    }

    private var rows: [Row] {
        let hooks: Row.Status = switch model.hooks {
        case .installed: .done("Installed")
        case .incomplete: .action("Update…", model.installHooks)
        case .notInstalled: .action("Install…", model.installHooks)
        }
        let automation: Row.Status = switch model.automation {
        case .granted: .done("Allowed")
        case .needsAsk: .action("Allow…", model.allowAutomation)
        case .denied: .action("Open Settings…", model.allowAutomation)
        case .asksOnFirstUse: .note("Asks on first use")
        }
        var rows = [Row(title: "Claude Code hooks", detail: "Adds \(HookInstaller.events.count) hooks to \(model.settingsPath)", status: hooks, agent: .claude)]
        if let codex = model.codexHooks {
            let status: Row.Status = switch codex {
            case .installed: .done("Installed")
            case .incomplete: .action("Update…") { model.installHooks(.codex) }
            case .notInstalled: .action("Install…") { model.installHooks(.codex) }
            }
            // Codex also needs the user to trust new hooks, so say so right in the row.
            rows.append(Row(title: "Codex hooks", detail: codex == .installed ? "Trust them in Codex with /hooks" : "Adds hooks to \(model.settingsPath(.codex))",
                            status: status, agent: .codex))
        }
        return rows + [
            Row(title: "Accessibility", detail: "Needed to raise the exact window",
                status: model.accessibility ? .done("Allowed") : .action("Allow…", model.allowAccessibility)),
            Row(title: "Automation", detail: "iTerm and Terminal, to switch tabs", status: automation),
        ]
    }
}

// MARK: Pieces

/// A rounded group of rows separated by hairlines.
private struct OnboardingList<Item: Identifiable, Content: View>: View {
    let rows: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                content(row)
                if index < rows.count - 1 { Rectangle().fill(Color.fill(0.05)).frame(height: 1) }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.fill(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.fill(0.06)))
    }
}

private struct RowText: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.nudge(13, .semibold))
            Text(detail)
                .font(.nudge(11.5))
                .foregroundStyle(Color.label(0.5))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The handoff's 30×18 switch: green when on.
private struct NudgeToggle: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Capsule()
                .fill(isOn ? Tokens.Accent.success : Color.fill(0.14))
                .frame(width: 30, height: 18)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                        .padding(2)
                }
                .animation(.easeOut(duration: 0.15), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "On" : "Off")
    }
}

private struct OnboardingPrimaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.nudge(13, .semibold))
            .foregroundStyle(Tokens.buttonText)
            .padding(.vertical, 7)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 8).fill(Tokens.textPrimary))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct OnboardingSmallStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.nudge(12))
            .foregroundStyle(Tokens.textPrimary)
            .padding(.vertical, 5)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.fill(configuration.isPressed ? 0.16 : 0.1)))
    }
}

extension HostApp {
    var onboardingName: String { self == .claude ? "Claude app" : displayName }
}
