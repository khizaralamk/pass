import Foundation

/// The signed-in person. Date of birth is kept only to enforce the 16+ rule during onboarding and is not shown anywhere.
struct User: Identifiable, Hashable, Codable, Sendable {
    let id: UserID
    var displayName: String
    var colorHex: String
    var avatarFileName: String?
    var memberSince: Date
    var dateOfBirth: Date?

    var initials: String { PassFormatters.initials(displayName) }
    var firstName: String { PassFormatters.firstName(displayName) }
    var summary: UserSummary { UserSummary(id: id, displayName: displayName, colorHex: colorHex) }
}

/// What other members see of a person: name and avatar colour only. No public profile exists (spec §1, §30).
struct UserSummary: Identifiable, Hashable, Codable, Sendable {
    let id: UserID
    var displayName: String
    var colorHex: String

    var initials: String { PassFormatters.initials(displayName) }
    var firstName: String { PassFormatters.firstName(displayName) }
}

/// Mock session persisted between launches so a returning user goes splash → Home (spec §3).
struct Session: Hashable, Codable, Sendable {
    var userID: UserID
    var onboardingComplete: Bool
}
