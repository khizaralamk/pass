import Foundation
import Observation
import SwiftUI

/// Every pushed screen in the main stack. Payloads are IDs (and small values), never whole models, so a route is cheap
/// to hash and safe to restore.
enum Route: Hashable {
    case profile
    case groupDetail(GroupID)
    case groupMembers(GroupID)
    case groupHistory(GroupID)
    case createGroupName
    case createGroupInvite(GroupID)
    case groupCreated(GroupID)
    case newRelayGroup(preselected: GroupID?)
    case newRelayChallenge(GroupID)
    case newRelayReview(GroupID, challenge: String)
    case baton(RelayID)
    case passBaton(RelayID)
    case progress(RelayID)
    case relayComplete(RelayID)
    case postReveal(RelayID)
    case notificationSettings
    case privacySettings
    case about
    case support
    case inviteCodeEntry
}

enum FullScreenRoute: Identifiable, Hashable {
    case capture(RelayID)
    case reveal(RelayID)
    case invite(code: String)

    var id: String {
        switch self {
        case .capture(let r): return "capture-\(r.raw)"
        case .reveal(let r): return "reveal-\(r.raw)"
        case .invite(let c): return "invite-\(c)"
        }
    }
}

enum DeepLink: Equatable {
    case invite(code: String)

    /// Accepts `pass://i/CODE`, `pass://invite?code=CODE`, `https://<host>/i/CODE`. Anything else is ignored.
    static func parse(_ url: URL, configuration: AppConfiguration) -> DeepLink? {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = url.pathComponents.filter { $0 != "/" }
        let host = url.host?.lowercased()
        if url.scheme?.lowercased() == configuration.urlScheme {
            if host == "i", let code = path.first.flatMap(InviteCode.normalize) { return .invite(code: code) }
            if host == "invite", let raw = comps?.queryItems?.first(where: { $0.name == "code" })?.value,
               let code = InviteCode.normalize(raw) { return .invite(code: code) }
            return nil
        }
        if url.scheme?.lowercased() == "https", host == configuration.inviteLinkBase.host?.lowercased(),
           path.first == "i", path.count >= 2, let code = InviteCode.normalize(path[1]) {
            return .invite(code: code)
        }
        return nil
    }
}

/// Owns navigation state for the signed-in shell. Deep links and notification taps resolve here into routes.
@MainActor
@Observable
final class AppRouter {
    var path: [Route] = []
    var fullScreen: FullScreenRoute?
    var toast: ToastMessage?
    /// Set by the session shell when a link arrives before the user is signed in.
    var deferredInviteCode: String?

    private let configuration: AppConfiguration
    @ObservationIgnored var relayResolver: ((RelayID) async throws -> Relay)?
    @ObservationIgnored var currentUserID: (() -> UserID?)?
    @ObservationIgnored private var openTask: Task<Void, Never>?

    init(configuration: AppConfiguration) { self.configuration = configuration }

    func push(_ route: Route) { path.append(route) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path.removeAll() }
    func replaceStack(with routes: [Route]) { path = routes }

    func showToast(_ text: String, emoji: String? = nil) { toast = ToastMessage(text: text, emoji: emoji) }

    /// Returns true when the URL was recognised. Unknown links are ignored (never trusted).
    @discardableResult
    func handle(url: URL, isSignedIn: Bool) -> Bool {
        guard let link = DeepLink.parse(url, configuration: configuration) else { return false }
        switch link {
        case .invite(let code):
            if isSignedIn { fullScreen = .invite(code: code) } else { deferredInviteCode = code }
        }
        return true
    }

    /// Payload from a notification: `{"relayId": "<id>"}`. Opens the right screen for that relay (spec §15).
    func handle(notificationUserInfo info: [AnyHashable: Any]) {
        guard let raw = info["relayId"] as? String, !raw.isEmpty else { return }
        openRelay(RelayID(raw))
    }

    /// Chooses Baton / Progress / Complete based on who holds the Baton and whether the relay has ended.
    func openRelay(_ id: RelayID) {
        openTask?.cancel()
        openTask = Task { [weak self] in
            guard let self, let resolver = self.relayResolver else { return }
            do {
                let relay = try await resolver(id)
                guard !Task.isCancelled else { return }
                self.show(relay: relay)
            } catch {
                self.showToast("That Relay isn't available anymore.")
            }
        }
    }

    func show(relay: Relay) {
        fullScreen = nil
        let me = currentUserID?()
        let route: Route
        switch relay.status {
        case .active:
            if let me, relay.isHolder(me) {
                route = relay.hasSubmitted(me) ? .passBaton(relay.id) : .baton(relay.id)
            } else {
                route = .progress(relay.id)
            }
        case .complete, .failed, .cancelled:
            route = relay.hasReveal ? .relayComplete(relay.id) : .progress(relay.id)
        }
        replaceStack(with: [route])
    }
}
