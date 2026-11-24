import XCTest
@testable import CamTwistControl

final class FileAccessKeeperTests: XCTestCase {
    private final class Bookmarks: BookmarkHandling {
        /// Paths the system will give a bookmark for.
        var grantable: Set<String> = []
        /// Bookmarks that still work.
        var working: Set<Data> = []
        private(set) var resumed: [Data] = []

        func bookmark(forPath path: String) -> Data? {
            grantable.contains(path) ? Data(path.utf8) : nil
        }

        func resume(_ bookmark: Data) -> Bool {
            resumed.append(bookmark)
            return working.contains(bookmark)
        }
    }

    private final class Store: BookmarkStoring {
        var bookmarks: [String: Data] = [:]
    }

    private final class Access: FileAccessKeeping {
        private(set) var remembered: [[String]] = []
        func remember(_ paths: [String]) { remembered.append(paths) }
        func restore() {}
    }

    private final class Scene: FileAdding {
        private(set) var added: [[String]] = []
        func addFiles(_ paths: [String]) { added.append(paths) }
    }

    func testWhatIsChosenIsKeptBesideWhatWasKeptBefore() {
        let bookmarks = Bookmarks()
        bookmarks.grantable = ["/new.png"]
        let store = Store()
        store.bookmarks = ["/old.png": Data("old".utf8)]
        let keeper = FileAccessKeeper(handler: bookmarks, store: store)

        keeper.remember(["/new.png", "/refused.png"])

        XCTAssertEqual(store.bookmarks, ["/old.png": Data("old".utf8), "/new.png": Data("/new.png".utf8)])
    }

    func testABookmarkThatNoLongerWorksIsDroppedAtLaunch() {
        let bookmarks = Bookmarks()
        bookmarks.working = [Data("good".utf8)]
        let store = Store()
        store.bookmarks = ["/kept.png": Data("good".utf8), "/gone.png": Data("stale".utf8)]
        let keeper = FileAccessKeeper(handler: bookmarks, store: store)

        keeper.restore()

        XCTAssertEqual(store.bookmarks, ["/kept.png": Data("good".utf8)])
        XCTAssertEqual(Set(bookmarks.resumed), [Data("good".utf8), Data("stale".utf8)])
    }

    @MainActor
    func testDroppedFilesAreRememberedThenAdded() {
        let access = Access()
        let scene = Scene()
        let receiver = FileDropReceiver(access: access, scene: scene)

        receiver.receive(["/a.png", "/b.mov"])

        XCTAssertEqual(access.remembered, [["/a.png", "/b.mov"]])
        XCTAssertEqual(scene.added, [["/a.png", "/b.mov"]])
    }

    @MainActor
    func testADropAfterTheSceneHasGoneIsStillRemembered() {
        let access = Access()
        var scene: Scene? = Scene()
        let receiver = FileDropReceiver(access: access, scene: scene!)
        scene = nil

        receiver.receive(["/a.png"])

        XCTAssertEqual(access.remembered, [["/a.png"]])
    }
}
