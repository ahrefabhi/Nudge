/// Pip's character state. State lives in the eyes.
public enum PipMood: String, Sendable, Hashable, CaseIterable {
    case idle, working, question, permission, error, success, multiple
}

extension SessionKind {
    public var mood: PipMood {
        switch self {
        case .idle: .idle
        case .working: .working
        case .permission, .usage: .permission
        case .question, .waiting: .question
        case .error: .error
        case .finished: .success
        }
    }
}
