import CamTwistCore
import Foundation

/// Keeps the app's permission to read the files and folders somebody has
/// chosen, from one launch to the next.
public protocol FileAccessKeeping {
    /// Remembers files or folders just chosen in a panel or dropped on the window.
    func remember(_ paths: [String])
    /// Takes up again every permission kept, at launch.
    func restore()
}

/// Makes the system's bookmarks, which are what carry a permission across
/// launches, and takes one up again.
public protocol BookmarkHandling {
    /// A bookmark for the file at a path, or nil when the system will not give one.
    func bookmark(forPath path: String) -> Data?
    /// Takes up the permission a bookmark holds. False when it no longer works.
    func resume(_ bookmark: Data) -> Bool
}

/// Where the bookmarks are kept between launches, by path.
public protocol BookmarkStoring: AnyObject {
    var bookmarks: [String: Data] { get set }
}

/// Keeps a bookmark for everything chosen and, at launch, takes each up
/// again. A sandboxed app may only read what it has been handed, and only
/// until it quits, unless it keeps a bookmark.
public final class FileAccessKeeper: FileAccessKeeping {
    private let handler: BookmarkHandling
    private let store: BookmarkStoring

    public init(handler: BookmarkHandling, store: BookmarkStoring) {
        self.handler = handler
        self.store = store
    }

    public func remember(_ paths: [String]) {
        var kept = store.bookmarks
        for path in paths {
            if let bookmark = handler.bookmark(forPath: path) {
                kept[path] = bookmark
            }
        }
        store.bookmarks = kept
    }

    /// One whose file has gone, or that no longer works, is dropped.
    public func restore() {
        store.bookmarks = store.bookmarks.filter { handler.resume($0.value) }
    }
}

/// Something files dropped on the picture can be added to.
@MainActor
public protocol FileAdding: AnyObject {
    func addFiles(_ paths: [String])
}

/// Takes files dropped on the picture: keeps the permission to read them,
/// then adds them to the scene.
public protocol FileDropReceiving: Sendable {
    @MainActor func receive(_ paths: [String])
}

@MainActor
public struct FileDropReceiver: FileDropReceiving {
    private let access: FileAccessKeeping
    private weak var scene: FileAdding?

    public init(access: FileAccessKeeping, scene: FileAdding) {
        self.access = access
        self.scene = scene
    }

    public func receive(_ paths: [String]) {
        access.remember(paths)
        scene?.addFiles(paths)
    }
}
