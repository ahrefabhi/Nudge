import AppKit
import NudgeKit

/// Plays Demo Mode as a fixed timeline, for recording the product video (`--demo-script`).
/// Every run looks the same, and no menu clicks end up on screen. Each scene prints its
/// offset so the recording can be cut and captioned from the log.
@MainActor
final class DemoScript {
    private struct Step {
        var at: TimeInterval
        var scene: String?
        var action: () -> Void
    }

    private let machine: PhaseMachine
    private let demo: DemoController
    private var start = Date()

    init(machine: PhaseMachine, demo: DemoController) {
        self.machine = machine
        self.demo = demo
    }

    /// Waits `lead` seconds, so the recorder can start, then plays the timeline and quits.
    func run(lead: TimeInterval = 3) {
        demo.reset()
        machine.usage = MockSessions.usage()
        start = Date().addingTimeInterval(lead)
        for step in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + lead + step.at) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let scene = step.scene { self.log(scene) }
                    step.action()
                }
            }
        }
    }

    private var steps: [Step] {
        let machine = machine, demo = demo
        return [
            Step(at: 0, scene: "working") {},
            Step(at: 3, scene: "permission") { demo.trigger(.permission) },
            Step(at: 7.5, scene: "open-permission") { machine.open("payments") },
            Step(at: 11, scene: "question") { demo.trigger(.question) },
            Step(at: 15.5, scene: "open-question") { machine.open("dash") },
            Step(at: 19, scene: "error") { demo.trigger(.error) },
            Step(at: 23.5, scene: "open-error") { machine.open("infra") },
            // A finished session is only a wink by default; pop it up so it reads on video. On for this
            // scene only, or docs-site, finished from the start, would join every other alert.
            Step(at: 27, scene: "finished") {
                machine.expandFinished = true
                demo.trigger(.success)
            },
            Step(at: 30.5, scene: "open-finished") {
                machine.open("docs")
                machine.expandFinished = false
            },
            Step(at: 32, scene: "multiple") { demo.trigger(.multiple) },
            Step(at: 35.5, scene: nil) { machine.cycleNext() },
            Step(at: 37, scene: nil) { machine.cycleNext() },
            Step(at: 39, scene: "open-multiple") { machine.openFocused() },
            // The other two are still waiting; clear them so the usage alert leads the queue.
            Step(at: 41.5, scene: nil) { demo.reset() },
            Step(at: 43, scene: "usage") { demo.triggerUsage() },
            Step(at: 47.5, scene: "open-usage") { machine.openFocused() },
            Step(at: 52, scene: "manager-now") { machine.managerTab = .now },
            Step(at: 56, scene: "manager-history") { machine.managerTab = .history },
            Step(at: 61, scene: "close") { machine.tapOutside() },
            Step(at: 64, scene: "done") { NSApp.terminate(nil) },
        ]
    }

    private func log(_ scene: String) {
        // The wall-clock time lines the log up with a recording that started earlier.
        print(String(format: "[Nudge demo] %6.2f %@ %.3f", Date().timeIntervalSince(start), scene, Date().timeIntervalSince1970))
        fflush(stdout)
    }
}
