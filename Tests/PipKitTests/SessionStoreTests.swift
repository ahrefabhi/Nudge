import Foundation
import PipHookSchema
import Testing
@testable import PipKit

@Suite struct SessionStoreTests {
    @Test func aWaitingQuestionSurvivesARestart() {
        var reducer = SessionReducer()
        var record = HookRecord(id: "r1", event: "PreToolUse", observedAt: 1_790_000_000_000, sessionID: "s1")
        record.cwd = "/Users/me/code/dashboard-v2"
        record.toolName = "AskUserQuestion"
        record.toolUseID = "q1"
        record.toolInput = HookRecord.ToolInput()
        record.toolInput?.questions = [HookRecord.Question(question: "Reuse <Popover>?", options: ["Reuse", "New"])]
        record.host = HookRecord.HostHint(bundleID: "com.microsoft.VSCode")
        reducer.apply(record)
        reducer.reconcile([RegistryEntry(pid: 7, sessionId: "s1", cwd: "/Users/me/code/dashboard-v2", status: .waiting)],
                          now: Date(timeIntervalSince1970: 1_790_000_001))

        let url = FileManager.default.temporaryDirectory.appending(path: "pip-sessions-\(UUID().uuidString).json")
        SessionStore(url: url).save(Array(reducer.sessions.values))
        let restored = SessionReducer(restoring: SessionStore(url: url).load())

        #expect(restored.sessions == reducer.sessions)
        let session = SessionProjection.session(restored.sessions["s1"]!, branch: nil)
        #expect(session.kind == .question)
        #expect(session.choices == ["Reuse", "New"])
        #expect(session.host == .vsCode)
    }

    @Test mutating func sessionsThatEndedWhilePipWasQuitAreDropped() {
        var saved = ObservedSession(id: "gone", cwd: "/x", since: Date(timeIntervalSince1970: 0))
        saved.registered = true
        saved.pid = 99_999
        var reducer = SessionReducer(restoring: [saved])
        reducer.reconcile([], now: Date())
        #expect(reducer.sessions.isEmpty)
    }

    @Test func aMissingOrDamagedFileStartsEmpty() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "pip-sessions-\(UUID().uuidString).json")
        #expect(SessionStore(url: url).load().isEmpty)
        try Data("{not json".utf8).write(to: url)
        #expect(SessionStore(url: url).load().isEmpty)
    }
}
