import CamTwistCore
import Foundation

/// Saves what stays with this Mac between launches: the global preferences.
/// Scenes and the rest of the settings live in setup files instead.
final class SavedState {
    private enum StorageKey {
        static let globals = "globalPreferences"
    }

    private let globalStore: CodableStore<GlobalPreferences>

    init(keyValueStore: KeyValueStore) {
        globalStore = CodableStore(
            store: keyValueStore, key: StorageKey.globals, fallback: GlobalPreferences(AppPreferences())
        )
    }

    func load() -> GlobalPreferences { globalStore.load() }
    func save(globals: GlobalPreferences) { globalStore.save(globals) }
}
