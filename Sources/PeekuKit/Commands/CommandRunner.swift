import Darwin
import Foundation
import Observation

public enum CommandStatus: Equatable, Sendable {
    case notStarted
    case running(since: Date)
    case stopping
    /// Ended on its own. A non-zero code is a failure.
    case exited(code: Int32, at: Date)
    /// Stopped from Peeku.
    case stopped(at: Date)
    case failed(String)

    public var isActive: Bool {
        switch self {
        case .running, .stopping: true
        default: false
        }
    }
}

/// One command's current or latest run: its status and the tail of its output.
@MainActor
@Observable
public final class CommandRun {
    /// Lines kept in memory for the views. The log file keeps the whole run.
    public static let maxLines = 5000

    public let id: UUID
    public internal(set) var status: CommandStatus = .notStarted
    public private(set) var lines: [String] = []
    /// Lines appended since the log was last cleared, so a view can append just the new ones.
    public private(set) var appended = 0
    /// Changes whenever the lines are replaced rather than added to.
    public private(set) var generation = 0
    /// Output after the last newline, usually a prompt like "Use another port? (Y/n) ".
    public private(set) var partial = ""
    /// The command printed a question and has gone quiet, so it's probably waiting for an answer.
    public internal(set) var waitingForInput = false
    @ObservationIgnored var lastOutput = Date.distantPast

    init(id: UUID) { self.id = id }

    /// The latest thing it printed, a prompt included.
    public var lastLine: String? {
        if !partial.trimmingCharacters(in: .whitespaces).isEmpty { return partial }
        return lines.last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    func append(_ new: [String], partial: String? = nil) {
        if let partial { self.partial = partial }
        guard !new.isEmpty else { return }
        lines += new
        if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
        appended += new.count
    }

    func clear() {
        lines = []
        partial = ""
        appended = 0
        generation += 1
    }
}

/// Starts, stops and restarts the user's quick commands, and collects what they print.
@MainActor
@Observable
public final class CommandRunner {
    /// How long a stopped command gets to exit before it's killed.
    public static let stopGrace: TimeInterval = 3
    /// How long a command stays quiet after printing a question before it counts as waiting.
    public static let promptQuiet: TimeInterval = 1.5

    public private(set) var commands: [QuickCommand]
    private var runs: [UUID: CommandRun] = [:]

    @ObservationIgnored private let store: CommandStore
    @ObservationIgnored private var processes: [UUID: CommandProcess] = [:]
    @ObservationIgnored private var restarting: Set<UUID> = []
    @ObservationIgnored private var stopping: Set<UUID> = []
    /// Commands the user sent Ctrl-C to, so exiting from it reads as stopped, not failed.
    @ObservationIgnored private var interrupted: Set<UUID> = []

    /// The manager asked to add a command (nil) or edit one.
    @ObservationIgnored public var onEdit: ((QuickCommand?) -> Void)?
    /// The manager asked to see a command's full output.
    @ObservationIgnored public var onShowLog: ((QuickCommand) -> Void)?
    /// A command started, ended or was edited, so its alert may have come or gone.
    @ObservationIgnored public var onChange: (() -> Void)?

    public init(store: CommandStore = CommandStore()) {
        self.store = store
        commands = store.load()
        for command in commands { runs[command.id] = CommandRun(id: command.id) }
    }

    public func run(for id: UUID) -> CommandRun? { runs[id] }

    public func command(_ id: UUID) -> QuickCommand? { commands.first { $0.id == id } }

    public var activeCount: Int { runs.values.count { $0.status.isActive } }

    public func logURL(for id: UUID) -> URL { store.logURL(for: id) }

    /// An alert for each command whose last run exited with an error, until it runs again, and
    /// for each one that seems to be waiting for an answer.
    public var alerts: [PeekuSession] {
        commands.compactMap { command in
            guard let run = runs[command.id] else { return nil }
            if run.waitingForInput, run.status.isActive {
                return Self.inputAlert(for: command, prompt: run.partial, since: run.lastOutput)
            }
            guard case .exited(let code, let at) = run.status, code != 0 else { return nil }
            return Self.alert(for: command, code: code, lastLine: run.lastLine, at: at)
        }
    }

