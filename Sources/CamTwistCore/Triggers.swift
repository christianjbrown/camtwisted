import Foundation

/// Something the app can be told to do from a menu, a MIDI note or a script.
public enum TriggerAction: Codable, Equatable, Sendable {
    case clearScene
    case studioPreview(button: String)
    case studioPunch(button: String)
    case studioTransition
    case studioCut
    case studioClear
    case runAppleScript(String)
}
