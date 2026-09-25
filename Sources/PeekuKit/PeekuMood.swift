/// Peeku's character state. State lives in the eyes.
public enum PeekuMood: String, Sendable, Hashable, CaseIterable {
    case idle, working, question, permission, error, success, multiple
}

extension SessionKind {
    public var mood: PeekuMood {
        switch self {
        case .idle: .idle
        case .working: .working
        case .permission, .usage: .permission
        case .question, .waiting, .commandInput: .question
        case .error, .command: .error
        case .finished: .success
        }
    }
}
