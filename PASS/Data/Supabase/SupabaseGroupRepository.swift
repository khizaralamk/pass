import Foundation
import Supabase

/// Groups through the contract's RPCs. Every rule (max 7, blocks, cancel-on-leave) is enforced server-side; the mapped
/// `AppError` carries the server's user-safe copy.
struct SupabaseGroupRepository: GroupRepository {
    let backend: SupabaseBackend

    func groups() async throws -> [Group] {
        try await backend.rpc("get_groups")
    }

    func group(_ id: GroupID) async throws -> Group {
        try await backend.rpc("get_group", ["p_group_id": .string(id.raw)])
    }

    func createGroup(name: String, emoji: String) async throws -> Group {
        try await backend.rpc("create_group", ["p_name": .string(name), "p_emoji": .string(emoji)])
    }

    func invitePreview(code: String) async throws -> InvitePreview {
        try await backend.rpc("invite_preview", ["p_code": .string(code)])
    }

    func joinGroup(code: String) async throws -> Group {
        try await backend.rpc("join_group", ["p_code": .string(code)])
    }

    func leaveGroup(_ id: GroupID) async throws {
        try await backend.rpcVoid("leave_group", ["p_group_id": .string(id.raw)])
    }

    func removeMember(_ userID: UserID, from groupID: GroupID) async throws {
        try await backend.rpcVoid("remove_member", ["p_group_id": .string(groupID.raw), "p_user_id": .string(userID.raw)])
    }
}
