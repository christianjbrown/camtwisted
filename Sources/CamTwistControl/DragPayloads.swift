import CamTwistCore
import Foundation

// Text the system's drag and drop carries between lists in the window.

/// A step being dragged from the picker into the chain.
public enum StepPayload {
    private static let prefix = "camtwisted-step:"

    public static func text(for content: ChainItem.Content) -> String {
        let json = (try? JSONEncoder().encode(content)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return prefix + json
    }

    public static func content(from text: String) -> ChainItem.Content? {
        guard text.hasPrefix(prefix), let data = text.dropFirst(prefix.count).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ChainItem.Content.self, from: data)
    }
}

/// A scene being dragged to a new place in the list. The prefix marks it
/// apart from a dragged step.
public enum ScenePayload {
    private static let prefix = "camtwisted-scene:"

    public static func text(for id: UUID) -> String {
        prefix + id.uuidString
    }

    public static func id(from text: String) -> UUID? {
        guard text.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(text.dropFirst(prefix.count)))
    }
}
