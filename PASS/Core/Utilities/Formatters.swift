import Foundation

enum PassFormatters {
    /// "1:58:07" style countdown used on the Baton and Home cards. Never negative.
    static func countdown(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }

    /// "14:59" style for short windows (rescue). Falls back to h:mm:ss above an hour.
    static func shortCountdown(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded(.down)))
        if total >= 3600 { return countdown(remaining) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Accessible phrasing: "1 hour 58 minutes left".
    static func spokenRemaining(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining))
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return "\(h) hour\(h == 1 ? "" : "s") \(m) minute\(m == 1 ? "" : "s") left" }
        if m > 0 { return "\(m) minute\(m == 1 ? "" : "s") left" }
        return "\(total % 60) seconds left"
    }

    static let memberSince: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f
    }()

    static let relayDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// First word of a display name, used by the Reveal (spec §19).
    static func firstName(_ displayName: String) -> String {
        displayName.split(separator: " ").first.map(String.init) ?? displayName
    }

    /// Two-letter initials ("Friday Night" → "FN", "Maya" → "MY" per the Figma style of taking two consonant-ish letters).
    static func initials(_ displayName: String) -> String {
        let parts = displayName.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2, let a = parts[0].first, let b = parts[1].first {
            return String([a, b]).uppercased()
        }
        let letters = Array(displayName.filter { $0.isLetter })
        guard let first = letters.first else { return "?" }
        if letters.count == 1 { return String(first).uppercased() }
        return String([first, letters[1]]).uppercased()
    }
}
