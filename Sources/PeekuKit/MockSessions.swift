import Foundation

/// The handoff README's sample sessions, for building the UI before real hooks exist.
public enum MockSessions {
    public enum Event: String, CaseIterable, Sendable {
        case permission, question, error, success, multiple
    }

    /// Everyone busy, docs-site finished a while ago.
    public static func calm(now: Date = Date()) -> [PeekuSession] {
        [
            payments(.working, since: now.addingTimeInterval(-40)),
            dashboard(.working, since: now.addingTimeInterval(-180)),
            infra(.working, since: now.addingTimeInterval(-400)),
            PeekuSession(id: "chrome", project: "chrome-extension", branch: "feat/popup-auth", task: "Adding OAuth to the popup",
                       activity: "Running tests · 42 of 118", host: .terminal, kind: .working, since: now.addingTimeInterval(-240)),
            PeekuSession(id: "auth", project: "auth-service", branch: "main", task: "Refreshing session tokens",
                       activity: "Editing src/session.ts", host: .claude, kind: .working, since: now.addingTimeInterval(-60)),
            docs(since: now.addingTimeInterval(-540)),
        ]
    }

    /// The README's snapshot: three waiting, two working, one finished.
    public static func sample(now: Date = Date()) -> [PeekuSession] {
        apply(.multiple, to: calm(now: now), now: now, staggered: true)
    }

    /// Simulates a hook event arriving for the matching sample session(s).
    public static func apply(_ event: Event, to sessions: [PeekuSession], now: Date = Date(), staggered: Bool = false) -> [PeekuSession] {
        let ages: [String: TimeInterval] = staggered ? ["payments": 12, "dash": 120, "infra": 360] : [:]
        func at(_ id: String) -> Date { now.addingTimeInterval(-(ages[id] ?? 0)) }
        let replacements: [PeekuSession]
        switch event {
        case .permission: replacements = [payments(.permission, since: at("payments"))]
        case .question: replacements = [dashboard(.question, since: at("dash"))]
        case .error: replacements = [infra(.error, since: at("infra"))]
        case .success: replacements = [docs(since: now)]
        case .multiple:
            replacements = [payments(.permission, since: at("payments")), dashboard(.question, since: at("dash")), infra(.error, since: at("infra"))]
        }
        return sessions.map { session in replacements.first { $0.id == session.id } ?? session }
    }

