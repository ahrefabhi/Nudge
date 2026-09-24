import Foundation
import NudgeHookSchema
import Testing
@testable import NudgeKit

@Suite struct LiveUsageTests {
    let root: URL
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "nudge-live-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// A stand-in for a CLI: a shell script, made executable.
    func tool(_ name: String, _ script: String) throws -> URL {
        let url = root.appending(path: name)
        try "#!/bin/sh\n\(script)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    static let rateLimits = #"{"rateLimits":{"primary":{"usedPercent":64,"windowDurationMins":300,"resetsAt":1790008000},"secondary":{"usedPercent":22,"windowDurationMins":10080,"resetsAt":1790500000},"planType":"plus"}}"#

    @Test func readsCodexsOwnAnswer() throws {
        // Answers only the rate limit request, after some unrelated output, as the real server may.
        let codex = try tool("codex", """
            while read line; do
              case "$line" in
                *'"id":1'*) echo '{"id":1,"result":{}}' ;;
                *'"id":2'*) echo 'not json'; echo '{"id":2,"result":\(Self.rateLimits)}' ;;
              esac
            done
            """)
        let report = try #require(CodexLiveUsage.read(codex: codex, now: now, timeout: 5))
        #expect(report.plan == "plus")
        #expect(report.observedAt == now)
        #expect(report.windows.map(\.title) == ["5-hour", "Weekly"])
        #expect(report.windows.first?.usedPercent == 64)
        #expect(report.windows.first?.resetsAt == Date(timeIntervalSince1970: 1_790_008_000))
    }

    @Test func givesUpOnACodexThatNeverAnswers() throws {
        let codex = try tool("codex", "sleep 30")
        let started = Date()
        #expect(CodexLiveUsage.read(codex: codex, now: now, timeout: 1) == nil)
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test func aCodexErrorIsNoReading() {
        #expect(CodexLiveUsage.parse(result: nil, now: now) == nil)
        #expect(CodexLiveUsage.parse(result: ["rateLimits": ["primary": NSNull()]], now: now) == nil)
    }

    static let claudeUsage = #"{"subscription_type":"team","rate_limits_available":true,"rate_limits":{"five_hour":{"utilization":6,"resets_at":"2026-09-25T00:30:00.298538+00:00"},"seven_day":{"utilization":23,"resets_at":"2026-09-27T04:00:00.298556+00:00"},"seven_day_opus":null}}"#

    @Test func readsClaudeCodesOwnAnswer() throws {
        // Answers `get_usage` only when started without the user's settings, hooks or MCP servers.
        let claude = try tool("claude", """
            case "$*" in *"--setting-sources  --strict-mcp-config --no-session-persistence"*) ;; *) exit 1 ;; esac
            while read line; do
              case "$line" in
                *'"request_id":"init"'*) echo '{"type":"control_response","response":{"subtype":"success","request_id":"init","response":{}}}' ;;
                *'"subtype":"get_usage"'*) echo '{"type":"control_response","response":{"subtype":"success","request_id":"usage","response":\(Self.claudeUsage)}}' ;;
              esac
            done
            """)
        guard case .report(let report) = try #require(ClaudeLiveUsage.read(claude: claude, now: now, timeout: 5)) else {
            Issue.record("expected a report"); return
        }
        #expect(report.plan == "team")
        #expect(report.windows.map(\.title) == ["5-hour", "Weekly"])
        #expect(report.windows.map(\.usedPercent) == [6, 23])
        let reset = try #require(report.windows.first?.resetsAt)
        #expect(abs(reset.timeIntervalSince(try #require(ISO8601DateFormatter().date(from: "2026-09-25T00:30:00Z"))) - 0.2985) < 0.001)
    }

    @Test func anAccountWithoutLimitsSaysSo() {
        #expect(ClaudeLiveUsage.parse(["rate_limits_available": false, "subscription_type": ""], now: now) == .unavailable)
        #expect(ClaudeLiveUsage.parse(["rate_limits": ["five_hour": NSNull()]], now: now) == nil)
        #expect(ClaudeLiveUsage.parse(nil, now: now) == nil)
    }

    @Test func givesUpOnAClaudeThatNeverAnswers() throws {
        let claude = try tool("claude", "sleep 30")
        #expect(ClaudeLiveUsage.read(claude: claude, now: now, timeout: 1) == nil)
    }
}

@Suite struct OwnHelperTests {
    @Test func aSessionListEntryForNudgesOwnChildIsSkipped() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "nudge-registry-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let child = Process()
        child.executableURL = URL(filePath: "/bin/sleep")
        child.arguments = ["10"]
        try child.run()
        defer { child.terminate() }
        for pid in [child.processIdentifier, getppid()] {
            try Data(#"{"pid":\#(pid),"sessionId":"s\#(pid)","cwd":"/tmp"}"#.utf8).write(to: directory.appending(path: "\(pid).json"))
        }
        #expect(SessionRegistry.read(from: directory).map(\.pid) == [getppid()])
    }
}

@Suite struct UsageServiceLiveTests {
    let root: URL
    let paths: NudgePaths
    let settings: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "nudge-usage-live-\(UUID().uuidString)", directoryHint: .isDirectory)
        paths = NudgePaths(root: root.appending(path: "Nudge", directoryHint: .isDirectory))
        settings = root.appending(path: "claude/settings.json")
    }

    func read(codexLive: UsageReport? = nil, claudeLive: ClaudeLiveUsage.Answer? = nil, codexSessions: URL? = nil) -> [AgentUsage] {
        UsageService.read(paths: paths, claudeSettings: settings, codexSessions: codexSessions ?? root.appending(path: "none"),
                          codexInstalled: true, codexLive: codexLive, claudeLive: claudeLive)
    }

    @Test func claudesOwnAnswerNeedsNoSetup() {
        let live = UsageReport(agent: .claude, windows: [UsageWindow(id: "five_hour", minutes: 300, usedPercent: 6, resetsAt: nil)],
                               plan: "team", observedAt: Date())
        let claude = read(claudeLive: .report(live)).first
        #expect(claude?.source == .connected)
        #expect(claude?.report == live)
        #expect(read(claudeLive: .unavailable).first?.source == .unavailable)
        #expect(read().first?.source == .needsSetup, "Without an answer, the status line is the way")
    }

    @Test func codexShowsItsLiveAnswerWhenTheLogsHaveNone() {
        let live = UsageReport(agent: .codex, windows: [UsageWindow(id: "primary", minutes: 300, usedPercent: 12, resetsAt: nil)],
                               observedAt: Date())
        #expect(read(codexLive: live).last?.report == live)
    }

    @Test func theNewerOfTheLogAndTheLiveAnswerWins() throws {
        let day = root.appending(path: "sessions/2026/09/24", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let line = UsageReaderTests.codexLine(timestamp: "2026-09-24T13:18:52.399Z",
                                              primary: #"{"used_percent":50,"window_minutes":300,"resets_at":1790010000}"#)
        try Data((line + "\n").utf8).write(to: day.appending(path: "rollout-1.jsonl"))
        let sessions = root.appending(path: "sessions")
        let logTime = try #require(CodexUsageReader.timestamp("2026-09-24T13:18:52.399Z"))

        func live(at date: Date) -> UsageReport {
            UsageReport(agent: .codex, windows: [UsageWindow(id: "primary", minutes: 300, usedPercent: 70, resetsAt: nil)], observedAt: date)
        }
        #expect(read(codexLive: live(at: logTime.addingTimeInterval(60)), codexSessions: sessions).last?.report?.windows.first?.usedPercent == 70)
        #expect(read(codexLive: live(at: logTime.addingTimeInterval(-60)), codexSessions: sessions).last?.report?.windows.first?.usedPercent == 50)
    }
}
