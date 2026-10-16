import Foundation
import Observation

/// Home = active relays (mine first) + my groups (spec §4). Refreshes on data changes and on pull-to-refresh.
@MainActor
@Observable
final class HomeViewModel {
    struct Content: Equatable {
        var relays: [Relay]
        var groups: [Group]
        func activeRelay(for group: Group) -> Relay? { relays.first { $0.groupID == group.id } }
    }

    private(set) var content: Loadable<Content> = .idle
    private let deps: AppDependencies
    private var loadGeneration = 0

    init(deps: AppDependencies) { self.deps = deps }

    var me: UserID? { deps.session.user?.id }

    func load(showLoading: Bool = true) async {
        loadGeneration += 1
        let generation = loadGeneration
        if showLoading, content.value == nil { content = .loading }
        do {
            async let relays = deps.relays.activeRelays()
            async let groups = deps.groups.groups()
            let (r, g) = try await (relays, groups)
            guard generation == loadGeneration else { return } // a newer load finished first; drop this result
            content = .loaded(Content(relays: sorted(r), groups: g))
        } catch {
            let e = AppError.wrap(error)
            guard generation == loadGeneration, !e.isCancellation else { return }
            if content.value == nil { content = .failed(e) } else { deps.router.showToast(e.userMessage) }
        }
    }

    /// Spec §4: relays where I hold the Baton first, then the rest, newest first.
    private func sorted(_ relays: [Relay]) -> [Relay] {
        guard let me else { return relays }
        return relays.sorted { a, b in
            let am = a.isHolder(me), bm = b.isHolder(me)
            if am != bm { return am }
            return a.createdAt > b.createdAt
        }
    }

    /// Listens for store changes for as long as the view is on screen (`.task` cancels it on disappear).
    func observeChanges() async {
        for await _ in deps.changes.changes() {
            guard !Task.isCancelled else { return }
            await load(showLoading: false)
        }
    }
}