    /// The handoff's sample history: five moments today, three yesterday.
    public static func history(now: Date = Date(), calendar: Calendar = .current) -> [HistoryEntry] {
        func today(_ minutesAgo: Double) -> Date { now.addingTimeInterval(-minutesAgo * 60) }
        func yesterday(_ hour: Int, _ minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        func entry(_ id: String, _ session: String, _ project: String, _ host: HostApp, _ kind: HistoryEntry.Kind, _ at: Date,
                   _ detail: String, answeredAfter: TimeInterval? = nil, took: TimeInterval? = nil) -> HistoryEntry {
            HistoryEntry(id: id, sessionID: session, agent: session == "infra" ? .codex : .claude, project: project, host: host, kind: kind, at: at, detail: detail,
                         endedAt: answeredAfter.map { at.addingTimeInterval($0) }, ended: kind != .started && kind != .finished,
                         duration: took)
        }
        return [
            entry("h1", "payments", "payments-api", .iTerm, .permission, today(2), "npm install stripe@17.2.0", answeredAfter: 38),
            entry("h2", "docs", "docs-site", .iTerm, .finished, today(13), "14 files changed", took: 161),
            entry("h3", "infra", "infra-terraform", .iTerm, .error, today(26), "State lock held by CI", answeredAfter: 240),
            entry("h4", "dash", "dashboard-v2", .vsCode, .question, today(47), "Tooltip component", answeredAfter: 72),
            entry("h5", "chrome", "chrome-extension", .terminal, .started, today(84), "Add OAuth to the popup"),
            entry("h6", "auth", "auth-service", .claude, .finished, yesterday(18, 4), "6 files changed", took: 660),
            entry("h7", "chrome", "chrome-extension", .terminal, .error, yesterday(17, 40), "3 tests failed in background.spec.ts"),
            entry("h8", "payments", "payments-api", .iTerm, .permission, yesterday(16, 12), "git push origin feat/stripe-v16", answeredAfter: 120),
        ]
    }

    /// What happens after the user answers in the real session.
    public static func answered(_ session: PeekuSession, now: Date = Date()) -> PeekuSession {
        var next = session
        next.kind = .working
        next.quote = nil
        next.choices = []
        next.since = now
        return next
    }

    private static func payments(_ kind: SessionKind, since: Date) -> PeekuSession {
        PeekuSession(id: "payments", project: "payments-api", branch: "feat/stripe-v17", task: "Upgrading Stripe SDK to v17",
                   host: .iTerm, location: "Tab 1", kind: kind,
                   quote: kind == .permission ? "npm install stripe@17.2.0" : nil, since: since)
    }

    private static func dashboard(_ kind: SessionKind, since: Date) -> PeekuSession {
        PeekuSession(id: "dash", project: "dashboard-v2", branch: "main", task: "Rebuilding chart tooltips",
                   host: .vsCode, location: "Window 1", kind: kind,
                   quote: kind == .question ? "Reuse <Popover>, or build a new <ChartTooltip>?" : nil,
                   choices: kind == .question ? ["Reuse Popover", "New ChartTooltip", "Something else…"] : [],
                   since: since)
    }

    private static func infra(_ kind: SessionKind, since: Date) -> PeekuSession {
        PeekuSession(id: "infra", agent: .codex, project: "infra-terraform", branch: "chore/tf-1.9", task: "Upgrading to Terraform 1.9",
                   host: .iTerm, location: "Tab 2", kind: kind,
                   quote: kind == .error ? "Error acquiring the state lock" : nil, since: since)
    }

    private static func docs(since: Date) -> PeekuSession {
        PeekuSession(id: "docs", project: "docs-site", branch: "main", task: "Migrated 14 pages to MDX",
                   host: .iTerm, location: "Tab 3", kind: .finished,
                   quote: "Migrated 14 pages to MDX · build passes · 2m 41s", since: since)
    }

    /// Claude past 90% of its 5-hour limit, for Demo Mode.
    public static func usageAlert(now: Date = Date()) -> PeekuSession {
        let window = UsageWindow(id: "five_hour", minutes: 300, usedPercent: 92, resetsAt: now.addingTimeInterval(42 * 60))
        return UsageAlerts.alert(id: UsageAlerts.id(.claude, window), agent: .claude, window: window, threshold: 90, since: now, now: now)
    }

    /// Readings for the Usage tab: Claude comfortable, Codex close to its 5-hour limit.
    public static func usage(now: Date = Date()) -> [AgentUsage] {
        func window(_ id: String, _ minutes: Int, _ used: Double, resetsIn: TimeInterval) -> UsageWindow {
            UsageWindow(id: id, minutes: minutes, usedPercent: used, resetsAt: now.addingTimeInterval(resetsIn))
        }
        return [
            AgentUsage(agent: .claude, source: .connected, report: UsageReport(
                agent: .claude,
                windows: [window("five_hour", 300, 64, resetsIn: 2 * 3600 + 14 * 60), window("seven_day", 10_080, 38, resetsIn: 3 * 86_400 + 3600)],
                observedAt: now.addingTimeInterval(-90))),
            AgentUsage(agent: .codex, source: .connected, report: UsageReport(
                agent: .codex,
                windows: [window("primary", 300, 91, resetsIn: 38 * 60), window("secondary", 10_080, 22, resetsIn: 5 * 86_400)],
                plan: "plus", observedAt: now.addingTimeInterval(-720))),
        ]
    }

    /// Thirty days of spend for the Usage tab: mostly Opus, some Fable, a little Haiku; Codex unpriced.
    public static func spend(now: Date = Date(), calendar: Calendar = .current) -> [SpendReport] {
        let today = calendar.startOfDay(for: now)
        func spend(_ model: String, _ scale: Double) -> Spend {
            let tokens = TokenCounts(input: Int(4_000 * scale), output: Int(90_000 * scale), cacheRead: Int(9_000_000 * scale),
                                     cacheWrite5m: Int(50_000 * scale), cacheWrite1h: Int(300_000 * scale))
            let price = ModelPrices.price(for: model)
            return Spend(tokens: tokens, cost: price?.cost(tokens) ?? 0, requests: Int(120 * scale) + 1, unpriced: price == nil ? Int(120 * scale) + 1 : 0)
        }
        // A fixed shape, weekends quiet, so snapshots don't change from run to run.
        let shape: [Double] = [3, 1.2, 6, 0.4, 1.8, 2.6, 0, 0.8, 2, 4, 0.6, 7, 7.4, 0.9, 4.5, 3.2, 0, 0, 0, 0.8, 0.7, 2.5, 0.5, 3.8, 4, 2.2, 0.9, 6.8, 4.9, 2.4]
        func days(_ models: (Double, Int) -> [String: Spend]) -> [SpendReport.Bucket] {
            shape.enumerated().map { index, scale in
                SpendReport.Bucket(date: calendar.date(byAdding: .day, value: index - (shape.count - 1), to: today) ?? today,
                                   models: scale == 0 ? [:] : models(scale, index))
            }
        }
        // Today by hour: a morning, a lunch dip and an afternoon, and the day is what the hours add up to.
        let hourShape: [Double] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0.15, 0.35, 0.3, 0.05, 0.1, 0.4, 0.45, 0.3, 0.2, 0.1, 0, 0, 0, 0, 0]
        func hours(_ models: (Double, Int) -> [String: Spend]) -> [SpendReport.Bucket] {
            hourShape.enumerated().compactMap { hour, scale in
                calendar.date(byAdding: .hour, value: hour, to: today).map {
                    SpendReport.Bucket(date: $0, models: scale == 0 ? [:] : models(scale, hour))
                }
            }
        }
        func report(_ agent: Agent, days: [SpendReport.Bucket], hours: [SpendReport.Bucket], sessions: [String: SessionSpend]) -> SpendReport {
            var days = days
            var today: [String: Spend] = [:]
            for hour in hours { for (model, spend) in hour.models { today[model, default: Spend()] += spend } }
            days[days.count - 1].models = today
            return SpendReport(agent: agent, days: days, hours: hours, sessions: sessions)
        }
        let claude = days { scale, index in
            var models = ["claude-opus-5": spend("claude-opus-5", scale)]
            if index % 3 == 0 { models["claude-fable-5-1"] = spend("claude-fable-5-1", scale * 0.4) }
            if index % 5 == 1 { models["claude-haiku-4-5"] = spend("claude-haiku-4-5", scale * 0.5) }
            return models
        }
        let codex = days { scale, index in index % 4 == 0 ? ["gpt-6-luna": spend("gpt-6-luna", scale * 0.3)] : [:] }
        let claudeHours = hours { scale, hour in
            var models = ["claude-opus-5": spend("claude-opus-5", scale * 2)]
            if hour % 4 == 2 { models["claude-fable-5-1"] = spend("claude-fable-5-1", scale) }
            return models
        }
        let codexHours = hours { scale, hour in hour == 10 || hour == 15 ? ["gpt-6-luna": spend("gpt-6-luna", scale)] : [:] }
        // The sample sessions: what each has cost and how full its context is.
        func session(_ model: String, _ scale: Double, context: Double, window: Int = 1_000_000) -> SessionSpend {
            SessionSpend(model: model, spend: spend(model, scale), context: Int(context * Double(window)), contextWindow: window)
        }
        let claudeSessions = ["payments": session("claude-opus-5", 0.9, context: 0.38), "dash": session("claude-fable-5-1", 0.8, context: 0.72),
                              "chrome": session("claude-opus-5-5", 0.4, context: 0.12), "auth": session("claude-sonnet-5", 0.3, context: 0.93),
                              "docs": session("claude-opus-5", 0.5, context: 0.44)]
        let codexSessions = ["infra": session("gpt-6-luna", 0.6, context: 0.3, window: 258_400)]
        return [report(.claude, days: claude, hours: claudeHours, sessions: claudeSessions),
                report(.codex, days: codex, hours: codexHours, sessions: codexSessions)]
    }
}

