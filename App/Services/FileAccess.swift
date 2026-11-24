import CamTwistControl
import Foundation

/// The system's security-scoped bookmarks, which carry a sandboxed app's
/// permission to read a file from one launch to the next.
struct SecurityScopedBookmarks: BookmarkHandling {
    func bookmark(forPath path: String) -> Data? {
        try? URL(fileURLWithPath: path).bookmarkData(options: .withSecurityScope)
    }

    func resume(_ bookmark: Data) -> Bool {
        var isStale = false
        let url = try? URL(
            resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale
        )
        guard let url, !isStale else { return false }
        return url.startAccessingSecurityScopedResource()
    }
}

/// Keeps the bookmarks in the app's defaults, by path.
final class DefaultsBookmarkStore: BookmarkStoring {
    private static let storageKey = "FileAccessBookmarks"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var bookmarks: [String: Data] {
        get { defaults.dictionary(forKey: Self.storageKey) as? [String: Data] ?? [:] }
        set { defaults.set(newValue, forKey: Self.storageKey) }
    }
}
