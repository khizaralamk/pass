import Foundation
import Supabase

/// Relays through the contract's RPCs. `submit` is the three-step upload: `create_upload_slot` → put the file in the
/// private `media` bucket → `submit`. Nobody can read the object before the Reveal (no SELECT policy; signed URLs only).
struct SupabaseRelayRepository: RelayRepository {
    let backend: SupabaseBackend
    let media: any MediaStore

    private struct UploadSlot: Decodable { var bucket: String; var storagePath: String }

    func activeRelays() async throws -> [Relay] {
        try await backend.rpc("get_active_relays")
    }

    func relay(_ id: RelayID) async throws -> Relay {
        try await backend.rpc("get_relay", ["p_relay_id": .string(id.raw)])
    }

    func history(groupID: GroupID) async throws -> [Relay] {
        try await backend.rpc("get_history", ["p_group_id": .string(groupID.raw)])
    }

    func challenges() async throws -> [Challenge] {
        try await backend.rpc("get_challenges")
    }

    func startRelay(groupID: GroupID, challengeTitle: String) async throws -> Relay {
        try await backend.rpc("start_relay", ["p_group_id": .string(groupID.raw), "p_challenge_title": .string(challengeTitle)])
    }

    func submit(relayID: RelayID, media captured: CapturedMedia) async throws -> Relay {
        let slot: UploadSlot = try await backend.rpc("create_upload_slot", [
            "p_relay_id": .string(relayID.raw),
            "p_media_type": .string(captured.type.rawValue),
        ])
        guard let data = try? Data(contentsOf: captured.fileURL), !data.isEmpty else {
            throw AppError.media("Couldn't read your capture. Please try again.")
        }
        try await upload(data, to: slot, contentType: Self.contentType(for: captured.type))
        let relay: Relay = try await backend.rpc("submit", [
            "p_relay_id": .string(relayID.raw),
            "p_storage_path": .string(slot.storagePath),
            "p_media_type": .string(captured.type.rawValue),
            "p_duration_ms": .int(captured.type == .video ? captured.durationMs : nil),
        ])
        cacheLocally(captured.fileURL, as: slot.storagePath)
        return relay
    }

    func passBaton(relayID: RelayID, to userID: UserID) async throws -> Relay {
        try await backend.rpc("pass_baton", ["p_relay_id": .string(relayID.raw), "p_to_user_id": .string(userID.raw)])
    }

    // MARK: - Upload

    private func upload(_ data: Data, to slot: UploadSlot, contentType: String) async throws {
        do {
            try await backend.client.storage.from(slot.bucket)
                .upload(slot.storagePath, data: data, options: FileOptions(contentType: contentType, upsert: false))
        } catch let error as StorageError where error.statusCode == "409" {
            // A retry after a failed `submit`: the object is already there (INSERT-only policy forbids overwriting).
            return
        } catch {
            throw SupabaseErrorMapping.map(error)
        }
    }

    static func contentType(for type: MediaType) -> String {
        switch type {
        case .photo: return "image/jpeg"
        case .video: return "video/quicktime"
        }
    }

    /// Keeps my own submission under its storage path so History/Reveal find it without a download.
    private func cacheLocally(_ source: URL, as storagePath: String) {
        let destination = media.url(for: storagePath)
        let fm = FileManager.default
        try? fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: destination)
        try? fm.copyItem(at: source, to: destination)
    }
}