extension MockSessions {
    /// A dev server that crashed, for Demo Mode's Simulate menu.
    public static func commandAlert(now: Date = Date()) -> PeekuSession {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let command = QuickCommand(name: "Dashboard", directory: "\(home)/code/dashboard", command: "npm run dev")
        return CommandRunner.alert(for: command, code: 1, lastLine: "Error: listen EADDRINUSE: address already in use :::5173", at: now)
    }

    /// Create React App asking to move off a taken port, for Demo Mode's Simulate menu.
    public static func commandPrompt(now: Date = Date()) -> PeekuSession {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let command = QuickCommand(name: "Storefront", directory: "\(home)/code/storefront", command: "npm start")
        return CommandRunner.inputAlert(for: command, prompt: "? Something is already running on port 3000. Would you like to run the app on another port instead? › (Y/n)", since: now)
    }

    /// Saved commands for snapshots: a dev server running, a worker that crashed, docs asking a question.
    /// Nothing is actually run; the store lives in `root`.
    @MainActor
    public static func commands(root: URL) -> CommandRunner {
        let runner = CommandRunner(store: CommandStore(root: root))
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let web = QuickCommand(name: "Dashboard", directory: "\(home)/code/dashboard", command: "npm run dev")
        let api = QuickCommand(directory: "\(home)/code/payments-api", command: "go run ./cmd/worker")
        let docs = QuickCommand(name: "Docs", directory: "\(home)/code/docs", command: "pnpm build && pnpm preview")
        for command in [web, api, docs] { runner.save(command) }
        let now = Date()
        if let run = runner.run(for: web.id) {
            run.status = .running(since: now.addingTimeInterval(-754))
            run.append(["> dashboard@2.4.0 dev", "> vite", "", "  VITE v7.1.3  ready in 412 ms", "",
                        "  ➜  Local:   http://localhost:5173/", "  ➜  Network: use --host to expose",
                        "12:04:18 [vite] hmr update /src/routes/usage.tsx"])
        }
        if let run = runner.run(for: api.id) {
            run.status = .exited(code: 1, at: now.addingTimeInterval(-95))
            run.append(["worker: connecting to redis://localhost:6379", "worker: dial tcp [::1]:6379: connect: connection refused", "exit status 1"])
        }
        if let run = runner.run(for: docs.id) {
            run.status = .running(since: now.addingTimeInterval(-40))
            run.append(["> docs@1.0.0 preview", "> vite preview", ""], partial: "? Port 4173 is in use. Use 4174 instead? (Y/n) ")
            run.waitingForInput = true
        }
        return runner
    }

