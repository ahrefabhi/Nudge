import Foundation
import Observation

public enum Phase: String, Sendable, Hashable, CaseIterable {
    case idle, working, peek, alert, pill, manager, opening

    /// Rough island size order, used to pick the expand spring or the collapse ease-in.
    var sizeRank: Int {
        switch self {
        case .idle, .opening: 0
        case .working: 1
        case .pill: 2
        case .peek: 3
        case .alert: 4
        case .manager: 5
        }
    }
}

/// What the session manager shows. Now, History and Usage are the agent tabs at the top;
/// Commands and Skills are utilities in the footer dock, and Settings opens from the gear.
public enum ManagerTab: Sendable, Hashable, CaseIterable {
    case now, history, usage, commands, skills, settings

    public static let agentTabs: [ManagerTab] = [.now, .history, .usage]

    public var isAgentTab: Bool { Self.agentTabs.contains(self) }
}

/// Owns what the notch shows and when. Views read it; inputs come from sessions, clicks and keys.
@MainActor
@Observable
public final class PhaseMachine {
    public struct Timing: Sendable {
        public var peekToAlert: TimeInterval = 0.72
        public var autoCollapse: TimeInterval = 8
        public var joinWindow: TimeInterval = 4
        public var openFocus: TimeInterval = 0.32
        public var openSettle: TimeInterval = 0.70
        public var nextPeekDelay: TimeInterval = 1.5
        public var peekHold: TimeInterval = 0.72
        public var celebrate: TimeInterval = 3
        public var chimeGap: TimeInterval = 1.5
        public init() {}
    }

    public private(set) var phase: Phase = .idle
    public private(set) var sessions: [PeekuSession] = []
    /// Rate limits past the user's threshold. They queue like sessions but aren't counted as agents.
    public private(set) var usageAlerts: [PeekuSession] = []
    /// Quick commands that exited with an error. They queue like sessions too.
    public private(set) var commandAlerts: [PeekuSession] = []
    /// The manager's selected tab.
    public var managerTab: ManagerTab = .now {
        didSet {
            if managerTab.isAgentTab { lastAgentTab = managerTab }
            if managerTab == .usage { onShowUsageTab?() }
        }
    }
    /// The agent tab to go back to from a utility or Settings.
    public private(set) var lastAgentTab: ManagerTab = .now
    /// Whether Commands is turned on in Settings, so it has a dock button.
    public var commandsEnabled = true {
        didSet { if !commandsEnabled, managerTab == .commands { managerTab = lastAgentTab } }
    }
    /// Whether Skills is turned on in Settings, so it has a dock button.
    public var skillsEnabled = true {
        didSet { if !skillsEnabled, managerTab == .skills { managerTab = lastAgentTab } }
    }
    /// The Usage tab was selected, so its numbers should be fresh.
    public var onShowUsageTab: (() -> Void)?
    /// Attention episodes the user already opened; hidden until the session changes state.
    public private(set) var resolved: Set<String> = []
    /// Focused queue row, moved by ⌥⌘↓.
    public private(set) var cursor = 0
    /// Whether the user has moved the cursor since the alert opened, so the row shows it.
    public private(set) var cursorMoved = false
    /// A session that just finished, shown as a 3s wink in the wings.
    public private(set) var celebrating: PeekuSession?
    /// Whether the last phase change grew the island.
    public private(set) var expanding = true

    /// Past moments for the manager's History tab, newest first.
    public var history: [HistoryEntry] = []
    /// Each agent's latest rate limit reading, for the manager's Usage tab.
    public var usage: [AgentUsage] = []
    /// Each agent's tokens and dollars over the last 30 days, from its session logs.
    public var spend: [SpendReport] = []
    /// The user's usage alerts, edited in the Usage tab.
    public private(set) var usageAlertRules: [UsageAlertRule] = []

    public var autoCollapse = true
    public var expandFinished = false

