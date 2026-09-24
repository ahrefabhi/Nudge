import Foundation
import Testing
@testable import PipKit

@MainActor
@Suite struct PhaseMachineTests {
    let clock = ManualScheduler()
    let machine: PhaseMachine

    init() {
        machine = PhaseMachine(scheduler: clock)
        machine.update(sessions: MockSessions.calm(now: clock.now))
    }

    func trigger(_ event: MockSessions.Event) {
        machine.update(sessions: MockSessions.apply(event, to: machine.sessions, now: clock.now))
    }

    @Test func startsWorkingWhenAgentsRun() {
        #expect(machine.phase == .working)
        #expect(machine.celebrating == nil, "a session already finished at launch is not news")
    }

    @Test func eventPeeksThenAlertsThenFoldsToPill() {
        trigger(.permission)
        #expect(machine.phase == .peek)
        clock.advance(by: 0.71)
        #expect(machine.phase == .peek)
        clock.advance(by: 0.01)
        #expect(machine.phase == .alert)
        #expect(machine.focused?.id == "payments")
        clock.advance(by: 8)
        #expect(machine.phase == .pill)
        clock.advance(by: 60)
        #expect(machine.phase == .pill, "the pill never re-expands on its own")
    }

    @Test func laterFoldsAndTappingThePillReopens() {
        trigger(.permission)
        clock.advance(by: 0.72)
        machine.later()
        #expect(machine.phase == .pill)
        machine.tapIsland()
        #expect(machine.phase == .alert)
    }

    @Test func secondEventJoinsTheOpenAlert() {
        trigger(.permission)
        clock.advance(by: 0.72)
        clock.advance(by: 5)
        trigger(.question)
        #expect(machine.phase == .alert)
        #expect(machine.queue.map(\.id) == ["payments", "dash"])
        clock.advance(by: 7.9)
        #expect(machine.phase == .alert, "a joining event restarts the 8s fold")
    }

    @Test func burstWithinJoinWindowDoesNotDropPipAgain() {
        trigger(.permission)
        clock.advance(by: 0.72)
        machine.later()
        clock.advance(by: 1)
        trigger(.error)
        #expect(machine.phase == .pill)
        clock.advance(by: 4)
        trigger(.question)
        #expect(machine.phase == .peek)
    }

    @Test func openingFocusesSettlesAndPeeksOnceForTheNext() {
        var opened: [String] = []
        machine.onOpen = { opened.append($0.id) }
        trigger(.multiple)
        clock.advance(by: 0.72)
        machine.openFocused()
        #expect(machine.phase == .opening)
        clock.advance(by: 0.32)
        #expect(opened == ["payments"])
        #expect(machine.queue.map(\.id) == ["dash", "infra"])
        clock.advance(by: 0.38)
        #expect(machine.phase == .working)
        clock.advance(by: 1.5)
        #expect(machine.phase == .peek)
        clock.advance(by: 0.72)
        #expect(machine.phase == .pill, "the reminder peek does not re-open the alert")
    }

    @Test func openingTheLastItemReturnsToWorking() {
        trigger(.permission)
        clock.advance(by: 0.72)
        machine.openFocused()
        clock.advance(by: 5)
        #expect(machine.phase == .working)
        #expect(machine.working.contains { $0.id == "payments" }, "an opened session reads as working")
    }

    @Test func finishedWinksWithoutExpanding() {
        trigger(.success)
        #expect(machine.phase == .working)
        #expect(machine.celebrating?.id == "docs")
        clock.advance(by: 3)
        #expect(machine.celebrating == nil)
    }

    @Test func managerOpensFromTheIslandAndClosesOnOutsideClick() {
        machine.tapIsland()
        #expect(machine.phase == .manager)
        trigger(.permission)
        #expect(machine.phase == .manager, "the manager already lists it")
        machine.tapOutside()
        #expect(machine.phase == .pill)
    }

    @Test func cycleMovesTheCursorThroughTheQueue() {
        trigger(.multiple)
        clock.advance(by: 0.72)
        #expect(machine.focused?.id == "payments")
        machine.cycleNext()
        #expect(machine.focused?.id == "dash")
        machine.cycleNext()
        machine.cycleNext()
        #expect(machine.focused?.id == "payments")
    }

    @Test func answeredElsewhereClearsTheAlert() {
        trigger(.permission)
        clock.advance(by: 0.72)
        let answered = machine.sessions.map { $0.id == "payments" ? MockSessions.answered($0, now: clock.now) : $0 }
        machine.update(sessions: answered)
        #expect(machine.phase == .working)
    }

