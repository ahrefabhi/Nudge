import Foundation
import PipHookSchema
import Testing
@testable import PipKit

@Suite struct UsageReaderTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "pip-usage-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// A `token_count` line as Codex writes it.
    static func codexLine(timestamp: String = "2026-09-24T13:18:52.399Z", primary: String, secondary: String = "null", plan: String = "plus") -> String {
        """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1}},\
        "rate_limits":{"limit_id":"codex","primary":\(primary),"secondary":\(secondary),"credits":{"has_credits":false},"plan_type":"\(plan)"}}}
        """
    }

    @Test func readsCodexWindowsAndPlan() throws {
        let line = Self.codexLine(primary: #"{"used_percent":12.5,"window_minutes":300,"resets_at":1792847571}"#,
                                  secondary: #"{"used_percent":40.0,"window_minutes":10080,"resets_at":1793000000}"#)
        let report = try #require(CodexUsageReader.parse(line: Data(line.utf8)))
        #expect(report.agent == .codex)
        #expect(report.plan == "plus")
        #expect(report.windows.map(\.title) == ["5-hour", "Weekly"])
        #expect(report.windows[0].usedPercent == 12.5)
        #expect(report.windows[0].resetsAt == Date(timeIntervalSince1970: 1_792_847_571))
        #expect(report.observedAt == CodexUsageReader.timestamp("2026-09-24T13:18:52.399Z"))
    }

    @Test func olderCodexResetsCountFromTheReading() throws {
        let line = Self.codexLine(primary: #"{"used_percent":5,"window_minutes":43200,"resets_in_seconds":60}"#, plan: "free")
        let report = try #require(CodexUsageReader.parse(line: Data(line.utf8)))
        #expect(report.windows.first?.title == "30-day")
        #expect(report.windows.first?.resetsAt == report.observedAt.addingTimeInterval(60))
    }

    @Test func takesTheLastReadingAndSkipsNullOnes() throws {
        let older = Self.codexLine(timestamp: "2026-09-24T10:00:00Z", primary: #"{"used_percent":1,"window_minutes":300}"#)
        let newer = Self.codexLine(timestamp: "2026-09-24T11:00:00Z", primary: #"{"used_percent":9,"window_minutes":300}"#)
        let apiKey = #"{"timestamp":"2026-09-24T12:00:00Z","payload":{"type":"token_count","rate_limits":null}}"#
        let text = [#"{"half a line"#, older, newer, apiKey, #"{"type":"turn_context"}"#].joined(separator: "\n")
        #expect(CodexUsageReader.latest(in: Data(text.utf8))?.windows.first?.usedPercent == 9)
    }

    @Test func findsTheMostRecentlyWrittenLog() throws {
        let sessions = root.appending(path: "sessions", directoryHint: .isDirectory)
        let manager = FileManager.default
        func log(_ day: String, _ name: String, used: Int, modified: Date) throws {
            let folder = sessions.appending(path: day, directoryHint: .isDirectory)
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appending(path: name)
            try Data(Self.codexLine(primary: #"{"used_percent":\#(used),"window_minutes":300}"#).utf8).write(to: file)
            try manager.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
        }
        // A session started yesterday that's still running beats a quieter one from today.
        try log("2026/09/24", "rollout-a.jsonl", used: 10, modified: Date(timeIntervalSinceNow: -600))
        try log("2026/09/23", "rollout-b.jsonl", used: 33, modified: Date(timeIntervalSinceNow: -5))
        #expect(CodexUsageReader.read(sessions: sessions)?.windows.first?.usedPercent == 33)
        #expect(CodexUsageReader.read(sessions: root.appending(path: "missing")) == nil)
    }

    @Test func readsClaudeStatusLineSnapshot() throws {
        let json = """
        {"observedAt":1790000000000,"rateLimits":{"five_hour":{"used_percentage":23.5,"resets_at":1790010000},\
        "seven_day":{"used_percentage":41.2,"resets_at":1790500000}}}
        """
        let report = try #require(ClaudeUsageReader.parse(Data(json.utf8)))
        #expect(report.agent == .claude)
        #expect(report.windows.map(\.title) == ["5-hour", "Weekly"])
        #expect(report.windows.map(\.usedPercent) == [23.5, 41.2])
        #expect(report.observedAt == Date(timeIntervalSince1970: 1_790_000_000))
        #expect(report.windows[0].hasReset(now: Date(timeIntervalSince1970: 1_790_010_001)))
        #expect(!report.windows[1].hasReset(now: Date(timeIntervalSince1970: 1_790_010_001)))
        #expect(ClaudeUsageReader.parse(Data(#"{"observedAt":1,"rateLimits":{}}"#.utf8)) == nil)
    }

    @Test func windowTitles() {
        func title(_ minutes: Int?, _ id: String = "primary") -> String { UsageWindow(id: id, minutes: minutes, usedPercent: 0, resetsAt: nil).title }
        #expect(title(300) == "5-hour")
        #expect(title(10_080) == "Weekly")
        #expect(title(43_200) == "30-day")
        #expect(title(90) == "90-minute")
        #expect(title(nil, "spend_limit") == "Spend limit")
    }
}

@Suite struct StatusLineInstallerTests {
    let root: URL
    let collector: URL
    let paths: PipPaths
    let installer: HookInstaller

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "pip-statusline-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        paths = PipPaths(root: root.appending(path: "App Support/Pip", directoryHint: .isDirectory))
        collector = root.appending(path: "pip-hook-source")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: collector)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: collector.path)
        installer = HookInstaller(target: .claude, settingsURL: root.appending(path: "claude/settings.json"), paths: paths)
    }

    func settings() throws -> OrderedJSON { try OrderedJSON.parse(Data(contentsOf: installer.settingsURL)) }

    @Test func installsAndRemovesWhenThereWasNoStatusLine() throws {
        try Data(#"{"model": "opus"}"#.utf8).write(to: installer.settingsURL.creatingParent())
        #expect(installer.statusLineStatus(bundledCollector: collector) == .notInstalled)
        #expect(try installer.installStatusLine(collectorSource: collector))
        #expect(installer.statusLineStatus(bundledCollector: collector) == .installed)
        let line = try settings()["statusLine"]
        #expect(line?["type"]?.stringValue == "command")
        #expect(line?["command"]?.stringValue == "'\(paths.collector.path)' statusline --usage '\(paths.claudeUsage.path)'")
        #expect(try !installer.installStatusLine(collectorSource: collector), "Installing twice changes nothing")

        #expect(try installer.uninstallStatusLine())
        #expect(try settings() == OrderedJSON.parse(Data(#"{"model": "opus"}"#.utf8)))
        #expect(try !installer.uninstallStatusLine())
    }

    @Test func keepsAndRestoresTheUsersStatusLine() throws {
        let original = #"{"statusLine": {"type": "command", "command": "~/.claude/line.sh 'a b'", "padding": 2}}"#
        try Data(original.utf8).write(to: installer.settingsURL.creatingParent())
        try installer.installStatusLine(collectorSource: collector)

        let line = try settings()["statusLine"]
        #expect(line?["padding"] == .number("2"))
        let command = try #require(line?["command"]?.stringValue)
        #expect(command.contains(" --then "))
        #expect(HookInstaller.forwardedCommand(in: command) == "~/.claude/line.sh 'a b'")

        try installer.uninstallStatusLine()
        #expect(try settings() == OrderedJSON.parse(Data(original.utf8)))
    }

    @Test func removingHooksLeavesTheStatusLine() throws {
        try installer.install(collectorSource: collector)
        try installer.installStatusLine(collectorSource: collector)
        try installer.uninstall()
        #expect(installer.statusLineStatus(bundledCollector: collector) == .installed)
        #expect(installer.status(bundledCollector: collector) == .notInstalled)
    }
}

private extension URL {
    func creatingParent() throws -> URL {
        try FileManager.default.createDirectory(at: deletingLastPathComponent(), withIntermediateDirectories: true)
        return self
    }
}

@Suite struct UsageServiceTests {
    let root: URL
    let paths: PipPaths
    let settings: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "pip-usage-service-\(UUID().uuidString)", directoryHint: .isDirectory)
        paths = PipPaths(root: root.appending(path: "Pip", directoryHint: .isDirectory))
        settings = root.appending(path: "claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.claudeUsage.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    func claude() -> AgentUsage? {
        UsageService.read(paths: paths, claudeSettings: settings, codexSessions: root.appending(path: "none"), codexInstalled: false).first
    }

    @Test func claudeMovesFromSetupToWaitingToNotSharedToConnected() throws {
        #expect(claude()?.source == .needsSetup)

        let installer = HookInstaller(target: .claude, settingsURL: settings, paths: paths)
        let command = installer.statusLineCommand(forwardingTo: nil)
        try Data(#"{"statusLine": {"type": "command", "command": "\#(command.replacing("\"", with: "\\\""))"}}"#.utf8).write(to: settings)
        #expect(claude()?.source == .waitingForStatusLine, "Pip is the status line, but it hasn't run")

        FileManager.default.createFile(atPath: paths.claudeStatusLineSeen.path, contents: nil)
        #expect(claude()?.source == .notShared, "It ran, without usage in its input")

        try Data(#"{"observedAt":1790000000000,"rateLimits":{"five_hour":{"used_percentage":5,"resets_at":1790010000}}}"#.utf8)
            .write(to: paths.claudeUsage)
        #expect(claude()?.source == .connected)
        #expect(claude()?.report?.windows.first?.usedPercent == 5)
    }

    @Test func codexIsListedOnlyWhenInstalled() {
        let none = root.appending(path: "none")
        #expect(UsageService.read(paths: paths, claudeSettings: settings, codexSessions: none, codexInstalled: false).map(\.agent) == [.claude])
        let both = UsageService.read(paths: paths, claudeSettings: settings, codexSessions: none, codexInstalled: true)
        #expect(both.map(\.agent) == [.claude, .codex])
        #expect(both.last?.report == nil)
    }
}