    /// While muted (screen sharing, full screen, Quiet), new waiting sessions only update the
    /// pill's count; the notch never expands on its own. Muting folds an open alert.
    public var muted = false {
        didSet {
            guard muted, !oldValue else { return }
            switch phase {
            case .peek, .alert: fold()
            default: cancel(.nextPeek, .peekHold)
            }
        }
    }
    /// Called at the moment the target session should be focused, or when a usage or command alert is opened.
    @ObservationIgnored public var onOpen: ((PeekuSession) -> Void)?
    /// A failed command's alert asked to run it again.
    @ObservationIgnored public var onRestartCommand: ((PeekuSession) -> Void)?
    /// A waiting command's alert answered its prompt, e.g. with "y".
    @ObservationIgnored public var onAnswerCommand: ((PeekuSession, String) -> Void)?
    /// Called after the Usage tab adds or removes an alert, so the app can save it.
    @ObservationIgnored public var onUsageAlertRulesChanged: (([UsageAlertRule]) -> Void)?
    /// Called when the Usage tab's "Set Up…" is clicked for an agent Peeku can't read yet.
    @ObservationIgnored public var onSetUpUsage: ((Agent) -> Void)?
    /// Called once per update that starts a new episode, with the most urgent one. Never while muted.
    @ObservationIgnored public var onChime: ((Chime) -> Void)?
    /// Whether the user is already looking at this session, e.g. its terminal tab is in front.
    /// A new episode in view is handled as if muted: the pill's count updates, and that's all.
    @ObservationIgnored public var isInView: ((PeekuSession) -> Bool)?

    public let timing: Timing

    private enum Slot: Hashable { case alert, collapse, open, settle, nextPeek, peekHold, celebrate }

    @ObservationIgnored private let scheduler: any PhaseScheduler
    @ObservationIgnored private var timers: [Slot: (timer: PhaseTimer, token: Int)] = [:]
    @ObservationIgnored private var tokenCounter = 0
    @ObservationIgnored private var lastAnnounce: Date?
    @ObservationIgnored private var lastChime: Date?
    @ObservationIgnored private var receivedFirstUpdate = false

    public init(scheduler: any PhaseScheduler = MainScheduler(), timing: Timing = Timing()) {
        self.scheduler = scheduler
        self.timing = timing
    }

    // MARK: Derived lists

    public var queue: [PeekuSession] {
        AttentionQueue.ordered(sessions + usageAlerts + commandAlerts, resolved: resolved, includeFinished: expandFinished)
    }

    /// Running sessions, plus opened ones the user is now answering.
    public var working: [PeekuSession] {
        sessions.filter { $0.kind == .working || ($0.needsYou && resolved.contains($0.attentionKey)) }
    }

    /// Every finished session, including one queued as an alert when "pop up on finish" is on:
    /// the manager lists only sessions that need you under NEEDS YOU, so it belongs here.
    public var finished: [PeekuSession] {
        sessions.filter { $0.kind == .finished }
    }

    public var idle: [PeekuSession] { sessions.filter { $0.kind == .idle } }

    /// Every session in the manager's order: needs you, working, finished, idle.
    public var managerRows: [PeekuSession] {
        queue.filter(\.needsYou) + working + finished + idle
    }

    public var focused: PeekuSession? {
        let items = queue
        return items.isEmpty ? nil : items[min(cursor, items.count - 1)]
    }

    private var quietPhase: Phase { working.isEmpty ? .idle : .working }

    // MARK: Session input

    public func update(sessions new: [PeekuSession]) {
        let queuedBefore = Set(queue.map(\.attentionKey))
        let finishedBefore = Set(sessions.filter { $0.kind == .finished }.map(\.attentionKey))
        let isFirst = !receivedFirstUpdate
        receivedFirstUpdate = true

        sessions = new
        pruneResolved()

        // Sessions that were already finished when Peeku started are not news.
        let justFinished = new.first(where: { $0.kind == .finished && !finishedBefore.contains($0.attentionKey) })
        if !isFirst, !expandFinished, let done = justFinished { celebrate(done) }
        let finishedUnseen = justFinished.flatMap { isInView?($0) == true ? nil : $0 }
        react(queuedBefore: queuedBefore, chimes: !isFirst, finished: finishedUnseen)
    }

