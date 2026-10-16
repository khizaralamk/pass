import CryptoKit
import Foundation
import Security

/// Nonce for Sign in with Apple: a random string whose SHA-256 goes on the request; the raw value goes to the backend,
/// which hashes it and compares it with the identity token's `nonce` claim.
enum AppleNonce {
    static func random(length: Int = 32) -> String {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        if status != errSecSuccess {
            // SecRandom practically never fails; fall back to the system generator rather than abort sign-in.
            bytes = (0..<length).map { _ in UInt8.random(in: 0...255) }
        }
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
