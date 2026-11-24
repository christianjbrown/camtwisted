import CamTwistCore
import Foundation

/// What a key pressed while a scene waits for its shortcut comes to.
public enum ShortcutOutcome: Equatable {
    /// The key becomes the scene's shortcut.
    case record(SceneShortcut)
    /// The scene stops waiting, with its shortcut as it was.
    case cancel
    /// Not a shortcut: the scene keeps waiting.
    case ignore
}

/// Turns a key press into a scene's keyboard shortcut.
protocol ShortcutRecording {
    func outcome(of press: KeyPress) -> ShortcutOutcome
}

/// A shortcut has to be something nobody would press by accident while
/// typing: a key held with Command, Control or Option, or a function key.
/// Escape on its own gives up.
struct ShortcutRecorder: ShortcutRecording {
    // Where these keys are on a Mac keyboard: the system's virtual key codes.
    private static let escapeKeyCode: UInt16 = 53
    private static let functionKeyNames: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20",
    ]
    /// Keys that type nothing worth showing, with the symbols a Mac menu shows for them.
    private static let otherKeyNames: [UInt16: String] = [
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟", escapeKeyCode: "⎋",
    ]

    func outcome(of press: KeyPress) -> ShortcutOutcome {
        if press.keyCode == Self.escapeKeyCode, press.modifiers.isEmpty {
            return .cancel
        }
        if let name = Self.functionKeyNames[press.keyCode] {
            return .record(shortcut(press, key: name))
        }
        guard !press.modifiers.isDisjoint(with: .commanding),
              let name = Self.otherKeyNames[press.keyCode] ?? shown(press.characters)
        else { return .ignore }
        return .record(shortcut(press, key: name))
    }

    private func shortcut(_ press: KeyPress, key: String) -> SceneShortcut {
        SceneShortcut(keyCode: Int(press.keyCode), key: key, modifiers: press.modifiers)
    }

    /// What a key types, in capitals as a keyboard shows it, or nil when it types nothing.
    private func shown(_ characters: String) -> String? {
        let trimmed = characters.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.uppercased()
    }
}
