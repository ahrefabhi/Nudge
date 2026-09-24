import Foundation
import NudgeHookSchema
import Testing
@testable import NudgeKit

@Suite struct CodexInstallerTests {
    let root: URL
    let collector: URL
    let paths: NudgePaths

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "nudge-codex-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // A space in the path, like "Application Support", so the quoting is exercised.
        paths = NudgePaths(root: root.appending(path: "App Support/Nudge", directoryHint: .isDirectory))
        collector = root.appending(path: "nudge-hook-source")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: collector)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: collector.path)
    }

    func installer(_ target: HookInstaller.Target) -> HookInstaller {
        HookInstaller(target: target, settingsURL: root.appending(path: target == .codex ? "codex/hooks.json" : "claude/settings.json"), paths: paths)
    }

    @Test func installsOneQuotedCommandPerCodexEvent() throws {
        let codex = installer(.codex)
        #expect(try codex.install(collectorSource: collector) == HookInstaller.Target.codex.events.count)
        #expect(codex.status(bundledCollector: collector) == .installed)

        let hooks = try OrderedJSON.parse(Data(contentsOf: codex.settingsURL))["hooks"]
        let handler = hooks?["PermissionRequest"]?.arrayValue?.first?["hooks"]?.arrayValue?.first
        #expect(handler?["args"] == nil, "Codex has no args field")
        #expect(handler?["command"]?.stringValue == "'\(paths.collector.path)' observe --agent codex --inbox '\(paths.inbox.path)'")
        #expect(hooks?["Notification"] == nil, "Codex has no Notification event")
        #expect(hooks?["Interrupt"] != nil)
    }

    @Test func uninstallRestoresTheCodexFileAndLeavesClaudeAlone() throws {
        let original = """
        {
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "say done"
                  }
                ]
              }
            ]
          }
        }

        """
        let codex = installer(.codex)
        try FileManager.default.createDirectory(at: codex.settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(original.utf8).write(to: codex.settingsURL)
        let claude = installer(.claude)
        try claude.install(collectorSource: collector)
        let claudeBefore = try Data(contentsOf: claude.settingsURL)

        try codex.install(collectorSource: collector)
        #expect(try codex.uninstall() == HookInstaller.Target.codex.events.count)
        #expect(String(decoding: try Data(contentsOf: codex.settingsURL), as: UTF8.self) == original)
        #expect(try Data(contentsOf: claude.settingsURL) == claudeBefore)
        #expect(claude.status(bundledCollector: collector) == .installed)
    }

    @Test func quotingSurvivesAQuoteInThePath() {
        #expect(HookInstaller.quoted("/a/it's/b") == "'/a/it'\\''s/b'")
    }
}

@Suite struct CodexSessionTests {
    var reducer = SessionReducer()
    let start: Int64 = 1_790_000_000_000

    func record(_ event: String, at offset: Int64 = 0, pid: Int32? = 4242, _ configure: (inout HookRecord) -> Void = { _ in }) -> HookRecord {
        var record = HookRecord(id: UUID().uuidString, event: event, observedAt: start + offset, sessionID: "codex-1")
        record.agent = "codex"
        record.agentPID = pid
        record.cwd = "/Users/me/code/api"
        configure(&record)
        return record
    }

    @Test mutating func aCodexPermissionIsAPermissionForCodex() {
        reducer.apply(record("SessionStart"))
        reducer.apply(record("PermissionRequest", at: 1000) {
            $0.toolName = "Bash"
            $0.toolInput = HookRecord.ToolInput()
            $0.toolInput?.command = "npm install"
        })
        let session = SessionProjection.session(reducer.sessions["codex-1"]!, branch: nil)
        #expect(session.agent == .codex)
        #expect(session.kind == .permission)
        #expect(session.quote == "npm install")
        #expect(reducer.sessions["codex-1"]?.pid == 4242, "the collector's Codex process")
    }

    @Test mutating func interruptReturnsToIdle() {
        reducer.apply(record("UserPromptSubmit") { $0.prompt = "refactor the router" })
        reducer.apply(record("Interrupt", at: 1000))
        #expect(reducer.sessions["codex-1"]?.phase == .idle)
    }

    @Test mutating func codexSessionsLiveAsLongAsTheirProcess() {
        reducer.processIsAlive = { $0 == 4242 }
        reducer.apply(record("SessionStart"))
        // Claude's registry never lists Codex sessions; that alone mustn't drop them.
        reducer.reconcile([], now: Date(timeIntervalSince1970: TimeInterval(start) / 1000 + 3600))
        #expect(reducer.sessions["codex-1"] != nil)
        reducer.processIsAlive = { _ in false }
        reducer.reconcile([], now: Date(timeIntervalSince1970: TimeInterval(start) / 1000 + 3601))
        #expect(reducer.sessions["codex-1"] == nil)
    }

    @Test mutating func withoutAProcessACodexSessionExpiresAfterTwoHoursQuiet() {
        reducer.apply(record("SessionStart", pid: nil))
        let last = TimeInterval(start) / 1000
        reducer.reconcile([], now: Date(timeIntervalSince1970: last + 60 * 60))
        #expect(reducer.sessions["codex-1"] != nil)
        reducer.reconcile([], now: Date(timeIntervalSince1970: last + 3 * 60 * 60))
        #expect(reducer.sessions["codex-1"] == nil)
    }
}

@Suite struct AgentCompatibilityTests {
    @Test func sessionsSavedBeforeCodexSupportLoadAsClaude() throws {
        var old = ObservedSession(id: "s1", cwd: "/x", since: Date(timeIntervalSince1970: 1))
        old.phase = .working
        let url = FileManager.default.temporaryDirectory.appending(path: "nudge-old-\(UUID().uuidString).json")
        SessionStore(url: url).save([old])
        // Strip the new field, as an older Nudge would have written it.
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
        json[0]["agent"] = nil
        try JSONSerialization.data(withJSONObject: json).write(to: url)

        let loaded = SessionStore(url: url).load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.resolvedAgent == .claude)
    }

    @Test func historySavedBeforeCodexSupportStillLoads() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "nudge-history-old-\(UUID().uuidString).json")
        let old = """
        [{"id":"a","sessionID":"s","project":"p","host":"iTerm","kind":"finished","at":1790000000000,"ended":false}]
        """
        try Data(old.utf8).write(to: url)
        let loaded = HistoryStore(url: url).load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.agent == nil)
    }
}
