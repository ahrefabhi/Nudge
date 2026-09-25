import AppKit
import PeekuKit
import SwiftUI

/// The Commands tab's windows: one editor at a time, and an output window per command. They're
/// ordinary windows because the notch folds on a click elsewhere and can't hold a text field.
final class CommandWindows: NSObject, NSWindowDelegate {
    private let runner: CommandRunner
    private var editor: NSWindow?
    private var logs: [UUID: NSWindow] = [:]

    init(runner: CommandRunner) {
        self.runner = runner
    }

    /// Opens the editor for `command`, or for a new one.
    func edit(_ command: QuickCommand?) {
        editor?.close()
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        let view = CommandEditorView(
            original: command,
            chooseFolder: { [weak window] current, chosen in
                guard let window else { return }
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.canCreateDirectories = true
                panel.prompt = "Choose"
                panel.message = "Choose the folder the command runs in."
                if !current.isEmpty { panel.directoryURL = URL(filePath: current, directoryHint: .isDirectory) }
                panel.beginSheetModal(for: window) { response in
                    if response == .OK, let url = panel.url { chosen(url.path) }
                }
            },
            onSave: { [weak self, weak window] saved, runNow in
                self?.runner.save(saved)
                if runNow { self?.runner.restart(saved.id) }
                window?.close()
            },
            onDelete: { [weak self, weak window] in
                guard let command else { return }
                self?.logs[command.id]?.close()
                self?.runner.delete(command.id)
                window?.close()
            },
            onCancel: { [weak window] in window?.close() })
        window.contentViewController = NSHostingController(rootView: view)
        window.title = command == nil ? "New Command" : "Edit \(command!.title)"
        window.isReleasedWhenClosed = false
        window.delegate = self
        editor = window
        present(window)
    }

    /// Opens, or brings forward, the window with the command's output.
    func showLog(_ command: QuickCommand) {
        if let window = logs[command.id] { return present(window, center: false) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 460),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: true)
        window.contentViewController = NSHostingController(rootView: CommandLogView(runner: runner, id: command.id))
        window.title = command.title
        window.setContentSize(NSSize(width: 720, height: 460))
        window.contentMinSize = NSSize(width: 420, height: 240)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("PeekuCommandLog")
        logs[command.id] = window
        present(window)
    }

    private func present(_ window: NSWindow, center: Bool = true) {
        if center && !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === editor { editor = nil }
        logs = logs.filter { $0.value !== window }
    }
}

// MARK: Editor

struct CommandEditorView: View {
    let original: QuickCommand?
    let chooseFolder: (_ current: String, _ chosen: @escaping (String) -> Void) -> Void
    let onSave: (_ command: QuickCommand, _ runNow: Bool) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var directory: String
    @State private var command: String
    @State private var confirmingDelete = false

    init(original: QuickCommand?, chooseFolder: @escaping (String, @escaping (String) -> Void) -> Void,
         onSave: @escaping (QuickCommand, Bool) -> Void, onDelete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.original = original
        self.chooseFolder = chooseFolder
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _name = State(initialValue: original?.name ?? "")
        _directory = State(initialValue: original?.directory ?? "")
        _command = State(initialValue: original?.command ?? "")
    }