    /// Plugins and skills for snapshots: a few of each agent's, globally and in two projects, and
    /// a marketplace to browse. Nothing is read from disk or the CLIs.
    @MainActor
    public static func skills() -> SkillManager {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dashboard = "\(home)/code/dashboard", payments = "\(home)/code/payments-api"
        let manager = SkillManager(locate: { _ in nil })
        manager.seed(installed: [
            InstalledSkill(agent: .claude, kind: .plugin(id: "superpowers@superpowers", cliScope: "user"), name: "superpowers",
                           summary: "Brainstorm, plan, test-drive and debug with a library of proven skills.", scope: .global,
                           enabled: true, version: "4.1.0", skills: ["brainstorming", "writing-plans", "test-driven-development", "systematic-debugging"]),
            InstalledSkill(agent: .claude, kind: .plugin(id: "code-review@claude-plugins-official", cliScope: "user"), name: "code-review",
                           summary: "Review the current diff for correctness bugs before you push.", scope: .global, enabled: false, version: "1.2.0"),
            InstalledSkill(agent: .codex, kind: .plugin(id: "github@openai-curated", cliScope: nil), name: "GitHub",
                           summary: "Triage PRs, issues, CI, and publish flows", scope: .global, skills: ["gh-fix-ci", "gh-address-comments"]),
            InstalledSkill(agent: .claude, kind: .skill(folder: URL(filePath: "\(home)/.claude/skills/changelog")), name: "changelog",
                           summary: "Write the changelog entry for the current branch in the project's voice.", scope: .global),
            InstalledSkill(agent: .codex, kind: .skill(folder: URL(filePath: "\(home)/.agents/skills/changelog")), name: "changelog",
                           summary: "Write the changelog entry for the current branch in the project's voice.", scope: .global),
            InstalledSkill(agent: .claude, kind: .plugin(id: "stripe@claude-plugins-official", cliScope: "project"), name: "stripe",
                           summary: "Stripe API best practices, test clocks and webhook debugging.", scope: .project(payments), enabled: true),
            InstalledSkill(agent: .claude, kind: .skill(folder: URL(filePath: "\(payments)/.claude/skills/migrate-db")), name: "migrate-db",
                           summary: "Write and dry-run a Postgres migration, then update the seed data.", scope: .project(payments)),
            InstalledSkill(agent: .claude, kind: .skill(folder: URL(filePath: "\(dashboard)/.claude/skills/storybook-diff")), name: "storybook-diff",
                           summary: "Screenshot the changed stories and compare them with main.", scope: .project(dashboard)),
        ], catalog: [
            CatalogPlugin(agent: .claude, pluginID: "frontend-design@claude-plugins-official", name: "frontend-design",
                          summary: "Create distinctive, production-grade frontend interfaces that avoid generic AI aesthetics.",
                          marketplace: "claude-plugins-official", origin: "github.com/anthropics/claude-plugins-official/plugins/frontend-design",
                          installs: 1_276_062),
            CatalogPlugin(agent: .claude, pluginID: "superpowers@superpowers", name: "superpowers",
                          summary: "Brainstorm, plan, test-drive and debug with a library of proven skills.", marketplace: "superpowers",
                          origin: "github.com/obra/superpowers", installs: 1_140_665),
            CatalogPlugin(agent: .claude, pluginID: "playwright@claude-plugins-official", name: "playwright",
                          summary: "Drive a real browser to test, screenshot and debug web apps.", marketplace: "claude-plugins-official",
                          origin: "github.com/microsoft/playwright-mcp", installs: 402_118),
            CatalogPlugin(agent: .claude, pluginID: "sentry@claude-plugins-official", name: "sentry",
                          summary: "Pull Sentry issues and traces into your session and fix them in place.", marketplace: "claude-plugins-official",
                          origin: "github.com/getsentry/sentry-mcp", installs: 98_420),
            CatalogPlugin(agent: .codex, pluginID: "github@openai-curated", name: "github", title: "GitHub",
                          summary: "Triage PRs, issues, CI, and publish flows", marketplace: "openai-curated", category: "Coding",
                          origin: "github.com/openai/plugins"),
            CatalogPlugin(agent: .codex, pluginID: "linear@openai-curated", name: "linear", title: "Linear",
                          summary: "Find, create and update Linear issues from Codex", marketplace: "openai-curated", category: "Productivity"),
        ], marketplaces: [
            Marketplace(agent: .claude, name: "claude-plugins-official", origin: "github.com/anthropics/claude-plugins-official"),
            Marketplace(agent: .claude, name: "superpowers", origin: "github.com/obra/superpowers-marketplace"),
            Marketplace(agent: .codex, name: "openai-curated"),
        ], projects: [dashboard, payments])
        return manager
    }
}
