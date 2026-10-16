import Foundation

/// Group codes look like `PASS-FN74` (Figma). Letters exclude I/O and digits exclude 0/1 to avoid confusion when read aloud.
enum InviteCode {
    static let prefix = "PASS-"
    static let alphabet: [Character] = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static let bodyLength = 4

    static func generate<G: RandomNumberGenerator>(using generator: inout G) -> String {
        prefix + String((0..<bodyLength).map { _ in alphabet.randomElement(using: &generator)! })
    }

    static func generate() -> String {
        var g = SystemRandomNumberGenerator()
        return generate(using: &g)
    }

    /// Accepts "pass-fn74", " PASS FN74 ", "FN74" or a full invite link and returns the canonical code, or nil.
    static func normalize(_ input: String) -> String? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let url = URL(string: s.lowercased()), url.scheme != nil, let last = url.pathComponents.last, last != "/" {
            s = last.uppercased()
        }
        s = s.replacingOccurrences(of: " ", with: "")
        if s.hasPrefix("PASS-") { s.removeFirst(5) } else if s.hasPrefix("PASS") { s.removeFirst(4) }
        guard s.count == bodyLength, s.allSatisfy({ alphabet.contains($0) }) else { return nil }
        return prefix + s
    }
}
