import Foundation

/// One Claude Code or Codex hook event, trimmed to what Peeku shows, as the collector writes it to the inbox.
public struct HookRecord: Codable, Sendable, Equatable {
    public static let currentSchema = 1
    public static let maximumBytes = 64 * 1024

    public var schema: Int
    public var id: String
    public var event: String
    /// Milliseconds since 1970, when the collector ran.
    public var observedAt: Int64
    public var sessionID: String
    public var agentID: String?
    public var toolUseID: String?
    public var cwd: String?
    /// The git branch checked out in `cwd`, or a short commit id when detached.
    public var branch: String?
    public var prompt: String?
    public var toolName: String?
    public var toolInput: ToolInput?
    public var error: String?
    public var message: String?
    public var notificationType: String?
    public var lastAssistantMessage: String?
    public var host: HostHint?
    /// Which coding agent sent the event: `nil` (or "claude") for Claude Code, "codex" for Codex.
    public var agent: String?
    /// The agent's own process, found by walking up from the collector. Codex has no session
    /// registry, so this is how Peeku tells a Codex session is still running and finds its terminal.
    public var agentPID: Int32?
    /// Set when fields were dropped to fit `maximumBytes`.
    public var truncated: Bool?

    public init(id: String, event: String, observedAt: Int64, sessionID: String) {
        schema = Self.currentSchema
        self.id = id
        self.event = event
        self.observedAt = observedAt
        self.sessionID = sessionID
    }

    public var date: Date { Date(timeIntervalSince1970: TimeInterval(observedAt) / 1000) }

    public struct ToolInput: Codable, Sendable, Equatable {
        public var filePath: String?
        public var pattern: String?
        public var query: String?
        public var description: String?
        /// First 512 characters of a shell command.
        public var command: String?
        public var questions: [Question]?

        public init() {}
    }

    public struct Question: Codable, Sendable, Equatable {
        public var question: String
        public var header: String?
        public var options: [String]
        public var multiSelect: Bool

        public init(question: String, header: String? = nil, options: [String], multiSelect: Bool = false) {
            self.question = question
            self.header = header
            self.options = options
            self.multiSelect = multiSelect
        }
    }

    /// Where the session runs, from the environment Claude Code passes to hooks.
    public struct HostHint: Codable, Sendable, Equatable {
        public var bundleID: String?
        public var termProgram: String?
        /// iTerm's `wNtNpN:GUID`, which names the exact tab and pane.
        public var itermSessionID: String?
        public var parentPID: Int32?
        /// The app found by walking up the collector's process ancestry. More reliable than
        /// `bundleID`, which is inherited and can name whichever app started the shell's parent.
        public var appBundleID: String?
        /// The name, as Finder shows it, of the app `resolvedBundleID` names, e.g. "Warp" or "Ghostty".
        public var appName: String?
        /// The app's main process.
        public var appPID: Int32?

        public init(bundleID: String? = nil, termProgram: String? = nil, itermSessionID: String? = nil, parentPID: Int32? = nil,
                    appBundleID: String? = nil, appName: String? = nil, appPID: Int32? = nil) {
            self.bundleID = bundleID
            self.termProgram = termProgram
            self.itermSessionID = itermSessionID
            self.parentPID = parentPID
            self.appBundleID = appBundleID
            self.appName = appName
            self.appPID = appPID
        }

        /// The session's app: the one from the process ancestry, else the inherited environment's.
        public var resolvedBundleID: String? { appBundleID ?? bundleID }
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

/// Peeku's own data folder. `PEEKU_HOME` overrides it, for tests and development.
public struct PeekuPaths: Sendable, Equatable {
    public var root: URL
    /// The collector's file name in `bin`.
    public var collectorName: String

    public init(root: URL, collectorName: String = "peeku-hook") {
        self.root = root
        self.collectorName = collectorName
    }

    public static var `default`: PeekuPaths {
        if let custom = ProcessInfo.processInfo.environment["PEEKU_HOME"], !custom.isEmpty {
            return PeekuPaths(root: URL(filePath: custom, directoryHint: .isDirectory))
        }
        let support = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Peeku", directoryHint: .isDirectory)
        return PeekuPaths(root: support)
    }

    /// Where the app kept its data when it was called Nudge, for moving it over once.
    public static var nudge: PeekuPaths {
        let support = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Nudge", directoryHint: .isDirectory)
        return PeekuPaths(root: support, collectorName: "nudge-hook")
    }

    /// Where the app kept its data when it was called Pip, before Nudge.
    public static var pip: PeekuPaths {
        let support = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Pip", directoryHint: .isDirectory)
        return PeekuPaths(root: support, collectorName: "pip-hook")
    }

    public var inbox: URL { root.appending(path: "inbox", directoryHint: .isDirectory) }
    public var collector: URL { root.appending(path: "bin/\(collectorName)") }
    /// The last subscription usage Claude Code passed to its status line, as the collector saved it.
    public var claudeUsage: URL { root.appending(path: "usage/claude.json") }
    /// Touched whenever Claude Code runs Peeku's status line, with or without usage in its input.
    public var claudeStatusLineSeen: URL { root.appending(path: "usage/claude-statusline-seen") }
}
