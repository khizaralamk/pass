import Foundation

/// Central, read-only app configuration. Nothing here is a secret: everything in an app bundle can be inspected
/// (the Supabase anon key is a public key; row-level security is the boundary).
/// Backend values come from `Config/*.xcconfig` → `Config/Info.plist` (`PASS_SUPABASE_URL`, `PASS_SUPABASE_ANON_KEY`).
/// When both are empty the app runs against the in-app mock; see Documentation/02-BACKEND-INTEGRATION.md.
struct AppConfiguration: Sendable {
    enum Environment: String, Sendable { case debug, release }

    /// Which data layer `AppDependencies.live()` builds. `.mock` is the default and what every test runs against.
    enum Backend: Sendable, Equatable {
        case mock
        case supabase(url: URL, anonKey: String)

        var isRemote: Bool { if case .supabase = self { return true } else { return false } }

        /// Reads the Info.plist keys. Empty or missing values keep the mock; a value without a scheme gets `https://`
        /// (xcconfig treats `//` as a comment, so the URL is often written without it).
        static func fromInfoPlist(_ bundle: Bundle = .main) -> Backend {
            let rawURL = (bundle.object(forInfoDictionaryKey: "PASS_SUPABASE_URL") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let key = (bundle.object(forInfoDictionaryKey: "PASS_SUPABASE_ANON_KEY") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !rawURL.isEmpty, !key.isEmpty else { return .mock }
            let withScheme = rawURL.contains("://") ? rawURL : "https://" + rawURL
            guard let url = URL(string: withScheme), url.host != nil else { return .mock }
            return .supabase(url: url, anonKey: key)
        }
    }

    let environment: Environment
    let backend: Backend
    /// Base for shareable invite links: `<inviteLinkBase>/<CODE>`. Placeholder domain until Luis provides one.
    let inviteLinkBase: URL
    /// Custom URL scheme handled by the app: `pass://i/<CODE>`.
    let urlScheme: String
    let supportEmail: String
    let privacyPolicyURL: URL
    let termsURL: URL
    /// DEBUG-only controls that drive the mock backend (simulate other members, advance timers). Compiled out of Release.
    let demoControlsEnabled: Bool
    let rules: RelayRules

    static let current: AppConfiguration = {
        #if DEBUG
        let env = Environment.debug
        let demo = true
        #else
        let env = Environment.release
        let demo = false
        #endif
        return AppConfiguration(
            environment: env,
            backend: Backend.fromInfoPlist(),
            inviteLinkBase: URL(string: "https://pass-app.example/i")!,
            urlScheme: "pass",
            supportEmail: "support@pass-app.example",
            privacyPolicyURL: URL(string: "https://pass-app.example/privacy")!,
            termsURL: URL(string: "https://pass-app.example/terms")!,
            demoControlsEnabled: demo,
            rules: .standard)
    }()

    /// Fails fast in development if a required value is malformed. Called once at launch.
    func validate() -> [String] {
        var problems: [String] = []
        if inviteLinkBase.scheme != "https" { problems.append("inviteLinkBase must be https") }
        if urlScheme.isEmpty { problems.append("urlScheme is empty") }
        if !supportEmail.contains("@") { problems.append("supportEmail is not an email address") }
        if case .supabase(let url, let key) = backend {
            if url.scheme != "https" && url.host != "localhost" && url.host != "127.0.0.1" { problems.append("Supabase URL must be https") }
            if key.count < 20 { problems.append("Supabase anon key looks truncated") }
        }
        return problems
    }

    func inviteLink(for code: String) -> URL {
        inviteLinkBase.appending(path: code)
    }
}