    nonisolated public static func inputAlert(for command: QuickCommand, prompt: String, since: Date) -> PeekuSession {
        PeekuSession(id: inputPrefix + command.id.uuidString, project: command.title, task: "is waiting for input",
                     host: .other, hostAppName: command.command, location: command.displayDirectory, kind: .commandInput,
                     quote: prompt.trimmingCharacters(in: .whitespaces), since: since)
    }

    nonisolated public static func alert(for command: QuickCommand, code: Int32, lastLine: String?, at: Date) -> PeekuSession {
        PeekuSession(id: alertPrefix + command.id.uuidString, project: command.title, task: "exited with code \(code)",
                     host: .other, hostAppName: command.command, location: command.displayDirectory, kind: .command,
                     quote: lastLine, since: at)
    }

    /// The command a failure alert is about.
    nonisolated public static func commandID(forAlert alert: PeekuSession) -> UUID? {
        for prefix in [alertPrefix, inputPrefix] where alert.id.hasPrefix(prefix) {
            return UUID(uuidString: String(alert.id.dropFirst(prefix.count)))
        }
        return nil
    }

    nonisolated private static let alertPrefix = "command:"
    nonisolated private static let inputPrefix = "command-input:"

    // MARK: Editing

    /// Adds the command, or replaces the saved one with the same id.
    public func save(_ command: QuickCommand) {
        if let index = commands.firstIndex(where: { $0.id == command.id }) {
            commands[index] = command
        } else {
            commands.append(command)
            runs[command.id] = CommandRun(id: command.id)
        }
        store.save(commands)
        onChange?()
    }

    public func delete(_ id: UUID) {
        stop(id)
        commands.removeAll { $0.id == id }
        store.save(commands)
        try? FileManager.default.removeItem(at: store.logURL(for: id))
        // The run stays until the process is gone, so its exit still has somewhere to land.
        if processes[id] == nil { runs[id] = nil }
        onChange?()
    }

    // MARK: Running

    public func start(_ id: UUID) {
        guard let command = command(id), let run = runs[id], processes[id] == nil else { return }
        interrupted.remove(id)
        run.clear()
        store.prepareLogs()
        let logURL = store.logURL(for: id)
        FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600])

        let process: CommandProcess
        do {
            process = try CommandProcess.spawn(command.command, in: command.directory, environment: Self.environment())
        } catch {
            run.status = .failed(String(describing: error))
            run.append(["Peeku: \(error)"])
            onChange?()
            return
        }
        processes[id] = process
        run.status = .running(since: Date())
        saveRunning()
        onChange?()

