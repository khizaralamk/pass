import Foundation
import Supabase

/// Realtime V2 `postgres_changes` on the five tables the screens care about, fanned out to every `changes()` consumer
/// as coarse `DataChange` values (the screens reload through the RPCs; row payloads are never used directly).
/// One channel is shared; it is subscribed when the first consumer appears and removed when the last one leaves.
final class SupabaseChangeSource: DataChangeSource, @unchecked Sendable {
    private static let tables: [(name: String, change: DataChange)] = [
        ("relays", .relays),
        ("relay_participants", .relays),
        ("baton_turns", .relays),
        ("groups", .groups),
        ("group_members", .groups),
    ]

    private let backend: SupabaseBackend
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<DataChange>.Continuation] = [:]
    private var channel: RealtimeChannelV2?
    private var listener: Task<Void, Never>?

    init(backend: SupabaseBackend) {
        self.backend = backend
    }

    func changes() -> AsyncStream<DataChange> {
        AsyncStream { continuation in
            let id = UUID()
            add(id, continuation)
            continuation.onTermination = { [weak self] _ in self?.remove(id) }
        }
    }

    // MARK: - Fan-out

    private func add(_ id: UUID, _ continuation: AsyncStream<DataChange>.Continuation) {
        lock.lock()
        continuations[id] = continuation
        let needsStart = listener == nil
        lock.unlock()
        if needsStart { start() }
    }

    private func remove(_ id: UUID) {
        lock.lock()
        continuations[id] = nil
        let isLast = continuations.isEmpty
        let channel = isLast ? self.channel : nil
        let listener = isLast ? self.listener : nil
        if isLast { self.channel = nil; self.listener = nil }
        lock.unlock()
        guard isLast else { return }
        listener?.cancel()
        if let channel {
            let client = backend.client
            Task { await client.realtimeV2.removeChannel(channel) }
        }
    }

    private func broadcast(_ change: DataChange) {
        lock.lock()
        let targets = Array(continuations.values)
        lock.unlock()
        for c in targets { c.yield(change) }
    }

    // MARK: - Channel

    private func start() {
        let channel = backend.client.realtimeV2.channel("pass-changes")
        // Streams must be created before `subscribe` so the join message carries the postgres_changes bindings.
        let streams = Self.tables.map { table in
            (stream: channel.postgresChange(AnyAction.self, schema: "public", table: table.name), change: table.change)
        }
        let task = Task { [weak self] in
            do {
                try await channel.subscribeWithError()
            } catch {
                #if DEBUG
                print("Realtime subscribe failed: \(error)")
                #endif
                return
            }
            await withTaskGroup(of: Void.self) { group in
                for entry in streams {
                    group.addTask {
                        for await _ in entry.stream {
                            guard !Task.isCancelled else { return }
                            self?.broadcast(entry.change)
                        }
                    }
                }
            }
        }
        lock.lock()
        self.channel = channel
        self.listener = task
        lock.unlock()
    }
}
