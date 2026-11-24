import CamTwistCore
import Foundation

// What a scene's bar in the Input pane shows and does, decided here so the
// view only draws it.

/// How a scene in the list is placed: on air or not, open or folded.
public struct SceneBarState: Equatable {
    public let isOnAir: Bool
    public let isOpen: Bool
    public let isPeeked: Bool

    /// - Parameters:
    ///   - isOnAirFolded: whether the scene on air has been folded away.
    ///   - peekedID: the folded scene being looked at in the preview.
    public init(
        sceneID: UUID, onAirID: UUID?, isEditingOnAir: Bool, isOnAirFolded: Bool, editedSceneID: UUID?, peekedID: UUID?
    ) {
        isOnAir = onAirID == sceneID
        isOpen = isOnAir ? isEditingOnAir && !isOnAirFolded : editedSceneID == sceneID
        isPeeked = peekedID == sceneID && !isOpen && !isOnAir
    }
}

/// The words, and which buttons, on a scene's bar.
public struct SceneBarContent: Equatable {
    public let foldHelp: String
    public let showsPeek: Bool
    public let peekHelp: String
    public let showsGoLive: Bool
    public let goLiveTitle: String
    public let lockHelp: String
    public let removalHelp: String
    public let canRemove: Bool
    public let showsSummary: Bool
    public let summary: String

    public init(scene: StudioButton, state: SceneBarState, isTransitioning: Bool) {
        foldHelp = state.isOpen ? "Fold away" : "Open to change it"
        showsPeek = !state.isOnAir && !state.isOpen
        peekHelp = state.isPeeked ? "Stop looking" : "Look at it live without opening it"
        showsGoLive = !state.isOnAir
        goLiveTitle = isTransitioning ? "Switching" : "Go live"
        lockHelp = scene.isLocked ? "Unlock, so it can be changed or removed" : "Lock, so nothing in it can be changed"
        if scene.isLocked {
            removalHelp = "Unlock it first to remove it"
        } else {
            removalHelp = state.isOnAir ? "The scene on air cannot be removed" : "Remove"
        }
        canRemove = !state.isOnAir && !scene.isLocked
        showsSummary = !state.isOnAir && !state.isOpen
        summary = Self.summary(of: scene.scene)
    }

    /// The sources in a folded scene, to tell it by.
    static func summary(of scene: SceneConfiguration) -> String {
        scene.items.compactMap { item in
            if case .source(let spec) = item.content { return spec.title }
            return nil
        }
        .joined(separator: ", ")
    }
}

/// What to do when a scene's chevron is pressed.
public struct SceneFolding: Equatable {
    /// Which scene is open for changing afterwards: nil closes whichever was open.
    public enum Edit: Equatable {
        case leaveAlone
        case closeAll
        case open
    }

    public let isOnAirFolded: Bool
    public let edit: Edit
    /// Whether the list of sources to add opens, which it does for a scene with nothing in it.
    public let opensSourcePicker: Bool

    public init(isOnAir: Bool, isOpen: Bool, isEditingOnAir: Bool, isOnAirFolded: Bool, isEmpty: Bool) {
        if isOnAir {
            // Opening the scene on air closes whichever other was open.
            if isEditingOnAir {
                self.isOnAirFolded = !isOnAirFolded
                edit = .leaveAlone
            } else {
                self.isOnAirFolded = false
                edit = .closeAll
            }
            opensSourcePicker = false
        } else if isOpen {
            self.isOnAirFolded = true
            edit = .closeAll
            opensSourcePicker = false
        } else {
            self.isOnAirFolded = isOnAirFolded
            edit = .open
            opensSourcePicker = isEmpty
        }
    }
}

/// Which list of things to add starts open on a fresh start.
public enum StartingPicker: Equatable {
    case none
    case sources
    case effects

    /// Effects when the scene has its camera already, sources when not.
    public static func choose(
        startsAfresh: Bool, opensPicker: Bool, showsEffects: Bool, isOnAir: Bool, hasCamera: Bool
    ) -> StartingPicker {
        guard startsAfresh || opensPicker || showsEffects, isOnAir else { return .none }
        return showsEffects || (hasCamera && !opensPicker) ? .effects : .sources
    }
}

/// The words of a MIDI key row.
public struct MIDIKeyRow: Equatable {
    public let title: String
    public let buttonTitle: String
    public let showsClear: Bool

    public init(note: Int?, isLearning: Bool) {
        title = note.map { "MIDI key: \($0)" } ?? "No MIDI key"
        buttonTitle = isLearning ? "Play a key" : "Record MIDI key"
        showsClear = note != nil
    }

    /// Which scene is being taught a key after the button is pressed.
    public static func learning(after press: UUID, current: UUID?) -> UUID? {
        KeyLearning.learning(after: press, current: current)
    }
}

/// Which scene waits for a key: the one whose button was pressed, or none
/// when it was already waiting and the press calls it off.
public enum KeyLearning {
    public static func learning(after press: UUID, current: UUID?) -> UUID? {
        current == press ? nil : press
    }
}

/// The words of a keyboard shortcut row.
public struct ShortcutKeyRow: Equatable {
    public let title: String
    public let buttonTitle: String
    public let showsClear: Bool

    public init(shortcut: SceneShortcut?, isLearning: Bool) {
        title = shortcut.map { "Keyboard shortcut: \($0.title)" } ?? "No keyboard shortcut"
        buttonTitle = isLearning ? "Press keys" : "Record shortcut"
        showsClear = shortcut != nil
    }

    /// What the row says while it waits, to say what counts as a shortcut.
    public static let learningHelp =
        "Press a key with Command, Control or Option, or a function key. Escape stops waiting."
}

/// The choices for which scene a scene hands over to by itself.
public struct HandoverChoices: Equatable {
    /// Every other scene, which is all a scene can hand over to.
    public let scenes: [StudioButton]
    /// The scene chosen, or nil when the scene stays on air.
    public let chosen: UUID?

    public init(for scene: StudioButton, among all: [StudioButton]) {
        scenes = all.filter { $0.id != scene.id }
        let target = scene.handover?.sceneID
        chosen = scenes.contains { $0.id == target } ? target : nil
    }

    /// The handover once a scene is picked, keeping the time already set.
    /// Picking none means staying on air.
    public static func picking(_ id: UUID?, current: SceneHandover?) -> SceneHandover? {
        id.map { SceneHandover(sceneID: $0, seconds: current?.seconds ?? SceneHandover.defaultSeconds) }
    }
}

/// Picks the picture on a transition's panel.
public enum TransitionPanel {
    private static let cutSymbol = "scissors"
    private static let transitionSymbol = "rectangle.2.swap"
    /// The symbol on the panel that leaves each scene to come on air its own way.
    public static let scenesOwnSymbol = "rectangle.stack"

    /// The name of the symbol shown when a transition has no thumbnail.
    public static func fallbackSymbol(for name: String) -> String {
        name == StudioSettings.cutName ? cutSymbol : transitionSymbol
    }
}
