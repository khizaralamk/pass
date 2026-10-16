import Foundation
import Testing
@testable import PASS

/// The API contract promises camelCase keys that match the Swift Codable structs, string ids and RFC 3339 dates.
/// These samples are lifted from backend/docs/01-API-CONTRACT.md; if they stop decoding, the contract drifted.
struct ContractDecodingTests {
    let decoder = SupabaseClientFactory.makeDecoder()

    static let relayJSON = """
    {
      "id": "6f1c2b4e-5f3a-4c2d-9e8b-1a2b3c4d5e6f",
      "groupID": "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d",
      "groupName": "Friday Night Crew",
      "groupEmoji": "🔥",
      "challengeTitle": "Worst selfie wins",
      "createdBy": "11111111-1111-4111-8111-111111111111",
      "createdAt": "2026-10-10T12:00:00Z",
      "status": "active",
      "outcome": null,
      "endedAt": null,
      "endedReason": null,
      "participants": [
        {
          "user": { "id": "11111111-1111-4111-8111-111111111111", "displayName": "Jake Miller", "colorHex": "#FF6B35" },
          "state": "submitted",
          "dropCount": 0,
          "deferredAt": null,
          "submission": {
            "id": "22222222-2222-4222-8222-222222222222",
            "userID": "11111111-1111-4111-8111-111111111111",
            "mediaType": "photo",
            "fileName": "relays/6f1c2b4e-5f3a-4c2d-9e8b-1a2b3c4d5e6f/11111111-1111-4111-8111-111111111111.jpg",
            "durationMs": null,
            "submittedAt": "2026-10-10T12:05:30.123456+00:00",
            "position": 1
          },
          "joinedGroupAt": "2026-09-01T09:00:00Z"
        },
        {
          "user": { "id": "33333333-3333-4333-8333-333333333333", "displayName": "Maya Chen", "colorHex": "#6B46FF" },
          "state": "holding",
          "dropCount": 1,
          "deferredAt": "2026-10-10T13:00:00Z",
          "submission": null,
          "joinedGroupAt": "2026-09-02T09:00:00Z"
        }
      ],
      "turns": [
        { "id": "t1", "holderID": "11111111-1111-4111-8111-111111111111", "passedBy": null,
          "startedAt": "2026-10-10T12:00:00Z", "deadline": "2026-10-10T14:00:00Z", "isRescue": false, "endedAt": "2026-10-10T12:06:00Z" },
        { "id": "t2", "holderID": "33333333-3333-4333-8333-333333333333", "passedBy": "11111111-1111-4111-8111-111111111111",
          "startedAt": "2026-10-10T12:06:00Z", "deadline": "2026-10-10T14:06:00Z", "isRescue": false, "endedAt": null }
      ]
    }
    """

    @Test func decodesContractRelay() throws {
        let relay = try decoder.decode(Relay.self, from: Data(Self.relayJSON.utf8))
        #expect(relay.id == RelayID("6f1c2b4e-5f3a-4c2d-9e8b-1a2b3c4d5e6f"))
        #expect(relay.groupName == "Friday Night Crew" && relay.isActive && relay.outcome == nil)
        #expect(relay.participants.count == 2 && relay.submittedCount == 1)
        #expect(relay.holder?.user.displayName == "Maya Chen")
        #expect(relay.currentTurn?.id == "t2" && relay.passer?.displayName == "Jake Miller")
        #expect(relay.submissionsInOrder.first?.fileName.hasPrefix("relays/") == true)

        let expectedSubmitted = try #require(RFC3339.date(from: "2026-10-10T12:05:30.123Z"))
        let submittedAt = try #require(relay.submissionsInOrder.first?.submittedAt)
        #expect(abs(submittedAt.timeIntervalSince(expectedSubmitted)) < 0.001)
        let deadline = try #require(relay.currentTurn?.deadline)
        #expect(deadline.timeIntervalSince(relay.createdAt) == 2 * 3600 + 6 * 60)
    }

    @Test func decodesProfileGroupAndPreferences() throws {
        let profile = """
        { "id": "11111111-1111-4111-8111-111111111111", "displayName": "Khizar", "colorHex": "#6B46FF",
          "avatarFileName": "11111111-1111-4111-8111-111111111111.jpg", "memberSince": "2026-08-30T10:00:00Z", "dateOfBirth": null }
        """
        let user = try decoder.decode(User.self, from: Data(profile.utf8))
        #expect(user.displayName == "Khizar" && user.avatarFileName?.hasSuffix(".jpg") == true && user.dateOfBirth == nil)

        let group = """
        { "id": "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d", "name": "Court Crew", "emoji": "🏀", "inviteCode": "PASS-BR22",
          "createdBy": "11111111-1111-4111-8111-111111111111", "createdAt": "2026-09-01T09:00:00Z",
          "members": [ { "user": { "id": "11111111-1111-4111-8111-111111111111", "displayName": "Khizar", "colorHex": "#6B46FF" },
                         "role": "creator", "joinedAt": "2026-09-01T09:00:00Z" } ],
          "stats": { "completedRelays": 4, "currentStreak": 2 } }
        """
        let g = try decoder.decode(Group.self, from: Data(group.utf8))
        #expect(g.inviteCode == "PASS-BR22" && g.members.first?.role == .creator && g.stats.currentStreak == 2)

        let prefs = try decoder.decode(NotificationPreferences.self, from: Data(#"{"batonReceived":true,"reminders":false,"relayProgress":true,"relayComplete":true}"#.utf8))
        #expect(prefs.reminders == false && prefs.batonReceived)
    }

    @Test func rfc3339AcceptsPostgresVariants() throws {
        let base = try #require(RFC3339.date(from: "2026-10-10T12:00:00Z"))
        for variant in ["2026-10-10T12:00:00+00:00", "2026-10-10T12:00:00.000000+00:00", "2026-10-10 12:00:00", "2026-10-10T12:00:00.5Z"] {
            let d = try #require(RFC3339.date(from: variant), "\(variant)")
            #expect(abs(d.timeIntervalSince(base)) <= 0.5, "\(variant)")
        }
        #expect(RFC3339.date(from: "not a date") == nil)
    }

    @Test func rpcParamsSendExplicitNulls() throws {
        let params: RPCParams = ["p_target_user_id": .string(nil), "p_target_relay_id": .string("r1"), "p_duration_ms": .int(nil), "p_flag": .bool(true)]
        let data = try SupabaseClientFactory.makeEncoder().encode(params)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object.count == 4)
        #expect(object["p_target_user_id"] is NSNull && object["p_duration_ms"] is NSNull)
        #expect(object["p_target_relay_id"] as? String == "r1" && object["p_flag"] as? Bool == true)
    }

    @Test func backendSelectionDefaultsToMock() {
        #expect(AppConfiguration.current.backend == .mock)
        #expect(AppConfiguration.Backend.fromInfoPlist(.main) == .mock)
    }
}
