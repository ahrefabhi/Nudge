import Foundation
import PeekuHookSchema
import Testing
@testable import PeekuKit

@Suite struct OrderedJSONTests {
    @Test func roundTripsKeepingOrderAndNumbers() throws {
        let text = """
        {
          "zeta": 1,
          "alpha": {
            "list": [
              1.50,
              -2e3,
              true,
              null
            ],
            "empty": {},
            "none": []
          },
          "text": "tab\\t quote\\" slash/ emoji 🐙 \\u00e9"
        }

        """
        let value = try OrderedJSON.parse(Data(text.utf8))
        #expect(value["text"]?.stringValue == "tab\t quote\" slash/ emoji 🐙 é")
        let written = String(decoding: value.serialized(), as: UTF8.self)
        #expect(written == text.replacing("\\u00e9", with: "é"))
    }

    @Test func rejectsInvalidJSON() {
        #expect(throws: OrderedJSON.ParseError.self) { try OrderedJSON.parse(Data("{\"a\": }".utf8)) }
        #expect(throws: OrderedJSON.ParseError.self) { try OrderedJSON.parse(Data("{} extra".utf8)) }
    }
}

@Suite struct HookInstallerTests {
    let root: URL
    let installer: HookInstaller
    let collector: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "peeku-install-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        installer = HookInstaller(settingsURL: root.appending(path: "claude/settings.json"),
                                  paths: PeekuPaths(root: root.appending(path: "Peeku", directoryHint: .isDirectory)))
        collector = root.appending(path: "peeku-hook-source")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: collector)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: collector.path)
    }

    func writeSettings(_ text: String) throws {
        try FileManager.default.createDirectory(at: installer.settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: installer.settingsURL)
    }

    func settings() throws -> OrderedJSON { try OrderedJSON.parse(Data(contentsOf: installer.settingsURL)) }

    @Test func installsIntoMissingSettings() throws {
        #expect(installer.status(bundledCollector: collector) == .notInstalled)
        #expect(try installer.install(collectorSource: collector) == HookInstaller.events.count)
        #expect(installer.status(bundledCollector: collector) == .installed)
        #expect(FileManager.default.isExecutableFile(atPath: installer.paths.collector.path))

        let notification = try settings()["hooks"]?["Notification"]?.arrayValue?.first
        #expect(notification?["matcher"]?.stringValue == "permission_prompt|elicitation_dialog")
        let handler = try settings()["hooks"]?["Stop"]?.arrayValue?.first?["hooks"]?.arrayValue?.first
        #expect(handler?["command"]?.stringValue == installer.paths.collector.path)
        #expect(handler?["args"]?.arrayValue == ["observe", "--event", "Stop", "--inbox", installer.paths.inbox.path].map { .string($0) })
    }

    @Test func keepsOtherSettingsAndHooksInPlace() throws {
        let original = """
        {
          "model": "opus",
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
          },
          "permissions": {
            "allow": [
              "Bash(ls:*)"
            ]
          }
        }

        """
        try writeSettings(original)
        try installer.install(collectorSource: collector)
        let installed = try settings()
        guard case .object(let members) = installed else { Issue.record("not an object"); return }
        #expect(members.map(\.key) == ["model", "hooks", "permissions"])
        #expect(installed["hooks"]?["Stop"]?.arrayValue?.count == 2, "the user's own Stop hook stays first")
        #expect(installed["hooks"]?["Stop"]?.arrayValue?.first?["hooks"]?.arrayValue?.first?["command"]?.stringValue == "say done")

        let backups = try FileManager.default.contentsOfDirectory(atPath: installer.settingsURL.deletingLastPathComponent().path)
            .filter { $0.hasPrefix("settings.json.peeku-backup-") }
        #expect(backups.count == 1)

        try installer.uninstall()
        #expect(String(decoding: try Data(contentsOf: installer.settingsURL), as: UTF8.self) == original)
    }

    @Test func installingTwiceAddsNothing() throws {
        try installer.install(collectorSource: collector)
        #expect(try installer.install(collectorSource: collector) == 0)
    }

    @Test func aChangedCollectorMakesItIncomplete() throws {
        try installer.install(collectorSource: collector)
        try Data("#!/bin/sh\necho new\n".utf8).write(to: collector)
        #expect(installer.status(bundledCollector: collector) == .incomplete)
    }

    @Test func refusesSettingsItDoesNotUnderstand() throws {
        try writeSettings("{\"hooks\": []}")
        #expect(throws: HookInstaller.InstallError.hooksNotAnObject) { try installer.install(collectorSource: collector) }
        try writeSettings("[1, 2]")
        #expect(throws: HookInstaller.InstallError.settingsNotAnObject) { try installer.install(collectorSource: collector) }
    }
}

