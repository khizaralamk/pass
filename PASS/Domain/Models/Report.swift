import Foundation

enum ReportReason: String, CaseIterable, Codable, Sendable, Identifiable {
    case harassment = "Harassment or bullying"
    case nudity = "Nudity or sexual content"
    case violence = "Violence or dangerous behaviour"
    case spam = "Spam or misleading"
    case other = "Something else"
    var id: String { rawValue }
}

enum ReportTarget: Hashable, Codable, Sendable {
    case user(UserID)
    case relay(RelayID)
}

struct Report: Identifiable, Hashable, Codable, Sendable {
    let id: ReportID
    var reporterID: UserID
    var target: ReportTarget
    var reason: ReportReason
    var details: String
    var createdAt: Date
}

struct NotificationPreferences: Hashable, Codable, Sendable {
    var batonReceived = true
    var reminders = true
    var relayProgress = true
    var relayComplete = true
}
