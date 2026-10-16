import Foundation

/// Keeps `AdjustableDateProvider` aligned with the server: `server_now()` on launch and foreground, offset = server
/// time minus the device time at the midpoint of the request. Deadlines from the backend are absolute timestamps in
/// server time, so countdowns (`deadline - clock.now()`) stay correct on devices with a skewed clock.
final class ServerClock: @unchecked Sendable {
    private let backend: SupabaseBackend
    private let clock: AdjustableDateProvider
    private let lock = NSLock()
    private var lastSync: Date?

    /// Offsets below this are noise (network jitter) and are ignored to keep countdowns from twitching.
    static let tolerance: TimeInterval = 1.0

    init(backend: SupabaseBackend, clock: AdjustableDateProvider) {
        self.backend = backend
        self.clock = clock
    }

    /// Never throws: a failed sync leaves the previous offset (initially 0 = device time).
    func sync() async {
        let started = Date()
        guard let raw: String = try? await backend.rpc("server_now"), let serverNow = RFC3339.date(from: raw) else { return }
        let finished = Date()
        let midpoint = started.addingTimeInterval(finished.timeIntervalSince(started) / 2)
        let offset = serverNow.timeIntervalSince(midpoint)
        if abs(offset - clock.currentOffset) >= Self.tolerance { clock.setOffset(offset) }
        lock.lock(); lastSync = finished; lock.unlock()
    }

    var lastSyncedAt: Date? {
        lock.lock(); defer { lock.unlock() }
        return lastSync
    }
}