@Suite struct InboxReaderTests {
    @Test func readsRecordsInOrderAndDeletesThem() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "peeku-inbox-\(UUID().uuidString)", directoryHint: .isDirectory)
        let reader = InboxReader(directory: directory)
        reader.prepare()
        let encoder = HookRecord.encoder()
        for (index, event) in ["SessionStart", "UserPromptSubmit"].enumerated() {
            let record = HookRecord(id: "r\(index)", event: event, observedAt: Int64(index), sessionID: "s1")
            try encoder.encode(record).write(to: directory.appending(path: "\(1000 + index)-r\(index).json"))
        }
        try Data("not json".utf8).write(to: directory.appending(path: "999-bad.json"))
        try Data(repeating: 0x20, count: HookRecord.maximumBytes + 1).write(to: directory.appending(path: "998-huge.json"))
        try Data("{}".utf8).write(to: directory.appending(path: ".pending.tmp"))

        #expect(reader.drain().map(\.event) == ["SessionStart", "UserPromptSubmit"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [".pending.tmp"], "an uncommitted temp file is left alone")
    }
}

@Suite struct LegacyMigrationTests {
    let root: URL
    let legacy: PeekuPaths
    let current: PeekuPaths
    let settings: [HookInstaller.Target: URL]
    let collector: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "peeku-migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        legacy = PeekuPaths(root: root.appending(path: "Nudge", directoryHint: .isDirectory), collectorName: "nudge-hook")
        current = PeekuPaths(root: root.appending(path: "Peeku", directoryHint: .isDirectory))
        settings = [.claude: root.appending(path: "claude/settings.json"), .codex: root.appending(path: "codex/hooks.json")]
        collector = root.appending(path: "peeku-hook-source")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: collector)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: collector.path)
    }

    func installer(_ target: HookInstaller.Target, _ paths: PeekuPaths) -> HookInstaller {
        HookInstaller(target: target, settingsURL: settings[target], paths: paths)
    }

    @Test func movesTheOldHooksStatusLineAndData() throws {
        try FileManager.default.createDirectory(at: settings[.claude]!.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"statusLine": {"type": "command", "command": "my-line"}}"#.utf8).write(to: settings[.claude]!)
        try installer(.claude, legacy).install(collectorSource: collector)
        try installer(.claude, legacy).installStatusLine(collectorSource: collector)
        try Data("[]".utf8).write(to: legacy.root.appending(path: "history.json"))

        let moved = try LegacyMigration(legacy: legacy, current: current, settings: settings).run(collectorSource: collector)

        #expect(moved == [.claude])
        #expect(installer(.claude, legacy).status(bundledCollector: nil) == .notInstalled)
        #expect(installer(.claude, current).status(bundledCollector: collector) == .installed)
        #expect(installer(.claude, current).statusLineStatus(bundledCollector: collector) == .installed)
        let line = try OrderedJSON.parse(Data(contentsOf: settings[.claude]!))["statusLine"]?["command"]?.stringValue ?? ""
        #expect(HookInstaller.forwardedCommand(in: line) == "my-line")
        #expect(FileManager.default.fileExists(atPath: current.root.appending(path: "history.json").path))
        #expect(!FileManager.default.fileExists(atPath: legacy.root.path))
    }

    @Test func leavesTheOldInstallAloneWhenTheCollectorIsMissing() throws {
        try installer(.claude, legacy).install(collectorSource: collector)
        #expect(throws: HookInstaller.InstallError.collectorMissing) {
            try LegacyMigration(legacy: legacy, current: current, settings: settings).run(collectorSource: nil)
        }
        #expect(installer(.claude, legacy).status(bundledCollector: nil) == .installed)
        #expect(FileManager.default.fileExists(atPath: legacy.collector.path))
    }

    @Test func doesNothingWithoutAnOldInstall() throws {
        let migration = LegacyMigration(legacy: legacy, current: current, settings: settings)
        #expect(!migration.isNeeded)
        #expect(try migration.run(collectorSource: collector).isEmpty)
    }
}
