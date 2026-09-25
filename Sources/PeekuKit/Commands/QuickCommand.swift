import Foundation
import PeekuHookSchema

/// A command the user saved to run from the manager, like `npm run dev` in a project folder.
public struct QuickCommand: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    /// Optional; the folder's name stands in when it's empty.
    public var name: String
    /// The folder the command runs in, as an absolute path.
    public var directory: String
    /// Run by the user's login shell, so it can use their PATH, aliases and pipes.
    public var command: String

    public init(id: UUID = UUID(), name: String = "", directory: String, command: String) {
        self.id = id
        self.name = name
        self.directory = directory
        self.command = command
    }

    public var title: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? folderName : trimmed
    }

    public var folderName: String { URL(filePath: directory).lastPathComponent }

    /// The folder with the home directory shortened to `~`.
    public var displayDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return directory == home || directory.hasPrefix(home + "/") ? "~" + directory.dropFirst(home.count) : directory
    }
}

/// Saved commands, one JSON file readable only by the user.
public struct CommandStore: Sendable {
    public let url: URL
    /// The latest run's output for each command, one file per command.
    public let logs: URL
    /// Process groups that are running, so the next launch can stop them if Peeku crashed.
    public let running: URL

    public init(root: URL) {
        url = root.appending(path: "commands.json")
        logs = root.appending(path: "commands", directoryHint: .isDirectory)
        running = logs.appending(path: "running.json")
    }

    public init(paths: PeekuPaths = .default) { self.init(root: paths.root) }

    public func load() -> [QuickCommand] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([QuickCommand].self, from: data)) ?? []
    }

    public func save(_ commands: [QuickCommand]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(commands) else { return }
        write(data, to: url)
    }

    public func logURL(for id: UUID) -> URL { logs.appending(path: "\(id.uuidString).log") }

    func loadRunning() -> [RunningRecord] {
        guard let data = try? Data(contentsOf: running) else { return [] }
        return (try? JSONDecoder().decode([RunningRecord].self, from: data)) ?? []
    }

    func saveRunning(_ records: [RunningRecord]) {
        guard !records.isEmpty else { try? FileManager.default.removeItem(at: running); return }
        guard let data = try? JSONEncoder().encode(records) else { return }
        write(data, to: running)
    }

    func prepareLogs() {
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    private func write(_ data: Data, to file: URL) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? data.write(to: file, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

/// A process group Peeku started, with its leader's start time so a reused pid is never signalled.
struct RunningRecord: Codable, Equatable, Sendable {
    var pid: Int32
    var started: UInt64
}
