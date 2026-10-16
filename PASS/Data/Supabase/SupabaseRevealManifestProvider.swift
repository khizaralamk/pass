import Foundation
import Supabase

/// Reveal media through the Edge Function `reveal-manifest`, which signs each storage path for 10 minutes. The files
/// are downloaded into `LocalMediaStore` under their storage path, so `RevealViewModel`, `RevealExporter` and the
/// History thumbnails keep working on local URLs exactly as with the mock.
final class SupabaseRevealManifestProvider: RevealManifestProvider, @unchecked Sendable {
    private let backend: SupabaseBackend
    private let media: any MediaStore
    private let session: URLSession

    init(backend: SupabaseBackend, media: any MediaStore, session: URLSession = .shared) {
        self.backend = backend
        self.media = media
        self.session = session
    }

    /// Wire shape (contract "RevealManifest"): `relayId` + signed `url` instead of `relayID` + `fileName`.
    nonisolated struct Wire: Decodable, Sendable {
        struct Item: Decodable, Sendable {
            var position: Int
            var firstName: String
            var colorHex: String
            var mediaType: MediaType
            var url: URL
            var durationMs: Int?
        }
        var relayId: String
        var templateVersion: Int?
        var challengeTitle: String
        var groupName: String
        var outcome: RelayOutcome
        var participantCount: Int
        var items: [Item]
    }

    func manifest(for relay: Relay) async throws -> RevealManifest? {
        guard relay.hasReveal else { return nil }
        let wire: Wire = try await backend.invoke("reveal-manifest", body: ["relayId": relay.id.raw])
        guard wire.outcome.hasReveal, !wire.items.isEmpty else { return nil }

        let items = wire.items.sorted { $0.position < $1.position }
        let fileNames = items.map { localFileName(for: $0, relay: relay) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (item, fileName) in zip(items, fileNames) {
                group.addTask { try await self.cache(item.url, as: fileName) }
            }
            try await group.waitForAll()
        }

        return RevealManifest(
            relayID: RelayID(wire.relayId),
            challengeTitle: wire.challengeTitle,
            groupName: wire.groupName,
            outcome: wire.outcome,
            participantCount: wire.participantCount,
            items: zip(items, fileNames).map { item, fileName in
                RevealManifest.Item(position: item.position, firstName: item.firstName, colorHex: item.colorHex,
                                    mediaType: item.mediaType, fileName: fileName, durationMs: item.durationMs)
            })
    }

    /// The submission's storage path when the relay has it (always, per contract); a stable fallback otherwise.
    private func localFileName(for item: Wire.Item, relay: Relay) -> String {
        if let submission = relay.submissionsInOrder.first(where: { $0.position == item.position }) { return submission.fileName }
        let ext = item.mediaType == .video ? "mov" : "jpg"
        return "relays/\(relay.id.raw)/\(item.position).\(ext)"
    }

    private func cache(_ url: URL, as fileName: String) async throws {
        if media.exists(fileName: fileName) { return }
        let destination = media.url(for: fileName)
        let (temporary, response): (URL, URLResponse)
        do {
            (temporary, response) = try await session.download(from: url)
        } catch {
            throw SupabaseErrorMapping.map(error)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: temporary)
            throw http.statusCode == 403 || http.statusCode == 401
                ? AppError.permissionDenied("The Reveal link expired. Open the Reveal again.")
                : AppError.media("Couldn't load the Reveal media. Please try again.")
        }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: destination)
            try fm.moveItem(at: temporary, to: destination)
        } catch {
            throw AppError.media("Couldn't save the Reveal media.")
        }
    }
}
