import Darwin
import Foundation
import Testing
@testable import PeekuKit

@Suite struct LogLineSplitterTests {
    @Test func linesWaitForTheirNewline() {
        var splitter = LogLineSplitter()
        #expect(splitter.feed(Data("hel".utf8)) == [])
        #expect(splitter.feed(Data("lo\nwor".utf8)) == ["hello"])
        #expect(splitter.finish() == ["wor"])
    }

    @Test func colorsAndCursorCodesAreDropped() {
        var splitter = LogLineSplitter()
        let line = "\u{1B}[32m➜\u{1B}[39m  Local: \u{1B}[1mhttp://localhost:5173/\u{1B}[22m\u{1B}[K\n"
        #expect(splitter.feed(Data(line.utf8)) == ["➜  Local: http://localhost:5173/"])
    }

    @Test func titleSequencesAreDropped() {
        #expect(LogLineSplitter.stripEscapes("\u{1B}]0;vite\u{07}ready") == "ready")
    }

    @Test func aCarriageReturnKeepsTheLastRedraw() {
        var splitter = LogLineSplitter()
        #expect(splitter.feed(Data("10%\r50%\r100%\n".utf8)) == ["100%"])
        #expect(splitter.feed(Data("windows line\r\n".utf8)) == ["windows line"])
    }

    @Test func aRunawayLineIsCut() {
        var splitter = LogLineSplitter()
        let lines = splitter.feed(Data(String(repeating: "x", count: LogLineSplitter.maxLineLength + 10).utf8))
        #expect(lines.count == 1)
    }
}

