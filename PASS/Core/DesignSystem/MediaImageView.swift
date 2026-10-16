import SwiftUI
import UIKit

/// Loads a locally stored media file off the main thread with a small cache. Used for avatars, fixture photos and
/// Reveal/History thumbnails. Never used before a Reveal for other members' submissions (spec §14).
struct MediaImageView<Placeholder: View>: View {
    let fileName: String?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: Placeholder
    @Environment(\.dependencies) private var deps
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .task(id: fileName) { await load() }
    }

    private func load() async {
        guard let fileName, let media = deps?.media else { image = nil; return }
        if let cached = ImageCache.shared.image(for: fileName) { image = cached; return }
        let url = media.url(for: fileName)
        let loaded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = try? Data(contentsOf: url), let img = UIImage(data: data) else { return nil }
            return img.preparingForDisplay() ?? img
        }.value
        guard !Task.isCancelled else { return }
        if let loaded { ImageCache.shared.store(loaded, for: fileName) }
        image = loaded
    }
}

final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private init() { cache.countLimit = 60 }
    func image(for key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    func store(_ image: UIImage, for key: String) { cache.setObject(image, forKey: key as NSString) }
    func remove(_ key: String) { cache.removeObject(forKey: key as NSString) }
}

/// Avatar that prefers the user's photo and falls back to initials.
struct UserAvatarView: View {
    let name: String
    let colorHex: String
    var avatarFileName: String? = nil
    var size: CGFloat = 44

    var body: some View {
        MediaImageView(fileName: avatarFileName) {
            AvatarView(initials: PassFormatters.initials(name), color: Color(hexString: colorHex), size: size)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// Live countdown to a deadline, recomputed every second from the app clock (never a stored remaining time).
struct CountdownText: View {
    let deadline: Date
    var short = false
    var font: Font = PassFont.outfit(12, .bold)
    var color: Color = PassColor.text(0.5)
    @Environment(\.dependencies) private var deps

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let remaining = deadline.timeIntervalSince(deps?.clock.now() ?? Date())
            Text(short ? PassFormatters.shortCountdown(remaining) : PassFormatters.countdown(remaining))
                .font(font)
                .monospacedDigit()
                .foregroundStyle(remaining < 15 * 60 ? PassColor.red : color)
                .accessibilityLabel(PassFormatters.spokenRemaining(remaining))
        }
    }
}
