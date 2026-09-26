import PeekuKit
import SwiftUI

/// The Commands utility, opened from the manager's footer dock: commands the user saved, like `npm run dev`, to start, restart and
/// stop from the notch. Adding, editing and the full output open in their own windows.
struct CommandsView: View {
    @Environment(\.palette) private var palette
    /// Nil in snapshots, which have no processes to show.
    let runner: CommandRunner?

    var body: some View {
        let commands = runner?.commands ?? []
        VStack(alignment: .leading, spacing: 0) {
            if commands.isEmpty {
                empty
            } else {
                // New lives in the header above, beside the way back.
                let active = runner?.activeCount ?? 0
                Text((active == 0 ? "Nothing running" : "\(active) running") + " · \(commands.count) saved")
                    .font(.peeku(11.5))
                    .foregroundStyle(palette.label(0.5))
                    .padding(EdgeInsets(top: 8, leading: 20, bottom: 2, trailing: 20))

                SnapshotSafeScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(commands) { command in
                            if let runner, let run = runner.run(for: command.id) {
                                CommandRow(command: command, run: run, runner: runner)
                            }
                        }
                    }
                    .padding(EdgeInsets(top: 6, leading: 8, bottom: 10, trailing: 8))
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Text("No commands yet")
                .font(.peeku(15, .semibold))
                .tracking(-0.15)
                .foregroundStyle(palette.primary)
            Text("Save a command like npm run dev with the folder it runs in, then start, restart and stop it from here.")
                .font(.peeku(12))
                .lineSpacing(3)
                .foregroundStyle(palette.label(0.55))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
                .fixedSize(horizontal: false, vertical: true)
            Button { runner?.onEdit?(nil) } label: { NewCommandLabel() }
                .buttonStyle(PrimaryPillStyle(fontSize: 12))
                .padding(.top, 8)
                .disabled(runner == nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CommandRow: View {
    @Environment(\.palette) private var palette
    let command: QuickCommand
    let run: CommandRun
    let runner: CommandRunner
    @State private var hovering = false
    /// The trash button was clicked once and now asks again, since the notch can't show a dialog.
    @State private var confirmingDelete = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusMark(status: run.status, waiting: run.waitingForInput)
                .frame(width: 16, height: 16)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(command.title)
                        .font(.peeku(13, .semibold))
                        .foregroundStyle(palette.primary)
                        .layoutPriority(1)
                    Group {
                        if run.waitingForInput {
                            Text("Waiting for input")
                        } else if case .running(let since) = run.status {
                            LiveText { "Running · " + RelativeTime.short(since: since, now: $0) }
                        } else {
                            Text(statusText)
                        }
                    }
                    .font(.peeku(11.5))
                    .foregroundStyle(statusColor)
                }
                .lineLimit(1)
                Text(command.command)
                    .font(.peekuMono(11))
                    .foregroundStyle(palette.label(0.6))
                    .lineLimit(1)
                    .truncationMode(.tail)
                // The latest output while it runs; the folder otherwise.
                Text(run.status.isActive ? run.lastLine ?? "Starting…" : command.displayDirectory)
                    .font(run.status.isActive ? .peekuMono(10.5) : .peeku(11))
                    .foregroundStyle(palette.label(0.4))
                    .lineLimit(1)
                    .truncationMode(run.status.isActive ? .tail : .head)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                if confirmingDelete {
                    Button(run.status.isActive ? "Stop and Delete" : "Delete") { runner.delete(command.id) }
                        .buttonStyle(DeleteStyle())
                        .fixedSize()
                } else if hovering {
                    IconButton(symbol: "trash", help: "Delete") { confirmingDelete = true }
                    IconButton(symbol: "pencil", help: "Edit") { runner.onEdit?(command) }
                }
                IconButton(symbol: "text.alignleft", help: "Show output") { runner.onShowLog?(command) }
                if run.status.isActive {
                    IconButton(symbol: "arrow.clockwise", help: "Restart") { runner.restart(command.id) }
                        .disabled(run.status == .stopping)
                    IconButton(symbol: "stop.fill", help: "Stop") { runner.stop(command.id) }
                        .disabled(run.status == .stopping)
                } else {
                    Button("Run") { runner.start(command.id) }
                        .buttonStyle(RowOpenStyle())
                        .fixedSize()
                }
            }
            .padding(.top, 1)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.fill(hovering ? 0.055 : 0)))
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if !inside { confirmingDelete = false }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: confirmingDelete)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(command.title), \(statusText)")
    }

    private var statusText: String {
        switch run.status {
        case .notStarted: ""
        case .running: "Running"
        case .stopping: "Stopping…"
        case .exited(let code, _): code == 0 ? "Finished" : "Exited \(code)"
        case .stopped: "Stopped"
        case .failed: "Couldn't start"
        }
    }

    private var statusColor: Color {
        if run.waitingForInput { return palette.accent(.commandInput) }
        return switch run.status {
        case .running: palette.accent(.finished)
        case .exited(let code, _) where code != 0: palette.accent(.error)
        case .failed: palette.accent(.error)
        default: palette.label(0.45)
        }
    }
}

/// "+ New Command".
private struct NewCommandLabel: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "plus").font(.system(size: 9.5, weight: .bold))
            Text("New Command")
        }
    }
}

/// Green dot while running, a spinner while stopping, red after a failure, grey otherwise.
private struct StatusMark: View {
    @Environment(\.palette) private var palette
    let status: CommandStatus
    /// Blue while it's asking something, like a question from an agent.
    var waiting = false

    var body: some View {
        switch status {
        case .running:
            let green = palette.accent(waiting ? .commandInput : .finished)
            Dot(color: green, size: 8).background(Circle().fill(green.opacity(0.22)).frame(width: 14, height: 14))
        case .stopping:
            Spinner(track: .fill(0.18), head: palette.label(0.6), period: 1.1)
        case .exited(let code, _) where code != 0:
            Dot(color: palette.accent(.error), size: 7)
        case .failed:
            Dot(color: palette.accent(.error), size: 7)
        default:
            Circle().stroke(palette.label(0.35), lineWidth: 1.2).frame(width: 7, height: 7)
        }
    }
}

/// The red confirm pill that takes the trash button's place.
struct DeleteStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label(label: configuration.label, pressed: configuration.isPressed)
    }

    private struct Label<Content: View>: View {
        let label: Content
        let pressed: Bool
        @Environment(\.palette) private var palette
        @State private var hovering = false

        var body: some View {
            let red = palette.accent(.error)
            label
                .font(.peeku(11.5, .semibold))
                .foregroundStyle(hovering ? palette.buttonText : red)
                .padding(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                .background(Capsule().fill(hovering ? red : red.opacity(0.16)))
                .scaleEffect(pressed ? 0.95 : 1)
                .onHover { hovering = $0 }
        }
    }
}

/// A small round symbol button, for the row's actions.
struct IconButton: View {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.label(isEnabled ? (hovering ? 0.95 : 0.7) : 0.3))
                .frame(width: 24, height: 24)
                .background(Circle().fill(palette.fill(hovering && isEnabled ? 0.14 : 0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
