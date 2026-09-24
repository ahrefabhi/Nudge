import Foundation
import Testing
@testable import NudgeKit

@Suite struct AttentionQueueTests {
    let now = Date(timeIntervalSinceReferenceDate: 1_000)

    func session(_ id: String, _ kind: SessionKind, age: TimeInterval) -> NudgeSession {
        NudgeSession(id: id, project: id, task: "", host: .iTerm, kind: kind, since: now.addingTimeInterval(-age))
    }

    @Test func ranksByUrgencyThenOldestWait() {
        let sessions = [
            session("err", .error, age: 900),
            session("q-new", .question, age: 10),
            session("perm", .permission, age: 5),
            session("q-old", .question, age: 60),
            session("wait", .waiting, age: 30),
            session("busy", .working, age: 1),
        ]
        #expect(AttentionQueue.ordered(sessions).map(\.id) == ["perm", "q-old", "q-new", "wait", "err"])
    }

    @Test func finishedOnlyQueuesWhenAsked() {
        let sessions = [session("done", .finished, age: 1), session("perm", .permission, age: 1)]
        #expect(AttentionQueue.ordered(sessions).map(\.id) == ["perm"])
        #expect(AttentionQueue.ordered(sessions, includeFinished: true).map(\.id) == ["perm", "done"])
    }

    @Test func resolvedEpisodesAreHidden() {
        let perm = session("perm", .permission, age: 1)
        #expect(AttentionQueue.ordered([perm], resolved: [perm.attentionKey]).isEmpty)
    }

    @Test func aNewEpisodeHasANewKey() {
        let first = session("perm", .permission, age: 10)
        var second = first
        second.since = now
        #expect(first.attentionKey != second.attentionKey)
    }
}
