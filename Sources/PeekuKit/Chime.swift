import Foundation

/// The sound a new attention episode plays. Waiting shares the question's sound.
public enum Chime: String, Sendable, Hashable, CaseIterable {
    case permission, question, error, finished, usage

    public init?(_ kind: SessionKind) {
        switch kind {
        case .permission: self = .permission
        case .question, .waiting, .commandInput: self = .question
        // A failed command sounds like a blocked agent, so it needs no setting of its own.
        case .error, .command: self = .error
        case .finished: self = .finished
        case .usage: self = .usage
        case .idle, .working: return nil
        }
    }
}
