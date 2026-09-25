import Foundation
import PeekuKit

/// Feeds the handoff README's sample sessions, for Demo Mode.
final class DemoController {
    private let machine: PhaseMachine
    private var sessions: [PeekuSession]

    init(machine: PhaseMachine) {
        self.machine = machine
        sessions = MockSessions.calm()
    }

    func trigger(_ event: MockSessions.Event) {
        sessions = MockSessions.apply(event, to: sessions)
        machine.update(sessions: sessions)
    }

    func triggerUsage() {
        machine.update(usageAlerts: [MockSessions.usageAlert()])
    }

    func triggerCommandFailure() {
        machine.update(commandAlerts: [MockSessions.commandAlert()])
    }

    func triggerCommandPrompt() {
        machine.update(commandAlerts: [MockSessions.commandPrompt()])
    }

    func reset() {
        sessions = MockSessions.calm()
        machine.update(sessions: sessions)
        machine.update(usageAlerts: [])
        machine.update(commandAlerts: [])
        machine.history = MockSessions.history()
    }

    /// Stands in for focusing a real session: the user "answers" a few seconds later.
    func didOpen(_ session: PeekuSession) {
        if session.kind == .usage { return machine.update(usageAlerts: []) }
        if session.kind.isCommand {
            print("[Peeku] would show the output of \(session.project)")
            return machine.update(commandAlerts: [])
        }
        print("[Peeku] would focus \(session.project) in \(session.hostLabel)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let index = self.sessions.firstIndex(where: { $0.attentionKey == session.attentionKey }) else { return }
                self.sessions[index] = MockSessions.answered(session)
                self.machine.update(sessions: self.sessions)
            }
        }
    }
}
