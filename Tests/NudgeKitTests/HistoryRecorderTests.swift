import Foundation
import Testing
@testable import NudgeKit

@Suite struct HistoryRecorderTests {
    let start = Date(timeIntervalSinceReferenceDate: 10_000)
    var recorder = HistoryRecorder()

    func session(_ kind: SessionKind, since offset: TimeInterval, id: String = "s1", quote: String? = nil) -> NudgeSession {
        NudgeSession(id: id, project: "payments-api", task: "Upgrading Stripe SDK", host: .iTerm, kind: kind,
                   quote: quote, since: start.addingTimeInterval(offset))
    }

    @Test mutating func aPermissionIsLoggedAndTimedWhenAnswered() {
        recorder.record([session(.working, since: 0)], now: start)
        recorder.record([session(.permission, since: 10, quote: "npm install stripe@17.2.0")], now: start.addingTimeInterval(10))
        #expect(recorder.entries.first?.summary == "npm install stripe@17.2.0 · waiting")
        recorder.record([session(.working, since: 48)], now: start.addingTimeInterval(48))
        #expect(recorder.entries.first?.summary == "npm install stripe@17.2.0 · answered after 38s")
    }

    @Test mutating func aFinishedRunRecordsHowLongItTook() {
        recorder.record([session(.idle, since: 0)], now: start)
        recorder.record([session(.working, since: 5)], now: start.addingTimeInterval(5))
        recorder.record([session(.finished, since: 166, quote: "Migrated 14 pages to MDX")], now: start.addingTimeInterval(166))
        #expect(recorder.entries.map(\.kind) == [.finished, .started])
        #expect(recorder.entries.first?.summary == "Migrated 14 pages to MDX · 2m 41s")
    }

    @Test mutating func errorsAreClearedNotAnswered() {
        recorder.record([session(.working, since: 0)], now: start)
        recorder.record([session(.error, since: 60, quote: "State lock held by CI")], now: start.addingTimeInterval(60))
        recorder.record([session(.working, since: 300)], now: start.addingTimeInterval(300))
        #expect(recorder.entries.first?.summary == "State lock held by CI · cleared after 4m")
    }

    @Test mutating func whatWasAlreadyTrueAtLaunchIsNotNews() {
        recorder.record([session(.finished, since: 0), session(.working, since: 0, id: "s2")], now: start)
        #expect(recorder.entries.isEmpty)
    }

    @Test mutating func aSessionWaitingAtLaunchIsLoggedOnce() {
        let waiting = session(.question, since: 0, quote: "Reuse <Popover>?")
        recorder.record([waiting], now: start)
        recorder.record([waiting], now: start.addingTimeInterval(1))
        #expect(recorder.entries.count == 1)
    }

    @Test func anEpisodeThatEndedWhileNudgeWasQuitHasNoDuration() {
        let open = HistoryEntry(id: "old", sessionID: "s1", project: "p", host: .iTerm, kind: .permission,
                                at: start, detail: "git push")
        var recorder = HistoryRecorder(entries: [open])
        recorder.record([], now: start.addingTimeInterval(3 * 3600))
        #expect(recorder.entries.first?.ended == true)
        #expect(recorder.entries.first?.endedAt == nil)
        #expect(recorder.entries.first?.summary == "git push", "no made-up 'answered after 3h'")
    }

    @Test func keepsAWeek() {
        let old = HistoryEntry(id: "old", sessionID: "s", project: "p", host: .iTerm, kind: .finished,
                               at: start.addingTimeInterval(-8 * 24 * 3600))
        var recorder = HistoryRecorder(entries: [old])
        let pruned = recorder.prune(now: start)
        #expect(pruned)
        #expect(recorder.entries.isEmpty)
    }

    @Test func roundTripsThroughTheStore() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "nudge-history-\(UUID().uuidString).json")
        let entry = HistoryEntry(id: "a", sessionID: "s", project: "p", host: .vsCode, kind: .question,
                                 at: Date(timeIntervalSince1970: 1_790_000_000.123), detail: "Which one?",
                                 endedAt: Date(timeIntervalSince1970: 1_790_000_072.5), ended: true)
        HistoryStore(url: url).save([entry])
        #expect(HistoryStore(url: url).load() == [entry])
    }

    @Test(arguments: [(5.0, "5s"), (38, "38s"), (72, "1m 12s"), (161, "2m 41s"), (240, "4m"), (660, "11m"), (3600, "1h"), (7500, "2h 5m")])
    func durations(_ seconds: TimeInterval, _ text: String) {
        #expect(Durations.short(seconds) == text)
    }
}
