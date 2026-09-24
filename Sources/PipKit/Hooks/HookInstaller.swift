import CryptoKit
import Foundation
import PipHookSchema

/// Adds and removes Pip's hook handlers in Claude Code's settings or Codex's hooks file.
///
/// It only ever touches handlers whose command is Pip's collector, keeps every other key in
/// place and in order, backs the file up before writing, and refuses to write if the file
/// changed while it worked.
public struct HookInstaller: Sendable {
    /// Which agent's hooks to manage. Both use the same `{"hooks": {Event: [groups]}}` shape.
    public enum Target: String, Sendable, CaseIterable {
        case claude, codex

        public var agent: Agent { self == .claude ? .claude : .codex }

        /// The events Pip reads. Each gets one handler that runs the collector.
        public var events: [String] {
            switch self {
            case .claude:
                ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                 "PermissionRequest", "PermissionDenied", "Notification", "Stop", "StopFailure", "PreCompact", "CwdChanged"]
            case .codex:
                ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                 "PermissionRequest", "Stop", "Interrupt", "PreCompact"]
            }
        }

        /// Claude's Notification fires for several reasons; Pip only needs these two.
        func matcher(for event: String) -> String? {
            self == .claude && event == "Notification" ? "permission_prompt|elicitation_dialog" : nil
        }

        public var defaultSettingsURL: URL { self == .claude ? ClaudePaths.settings : CodexPaths.hooks }

        var manifestName: String { self == .claude ? "hook-manifest.json" : "hook-manifest-codex.json" }
    }

    /// Claude Code's events, kept for existing callers.
    public static var events: [String] { Target.claude.events }
    static let timeoutSeconds = 2

    public enum Status: Equatable, Sendable {
        case notInstalled
        case installed
        /// Some events have no Pip handler, or the collector binary is missing or out of date.
        case incomplete
    }

    public enum InstallError: Error, Equatable, LocalizedError {
        case settingsNotAnObject
        case hooksNotAnObject
        case eventNotAnArray(String)
        case settingsChanged
        case collectorMissing

        public var errorDescription: String? {
            switch self {
            case .settingsNotAnObject: "The settings file doesn't contain a JSON object."
            case .hooksNotAnObject: "The \"hooks\" value in the settings file isn't an object."
            case .eventNotAnArray(let event): "The \"\(event)\" hooks value in the settings file isn't a list."
            case .settingsChanged: "The settings file changed while Pip was editing it. Try again."
            case .collectorMissing: "Pip's hook collector wasn't found in the app."
            }
        }
    }

    public let target: Target
    public let settingsURL: URL
    public let paths: PipPaths

    public init(target: Target = .claude, settingsURL: URL? = nil, paths: PipPaths = .default) {
        self.target = target
        self.settingsURL = settingsURL ?? target.defaultSettingsURL
        self.paths = paths
    }

    public var events: [String] { target.events }

    // MARK: Status

    public func status(bundledCollector: URL?) -> Status {
        guard let settings = try? readSettings().value else { return .notInstalled }
        let installed = events.filter { hasPipHandler(in: settings["hooks"]?[$0]) }
        if installed.isEmpty { return .notInstalled }
        guard installed.count == events.count, collectorIsCurrent(bundled: bundledCollector) else { return .incomplete }
        return .installed
    }

    func collectorIsCurrent(bundled: URL?) -> Bool {
        guard let installed = try? Data(contentsOf: paths.collector) else { return false }
        guard let bundled, let source = try? Data(contentsOf: bundled) else { return true }
        return SHA256.hash(data: installed) == SHA256.hash(data: source)
    }

    // MARK: Install

    /// Copies the collector to its stable path, then adds any missing handlers.
    /// Returns how many handlers were added.
    @discardableResult
    public func install(collectorSource: URL) throws -> Int {
        guard FileManager.default.isExecutableFile(atPath: collectorSource.path) else { throw InstallError.collectorMissing }
        let original = try readSettings()
        var settings = original.value
        guard case .object = settings else { throw InstallError.settingsNotAnObject }

        var hooks = settings["hooks"] ?? .object([])
        guard case .object = hooks else { throw InstallError.hooksNotAnObject }
        var added = 0
        for event in events {
            var groups = hooks[event] ?? .array([])
            guard case .array(var list) = groups else { throw InstallError.eventNotAnArray(event) }
            if hasPipHandler(in: groups) { continue }
            var group = OrderedJSON.object([])
            if let matcher = target.matcher(for: event) { group.set("matcher", .string(matcher)) }
            group.set("hooks", .array([handler(for: event)]))
            list.append(group)
            groups = .array(list)
            hooks.set(event, groups)
            added += 1
        }

        // The collector goes in place first, so handlers never point at a missing binary.
        try installCollector(from: collectorSource)
        guard added > 0 else { return 0 }
        settings.set("hooks", hooks)
        try write(settings, replacing: original)
        try writeManifest()
        return added
    }

    /// Removes Pip's handlers, and any groups or events left empty by that. Returns how many were removed.
    @discardableResult
    public func uninstall() throws -> Int {
        let original = try readSettings()
        var settings = original.value
        guard case .object = settings, case .object(let events)? = settings["hooks"] else { return 0 }
        var hooks = OrderedJSON.object([])
        var removed = 0
        for member in events {
            guard case .array(let groups) = member.value else {
                hooks.set(member.key, member.value)
                continue
            }
            var kept: [OrderedJSON] = []
            for group in groups {
                guard case .array(let handlers)? = group["hooks"] else { kept.append(group); continue }
                let others = handlers.filter { !isPipHandler($0) }
                removed += handlers.count - others.count
                if others.count == handlers.count { kept.append(group); continue }
                if others.isEmpty { continue }
                var trimmed = group
                trimmed.set("hooks", .array(others))
                kept.append(trimmed)
            }
            if !kept.isEmpty || groups.isEmpty { hooks.set(member.key, .array(kept)) }
        }
        guard removed > 0 else { return 0 }
        if case .object(let remaining) = hooks, remaining.isEmpty { settings.set("hooks", nil) } else { settings.set("hooks", hooks) }
        try write(settings, replacing: original)
        return removed
    }

    // MARK: Handlers

    func handler(for event: String) -> OrderedJSON {
        switch target {
        case .claude:
            return .object([
                .init("type", .string("command")),
                .init("command", .string(paths.collector.path)),
                .init("args", .array(["observe", "--event", event, "--inbox", paths.inbox.path].map { .string($0) })),
                .init("timeout", .number(String(Self.timeoutSeconds))),
            ])
        case .codex:
            // Codex has no "args": one command line, quoted because the path has a space in it.
            // The collector reads the event name from the payload.
            let command = [Self.quoted(paths.collector.path), "observe", "--agent", "codex", "--inbox", Self.quoted(paths.inbox.path)]
                .joined(separator: " ")
            return .object([
                .init("type", .string("command")),
                .init("command", .string(command)),
                .init("timeout", .number(String(Self.timeoutSeconds))),
            ])
        }
    }

    /// Single-quoted for the shell, with any single quote escaped.
    static func quoted(_ path: String) -> String {
        "'" + path.replacing("'", with: "'\\''") + "'"
    }

    func isPipHandler(_ handler: OrderedJSON) -> Bool {
        guard let command = handler["command"]?.stringValue else { return false }
        switch target {
        case .claude: return command == paths.collector.path
        case .codex: return command.hasPrefix(Self.quoted(paths.collector.path) + " ")
        }
    }

    func hasPipHandler(in groups: OrderedJSON?) -> Bool {
        groups?.arrayValue?.contains { group in group["hooks"]?.arrayValue?.contains(where: isPipHandler) == true } == true
    }

    // MARK: Files

    private struct Snapshot {
        var value: OrderedJSON
        var data: Data?
        var permissions: Int
    }

    private func readSettings() throws -> Snapshot {
        guard let data = try? Data(contentsOf: settingsURL) else {
            return Snapshot(value: .object([]), data: nil, permissions: 0o600)
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: settingsURL.path)
        let permissions = (attributes?[.posixPermissions] as? Int) ?? 0o600
        let trimmed = data.isEmpty || String(decoding: data, as: UTF8.self).allSatisfy(\.isWhitespace)
        return Snapshot(value: trimmed ? .object([]) : try OrderedJSON.parse(data), data: data, permissions: permissions)
    }

    private func write(_ settings: OrderedJSON, replacing original: Snapshot) throws {
        let manager = FileManager.default
        let directory = settingsURL.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard (try? Data(contentsOf: settingsURL)) == original.data else { throw InstallError.settingsChanged }

        if let data = original.data {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacing(":", with: "-")
            let backup = directory.appending(path: "\(settingsURL.lastPathComponent).pip-backup-\(stamp)")
            manager.createFile(atPath: backup.path, contents: data, attributes: [.posixPermissions: 0o600])
        }

        let temporary = directory.appending(path: ".\(settingsURL.lastPathComponent).pip-\(UUID().uuidString).tmp")
        guard manager.createFile(atPath: temporary.path, contents: settings.serialized(), attributes: [.posixPermissions: original.permissions]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard rename(temporary.path, settingsURL.path) == 0 else {
            try? manager.removeItem(at: temporary)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private func installCollector(from source: URL) throws {
        let manager = FileManager.default
        let destination = paths.collector
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try manager.createDirectory(at: paths.inbox, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let staged = destination.deletingLastPathComponent().appending(path: ".pip-hook-\(UUID().uuidString).tmp")
        try manager.copyItem(at: source, to: staged)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: staged.path)
        guard rename(staged.path, destination.path) == 0 else {
            try? manager.removeItem(at: staged)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    /// Records what Pip added, for support and for a future clean uninstall.
    private func writeManifest() throws {
        let manifest: [String: Any] = [
            "settings": settingsURL.path, "collector": paths.collector.path, "inbox": paths.inbox.path,
            "agent": target.rawValue, "events": events, "installedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: paths.root.appending(path: target.manifestName), options: .atomic)
    }
}
