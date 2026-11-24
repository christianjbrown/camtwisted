import CamTwistCore
import Foundation

/// A key pressed in the app's window, with what was going on when it was.
public struct KeyPress: Equatable {
    /// Where the key is on the keyboard.
    public let keyCode: UInt16
    /// What the key types with no keys held down with it.
    public let characters: String
    public let modifiers: ShortcutModifiers
    /// Whether the key went into a text field.
    public let isTyping: Bool
    /// Whether a sheet over the window has the keys.
    public let isSheetUp: Bool

    public init(keyCode: UInt16, characters: String, modifiers: ShortcutModifiers, isTyping: Bool, isSheetUp: Bool) {
        self.keyCode = keyCode
        self.characters = characters
        self.modifiers = modifiers
        self.isTyping = isTyping
        self.isSheetUp = isSheetUp
    }
}

/// Something that may take a key pressed in the window.
@MainActor
public protocol KeyPressHandling {
    /// Whether it took the key, so nothing else sees it.
    func handle(_ press: KeyPress) -> Bool
}

/// Offers each key to one handler after another, until one takes it.
@MainActor
public struct KeyPressChain: KeyPressHandling {
    let handlers: [KeyPressHandling]

    public func handle(_ press: KeyPress) -> Bool {
        handlers.contains { $0.handle(press) }
    }
}

extension PictureModel: KeyPressHandling {
    public func handle(_ press: KeyPress) -> Bool {
        keyPressed(press.keyCode, isTyping: press.isTyping, isSheetUp: press.isSheetUp)
    }
}
