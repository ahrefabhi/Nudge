import Foundation
import Testing
@testable import NudgeKit

@Suite struct HostFilterTests {
    let date = Date(timeIntervalSince1970: 0)

    func session(_ id: String, _ host: HostApp, app: (String, String)? = nil) -> NudgeSession {
        NudgeSession(id: id, project: "p", task: "t", host: host, hostAppName: app?.1, hostBundleID: app?.0, kind: .working, since: date)
    }

    @Test func hidesOtherAppsByBundleIDAndBuiltInsByType() {
        let filter = HostFilter(hiddenHosts: [.iTerm], hiddenApps: ["dev.warp.Warp-Stable"])
        #expect(filter.hides(session("a", .iTerm)))
        #expect(filter.hides(session("b", .other, app: ("dev.warp.Warp-Stable", "Warp"))))
        #expect(!filter.hides(session("c", .other, app: ("com.mitchellh.ghostty", "Ghostty"))))
        #expect(!filter.hides(session("d", .other)))
        #expect(!filter.hides(session("e", .terminal)))
    }

    @Test func seenAppsComeFromSessionsHistoryAndHiddenAppsSortedByName() {
        let history = [HistoryEntry(id: "h", sessionID: "old", project: "p", host: .other, hostName: "Zed",
                                    hostBundleID: "dev.zed.Zed", kind: .finished, at: date)]
        let apps = OtherApp.seen(sessions: [session("a", .other, app: ("com.mitchellh.ghostty", "Ghostty")), session("b", .iTerm)],
                                 history: history, hidden: ["dev.warp.Warp-Stable": "Warp"])
        #expect(apps.map(\.name) == ["Ghostty", "Warp", "Zed"])
    }

    @Test func sessionsWithoutAnAppShareOneEntryThatHidesThemAll() {
        let history = [HistoryEntry(id: "h", sessionID: "old", project: "p", host: .other, kind: .finished, at: date)]
        let apps = OtherApp.seen(sessions: [session("a", .other, app: ("dev.zed.Zed", "Zed"))], history: history, hidden: [:])
        #expect(apps == [OtherApp(bundleID: "dev.zed.Zed", name: "Zed"), .unidentified])

        let filter = HostFilter(hiddenHosts: [], hiddenApps: [OtherApp.unidentified.bundleID])
        #expect(filter.hides(session("b", .other)))
        #expect(filter.hides(history[0]))
        #expect(!filter.hides(session("c", .other, app: ("dev.zed.Zed", "Zed"))))
    }

    @Test func anAppWithoutANameIsLookedUp() {
        var unnamed = session("a", .other)
        unnamed.hostBundleID = "com.mitchellh.ghostty"
        #expect(OtherApp.seen(sessions: [unnamed], history: [], hidden: [:]) { _ in "Ghostty" }.map(\.name) == ["Ghostty"])
        #expect(OtherApp.seen(sessions: [unnamed], history: [], hidden: [:]) == [.unidentified])
    }

    @Test func oldHistoryLearnsItsAppWhileTheSessionRuns() {
        let old = HistoryEntry(id: "h", sessionID: "a", project: "p", host: .other, kind: .finished, at: date)
        #expect(old.displayHostName == "Claude Code")
        var recorder = HistoryRecorder(entries: [old])
        let changed = recorder.record([session("a", .other, app: ("dev.warp.Warp-Stable", "Warp"))], now: date)
        #expect(changed)
        #expect(recorder.entries[0].hostBundleID == "dev.warp.Warp-Stable")
        #expect(recorder.entries[0].displayHostName == "Warp")
    }
}