    public func update(usageAlerts new: [PeekuSession]) {
        let queuedBefore = Set(queue.map(\.attentionKey))
        usageAlerts = new
        pruneResolved()
        react(queuedBefore: queuedBefore, chimes: true, finished: nil)
    }

    public func update(commandAlerts new: [PeekuSession]) {
        let queuedBefore = Set(queue.map(\.attentionKey))
        commandAlerts = new
        pruneResolved()
        react(queuedBefore: queuedBefore, chimes: true, finished: nil)
    }

    private func pruneResolved() {
        resolved.formIntersection((sessions + usageAlerts + commandAlerts).map(\.attentionKey))
        clampCursor()
    }

    /// Announces what joined the queue, or settles if nothing did.
    private func react(queuedBefore: Set<String>, chimes: Bool, finished: PeekuSession?) {
        let arrived = queue.filter { !queuedBefore.contains($0.attentionKey) }
        let unseen = arrived.filter { !(isInView?($0) ?? false) }
        if chimes, let kind = unseen.first?.kind ?? finished?.kind { chime(kind) }

        if !unseen.isEmpty {
            announce()
        } else if !arrived.isEmpty {
            if phase == .idle || phase == .working { setPhase(.pill) }
        } else {
            settleIfQuiet()
        }
    }

    // MARK: User input

    public func tapIsland() {
        switch phase {
        case .idle, .working: openManager()
        case .pill, .peek: showAlert()
        case .alert, .manager, .opening: break
        }
    }

    public func tapOutside() {
        switch phase {
        case .manager: closeManager()
        case .alert: fold()
        default: break
        }
    }

    public func escape() {
        switch phase {
        case .alert, .peek: fold()
        // Esc in a utility or Settings goes back to the agents first.
        case .manager where !managerTab.isAgentTab: managerTab = lastAgentTab
        case .manager: closeManager()
        default: break
        }
    }

    public func setUsageAlertRules(_ rules: [UsageAlertRule]) {
        usageAlertRules = UsageAlertRule.sorted(rules)
    }

    /// Adds an alert from the Usage tab. One that already exists, or outside 1–100%, is left alone.
    public func addUsageAlertRule(scope: UsageAlertRule.Scope, threshold: Int) {
        guard UsageAlertRule.validThresholds.contains(threshold),
              !usageAlertRules.contains(where: { $0.scope == scope && $0.threshold == threshold }) else { return }
        setUsageAlertRules(usageAlertRules + [UsageAlertRule(scope: scope, threshold: threshold)])
        onUsageAlertRulesChanged?(usageAlertRules)
    }

    public func removeUsageAlertRule(_ id: UUID) {
        setUsageAlertRules(usageAlertRules.filter { $0.id != id })
        onUsageAlertRulesChanged?(usageAlertRules)
    }

    /// "Later" folds the alert to the pill. The pill never re-expands on its own.
    public func later() { fold() }

    /// Opens the manager on its Usage tab, e.g. from Settings.
    public func showUsage() {
        guard phase != .opening else { return }
        openManager(on: .usage)
    }

    /// Opens the manager on Settings, e.g. from the menu's Settings… item.
    public func showSettings() {
        guard phase != .opening else { return }
        if phase == .manager { managerTab = .settings } else { openManager(on: .settings) }
    }

    /// The dock's Agents button: back to the last agent tab.
    public func showAgents() {
        managerTab = lastAgentTab
    }

    /// The footer dock's buttons in order: Agents, then each enabled utility.
    public var dock: [ManagerTab] {
        let utilities = (commandsEnabled ? [ManagerTab.commands] : []) + (skillsEnabled ? [.skills] : [])
        return utilities.isEmpty ? [] : [.now] + utilities
    }

    /// Opens the manager on Skills, e.g. after a folder dialog closed it.
    public func showSkills() {
        guard skillsEnabled, phase != .opening else { return }
        if phase == .manager { managerTab = .skills } else { openManager(on: .skills) }
    }

