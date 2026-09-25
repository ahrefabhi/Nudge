import Foundation
import NudgeHookSchema

/// Watches Nudge's hook inbox and Claude's session registry, and publishes `NudgeSession`s.
/// File reads happen on a background queue; state lives on the main actor.
@MainActor
public final class ObservationService {
    public var onChange: (([NudgeSession]) -> Void)?
    public private(set) var sessions: [NudgeSession] = []

    private var reducer: SessionReducer
    private let store: SessionStore
    private var saveScheduled = false
    private var registryEntries: [RegistryEntry] = []
    private let inbox: InboxReader
    private let registryDirectory: URL
    private let io = DispatchQueue(label: "app.nudge.observation", qos: .utility)
    private var watchers: [DirectoryWatcher] = []
    /// Claude rewrites `<pid>.json` in place, which the directory watcher doesn't see, so each file is watched too.
    private var registryFileWatchers: [Int32: DirectoryWatcher] = [:]
    private var sweep: Timer?
    private var publishScheduled = false

    /// Also rescans on this interval, to notice exited processes and missed file events.
    static let sweepInterval: TimeInterval = 10

    public init(paths: NudgePaths = .default, registryDirectory: URL = ClaudePaths.sessions) {
        inbox = InboxReader(directory: paths.inbox)
        self.registryDirectory = registryDirectory
        store = SessionStore(paths: paths)
        // What hooks said before Nudge last quit, e.g. a question's choices.
        reducer = SessionReducer(restoring: store.load())
    }

    public func start() {
        inbox.prepare()
        refreshRegistry()
        drainInbox()
        if let watcher = DirectoryWatcher(directory: inbox.directory, queue: io, onChange: { [weak self] in
            Task { @MainActor in self?.drainInbox() }
        }) { watchers.append(watcher) }
        if let watcher = DirectoryWatcher(directory: registryDirectory, queue: io, onChange: { [weak self] in
            Task { @MainActor in self?.refreshRegistry() }
        }) { watchers.append(watcher) }
        sweep = Timer.scheduledTimer(withTimeInterval: Self.sweepInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshRegistry()
                self?.drainInbox()
            }
        }
    }

    public func stop() {
        watchers.removeAll()
        registryFileWatchers.removeAll()
        sweep?.invalidate()
        sweep = nil
        store.save(Array(reducer.sessions.values))
    }

    /// Everything known about a session, for focusing it.
    public func observed(_ id: String) -> ObservedSession? { reducer.sessions[id] }

    // MARK: Inputs

    private func drainInbox() {
        let inbox = inbox
        io.async { [weak self] in
            let records = inbox.drain()
            guard !records.isEmpty else { return }
            Task { @MainActor in self?.ingest(records) }
        }
    }

    private func refreshRegistry() {
        let directory = registryDirectory
        io.async { [weak self] in
            let entries = SessionRegistry.read(from: directory)
            Task { @MainActor in self?.reconcile(entries) }
        }
    }

    private func ingest(_ records: [HookRecord]) {
        for record in records { reducer.apply(record) }
        schedulePublish()
    }

    private func reconcile(_ entries: [RegistryEntry]) {
        registryEntries = entries
        watchRegistryFiles(entries)
        reducer.reconcile(entries)
        schedulePublish()
    }

    private func watchRegistryFiles(_ entries: [RegistryEntry]) {
        let live = Set(entries.map(\.pid))
        registryFileWatchers = registryFileWatchers.filter { live.contains($0.key) }
        for pid in live where registryFileWatchers[pid] == nil {
            let file = registryDirectory.appending(path: "\(pid).json")
            registryFileWatchers[pid] = DirectoryWatcher(directory: file, queue: io) { [weak self] in
                Task { @MainActor in self?.refreshRegistry() }
            }
        }
    }

    // MARK: Output

    /// Coalesces bursts of events (a tool call is several) into one update.
    private func schedulePublish() {
        guard !publishScheduled else { return }
        publishScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            MainActor.assumeIsolated { self?.publish() }
        }
    }

    private func publish() {
        publishScheduled = false
        scheduleSave()
        let next = reducer.sessions.values
            .map(SessionProjection.session)
            .sorted { ($0.project, $0.id) < ($1.project, $1.id) }
        guard next != sessions else { return }
        sessions = next
        onChange?(next)
    }

    /// At most once a second: bursts of hook events don't each rewrite the file.
    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.saveScheduled = false
                self.store.save(Array(self.reducer.sessions.values))
            }
        }
    }
}
