import Foundation
import PeekuHookSchema

/// Turns successive session snapshots into history entries. Pure, so it is easy to test.
public struct HistoryRecorder: Sendable {
    /// Newest first.
    public private(set) var entries: [HistoryEntry]
    private var previous: [String: PeekuSession] = [:]
    /// When each session last started working, to time finished runs.
    private var workingSince: [String: Date] = [:]
    private var receivedFirstSnapshot = false

    public static let retention: TimeInterval = 7 * 24 * 60 * 60
    public static let limit = 500

    public init(entries: [HistoryEntry] = []) {
        self.entries = entries.sorted { $0.at > $1.at }
    }

    /// Records what changed since the last snapshot. Returns whether any entry changed.
    @discardableResult
    public mutating func record(_ sessions: [PeekuSession], now: Date = Date()) -> Bool {
        let current = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let isFirst = !receivedFirstSnapshot
        receivedFirstSnapshot = true
        var changed = false

        // Entries saved before apps were recorded learn theirs while the session still runs.
        for index in entries.indices where entries[index].host == .other && entries[index].hostBundleID == nil {
            guard let session = current[entries[index].sessionID], session.host == .other, let bundleID = session.hostBundleID else { continue }
            entries[index].hostBundleID = bundleID
            entries[index].hostName = session.hostAppName
            changed = true
        }

        // Close waiting episodes the session has moved on from. On the first snapshot after a
        // restart the true end time is unknown, so none is recorded.
        for index in entries.indices where entries[index].isOpenEpisode {
            if current[entries[index].sessionID]?.attentionKey == entries[index].id { continue }
            entries[index].ended = true
            entries[index].endedAt = isFirst ? nil : now
            changed = true
        }

        for session in sessions {
            let before = previous[session.id]
            if session.kind == .working, before?.kind != .working { workingSince[session.id] = session.since }

            if session.needsYou, let kind = HistoryEntry.Kind(session.kind) {
                changed = insert(HistoryEntry(id: session.attentionKey, sessionID: session.id, agent: session.agent, project: session.project,
                                              host: session.host, hostName: session.hostAppName, hostBundleID: session.hostBundleID, kind: kind, at: session.since,
                                              detail: session.quote ?? session.task)) || changed
            }

            // A session that was already finished or working when Peeku started isn't news.
            guard !isFirst else { continue }

            if session.kind == .finished, before?.kind != .finished {
                let duration = workingSince[session.id].map { session.since.timeIntervalSince($0) }
                changed = insert(HistoryEntry(id: session.attentionKey, sessionID: session.id, agent: session.agent, project: session.project,
                                              host: session.host, hostName: session.hostAppName, hostBundleID: session.hostBundleID, kind: .finished, at: session.since,
                                              detail: session.quote ?? session.task, duration: duration)) || changed
            }

            if session.kind == .working, before == nil || before?.kind == .idle {
                changed = insert(HistoryEntry(id: "started|\(session.id)|\(session.since.timeIntervalSinceReferenceDate)",
                                              sessionID: session.id, agent: session.agent, project: session.project, host: session.host, hostName: session.hostAppName, hostBundleID: session.hostBundleID,
                                              kind: .started, at: session.since, detail: session.task)) || changed
            }
        }

        previous = current
        workingSince = workingSince.filter { current[$0.key] != nil }
        return prune(now: now) || changed
    }

    /// Drops entries older than a week, and the oldest beyond `limit`.
    @discardableResult
    public mutating func prune(now: Date = Date()) -> Bool {
        let count = entries.count
        entries = Array(entries.filter { now.timeIntervalSince($0.at) < Self.retention }.prefix(Self.limit))
        return entries.count != count
    }

    private mutating func insert(_ entry: HistoryEntry) -> Bool {
        guard !entries.contains(where: { $0.id == entry.id }) else { return false }
        let index = entries.firstIndex { $0.at < entry.at } ?? entries.endIndex
        entries.insert(entry, at: index)
        return true
    }
}

/// History on disk: one small JSON file, rewritten atomically.
public struct HistoryStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public init(paths: PeekuPaths = .default) { url = paths.history }

    public func load() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    public func save(_ entries: [HistoryEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(entries) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

extension PeekuPaths {
    public var history: URL { root.appending(path: "history.json") }
}
