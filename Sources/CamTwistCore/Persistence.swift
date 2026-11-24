import Foundation

/// Saves and restores one value between launches.
public final class CodableStore<Value: Codable> {
    private let store: KeyValueStore
    private let key: String
    private let fallback: () -> Value

    public init(store: KeyValueStore, key: String, fallback: @escaping @autoclosure () -> Value) {
        self.store = store
        self.key = key
        self.fallback = fallback
    }

    /// The saved value, or the fallback when nothing readable is saved.
    public func load() -> Value {
        guard let data = store.data(forKey: key), let value = try? JSONDecoder().decode(Value.self, from: data)
        else { return fallback() }
        return value
    }

    public func save(_ value: Value) {
        store.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
