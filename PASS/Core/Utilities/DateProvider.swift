import Foundation

/// Source of "now". Countdowns are always `deadline - now`; nothing is ever persisted as a remaining duration.
/// The backend phase replaces `SystemDateProvider` with a server-corrected clock (BUILD-PLAN 5.2 ServerClock).
protocol DateProvider: Sendable {
    func now() -> Date
}

struct SystemDateProvider: DateProvider {
    func now() -> Date { Date() }
}

/// Clock with an adjustable offset so demo controls and tests can "advance" time deterministically.
final class AdjustableDateProvider: DateProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var offset: TimeInterval = 0
    private let base: @Sendable () -> Date

    init(base: @escaping @Sendable () -> Date = { Date() }) { self.base = base }

    func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        return base().addingTimeInterval(offset)
    }

    func advance(by interval: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        offset += interval
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        offset = 0
    }

    /// Replaces the offset outright. `ServerClock` uses this with `serverNow - deviceNow` so deadlines from the backend
    /// are compared against the server's idea of now, not the device's.
    func setOffset(_ newOffset: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        offset = newOffset
    }

    var currentOffset: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return offset
    }
}
