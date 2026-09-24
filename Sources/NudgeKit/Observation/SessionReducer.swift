import Foundation
import NudgeHookSchema

/// Folds hook events and registry snapshots into session state. Pure, so it is easy to test.
///
/// Only observed facts change a session's phase. Nudge does not guess that a session is stuck.
public struct SessionReducer: Sendable {
    public private(set) var sessions: [String: ObservedSession] = [:]
    /// Tool calls in flight, so a permission request can show the command it is about.
    private var tools: [String: HookRecord.ToolInput] = [:]

    /// A session that sent events but is not in the registry yet (it may still be starting).
    static let unregisteredGrace: TimeInterval = 30
    /// Codex has no registry. A Codex session whose process Nudge couldn't find is kept this long
    /// after its last event (Codex ends idle sessions after 30 minutes anyway).
    static let codexWithoutProcessLimit: TimeInterval = 2 * 60 * 60

    /// Whether a process is still running. Replaceable for tests.
    var processIsAlive: @Sendable (Int32) -> Bool = { SessionRegistry.isAlive($0) }

    public init() {}

    /// Starts from sessions saved before Nudge last quit. The registry check that follows drops
    /// any that ended in the meantime.
    public init(restoring saved: [ObservedSession]) {
        sessions = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { _, newer in newer })
    }

    // MARK: Hook events

    public mutating func apply(_ record: HookRecord) {
        let at = record.date
        var session = sessions[record.sessionID] ?? ObservedSession(id: record.sessionID, cwd: record.cwd ?? "", since: at)
        if let cwd = record.cwd { session.cwd = cwd }
        session.lastEventAt = max(session.lastEventAt, at)
        if let host = record.host { session.host.merge(host) }
        if let agent = record.agent.flatMap(Agent.init(rawValue:)) { session.agent = agent }
        // Codex has no registry, so its process comes from the collector.
        if let pid = record.agentPID, pid > 0 { session.pid = pid }
        let toolKey = record.toolUseID.map { "\(record.sessionID)|\($0)" }

        switch record.event {
        case "SessionStart":
            if !session.phase.needsUser { session.set(.idle, at: at) }

        case "UserPromptSubmit":
            session.prompt = record.prompt ?? session.prompt
            session.activity = nil
            session.set(.working, at: at)
            tools = tools.filter { !$0.key.hasPrefix("\(record.sessionID)|") }

        case "PreToolUse":
            if let toolKey, let input = record.toolInput { tools[toolKey] = input }
            if record.toolName == "AskUserQuestion", let question = Self.question(record.toolInput, toolUseID: record.toolUseID) {
                session.set(.question(question), at: at)
            } else if !session.phase.needsUser {
                session.set(.working, at: at)
                session.activity = Self.activity(tool: record.toolName, input: record.toolInput) ?? session.activity
            }

        case "PermissionRequest":
            let input = record.toolInput ?? toolKey.flatMap { tools[$0] }
            if record.toolName == "AskUserQuestion" {
                if let question = Self.question(input, toolUseID: record.toolUseID) { session.set(.question(question), at: at) }
            } else {
                session.set(.permission(Self.permission(tool: record.toolName, input: input, toolUseID: record.toolUseID)), at: at)
            }

        case "Notification":
            switch record.notificationType {
            case "permission_prompt":
                // Usually follows PermissionRequest; only fill in when that was missed.
                if case .permission = session.phase { break }
                session.set(.permission(ObservedSession.Permission(toolName: "tool", preview: nil, detail: record.message)), at: at)
            case "elicitation_dialog":
                session.set(.question(ObservedSession.Question(text: record.message ?? "Claude needs your input", choices: [])), at: at)
            default:
                break
            }

        case "PostToolUse", "PostToolUseFailure", "PermissionDenied":
            if let toolKey { tools[toolKey] = nil }
            // The user answered: in the session, or elsewhere.
            if session.phase.needsUser, session.phase.toolUseID == nil || session.phase.toolUseID == record.toolUseID {
                if case .failed = session.phase {} else { session.set(.working, at: at) }
            }

        case "Stop":
            session.set(.finished(summary: Self.summary(record.lastAssistantMessage)), at: at)
            session.activity = nil

        case "StopFailure":
            session.set(.failed(record.error ?? "Claude's response failed"), at: at)

        case "Interrupt":
            // Codex: the user stopped the turn, so it's waiting for the next prompt.
            session.set(.idle, at: at)
            session.activity = nil

        case "PreCompact":
            if !session.phase.needsUser {
                session.set(.working, at: at)
                session.activity = "Compacting context"
            }

        case "SessionEnd":
            sessions[record.sessionID] = nil
            return

        default:
            break
        }
        sessions[record.sessionID] = session
    }

    // MARK: Registry

    /// Reconciles with Claude's registry: adds sessions that started before Nudge, notices answers
    /// given elsewhere, and drops sessions whose process is gone.
    public mutating func reconcile(_ entries: [RegistryEntry], now: Date = Date()) {
        let live = Set(entries.map(\.sessionId))
        for entry in entries {
            let changedAt = entry.statusDate ?? now
            guard var session = sessions[entry.sessionId] else {
                // First sight, e.g. a session that started before Nudge: take the registry's word.
                var session = ObservedSession(id: entry.sessionId, cwd: entry.cwd, since: changedAt)
                session.pid = entry.pid
                session.registered = true
                session.title = entry.name
                session.entrypoint = entry.entrypoint
                switch entry.status {
                case .busy: session.phase = .working
                case .waiting: session.phase = .waiting(entry.waitingFor)
                case .idle, nil: session.phase = .idle
                }
                sessions[entry.sessionId] = session
                continue
            }
            session.pid = entry.pid
            session.registered = true
            if session.cwd.isEmpty { session.cwd = entry.cwd }
            session.title = entry.name ?? session.title
            session.entrypoint = entry.entrypoint ?? session.entrypoint

            switch entry.status {
            case .waiting:
                if !session.phase.needsUser { session.set(.waiting(entry.waitingFor), at: changedAt) }
            case .busy:
                // Busy since the phase began: the user answered, or prompted again, and Claude carried on.
                if session.phase != .working, changedAt > session.since { session.set(.working, at: changedAt) }
            case .idle:
                if session.phase == .working, changedAt > session.lastEventAt { session.set(.idle, at: changedAt) }
                if case .waiting = session.phase, changedAt > session.since { session.set(.idle, at: changedAt) }
            case nil:
                break
            }
            sessions[entry.sessionId] = session
        }

        sessions = sessions.filter { id, session in
            if session.resolvedAgent == .codex { return codexIsRunning(session, now: now) }
            return live.contains(id) || (!session.registered && now.timeIntervalSince(session.lastEventAt) < Self.unregisteredGrace)
        }
    }

    /// Codex sessions aren't in Claude's registry: they stay while their process runs.
    private func codexIsRunning(_ session: ObservedSession, now: Date) -> Bool {
        if let pid = session.pid { return processIsAlive(pid) }
        return now.timeIntervalSince(session.lastEventAt) < Self.codexWithoutProcessLimit
    }

    // MARK: Interpreting tool input

    static func activity(tool: String?, input: HookRecord.ToolInput?) -> String? {
        guard let tool else { return nil }
        let file = input?.filePath.map { ($0 as NSString).lastPathComponent }
        switch tool {
        case "Edit", "Write", "MultiEdit", "NotebookEdit": return file.map { "Editing \($0)" } ?? "Editing files"
        case "Read": return file.map { "Reading \($0)" } ?? "Reading files"
        case "Grep", "Glob": return "Searching the codebase"
        case "WebFetch", "WebSearch": return "Searching the web"
        case "Task", "Agent": return input?.description ?? "Running a subagent"
        case "Bash":
            if let command = input?.command, command.range(of: #"(^|[\s/])(test|tests|vitest|jest|pytest|mocha)([\s:;]|$)"#, options: .regularExpression) != nil {
                return "Running tests"
            }
            return input?.description ?? "Running a command"
        default: return nil
        }
    }

    static func permission(tool: String?, input: HookRecord.ToolInput?, toolUseID: String?) -> ObservedSession.Permission {
        let name = tool ?? "tool"
        let file = input?.filePath.map { ($0 as NSString).lastPathComponent }
        let preview = input?.command ?? file.map { "\(name) \($0)" } ?? input?.pattern ?? input?.query
        return ObservedSession.Permission(toolName: name, preview: preview, detail: input?.description, toolUseID: toolUseID)
    }

    static func question(_ input: HookRecord.ToolInput?, toolUseID: String?) -> ObservedSession.Question? {
        guard let first = input?.questions?.first else { return nil }
        return ObservedSession.Question(text: first.question, choices: first.options, toolUseID: toolUseID)
    }

    /// First meaningful line of Claude's last message.
    static func summary(_ message: String?) -> String? {
        guard let message else { return nil }
        let line = message.split(whereSeparator: \.isNewline)
            .map { TitleCleaner.stripMarkdown(String($0)) }
            .first { !$0.isEmpty }
        return line.map { String($0.prefix(200)) }
    }
}

extension ObservedSession {
    /// Changes phase, restarting `since` only when the kind of phase actually changes.
    mutating func set(_ next: Phase, at date: Date) {
        if next.kindMatches(phase) {
            phase = next
            return
        }
        phase = next
        since = date
    }
}

extension ObservedSession.Phase {
    func kindMatches(_ other: Self) -> Bool {
        switch (self, other) {
        case (.idle, .idle), (.working, .working), (.waiting, .waiting), (.finished, .finished), (.failed, .failed): true
        case (.permission(let a), .permission(let b)): a.toolUseID == b.toolUseID
        case (.question(let a), .question(let b)): a.toolUseID == b.toolUseID
        default: false
        }
    }
}

extension HookRecord.HostHint {
    mutating func merge(_ newer: HookRecord.HostHint) {
        bundleID = newer.bundleID ?? bundleID
        termProgram = newer.termProgram ?? termProgram
        itermSessionID = newer.itermSessionID ?? itermSessionID
        parentPID = newer.parentPID ?? parentPID
    }
}
