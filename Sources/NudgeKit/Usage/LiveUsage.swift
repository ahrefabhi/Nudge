import Foundation

// MARK: Codex

/// Asks Codex itself for its rate limits, through `codex app-server`'s `account/rateLimits/read`.
/// Codex fetches them from OpenAI with its own sign-in, so they're current with no session
/// running, and Nudge never touches Codex's credentials. The session logs stay the fallback.
public enum CodexLiveUsage {
    public static func read(codex: URL? = AgentCLI.locate("codex"), now: Date = Date(), timeout: TimeInterval = 20) -> UsageReport? {
        guard let codex else { return nil }
        let requests = [
            #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"nudge","version":"1"}}}"#,
            #"{"method":"initialized"}"#,
            #"{"id":2,"method":"account/rateLimits/read"}"#,
        ]
        var report: UsageReport?
        AgentCLI.run(codex, arguments: ["app-server"], timeout: timeout) { input, output in
            // The server takes requests in order, so they can all go at once.
            try? input.write(contentsOf: Data((requests.joined(separator: "\n") + "\n").utf8))
            return output.readLines(limit: 1024 * 1024) { line in
                guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                      (message["id"] as? NSNumber)?.intValue == 2 else { return false }
                report = parse(result: message["result"], now: now)
                return true
            }
        }
        return report
    }

    /// `{"rateLimits": {"primary": {"usedPercent", "windowDurationMins", "resetsAt"}, "secondary": …, "planType"}}`
    static func parse(result: Any?, now: Date) -> UsageReport? {
        guard let result = result as? [String: Any], let limits = result["rateLimits"] as? [String: Any] else { return nil }
        let windows = ["primary", "secondary"].compactMap { key -> UsageWindow? in
            guard let window = limits[key] as? [String: Any],
                  let used = (window["usedPercent"] as? NSNumber)?.doubleValue else { return nil }
            return UsageWindow(id: key, minutes: (window["windowDurationMins"] as? NSNumber)?.intValue, usedPercent: used,
                               resetsAt: (window["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) })
        }
        guard !windows.isEmpty else { return nil }
        return UsageReport(agent: .codex, windows: windows, plan: limits["planType"] as? String, observedAt: now)
    }
}

// MARK: Claude Code

/// Asks Claude Code itself for its rate limits, the way its VS Code extension does: a `get_usage`
/// control request over the Agent SDK's stream-json protocol. Claude Code fetches them with its
/// own sign-in, on every plan that has limits (Team too, not just Pro and Max), with no session
/// running and no model call. Nudge never touches Claude's credentials.
public enum ClaudeLiveUsage {
    public enum Answer: Sendable, Equatable {
        case report(UsageReport)
        /// Claude Code says this account has no rate limits to report, e.g. an API key.
        case unavailable
    }

    /// Loads no settings, so none of the user's hooks (Nudge's included), status line or MCP
    /// servers run, and saves no session. The SDK marks `get_usage` experimental, so the status
    /// line stays as the fallback.
    static let arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                            "--setting-sources", "", "--strict-mcp-config", "--no-session-persistence", "--disable-slash-commands"]

    public static func read(claude: URL? = AgentCLI.locate("claude"), now: Date = Date(), timeout: TimeInterval = 20) -> Answer? {
        guard let claude else { return nil }
        let requests = [
            #"{"type":"control_request","request_id":"init","request":{"subtype":"initialize"}}"#,
            #"{"type":"control_request","request_id":"usage","request":{"subtype":"get_usage"}}"#,
        ]
        var answer: Answer?
        // Somewhere with no project settings or CLAUDE.md to pick up.
        AgentCLI.run(claude, arguments: arguments, in: FileManager.default.temporaryDirectory, timeout: timeout) { input, output in
            try? input.write(contentsOf: Data((requests.joined(separator: "\n") + "\n").utf8))
            return output.readLines(limit: 4 * 1024 * 1024) { line in
                guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                      message["type"] as? String == "control_response",
                      let response = message["response"] as? [String: Any],
                      response["request_id"] as? String == "usage" else { return false }
                answer = response["subtype"] as? String == "success" ? parse(response["response"], now: now) : nil
                return true
            }
        }
        return answer
    }

    /// `{"subscription_type", "rate_limits_available", "rate_limits": {"five_hour": {"utilization", "resets_at"}, "seven_day": …}}`
    static func parse(_ usage: Any?, now: Date) -> Answer? {
        guard let usage = usage as? [String: Any] else { return nil }
        if usage["rate_limits_available"] as? Bool == false { return .unavailable }
        guard let limits = usage["rate_limits"] as? [String: Any] else { return nil }
        let windows = ClaudeUsageReader.windows.compactMap { key, minutes -> UsageWindow? in
            guard let window = limits[key] as? [String: Any],
                  let used = (window["utilization"] as? NSNumber)?.doubleValue else { return nil }
            return UsageWindow(id: key, minutes: minutes, usedPercent: used,
                               resetsAt: (window["resets_at"] as? String).flatMap(timestamp))
        }
        guard !windows.isEmpty else { return nil }
        let plan = (usage["subscription_type"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return .report(UsageReport(agent: .claude, windows: windows, plan: plan, observedAt: now))
    }

    /// e.g. "2026-09-25T00:30:00.298538+00:00": microseconds, which not every formatter takes.
    static func timestamp(_ string: String) -> Date? {
        CodexUsageReader.timestamp(string) ?? CodexUsageReader.timestamp(string.replacing(/\.\d+/, with: ""))
    }
}