    /// The agents' shortcut: opens the manager on the agents, or goes back to them from a utility or Settings.
    /// Closes it when the agents already show.
    public func toggleAgents() {
        if phase == .manager, !managerTab.isAgentTab { return showAgents() }
        toggleManager()
    }

    /// Commands' shortcut: opens the manager on Commands, or closes it when Commands already shows.
    public func toggleCommands() {
        guard commandsEnabled else { return }
        toggle(.commands)
    }

    /// Skills' shortcut, the same way.
    public func toggleSkills() {
        guard skillsEnabled else { return }
        toggle(.skills)
    }

    private func toggle(_ utility: ManagerTab) {
        guard phase != .opening else { return }
        switch phase {
        case .manager where managerTab == utility: closeManager()
        case .manager: managerTab = utility
        default: openManager(on: utility)
        }
    }

    public func toggleManager() {
        phase == .manager ? closeManager() : openManager()
    }

    public func cycleNext() {
        let items = queue
        guard !items.isEmpty else { return }
        if phase == .alert {
            cursor = (cursor + 1) % items.count
            scheduleCollapse()
        } else if phase != .manager && phase != .opening {
            cursor = 0
            showAlert()
        }
        cursorMoved = phase == .alert
    }

    public func openFocused() {
        if let session = focused { open(session.id) }
    }

    /// Opens row `number` (1-based) of what's showing, for ⌘1–9: every session in the
    /// manager, otherwise the queue.
    public func openRow(_ number: Int) {
        let items = phase == .manager ? managerRows : queue
        guard number >= 1, number <= items.count else { return }
        open(items[number - 1].id)
    }

    /// Switches the open manager to agent tab `number` (1-based), for ⌥⌘1–3. Returns whether it did.
    @discardableResult
    public func showTab(_ number: Int) -> Bool {
        let tabs = ManagerTab.agentTabs
        guard phase == .manager, number >= 1, number <= tabs.count else { return false }
        managerTab = tabs[number - 1]
        return true
    }

    /// Restarts a failed command from its alert, which is then done with.
    public func restartCommand(_ alertID: String) {
        guard let alert = commandAlerts.first(where: { $0.id == alertID }) else { return }
        resolved.insert(alert.attentionKey)
        fold()
        onRestartCommand?(alert)
    }

    /// Answers a waiting command's prompt from its alert, which is then done with.
    public func answerCommand(_ alertID: String, _ answer: String) {
        guard let alert = commandAlerts.first(where: { $0.id == alertID }) else { return }
        resolved.insert(alert.attentionKey)
        fold()
        onAnswerCommand?(alert, answer)
    }

    /// Jumps to any session, waiting or not. A usage alert opens the manager's Usage tab instead,
    /// and a failed command folds the notch for its output window.
    public func open(_ sessionID: String) {
        if let alert = commandAlerts.first(where: { $0.id == sessionID }) {
            resolved.insert(alert.attentionKey)
            fold()
            onOpen?(alert)
            return
        }
        if let alert = usageAlerts.first(where: { $0.id == sessionID }) {
            resolved.insert(alert.attentionKey)
            clampCursor()
            openManager(on: .usage)
            onOpen?(alert)
            return
        }
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
        cancelAll()
        setPhase(.opening)
        schedule(.open, after: timing.openFocus) { [weak self] in
            guard let self else { return }
            // Only a waiting session has an episode to resolve.
            if session.needsYou || self.queue.contains(session) { self.resolved.insert(session.attentionKey) }
            self.clampCursor()
            self.onOpen?(session)
        }
        schedule(.settle, after: timing.openSettle) { [weak self] in
            guard let self else { return }
            self.setPhase(self.quietPhase)
            guard !self.queue.isEmpty else { return }
            self.schedule(.nextPeek, after: self.timing.nextPeekDelay) { [weak self] in self?.peekOnce() }
        }
    }

    // MARK: Transitions

