import Foundation
import NudgeHookSchema
import Testing
@testable import NudgeKit

@Suite struct SessionReducerTests {
    var reducer = SessionReducer()
    var clock: Int64 = 1_790_000_000_000

    mutating func send(_ event: String, _ configure: (inout HookRecord) -> Void = { _ in }) {
        clock += 1000
        var record = HookRecord(id: UUID().uuidString, event: event, observedAt: clock, sessionID: "s1")
        record.cwd = "/Users/me/code/payments-api"
        configure(&record)
        reducer.apply(record)
    }

    var session: ObservedSession? { reducer.sessions["s1"] }

    @Test mutating func promptThenToolIsWorkingWithActivity() {
        send("SessionStart")
        #expect(session?.phase == .idle)
        send("UserPromptSubmit") { $0.prompt = "please upgrade the stripe sdk to v17" }
        send("PreToolUse") {
            $0.toolName = "Edit"
            $0.toolUseID = "t1"
            $0.toolInput = HookRecord.ToolInput()
            $0.toolInput?.filePath = "/Users/me/code/payments-api/src/billing.ts"
        }
        #expect(session?.phase == .working)
        #expect(session?.activity == "Editing billing.ts")
        #expect(session?.prompt == "please upgrade the stripe sdk to v17")
    }

    @Test mutating func permissionShowsTheCommandAndClearsWhenTheToolRuns() {
        send("UserPromptSubmit") { $0.prompt = "install stripe" }
        send("PreToolUse") {
            $0.toolName = "Bash"
            $0.toolUseID = "t1"
            $0.toolInput = HookRecord.ToolInput()
            $0.toolInput?.command = "npm install stripe@17.2.0"
        }
        // PermissionRequest may omit the input; the reducer remembers it from PreToolUse.
        send("PermissionRequest") { $0.toolName = "Bash"; $0.toolUseID = "t1" }
        guard case .permission(let permission)? = session?.phase else { Issue.record("expected permission"); return }
        #expect(permission.preview == "npm install stripe@17.2.0")
        let asked = session?.since

        send("Notification") { $0.notificationType = "permission_prompt"; $0.message = "Claude needs your permission" }
        #expect(session?.since == asked, "the confirming notification is the same episode")

        send("PostToolUse") { $0.toolName = "Bash"; $0.toolUseID = "t1" }
        #expect(session?.phase == .working)
    }

    @Test mutating func askUserQuestionIsAQuestionWithChoices() {
        send("PreToolUse") {
            $0.toolName = "AskUserQuestion"
            $0.toolUseID = "q1"
            $0.toolInput = HookRecord.ToolInput()
            $0.toolInput?.questions = [HookRecord.Question(question: "Reuse <Popover>?", options: ["Reuse", "New"])]
        }
        #expect(session?.phase == .question(ObservedSession.Question(text: "Reuse <Popover>?", choices: ["Reuse", "New"], toolUseID: "q1")))
        send("PostToolUse") { $0.toolName = "AskUserQuestion"; $0.toolUseID = "q1" }
        #expect(session?.phase == .working)
    }

    @Test mutating func aSubagentToolDoesNotClearAPendingPermission() {
        send("PermissionRequest") { $0.toolName = "Bash"; $0.toolUseID = "main-tool" }
        send("PreToolUse") { $0.toolName = "Read"; $0.toolUseID = "other"; $0.agentID = "sub" }
        send("PostToolUse") { $0.toolName = "Read"; $0.toolUseID = "other"; $0.agentID = "sub" }
        guard case .permission? = session?.phase else { Issue.record("permission was cleared"); return }
    }

    @Test mutating func stopFinishesWithTheFirstLineAsSummary() {
        send("UserPromptSubmit") { $0.prompt = "migrate docs" }
        send("Stop") { $0.lastAssistantMessage = "## Done\n\nMigrated **14 pages** to MDX." }
        #expect(session?.phase == .finished(summary: "Done"))
    }

    @Test mutating func stopFailureIsAnError() {
        send("StopFailure") { $0.error = "Error acquiring the state lock" }
        #expect(session?.phase == .failed("Error acquiring the state lock"))
        send("UserPromptSubmit") { $0.prompt = "try again" }
        #expect(session?.phase == .working)
    }

    @Test mutating func sessionEndRemovesIt() {
        send("SessionStart")
        send("SessionEnd")
        #expect(session == nil)
    }

    @Test mutating func registryAddsSessionsStartedBeforeNudge() {
        reducer.reconcile([RegistryEntry(pid: 42, sessionId: "old", cwd: "/tmp/app", name: "fix-login", entrypoint: "cli", status: .busy)])
        #expect(reducer.sessions["old"]?.phase == .working)
        #expect(reducer.sessions["old"]?.pid == 42)
    }

    @Test mutating func registryWaitingWithoutAHookIsWaiting() {
        send("UserPromptSubmit") { $0.prompt = "go" }
        reducer.reconcile([RegistryEntry(pid: 1, sessionId: "s1", cwd: "/x", status: .waiting, statusUpdatedAt: clock + 500)])
        #expect(session?.phase == .waiting(nil))
    }