    private var draft: QuickCommand {
        QuickCommand(id: original?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespaces),
                     directory: directory, command: command.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var folderExists: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private var canSave: Bool { folderExists && !draft.command.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent {
                        HStack {
                            Text(directory.isEmpty ? "None" : draft.displayDirectory)
                                .foregroundStyle(directory.isEmpty || !folderExists ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.head)
                            Button("Choose…") { chooseFolder(directory) { directory = $0 } }
                        }
                    } label: {
                        Text("Folder")
                        if !directory.isEmpty && !folderExists { Text("This folder doesn't exist anymore.") }
                    }
                    // Full width and left-aligned, like a terminal, rather than a settings value.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Command")
                        TextField("Command", text: $command, prompt: Text("npm run dev"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        Text("Runs in your login shell, like a new terminal tab.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    // Left-aligned too: a right-aligned field hides a trailing space until the next letter.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                        TextField("Name", text: $name, prompt: Text(directory.isEmpty ? "Optional" : draft.folderName))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            HStack {
                if original != nil {
                    Button("Delete…", role: .destructive) { confirmingDelete = true }
                }
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button(original == nil ? "Add and Run" : "Save and Run") { onSave(draft, true) }
                    .disabled(!canSave)
                Button(original == nil ? "Add" : "Save") { onSave(draft, false) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(EdgeInsets(top: 0, leading: 20, bottom: 16, trailing: 20))
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Delete \(original?.title ?? "this command")?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("It stops if it's running, and its saved output is removed.")
        }
    }
}

// MARK: Output

struct CommandLogView: View {
    let runner: CommandRunner
    let id: UUID
    @State private var reply = ""
    @FocusState private var replyFocused: Bool

    var body: some View {
        if let command = runner.command(id), let run = runner.run(for: id) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(command.command).font(.system(.body, design: .monospaced)).lineLimit(1)
                        Text("\(command.displayDirectory) · \(status(run.status))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Clear") { runner.clearLog(id) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([runner.logURL(for: id)]) }
                        .disabled(!FileManager.default.fileExists(atPath: runner.logURL(for: id).path))
                    if run.status.isActive {
                        Button("Restart") { runner.restart(id) }.disabled(run.status == .stopping)
                        Button("Stop") { runner.stop(id) }.disabled(run.status == .stopping)
                    } else {
                        Button("Run") { runner.start(id) }.keyboardShortcut(.defaultAction)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                Divider()
                LogTextView(run: run)
                Divider()
                replyBar(run)
            }
            // Someone who opened this to answer a prompt can type straight away.
            .onAppear { if run.waitingForInput { replyFocused = true } }
            .onChange(of: run.waitingForInput) { _, waiting in if waiting { replyFocused = true } }
        } else {
            Text("This command was deleted.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Types into the command's terminal: a line of text, or a key for a yes/no prompt or Ctrl-C.
    private func replyBar(_ run: CommandRun) -> some View {
        let running = run.status.isActive
        return HStack(spacing: 8) {
            if run.waitingForInput {
                Image(systemName: "questionmark.bubble").foregroundStyle(.blue).help("Waiting for input")
            }
            TextField("Reply", text: $reply, prompt: Text(running ? (run.waitingForInput ? "Type your answer and press Return" : "Type into the command") : "Not running"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .focused($replyFocused)
                .onSubmit {
                    runner.send(id, reply + "\r")
                    reply = ""
                }
            Button("Yes") { runner.send(id, "y\r") }.help("Types y and Return")
            Button("No") { runner.send(id, "n\r") }.help("Types n and Return")
            Button("Return") { runner.send(id, "\r") }.help("Presses Return, to take the default answer")
            Button("Ctrl-C") { runner.send(id, "\u{03}") }.help("Interrupts the command, like Ctrl-C in a terminal")
        }
        .controlSize(.small)
        .disabled(!running)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func status(_ status: CommandStatus) -> String {
        if case .running = status, runner.run(for: id)?.waitingForInput == true { return "Waiting for input" }
        return switch status {
        case .notStarted: "Not started"
        case .running(let since): "Running since \(since.formatted(date: .omitted, time: .shortened))"
        case .stopping: "Stopping…"
        case .exited(let code, let at): (code == 0 ? "Finished" : "Exited with code \(code)") + " at \(at.formatted(date: .omitted, time: .shortened))"
        case .stopped(let at): "Stopped at \(at.formatted(date: .omitted, time: .shortened))"
        case .failed(let reason): reason
        }
    }
}

/// The output as selectable monospaced text. New lines are appended rather than the whole log
/// redrawn, and it follows the end unless the user has scrolled up.
private struct LogTextView: NSViewRepresentable {
    let run: CommandRun

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let text = scroll.documentView as! NSTextView
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.usesFindBar = true
        text.isIncrementalSearchingEnabled = true
        text.textContainerInset = NSSize(width: 8, height: 8)
        text.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        text.textColor = .labelColor
        text.backgroundColor = .textBackgroundColor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        // Read here, so SwiftUI calls this again whenever they change.
        let lines = run.lines, appended = run.appended, generation = run.generation, partial = run.partial
        guard let text = scroll.documentView as? NSTextView, let storage = text.textStorage else { return }
        let state = context.coordinator
        let atEnd = scroll.contentView.bounds.maxY >= text.frame.maxY - 24
        let attributes: [NSAttributedString.Key: Any] = [.font: text.font as Any, .foregroundColor: NSColor.labelColor]

        let new = appended - state.appended
        if generation == state.generation, new >= 0, new <= lines.count, state.shown + new <= CommandRun.maxLines * 2 {
            guard new > 0 || partial != state.partial else { return }
            // The unfinished line sits at the end; take it off, add the new lines, put the new one back.
            let tail = (storage.string as NSString).length
            storage.deleteCharacters(in: NSRange(location: tail - state.partialLength, length: state.partialLength))
            storage.append(NSAttributedString(string: lines.suffix(new).map { $0 + "\n" }.joined() + partial, attributes: attributes))
            state.shown += new
        } else {
            storage.setAttributedString(NSAttributedString(string: lines.map { $0 + "\n" }.joined() + partial, attributes: attributes))
            state.shown = lines.count
        }
        state.appended = appended
        state.generation = generation
        state.partial = partial
        state.partialLength = (partial as NSString).length
        if atEnd { text.scrollToEndOfDocument(nil) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var appended = 0
        var generation = -1
        /// Lines in the text view, which can run past the run's own cap until the next redraw.
        var shown = 0
        /// The unfinished line shown after them, like a prompt.
        var partial = ""
        var partialLength = 0
    }
}