    private func announce() {
        let now = scheduler.now
        defer { lastAnnounce = now }
        if muted {
            if phase == .idle || phase == .working { setPhase(.pill) }
            return
        }
        switch phase {
        case .manager, .opening:
            return
        case .peek:
            // A reminder peek turns into a full alert when something new arrives.
            if timers[.peekHold] != nil {
                cancel(.peekHold)
                schedule(.alert, after: timing.peekToAlert) { [weak self] in self?.showAlert() }
            }
        case .alert:
            scheduleCollapse()
        case .pill:
            // Bursts join the folded popover instead of dropping Peeku again.
            if let last = lastAnnounce, now.timeIntervalSince(last) < timing.joinWindow { return }
            peek()
        case .idle, .working:
            peek()
        }
    }

    private func peek() {
        cancel(.collapse, .peekHold, .nextPeek)
        cursorMoved = false
        setPhase(.peek)
        schedule(.alert, after: timing.peekToAlert) { [weak self] in self?.showAlert() }
    }

    private func peekOnce() {
        guard phase == .idle || phase == .working, !queue.isEmpty else { return }
        guard !muted else { return setPhase(.pill) }
        setPhase(.peek)
        schedule(.peekHold, after: timing.peekHold) { [weak self] in
            guard let self, self.phase == .peek else { return }
            self.setPhase(self.queue.isEmpty ? self.quietPhase : .pill)
        }
    }

    private func showAlert() {
        cancel(.alert, .peekHold)
        guard !queue.isEmpty else { return settleIfQuiet() }
        setPhase(.alert)
        scheduleCollapse()
    }

    private func scheduleCollapse() {
        cancel(.collapse)
        guard autoCollapse else { return }
        schedule(.collapse, after: timing.autoCollapse) { [weak self] in
            if self?.phase == .alert { self?.fold() }
        }
    }

    private func fold() {
        cancel(.alert, .collapse, .peekHold)
        setPhase(queue.isEmpty ? quietPhase : .pill)
    }

    private func openManager(on tab: ManagerTab = .now) {
        cancel(.alert, .collapse, .peekHold, .nextPeek)
        managerTab = tab
        setPhase(.manager)
    }

    private func closeManager() {
        setPhase(queue.isEmpty ? quietPhase : .pill)
    }

    private func settleIfQuiet() {
        switch phase {
        case .idle, .working:
            setPhase(quietPhase)
        case .peek, .alert, .pill:
            guard queue.isEmpty else { return }
            cancel(.alert, .collapse, .peekHold)
            setPhase(quietPhase)
        case .manager, .opening:
            break
        }
    }

    private func celebrate(_ session: PeekuSession) {
        celebrating = session
        schedule(.celebrate, after: timing.celebrate) { [weak self] in self?.celebrating = nil }
    }

    /// Bursts, like several sessions finishing together, play one sound.
    private func chime(_ kind: SessionKind) {
        guard !muted, let chime = Chime(kind) else { return }
        let now = scheduler.now
        if let last = lastChime, now.timeIntervalSince(last) < timing.chimeGap { return }
        lastChime = now
        onChime?(chime)
    }

    private func setPhase(_ next: Phase) {
        guard next != phase else { return }
        expanding = next.sizeRank > phase.sizeRank
        phase = next
    }

    private func clampCursor() {
        let count = queue.count
        cursor = count == 0 ? 0 : min(cursor, count - 1)
    }

    // MARK: Timers

    private func schedule(_ slot: Slot, after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        timers[slot]?.timer.cancel()
        tokenCounter += 1
        let token = tokenCounter
        let timer = scheduler.schedule(after: delay) { [weak self] in
            if self?.timers[slot]?.token == token { self?.timers[slot] = nil }
            work()
        }
        timers[slot] = (timer, token)
    }

    private func cancel(_ slots: Slot...) {
        for slot in slots {
            timers[slot]?.timer.cancel()
            timers[slot] = nil
        }
    }

    /// Cancels presentation timers. The finished wink runs on its own clock.
    private func cancelAll() {
        for slot in timers.keys where slot != .celebrate { cancel(slot) }
    }
}
