import Foundation
import SwiftUI

/// Deterministic demo data mirroring the Figma prototype (Friday Night Crew, Court Crew) plus a third group the demo
/// user is not in yet, so the invite flow can be exercised with code `PASS-BR22`.
enum MockFixtures {
    static let meID: UserID = "me"
    static let fridayID: GroupID = "friday"
    static let courtID: GroupID = "court"
    static let brunchID: GroupID = "brunch"
    static let fridayCode = "PASS-FN74"
    static let courtCode = "PASS-CT31"
    static let brunchCode = "PASS-BR22"

    static func bot(_ id: String, _ name: String, _ hex: String) -> UserSummary {
        UserSummary(id: UserID(id), displayName: name, colorHex: hex)
    }

    static let jake = bot("jake", "Jake", "#FF6B35")
    static let maya = bot("maya", "Maya", "#FF2D55")
    static let zoe = bot("zoe", "Zoe", "#0A84FF")
    static let cam = bot("cam", "Cam", "#30D158")
    static let jordan = bot("jordan", "Jordan", "#FF9F0A")
    static let dev = bot("dev", "Dev", "#30D158")
    static let sam = bot("sam", "Sam", "#BF5AF2")
    static let priya = bot("priya", "Priya", "#FF6B35")
    static let leo = bot("leo", "Leo", "#0A84FF")

    /// Extra members that "Simulate a friend joining" pulls from, in order.
    static let joinPool: [UserSummary] = [
        bot("nia", "Nia", "#BF5AF2"), bot("theo", "Theo", "#FF9F0A"), bot("ava", "Ava", "#30D158"),
        bot("omar", "Omar", "#0A84FF"), bot("lina", "Lina", "#FF2D55"), bot("max", "Max", "#FF6B35"),
    ]

    /// Luis's V1 list (email 2026-10-10). Custom challenges stay available via "Write your own".
    static let challenges: [Challenge] = [
        "Worst Selfie", "Show Your View", "Current Fit", "What Are You Eating?", "Find Something Red",
        "Friday Night", "Recreate This Photo", "One Second From Your Day", "Best Impression", "Before Midnight",
    ].enumerated().map { Challenge(id: ChallengeID("c\($0.offset + 1)"), title: $0.element, isBuiltIn: true) }

    static func placeholderMe(now: Date) -> User {
        User(id: meID, displayName: "You", colorHex: "#6B46FF", avatarFileName: nil, memberSince: now, dateOfBirth: nil)
    }

    /// Builds the seed groups. `me` is a member of Friday and Court, not of Brunch.
    static func groups(me: UserSummary, now: Date) -> [Group] {
        let day: TimeInterval = 86_400
        func member(_ u: UserSummary, _ role: GroupRole, daysAgo: Double) -> GroupMember {
            GroupMember(user: u, role: role, joinedAt: now.addingTimeInterval(-daysAgo * day))
        }
        return [
            Group(id: fridayID, name: "Friday Night Crew", emoji: "🌙", inviteCode: fridayCode, createdBy: jake.id,
                  createdAt: now.addingTimeInterval(-60 * day),
                  members: [member(jake, .creator, daysAgo: 60), member(me, .member, daysAgo: 58), member(maya, .member, daysAgo: 55),
                            member(zoe, .member, daysAgo: 50), member(cam, .member, daysAgo: 44)],
                  stats: GroupStats(completedRelays: 23, currentStreak: 7)),
            Group(id: courtID, name: "Court Crew", emoji: "🏀", inviteCode: courtCode, createdBy: jordan.id,
                  createdAt: now.addingTimeInterval(-30 * day),
                  members: [member(jordan, .creator, daysAgo: 30), member(me, .member, daysAgo: 29), member(dev, .member, daysAgo: 20)],
                  stats: GroupStats(completedRelays: 5, currentStreak: 2)),
            Group(id: brunchID, name: "Brunch Club", emoji: "🥞", inviteCode: brunchCode, createdBy: sam.id,
                  createdAt: now.addingTimeInterval(-12 * day),
                  members: [member(sam, .creator, daysAgo: 12), member(priya, .member, daysAgo: 11), member(leo, .member, daysAgo: 9)],
                  stats: GroupStats(completedRelays: 1, currentStreak: 1)),
        ]
    }
}

/// Generates placeholder "photos" for simulated members so Reveals and History have real image files without any network.
/// Each image is a gradient in the member's colour with their initials, rendered once and cached by file name.
@MainActor
enum FixtureMediaFactory {
    static func photoFileName(for member: UserSummary, seed: Int) -> String {
        "fixture-\(member.id.raw)-\(seed).jpg"
    }

    @discardableResult
    static func ensurePhoto(for member: UserSummary, seed: Int, in store: any MediaStore) -> String {
        let name = photoFileName(for: member, seed: seed)
        if store.exists(fileName: name) { return name }
        let color = Color(hexString: member.colorHex)
        let emojis = ["🌙", "🍕", "🎯", "🌊", "🎉", "⚡", "🏖️", "🎮", "🎵", "🏀"]
        let emoji = emojis[abs(seed) % emojis.count]
        let view = ZStack {
            LinearGradient(colors: [color, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 24) {
                Text(emoji).font(.system(size: 220))
                Text(member.initials).font(.system(size: 160, weight: .black)).foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(width: 1080, height: 1920)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.uiImage else { return name }
        _ = try? store.saveJPEG(image, quality: 0.8, fileName: name)
        return name
    }
}
