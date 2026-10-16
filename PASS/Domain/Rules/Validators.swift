import Foundation

/// Client-side input rules. Documented in Documentation/VALIDATION.md; the backend must enforce the same constraints.
enum ValidationError: Error, Equatable {
    case required(String)
    case tooShort(String, Int)
    case tooLong(String, Int)
    case invalid(String)

    var message: String {
        switch self {
        case .required(let f): return "\(f) is required."
        case .tooShort(let f, let n): return "\(f) needs at least \(n) characters."
        case .tooLong(let f, let n): return "\(f) can't be longer than \(n) characters."
        case .invalid(let m): return m
        }
    }
}

enum Validators {
    static let displayNameRange = 2...30
    static let groupNameRange = 2...30
    static let challengeRange = 3...60
    static let reportDetailsMax = 500

    /// Collapses internal whitespace and trims the ends.
    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    static func displayName(_ raw: String) -> Result<String, ValidationError> {
        text(raw, field: "Name", range: displayNameRange)
    }

    static func groupName(_ raw: String) -> Result<String, ValidationError> {
        text(raw, field: "Group name", range: groupNameRange)
    }

    static func challengeTitle(_ raw: String) -> Result<String, ValidationError> {
        text(raw, field: "Challenge", range: challengeRange)
    }

    static func reportDetails(_ raw: String) -> Result<String, ValidationError> {
        let n = normalized(raw)
        if n.count > reportDetailsMax { return .failure(.tooLong("Details", reportDetailsMax)) }
        return .success(n)
    }

    /// 16+ (spec §3). Rejects future dates and implausible ages.
    static func dateOfBirth(_ dob: Date, now: Date, minimumAge: Int = RelayRules.standard.minimumAge, calendar: Calendar = .current) -> Result<Date, ValidationError> {
        if dob > now { return .failure(.invalid("Date of birth can't be in the future.")) }
        guard let age = calendar.dateComponents([.year], from: dob, to: now).year else {
            return .failure(.invalid("Enter a valid date of birth."))
        }
        if age > 120 { return .failure(.invalid("Enter a valid date of birth.")) }
        if age < minimumAge { return .failure(.invalid("You need to be \(minimumAge) or older to use PASS.")) }
        return .success(dob)
    }

    static func inviteCode(_ raw: String) -> Result<String, ValidationError> {
        guard let code = InviteCode.normalize(raw) else {
            return .failure(.invalid("That doesn't look like a PASS code. It looks like PASS-AB12."))
        }
        return .success(code)
    }

    static func emoji(_ raw: String) -> Result<String, ValidationError> {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard let first = s.first, s.count == 1 || (s.unicodeScalars.count <= 8 && first.unicodeScalars.first!.properties.isEmoji) else {
            return .failure(.invalid("Pick a single emoji."))
        }
        return .success(s)
    }

    private static func text(_ raw: String, field: String, range: ClosedRange<Int>) -> Result<String, ValidationError> {
        let n = normalized(raw)
        if n.isEmpty { return .failure(.required(field)) }
        if n.count < range.lowerBound { return .failure(.tooShort(field, range.lowerBound)) }
        if n.count > range.upperBound { return .failure(.tooLong(field, range.upperBound)) }
        return .success(n)
    }
}
