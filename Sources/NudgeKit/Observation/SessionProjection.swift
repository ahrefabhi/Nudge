import Foundation
import NudgeHookSchema

/// Maps observed state to the `NudgeSession` the UI shows.
public enum SessionProjection {
    public static func session(_ observed: ObservedSession, branch: String?) -> NudgeSession {
        let (kind, quote, choices) = presentation(observed.phase)
        let project = observed.cwd.isEmpty ? (observed.title ?? observed.resolvedAgent.name) : (observed.cwd as NSString).lastPathComponent
        let agent = observed.resolvedAgent
        return NudgeSession(
            id: observed.id,
            agent: agent,
            project: project,
            branch: branch,
            task: TitleCleaner.title(from: observed.prompt) ?? observed.title ?? "\(agent.productName) session",
            activity: kind == .working ? observed.activity : nil,
            host: host(observed),
            location: location(observed),
            kind: kind,
            quote: quote,
            choices: choices,
            since: observed.since
        )
    }

    static func presentation(_ phase: ObservedSession.Phase) -> (SessionKind, String?, [String]) {
        switch phase {
        case .idle: (.idle, nil, [])
        case .working: (.working, nil, [])
        case .permission(let permission): (.permission, permission.preview ?? permission.detail, [])
        case .question(let question): (.question, question.text, question.choices)
        case .waiting(let reason): (.waiting, reason.flatMap(waitingText), [])
        case .failed(let error): (.error, error, [])
        case .finished(let summary): (.finished, summary, [])
        }
    }

    private static func waitingText(_ reason: String) -> String? {
        reason.isEmpty || reason == "unknown" ? nil : reason
    }

    // MARK: Host

    public static func host(_ observed: ObservedSession) -> HostApp {
        let hint = observed.host
        switch hint.bundleID {
        case "com.googlecode.iterm2": return .iTerm
        case "com.apple.Terminal": return .terminal
        case "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders": return .vsCode
        case "com.anthropic.claudefordesktop": return .claude
        default: break
        }
        switch hint.termProgram {
        case "iTerm.app": return .iTerm
        case "Apple_Terminal": return .terminal
        case "vscode": return .vsCode
        default: break
        }
        if observed.entrypoint == "claude-vscode" { return .vsCode }
        if observed.entrypoint?.contains("desktop") == true { return .claude }
        return .other
    }

    /// "Tab 2" for iTerm, from `ITERM_SESSION_ID` (`w0t1p0:GUID`, zero-based).
    static func location(_ observed: ObservedSession) -> String? {
        guard let id = observed.host.itermSessionID,
              let match = id.firstMatch(of: /^w(\d+)t(\d+)p(\d+):/),
              let tab = Int(match.output.2) else { return nil }
        return "Tab \(tab + 1)"
    }

    /// The GUID half of `ITERM_SESSION_ID`, which iTerm's AppleScript `id of session` returns.
    public static func itermSessionGUID(_ observed: ObservedSession) -> String? {
        guard let id = observed.host.itermSessionID,
              let match = id.firstMatch(of: /^w\d+t\d+p\d+:([0-9A-Fa-f-]{36})$/) else { return nil }
        return String(match.output.1)
    }
}
