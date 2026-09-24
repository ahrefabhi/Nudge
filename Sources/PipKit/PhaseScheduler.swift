import Foundation

@MainActor
public final class PhaseTimer {
    public private(set) var isCancelled = false
    public func cancel() { isCancelled = true }
}

/// Time source for the phase machine, so tests and snapshots can drive it deterministically.
@MainActor
public protocol PhaseScheduler: AnyObject {
    var now: Date { get }
    func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> PhaseTimer
}

public final class MainScheduler: PhaseScheduler {
    public init() {}
    public var now: Date { Date() }

    public func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> PhaseTimer {
        let timer = PhaseTimer()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                if !timer.isCancelled { work() }
            }
        }
        return timer
    }
}

/// Runs scheduled work only when `advance(by:)` moves time past it.
public final class ManualScheduler: PhaseScheduler {
    private struct Pending {
        let fireAt: TimeInterval
        let order: Int
        let timer: PhaseTimer
        let work: @MainActor () -> Void
    }

    private var time: TimeInterval
    private var pending: [Pending] = []
    private var counter = 0

    public init(start: Date = Date(timeIntervalSinceReferenceDate: 0)) {
        time = start.timeIntervalSinceReferenceDate
    }

    public var now: Date { Date(timeIntervalSinceReferenceDate: time) }

    public func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> PhaseTimer {
        let timer = PhaseTimer()
        counter += 1
        pending.append(Pending(fireAt: time + delay, order: counter, timer: timer, work: work))
        return timer
    }

    public func advance(by seconds: TimeInterval) {
        let end = time + seconds
        while let next = pending.filter({ $0.fireAt <= end }).min(by: { ($0.fireAt, $0.order) < ($1.fireAt, $1.order) }) {
            pending.removeAll { $0.order == next.order }
            time = max(time, next.fireAt)
            if !next.timer.isCancelled { next.work() }
        }
        time = end
    }
}