        let pump = LogPump(file: logURL) { [weak self] lines, partial in self?.received(id, lines: lines, partial: partial) }
        process.readOutput { pump.feed($0) }
        process.waitForExit { termination in
            Task { @MainActor [weak self] in self?.ended(id, process: process, termination: termination) }
        }
    }

    public func stop(_ id: UUID) {
        guard let process = processes[id], !stopping.contains(id) else { return }
        stopping.insert(id)
        runs[id]?.status = .stopping
        process.signal(SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.stopGrace) {
            if process.anythingAlive { process.signal(SIGKILL) }
        }
    }

    /// Stops the command if it's running, then starts it again once it has exited.
    public func restart(_ id: UUID) {
        guard processes[id] != nil else { return start(id) }
        restarting.insert(id)
        stop(id)
    }

    public func clearLog(_ id: UUID) { runs[id]?.clear() }

    /// Types `text` into the command's terminal, e.g. "y\r" to answer a prompt or "\u{03}" for Ctrl-C.
    public func send(_ id: UUID, _ text: String) {
        guard let process = processes[id] else { return }
        if text.contains("\u{03}") { interrupted.insert(id) }
        process.write(text)
        if let run = runs[id], run.waitingForInput {
            run.waitingForInput = false
            onChange?()
        }
    }

    public func isRunning(_ id: UUID) -> Bool { processes[id] != nil }

    private func received(_ id: UUID, lines: [String], partial: String) {
        guard let run = runs[id] else { return }
        run.append(lines, partial: partial)
        let now = Date()
        run.lastOutput = now
        if run.waitingForInput {
            run.waitingForInput = false
            onChange?()
        }
        guard LogLineSplitter.looksLikePrompt(partial) else { return }
        Task { [weak self, weak run] in
            try? await Task.sleep(for: .seconds(Self.promptQuiet))
            guard let self, let run, run.lastOutput == now, run.status.isActive, !run.waitingForInput,
                  LogLineSplitter.looksLikePrompt(run.partial) else { return }
            run.waitingForInput = true
            self.onChange?()
        }
    }

    /// For quitting: asks every command to stop, waits briefly, then kills whatever is left.
    public func stopAll() {
        let all = Array(processes.values)
        guard !all.isEmpty else { return }
        for process in all { process.signal(SIGTERM) }
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline, all.contains(where: \.anythingAlive) { usleep(50_000) }
        for process in all where process.anythingAlive { process.signal(SIGKILL) }
        processes = [:]
        saveRunning()
    }

    /// Stops process groups a crashed Peeku left running. Only ones whose leader is the same
    /// process Peeku started, never a later one that reused the pid.
    public func stopLeftovers() {
        for record in store.loadRunning() where CommandProcess.isLeader(record.pid, started: record.started) {
            kill(-record.pid, SIGTERM)
        }
        saveRunning()
    }

    private func ended(_ id: UUID, process: CommandProcess, termination: CommandProcess.Termination) {
        guard processes[id] === process else { return }
        // Anything the shell left behind (a dev server whose npm died) would keep the port.
        if process.anythingAlive { process.signal(SIGTERM) }
        processes[id] = nil
        saveRunning()
        // 130 is how a shell reports Ctrl-C.
        let stopped = stopping.remove(id) != nil || (interrupted.remove(id) != nil && termination.code == 130)
        guard let run = runs[id] else { return }
        guard command(id) != nil else { runs[id] = nil; return }
        run.waitingForInput = false
        run.status = stopped ? .stopped(at: Date()) : .exited(code: termination.code, at: Date())
        if restarting.remove(id) != nil { start(id) } else { onChange?() }
    }

    /// Peeku's environment without the terminal it may have been started from: a shell that
    /// thinks it's in Terminal restores and saves that tab's session, and iTerm and VS Code
    /// integrations print escape codes.
    static func environment(_ base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        let terminal: Set = ["TERM", "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "TERM_SESSION_ID", "SHELL_SESSION_ID",
                             "ITERM_SESSION_ID", "ITERM_PROFILE", "LC_TERMINAL", "LC_TERMINAL_VERSION", "COLORTERM"]
        var environment = base.filter { !terminal.contains($0.key) && !$0.key.hasPrefix("VSCODE_") }
        // A plain terminal: tools still ask their questions, but skip colors, spinners and screen clearing.
        environment["TERM"] = "dumb"
        environment["PYTHONUNBUFFERED"] = "1"
        return environment
    }

    private func saveRunning() {
        store.saveRunning(processes.values.map { RunningRecord(pid: $0.pid, started: $0.started) })
    }
}

/// Splits output into lines off the main thread, writes them to the log file, and hands them —
/// with the unfinished last line, which may be a prompt — to the main actor at most ten times a
/// second, so a chatty build doesn't flood the UI.
private final class LogPump: @unchecked Sendable {
    private let lock = NSLock()
    private var splitter = LogLineSplitter()
    private var pending: [String] = []
    private var partial = ""
    private var scheduled = false
    private let file: FileHandle?
    private let deliver: @MainActor (_ lines: [String], _ partial: String) -> Void

    init(file url: URL, deliver: @escaping @MainActor ([String], String) -> Void) {
        file = try? FileHandle(forWritingTo: url)
        self.deliver = deliver
    }

    /// Empty data means the output ended.
    func feed(_ data: Data) {
        let lines: [String]
        let schedule: Bool
        do {
            lock.lock()
            defer { lock.unlock() }
            lines = data.isEmpty ? splitter.finish() : splitter.feed(data)
            pending += lines
            partial = splitter.partial
            schedule = !scheduled
            if schedule { scheduled = true }
        }
        if !lines.isEmpty, let file {
            file.write(Data((lines.joined(separator: "\n") + "\n").utf8))
        }
        if data.isEmpty { try? file?.close() }
        guard schedule else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + (data.isEmpty ? 0 : 0.1)) { [self] in
            let (batch, last) = lock.withLock {
                scheduled = false
                defer { pending = [] }
                return (pending, partial)
            }
            MainActor.assumeIsolated { deliver(batch, last) }
        }
    }
}