    @Test mutating func registryBusyAfterAPermissionMeansItWasAnswered() {
        send("PermissionRequest") { $0.toolName = "Bash"; $0.toolUseID = "t1" }
        reducer.reconcile([RegistryEntry(pid: 1, sessionId: "s1", cwd: "/x", status: .busy, statusUpdatedAt: clock + 5000)])
        #expect(session?.phase == .working)
    }

    @Test mutating func sessionsLeaveWhenTheRegistryDropsThem() {
        send("SessionStart")
        reducer.reconcile([RegistryEntry(pid: 1, sessionId: "s1", cwd: "/x", status: .idle)], now: Date(timeIntervalSince1970: 1_790_000_010))
        #expect(session != nil)
        reducer.reconcile([], now: Date(timeIntervalSince1970: 1_790_000_020))
        #expect(session == nil)
    }

    @Test mutating func unregisteredSessionsGetAGracePeriod() {
        send("SessionStart")
        let eventTime = Date(timeIntervalSince1970: TimeInterval(clock) / 1000)
        reducer.reconcile([], now: eventTime.addingTimeInterval(5))
        #expect(session != nil)
        reducer.reconcile([], now: eventTime.addingTimeInterval(60))
        #expect(session == nil)
    }
}

@Suite struct SessionProjectionTests {
    func observed(_ configure: (inout ObservedSession) -> Void) -> ObservedSession {
        var session = ObservedSession(id: "s1", cwd: "/Users/me/code/payments-api", since: Date(timeIntervalSince1970: 0))
        configure(&session)
        return session
    }

    @Test func projectIsTheFolderAndTaskComesFromThePrompt() {
        let session = SessionProjection.session(observed {
            $0.prompt = "Can you upgrade the Stripe SDK to v17? It's failing."
            $0.phase = .permission(.init(toolName: "Bash", preview: "npm install stripe@17.2.0", detail: nil, toolUseID: "t1"))
        }, branch: "feat/stripe-v17")
        #expect(session.project == "payments-api")
        #expect(session.task == "Upgrade the Stripe SDK to v17?")
        #expect(session.kind == .permission)
        #expect(session.quote == "npm install stripe@17.2.0")
        #expect(session.branch == "feat/stripe-v17")
    }

    @Test func hostComesFromTheBundleIDThenTheTerminalThenTheEntrypoint() {
        #expect(SessionProjection.host(observed { $0.host.bundleID = "com.googlecode.iterm2" }) == .iTerm)
        #expect(SessionProjection.host(observed { $0.host.termProgram = "Apple_Terminal" }) == .terminal)
        #expect(SessionProjection.host(observed { $0.entrypoint = "claude-vscode" }) == .vsCode)
        #expect(SessionProjection.host(observed { _ in }) == .other)
    }

    @Test func itermTabComesFromTheSessionID() {
        let guid = "6C1E2D3A-0B4F-4E5D-9A8B-7C6D5E4F3A2B"
        let session = observed { $0.host.itermSessionID = "w0t2p0:\(guid)"; $0.host.bundleID = "com.googlecode.iterm2" }
        #expect(SessionProjection.location(session) == "Tab 3")
        #expect(SessionProjection.itermSessionGUID(session) == guid)
        #expect(SessionProjection.itermSessionGUID(observed { $0.host.itermSessionID = "w0t0p0:not a guid\" & do shell" }) == nil)
    }
}

@Suite struct TitleCleanerTests {
    @Test(arguments: [
        ("please fix the flaky login test in ci", "Fix the flaky login test in ci"),
        ("Can you look at https://example.com/x and tell me why the build fails. Thanks", "Look at and tell me why the build…"),
        ("/review-pr 123", "123"),
        ("<pasted_content>\nstack trace here\n</pasted_content>", "Stack trace here"),
        ("## Refactor the **session** store", "Refactor the session store"),
        ("migrate /Users/me/code/docs/guides/intro.md to mdx", "Migrate intro.md to mdx"),
    ])
    func cleans(_ prompt: String, _ expected: String) {
        #expect(TitleCleaner.title(from: prompt) == expected)
    }

    @Test func emptyPromptHasNoTitle() {
        #expect(TitleCleaner.title(from: "   \n ") == nil)
    }
}

@Suite struct GitBranchTests {
    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "nudge-git-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func readsTheBranchFromANestedFolder() throws {
        let repo = try temporaryDirectory()
        try FileManager.default.createDirectory(at: repo.appending(path: ".git"), withIntermediateDirectories: true)
        try "ref: refs/heads/feat/stripe-v17\n".write(to: repo.appending(path: ".git/HEAD"), atomically: true, encoding: .utf8)
        let nested = repo.appending(path: "src/billing", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        #expect(GitBranch.current(in: nested.path) == "feat/stripe-v17")
    }

    @Test func followsAWorktreeAndShortensADetachedHead() throws {
        let root = try temporaryDirectory()
        let gitdir = root.appending(path: "main/.git/worktrees/wt", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: gitdir, withIntermediateDirectories: true)
        try "0123456789abcdef0123456789abcdef01234567\n".write(to: gitdir.appending(path: "HEAD"), atomically: true, encoding: .utf8)
        let worktree = root.appending(path: "wt", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try "gitdir: ../main/.git/worktrees/wt\n".write(to: worktree.appending(path: ".git"), atomically: true, encoding: .utf8)
        #expect(GitBranch.current(in: worktree.path) == "0123456")
    }
}
