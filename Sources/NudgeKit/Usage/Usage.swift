import Foundation

/// One rate limit window, like Claude's 5-hour limit or Codex's weekly one.
public struct UsageWindow: Sendable, Equatable, Identifiable {
    public var id: String
    /// How long the window is, when the agent says. Claude's spend limit has none.
    public var minutes: Int?
    /// 0 to 100. A spend limit can go past 100.
    public var usedPercent: Double
    public var resetsAt: Date?

    public init(id: String, minutes: Int?, usedPercent: Double, resetsAt: Date?) {
        self.id = id
        self.minutes = minutes
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }

    /// "5-hour", "Weekly", "30-day", or "Spend limit".
    public var title: String {
        guard let minutes, minutes > 0 else { return id == "spend_limit" ? "Spend limit" : "Limit" }
        switch minutes {
        case 10_080: return "Weekly"
        case let m where m % 1440 == 0: return "\(m / 1440)-day"
        case let m where m % 60 == 0: return "\(m / 60)-hour"
        default: return "\(minutes)-minute"
        }
    }

    /// The window has reset since the reading, so its percentage no longer applies.
    public func hasReset(now: Date = Date()) -> Bool { resetsAt.map { $0 <= now } ?? false }
}

/// The latest usage reading for one agent.
public struct UsageReport: Sendable, Equatable {
    public var agent: Agent
    public var windows: [UsageWindow]
    /// Codex's plan, like "plus" or "free". Claude doesn't say.
    public var plan: String?
    /// When the agent reported these numbers. They only change while a session runs.
    public var observedAt: Date

    public init(agent: Agent, windows: [UsageWindow], plan: String? = nil, observedAt: Date) {
        self.agent = agent
        self.windows = windows
        self.plan = plan
        self.observedAt = observedAt
    }
}

/// What the Usage tab shows for one agent.
public struct AgentUsage: Sendable, Equatable, Identifiable {
    public enum Source: Sendable, Equatable {
        /// Nudge can read this agent's usage.
        case connected
        /// Claude Code only: Nudge isn't its status line yet.
        case needsSetup
        /// Claude Code only: Nudge is its status line, but no session has run it yet.
        case waitingForStatusLine
        /// Claude Code only: the status line runs, but Claude Code hasn't included usage in it.
        case notShared
    }

    public var agent: Agent
    public var source: Source
    public var report: UsageReport?
    public var id: Agent { agent }

    public init(agent: Agent, source: Source, report: UsageReport?) {
        self.agent = agent
        self.source = source
        self.report = report
    }
}

// MARK: Claude Code

/// Reads what the collector saved from Claude Code's status line input:
/// `{"observedAt": ms, "rateLimits": {"five_hour": {"used_percentage", "resets_at"}, "seven_day": …}}`.
public enum ClaudeUsageReader {
    static let windows: [(key: String, minutes: Int?)] = [("five_hour", 300), ("seven_day", 10_080), ("spend_limit", nil)]

    public static func read(from file: URL) -> UsageReport? {
        guard SafeFile.isOwnedRegularFile(file, maximumBytes: 64 * 1024),
              let data = try? Data(contentsOf: file) else { return nil }
        return parse(data)
    }

    static func parse(_ data: Data) -> UsageReport? {
        guard let snapshot = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let limits = snapshot["rateLimits"] as? [String: Any],
              let observed = (snapshot["observedAt"] as? NSNumber)?.doubleValue else { return nil }
        let windows = Self.windows.compactMap { key, minutes -> UsageWindow? in
            guard let window = limits[key] as? [String: Any],
                  let used = (window["used_percentage"] as? NSNumber)?.doubleValue else { return nil }
            let resets = (window["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return UsageWindow(id: key, minutes: minutes, usedPercent: used, resetsAt: resets)
        }
        guard !windows.isEmpty else { return nil }
        return UsageReport(agent: .claude, windows: windows, observedAt: Date(timeIntervalSince1970: observed / 1000))
    }
}

// MARK: Codex

/// Finds the newest `rate_limits` Codex wrote to its session logs. Each turn's `token_count`
/// event carries one: `{"primary": {"used_percent", "window_minutes", "resets_at"}, "secondary": …, "plan_type"}`.
public enum CodexUsageReader {
    /// A long session keeps writing to the log it started in, so look back a week of days.
    static let daysToSearch = 7
    static let logsToSearch = 6
    /// Only the end of each log is read; the latest reading is near it.
    static let tailBytes = 512 * 1024

    public static func read(sessions: URL = CodexPaths.sessions) -> UsageReport? {
        for log in recentLogs(in: sessions) {
            if let report = latest(in: tail(of: log)) { return report }
        }
        return nil
    }

    /// Logs in the newest day folders, most recently written first.
    static func recentLogs(in sessions: URL) -> [URL] {
        let manager = FileManager.default
        func children(_ url: URL) -> [String] {
            ((try? manager.contentsOfDirectory(atPath: url.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted(by: >)
        }
        var days: [URL] = []
        search: for year in children(sessions) {
            for month in children(sessions.appending(path: year)) {
                for day in children(sessions.appending(path: "\(year)/\(month)")) {
                    days.append(sessions.appending(path: "\(year)/\(month)/\(day)", directoryHint: .isDirectory))
                    if days.count == daysToSearch { break search }
                }
            }
        }
        let logs = days.flatMap { day in children(day).filter { $0.hasSuffix(".jsonl") }.map { day.appending(path: $0) } }
        func modified(_ url: URL) -> Date {
            ((try? manager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date) ?? .distantPast
        }
        return logs.map { ($0, modified($0)) }.sorted { $0.1 > $1.1 }.prefix(logsToSearch).map(\.0)
    }

    static func tail(of url: URL) -> Data {
        guard SafeFile.isOwnedRegularFile(url, maximumBytes: .max), let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0)
        return (try? handle.readToEnd()) ?? Data()
    }

    /// The last line with a non-null `rate_limits`. A partial first line from the tail just fails to parse.
    static func latest(in data: Data) -> UsageReport? {
        let marker = Data(#""rate_limits":{"#.utf8)
        for line in data.split(separator: UInt8(ascii: "\n")).reversed() where line.range(of: marker) != nil {
            if let report = parse(line: Data(line)) { return report }
        }
        return nil
    }

    static func parse(line: Data) -> UsageReport? {
        guard let event = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let payload = event["payload"] as? [String: Any],
              let limits = payload["rate_limits"] as? [String: Any] else { return nil }
        let observed = (event["timestamp"] as? String).flatMap(timestamp) ?? Date()
        let windows = ["primary", "secondary"].compactMap { key -> UsageWindow? in
            guard let window = limits[key] as? [String: Any],
                  let used = (window["used_percent"] as? NSNumber)?.doubleValue else { return nil }
            let minutes = (window["window_minutes"] as? NSNumber)?.intValue
            // Older Codex builds gave seconds from now instead of a timestamp.
            let resets = (window["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
                ?? (window["resets_in_seconds"] as? NSNumber).map { observed.addingTimeInterval($0.doubleValue) }
            return UsageWindow(id: key, minutes: minutes, usedPercent: used, resetsAt: resets)
        }
        guard !windows.isEmpty else { return nil }
        return UsageReport(agent: .codex, windows: windows, plan: limits["plan_type"] as? String, observedAt: observed)
    }

    static func timestamp(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