    @Test func aWorkingSessionCanBeOpenedFromTheManager() {
        var opened: [String] = []
        machine.onOpen = { opened.append($0.id) }
        machine.tapIsland()
        machine.open("chrome")
        #expect(machine.phase == .opening)
        clock.advance(by: 0.32)
        #expect(opened == ["chrome"])
        #expect(machine.resolved.isEmpty, "nothing was waiting, so nothing is resolved")
        clock.advance(by: 0.38)
        #expect(machine.phase == .working)
        clock.advance(by: 5)
        #expect(machine.phase == .working, "no reminder peek when nothing is waiting")
    }

    @Test func managerShortcutsCoverEveryRowInOrder() {
        machine.update(sessions: MockSessions.sample(now: clock.now))
        clock.advance(by: 1)
        machine.toggleManager()
        #expect(machine.managerRows.map(\.id) == ["payments", "dash", "infra", "chrome", "auth", "docs"])
        var opened: [String] = []
        machine.onOpen = { opened.append($0.id) }
        machine.openRow(4)
        clock.advance(by: 0.32)
        #expect(opened == ["chrome"])
    }

    @Test func mutedEventsOnlyUpdateThePill() {
        machine.muted = true
        trigger(.permission)
        #expect(machine.phase == .pill)
        clock.advance(by: 10)
        #expect(machine.phase == .pill, "never expands on its own while muted")
        machine.tapIsland()
        #expect(machine.phase == .alert, "the user can still open it")
    }

    @Test func mutingFoldsAnOpenAlertAndUnmutingDoesNotReopenIt() {
        trigger(.permission)
        clock.advance(by: 0.72)
        #expect(machine.phase == .alert)
        machine.muted = true
        #expect(machine.phase == .pill)
        machine.muted = false
        clock.advance(by: 10)
        #expect(machine.phase == .pill)
    }

    @Test func noReminderPeekWhileMuted() {
        trigger(.multiple)
        clock.advance(by: 0.72)
        machine.openFocused()
        machine.muted = true
        clock.advance(by: 5)
        #expect(machine.phase == .pill)
    }

    @Test func aResolvedSessionThatAsksAgainIsAnnounced() {
        trigger(.permission)
        clock.advance(by: 0.72)
        machine.openFocused()
        clock.advance(by: 5)
        clock.advance(by: 10)
        trigger(.permission)
        #expect(machine.phase == .peek)
    }

    // MARK: Chimes

    @Test func eachNewEpisodeChimesWithItsKind() {
        var chimes: [Chime] = []
        machine.onChime = { chimes.append($0) }
        trigger(.permission)
        clock.advance(by: 2)
        trigger(.error)
        clock.advance(by: 2)
        trigger(.success)
        #expect(chimes == [.permission, .error, .finished])
    }

    @Test func aBurstChimesOnceWithTheMostUrgent() {
        var chimes: [Chime] = []
        machine.onChime = { chimes.append($0) }
        trigger(.multiple)
        #expect(chimes == [.permission])
        clock.advance(by: 0.5)
        trigger(.success)
        #expect(chimes == [.permission], "a second event right after stays silent")
    }

    @Test func noChimeWhileMutedOrAtLaunch() {
        var chimes: [Chime] = []
        let fresh = PhaseMachine(scheduler: clock)
        fresh.onChime = { chimes.append($0) }
        fresh.update(sessions: MockSessions.apply(.permission, to: MockSessions.calm(now: clock.now), now: clock.now))
        #expect(chimes.isEmpty, "sessions already waiting at launch are not news")

        machine.onChime = { chimes.append($0) }
        machine.muted = true
        trigger(.permission)
        #expect(chimes.isEmpty)
    }

    // MARK: In view

    @Test func aSessionInViewOnlyUpdatesThePill() {
        var chimes: [Chime] = []
        machine.onChime = { chimes.append($0) }
        machine.isInView = { $0.id == "payments" }
        trigger(.permission)
        #expect(machine.phase == .pill, "no peek for the tab you're looking at")
        #expect(machine.queue.map(\.id) == ["payments"], "it still counts")
        #expect(chimes.isEmpty)
        clock.advance(by: 10)
        #expect(machine.phase == .pill)
    }

    @Test func anotherSessionStillAnnouncesWhileOneIsInView() {
        var chimes: [Chime] = []
        machine.onChime = { chimes.append($0) }
        machine.isInView = { $0.id == "payments" }
        trigger(.multiple)
        #expect(machine.phase == .peek)
        #expect(chimes == [.question], "the sound is for the most urgent session not in view")
    }
}
