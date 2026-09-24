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
        public init() {}
    }

    public private(set) var phase: Phase = .idle
    public private(set) var sessions: [PipSession] = []
    /// Attention episodes the user already opened; hidden until the session changes state.
    public private(set) var resolved: Set<String> = []
    /// Focused queue row, moved by ⌥⌘↓.
    public private(set) var cursor = 0
    /// Whether the user has moved the cursor since the alert opened, so the row shows it.
    public private(set) var cursorMoved = false
    /// A session that just finished, shown as a 3s wink in the wings.
    public private(set) var celebrating: PipSession?
    /// Whether the last phase change grew the island.
    public private(set) var expanding = true

    /// Past moments for the manager's History tab, newest first.
    public var history: [HistoryEntry] = []
    /// Each agent's latest rate limit reading, for the manager's Usage tab.
    public var usage: [AgentUsage] = []

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
    /// Called at the moment the target session should be focused.
    @ObservationIgnored public var onOpen: ((PipSession) -> Void)?
    /// Called when the Usage tab's "Set Up…" is clicked for an agent Pip can't read yet.
    @ObservationIgnored public var onSetUpUsage: ((Agent) -> Void)?

    public let timing: Timing

    private enum Slot: Hashable { case alert, collapse, open, settle, nextPeek, peekHold, celebrate }

    @ObservationIgnored private let scheduler: any PhaseScheduler
    @ObservationIgnored private var timers: [Slot: (timer: PhaseTimer, token: Int)] = [:]
    @ObservationIgnored private var tokenCounter = 0
    @ObservationIgnored private var lastAnnounce: Date?
    @ObservationIgnored private var receivedFirstUpdate = false

    public init(scheduler: any PhaseScheduler = MainScheduler(), timing: Timing = Timing()) {
        self.scheduler = scheduler
        self.timing = timing
    }

    // MARK: Derived lists

    public var queue: [PipSession] {
        AttentionQueue.ordered(sessions, resolved: resolved, includeFinished: expandFinished)
    }

    /// Running sessions, plus opened ones the user is now answering.
    public var working: [PipSession] {
        sessions.filter { $0.kind == .working || ($0.needsYou && resolved.contains($0.attentionKey)) }
    }

    public var finished: [PipSession] {
        sessions.filter { $0.kind == .finished && !queue.contains($0) }
    }

    public var idle: [PipSession] { sessions.filter { $0.kind == .idle } }

    /// Every session in the manager's order: needs you, working, finished, idle.
    public var managerRows: [PipSession] {
        queue.filter(\.needsYou) + working + finished + idle
    }

    public var focused: PipSession? {
        let items = queue
        return items.isEmpty ? nil : items[min(cursor, items.count - 1)]
    }

    private var quietPhase: Phase { working.isEmpty ? .idle : .working }

    // MARK: Session input

    public func update(sessions new: [PipSession]) {
        let queuedBefore = Set(queue.map(\.attentionKey))
        let finishedBefore = Set(sessions.filter { $0.kind == .finished }.map(\.attentionKey))
        let isFirst = !receivedFirstUpdate
        receivedFirstUpdate = true

        sessions = new
        resolved.formIntersection(new.map(\.attentionKey))
        clampCursor()

        // Sessions that were already finished when Pip started are not news.
        if !isFirst, !expandFinished,
           let done = new.first(where: { $0.kind == .finished && !finishedBefore.contains($0.attentionKey) }) {
            celebrate(done)
        }

        if queue.contains(where: { !queuedBefore.contains($0.attentionKey) }) {
            announce()
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
        case .manager: closeManager()
        default: break
        }
    }

    /// "Later" folds the alert to the pill. The pill never re-expands on its own.
    public func later() { fold() }

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

    /// Jumps to any session, waiting or not.
    public func open(_ sessionID: String) {
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
            // Bursts join the folded popover instead of dropping Pip again.
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

    private func openManager() {
        cancel(.alert, .collapse, .peekHold, .nextPeek)
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

    private func celebrate(_ session: PipSession) {
        celebrating = session
        schedule(.celebrate, after: timing.celebrate) { [weak self] in self?.celebrating = nil }
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
