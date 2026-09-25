import Darwin
import Foundation

/// One `~/.claude/sessions/<pid>.json` file: Claude Code's own list of live sessions.
public struct RegistryEntry: Sendable, Equatable, Decodable {
    public enum Status: String, Sendable, Decodable { case busy, idle, waiting }

    public var pid: Int32
    public var sessionId: String
    public var cwd: String
    public var name: String?
    public var entrypoint: String?
    public var status: Status?
    public var waitingFor: String?
    /// Milliseconds since 1970.
    public var startedAt: Int64?
    public var statusUpdatedAt: Int64?

    public init(pid: Int32, sessionId: String, cwd: String, name: String? = nil, entrypoint: String? = nil,
                status: Status? = nil, waitingFor: String? = nil, startedAt: Int64? = nil, statusUpdatedAt: Int64? = nil) {
        self.pid = pid
        self.sessionId = sessionId
        self.cwd = cwd
        self.name = name
        self.entrypoint = entrypoint
        self.status = status
        self.waitingFor = waitingFor
        self.startedAt = startedAt
        self.statusUpdatedAt = statusUpdatedAt
    }

    var statusDate: Date? { statusUpdatedAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } }
    var startDate: Date? { startedAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } }
}

public enum ClaudePaths {
    /// `CLAUDE_CONFIG_DIR`, or `~/.claude`.
    public static var configRoot: URL {
        if let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            return URL(filePath: custom, directoryHint: .isDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude", directoryHint: .isDirectory)
    }

    public static var settings: URL { configRoot.appending(path: "settings.json") }
    public static var sessions: URL { configRoot.appending(path: "sessions", directoryHint: .isDirectory) }
}

public enum CodexPaths {
    /// `CODEX_HOME`, or `~/.codex`.
    public static var home: URL {
        if let custom = ProcessInfo.processInfo.environment["CODEX_HOME"], !custom.isEmpty {
            return URL(filePath: custom, directoryHint: .isDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex", directoryHint: .isDirectory)
    }

    public static var hooks: URL { home.appending(path: "hooks.json") }
    public static var config: URL { home.appending(path: "config.toml") }
    /// Session logs, as `YYYY/MM/DD/rollout-….jsonl`.
    public static var sessions: URL { home.appending(path: "sessions", directoryHint: .isDirectory) }

    /// Codex looks installed when its home folder exists.
    public static var isInstalled: Bool { FileManager.default.fileExists(atPath: home.path) }
}

public enum SessionRegistry {
    /// Live entries only: files for processes that have exited are skipped.
    public static func read(from directory: URL = ClaudePaths.sessions) -> [RegistryEntry] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        let decoder = JSONDecoder()
        return names.filter { $0.hasSuffix(".json") }.compactMap { name in
            let url = directory.appending(path: name)
            guard SafeFile.isOwnedRegularFile(url, maximumBytes: 1024 * 1024),
                  let data = try? Data(contentsOf: url),
                  let entry = try? decoder.decode(RegistryEntry.self, from: data),
                  isAlive(entry.pid), !isOwnChild(entry.pid) else { return nil }
            return entry
        }
    }

    static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    /// The `claude` Peeku runs to ask for usage lists itself while it runs; it isn't a session.
    static func isOwnChild(_ pid: Int32) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size && pid_t(info.pbi_ppid) == getpid()
    }
}

enum SafeFile {
    /// A regular file (not a symlink) owned by this user and no larger than `maximumBytes`.
    static func isOwnedRegularFile(_ url: URL, maximumBytes: Int) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return false }
        return (info.st_mode & S_IFMT) == S_IFREG && info.st_uid == getuid() && info.st_size <= maximumBytes
    }
}
