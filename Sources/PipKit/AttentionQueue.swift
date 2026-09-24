import Foundation

public enum AttentionQueue {
    /// permission > question > waiting > error > finished. Working sessions never queue.
    public static func rank(_ kind: SessionKind) -> Int? {
        switch kind {
        case .permission: 0
        case .question: 1
        case .waiting: 2
        case .error: 3
        case .finished: 4
        case .idle, .working: nil
        }
    }

    /// Sessions that need the user, most urgent first, ties to the oldest wait.
    public static func ordered(
        _ sessions: [PipSession], resolved: Set<String> = [], includeFinished: Bool = false
    ) -> [PipSession] {
        sessions
            .filter { ($0.needsYou || (includeFinished && $0.kind == .finished)) && !resolved.contains($0.attentionKey) }
            .sorted { a, b in
                let ra = rank(a.kind) ?? .max, rb = rank(b.kind) ?? .max
                if ra != rb { return ra < rb }
                if a.since != b.since { return a.since < b.since }
                return a.id < b.id
            }
    }
}