@Suite(.serialized) @MainActor struct CommandRunnerTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "peeku-commands-\(UUID().uuidString)")

    private func runner(_ command: String) -> (CommandRunner, UUID) {
        let runner = CommandRunner(store: CommandStore(root: root))
        let saved = QuickCommand(directory: FileManager.default.temporaryDirectory.path, command: command)
        runner.save(saved)
        return (runner, saved.id)
    }

    private func waitUntil(_ timeout: TimeInterval = 10, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(50)) }
    }

    @Test func commandsAreSavedAndReloaded() {
        let (_, id) = runner("npm run dev")
        let reloaded = CommandRunner(store: CommandStore(root: root))
        #expect(reloaded.commands.map(\.id) == [id])
        #expect(reloaded.commands.first?.command == "npm run dev")
    }

    @Test func outputAndExitCodeAreCollected() async throws {
        let (runner, id) = runner("echo one; echo two >&2; exit 3")
        runner.start(id)
        let run = try #require(runner.run(for: id))
        await waitUntil { !run.status.isActive && run.lines.contains("two") }
        #expect(run.lines.suffix(2) == ["one", "two"])
        guard case .exited(let code, _) = run.status else { Issue.record("status \(run.status)"); return }
        #expect(code == 3)
        let file = try String(contentsOf: runner.logURL(for: id), encoding: .utf8)
        #expect(file.hasSuffix("one\ntwo\n"))
    }

    @Test func itRunsInTheChosenFolder() async throws {
        let (runner, id) = runner("pwd -P")
        runner.start(id)
        let run = try #require(runner.run(for: id))
        await waitUntil { !run.status.isActive && run.lastLine != nil }
        let resolved = try #require(realpath(FileManager.default.temporaryDirectory.path, nil))
        defer { free(resolved) }
        #expect(run.lastLine == String(cString: resolved))
    }

    @Test func stoppingKillsGrandchildrenToo() async throws {
        // A background grandchild that ignores SIGTERM, like a stubborn dev server.
        let (runner, id) = runner("sh -c 'trap \"\" TERM; echo $$; sleep 60' & wait")
        runner.start(id)
        let run = try #require(runner.run(for: id))
        await waitUntil { run.lastLine != nil }
        let grandchild = try #require(run.lastLine.flatMap { pid_t($0) })
        #expect(kill(grandchild, 0) == 0)

        runner.stop(id)
        await waitUntil { !run.status.isActive }
        guard case .stopped = run.status else { Issue.record("status \(run.status)"); return }
        await waitUntil(CommandRunner.stopGrace + 3) { kill(grandchild, 0) != 0 }
        #expect(kill(grandchild, 0) != 0)
    }

    @Test func restartRunsItAgain() async throws {
        let (runner, id) = runner("echo started; sleep 60")
        runner.start(id)
        let run = try #require(runner.run(for: id))
        await waitUntil { run.lastLine == "started" }
        guard case .running(let first) = run.status else { Issue.record("status \(run.status)"); return }

        runner.restart(id)
        await waitUntil {
            if case .running(let since) = run.status, since > first, run.lastLine == "started" { return true }
            return false
        }
        guard case .running(let second) = run.status else { Issue.record("status \(run.status)"); return }
        #expect(second > first)
        runner.stopAll()
    }

    @Test func aFailureRaisesAnAlertUntilItRunsAgain() async throws {
        let (runner, id) = runner("echo boom; exit 2")
        var changes = 0
        runner.onChange = { changes += 1 }
        runner.start(id)
        let run = try #require(runner.run(for: id))
        await waitUntil { !run.status.isActive && run.lastLine == "boom" }
        let alert = try #require(runner.alerts.first)
        #expect(alert.kind == .command)
        #expect(alert.task == "exited with code 2")
        #expect(alert.quote == "boom")
        #expect(CommandRunner.commandID(forAlert: alert) == id)
        #expect(changes >= 2)

        runner.save(QuickCommand(id: id, directory: FileManager.default.temporaryDirectory.path, command: "sleep 60"))
        runner.start(id)
        #expect(runner.alerts.isEmpty)
        runner.stop(id)
        await waitUntil { !run.status.isActive }
        // Stopping it yourself isn't a failure.
        #expect(runner.alerts.isEmpty)
    }

    @Test func itRunsInATerminal() async throws {
        let (runner, id) = runner("tty")
        runner.start(id)
        let run = try #require(runner.run(for: id))
        await waitUntil { !run.status.isActive && run.lastLine != nil }
        #expect(run.lastLine?.hasPrefix("/dev/ttys") == true)
    }

    @Test func aPromptIsNoticedAndAnswered() async throws {
        let (runner, id) = runner("printf 'Something is already running on port 3000. Use another port? (Y/n) '; read answer; echo \"got $answer\"")
        runner.start(id)
        let run = try #require(runner.run(for: id))
        await waitUntil { run.waitingForInput }
        #expect(run.lastLine?.trimmingCharacters(in: .whitespaces) == "Something is already running on port 3000. Use another port? (Y/n)")
        let alert = try #require(runner.alerts.first)
        #expect(alert.kind == .commandInput)
        #expect(CommandRunner.commandID(forAlert: alert) == id)

        runner.send(id, "y\r")
        #expect(!run.waitingForInput)
        await waitUntil { !run.status.isActive && run.lines.contains("got y") }
        #expect(run.lines.contains("got y"))
        guard case .exited(0, _) = run.status else { Issue.record("status \(run.status)"); return }
        #expect(runner.alerts.isEmpty)
    }

    @Test func ctrlCStopsItWithoutAFailure() async throws {
        let (runner, id) = runner("echo ready; sleep 60")
        runner.start(id)
        let run = try #require(runner.run(for: id))
        await waitUntil { run.lastLine == "ready" }
        runner.send(id, "\u{03}")
        await waitUntil { !run.status.isActive }
        guard case .stopped = run.status else { Issue.record("status \(run.status)"); return }
        #expect(runner.alerts.isEmpty)
    }

    @Test func progressIsNotMistakenForAPrompt() {
        #expect(!LogLineSplitter.looksLikePrompt("Building [=====>    ] 45%"))
        #expect(LogLineSplitter.looksLikePrompt("? Would you like to use a different port? "))
        #expect(LogLineSplitter.looksLikePrompt("Proceed [y/N] "))
    }

    @Test func aMissingFolderFailsToStart() throws {
        let runner = CommandRunner(store: CommandStore(root: root))
        let command = QuickCommand(directory: "/no/such/folder", command: "true")
        runner.save(command)
        runner.start(command.id)
        guard case .failed = try #require(runner.run(for: command.id)).status else { Issue.record("should fail"); return }
    }
}

@Suite @MainActor struct CommandAlertTests {
    let alert = MockSessions.commandAlert(now: Date())

    @Test func aFailureQueuesAndOpensItsOutput() {
        let machine = PhaseMachine(scheduler: ManualScheduler())
        var opened: [PeekuSession] = []
        machine.onOpen = { opened.append($0) }
        machine.update(commandAlerts: [alert])
        #expect(machine.queue.map(\.id) == [alert.id])
        machine.open(alert.id)
        #expect(opened.map(\.id) == [alert.id])
        #expect(machine.queue.isEmpty)
    }

    @Test func restartingFromTheAlertResolvesIt() {
        let machine = PhaseMachine(scheduler: ManualScheduler())
        var restarted: [String] = []
        machine.onRestartCommand = { restarted.append($0.id) }
        machine.update(commandAlerts: [alert])
        machine.restartCommand(alert.id)
        #expect(restarted == [alert.id])
        #expect(machine.queue.isEmpty)
    }
}
