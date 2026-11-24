import Foundation

/// A studio button: a scene ready to go on air at a click.
public struct StudioButton: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var scene: SceneConfiguration
    public var midiNote: Int?
    /// A small picture of the look, as PNG data, to recognise it by.
    public var thumbnail: Data?
    /// How this scene comes on air. Nil means at once, with a cut.
    public var transitionName: String?
    /// Seconds its transition takes. Nil means the usual time.
    public var transitionTime: Double?
    /// Whether the scene is locked against changes. Optional so scenes
    /// saved before it existed still load.
    public var locked: Bool?
    /// The keyboard shortcut that puts this scene on air, if it has one.
    public var shortcut: SceneShortcut?
    /// The scene that takes over by itself after this one has been on air
    /// a while. Nil means it stays on air until somebody changes it.
    public var handover: SceneHandover?

    /// A locked scene cannot be changed or removed until it is unlocked.
    public var isLocked: Bool {
        get { locked ?? false }
        set { locked = newValue }
    }

    public init(
        id: UUID = UUID(), name: String, scene: SceneConfiguration, midiNote: Int? = nil, thumbnail: Data? = nil,
        transitionName: String? = nil, transitionTime: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.scene = scene
        self.midiNote = midiNote
        self.thumbnail = thumbnail
        self.transitionName = transitionName
        self.transitionTime = transitionTime
    }

    /// The transition this scene comes on air with: a cut unless one is chosen.
    public var switchName: String {
        get { transitionName ?? StudioSettings.cutName }
        set { transitionName = newValue }
    }

    public var switchTime: Double {
        get { transitionTime ?? StudioSettings.defaultTransitionTime }
        set { transitionTime = newValue }
    }

    /// Whether this scene appears at once rather than through a transition.
    public var cutsInstantly: Bool { switchName == StudioSettings.cutName }

    /// A copy under a new identity and a name that says so. Keys stay with
    /// the original, since one key can only put one scene on air.
    public func duplicated() -> StudioButton {
        var copy = StudioButton(
            name: name + Self.copySuffix, scene: scene, midiNote: nil, thumbnail: thumbnail,
            transitionName: transitionName, transitionTime: transitionTime
        )
        copy.handover = handover
        return copy
    }

    private static let copySuffix = " copy"
}

/// The studio's settings and buttons.
public struct StudioSettings: Codable, Equatable, Sendable {
    public static let defaultTransitionName = "Dissolve"
    /// The transition that is no transition: the new look appears at once.
    public static let cutName = "Cut"
    public static let defaultTransitionTime = 1.0
    public static let transitionTimeRange: ClosedRange<Double> = 0.1...10

    public var buttons: [StudioButton]
    public var transitionName: String
    public var transitionTime: Double
    /// After a cut or transition, the old program becomes the preview.
    public var swapMode: Bool
    /// Which of the scenes is on air. Nil until one has been.
    public var onAirID: UUID?
    /// The transition the studio switches with in place of each scene's
    /// own, for its time. Nil means each scene comes on air its own way.
    public var chosenTransition: String?

    public init(
        buttons: [StudioButton] = [],
        transitionName: String = StudioSettings.defaultTransitionName,
        transitionTime: Double = StudioSettings.defaultTransitionTime,
        swapMode: Bool = false,
        onAirID: UUID? = nil
    ) {
        self.buttons = buttons
        self.transitionName = transitionName
        self.transitionTime = transitionTime
        self.swapMode = swapMode
        self.onAirID = onAirID
    }

    // MARK: Scenes

    private static func sceneName(_ number: Int) -> String { "Scene \(number)" }

    /// The name a new scene gets: "Scene" and the first number not in use.
    public var nextSceneName: String {
        let taken = Set(buttons.map(\.name))
        var number = buttons.count + 1
        while taken.contains(Self.sceneName(number)) {
            number += 1
        }
        return Self.sceneName(number)
    }

    /// The scene that is on air.
    public var sceneOnAir: StudioButton? {
        buttons.first { $0.id == onAirID }
    }

    /// Records what is on air. The scene on air takes it as its own; with
    /// none marked, a scene already showing exactly that is the one, and
    /// failing that it becomes a new scene at the top of the list.
    public mutating func adoptProgram(_ program: SceneConfiguration) {
        if let index = buttons.firstIndex(where: { $0.id == onAirID }) {
            buttons[index].scene = program
        } else if let showing = button(showing: program) {
            onAirID = showing.id
        } else {
            let scene = StudioButton(name: nextSceneName, scene: program)
            buttons.insert(scene, at: 0)
            onAirID = scene.id
        }
    }

    /// Marks the scene showing a program as the one on air, when one is.
    /// The scene already on air keeps its place when it shows it too.
    public mutating func markOnAir(showing program: SceneConfiguration) {
        guard sceneOnAir?.scene != program, let showing = button(showing: program) else { return }
        onAirID = showing.id
    }

    /// Adds a scene at the end, under the next free name.
    @discardableResult
    public mutating func addScene(_ scene: SceneConfiguration) -> UUID {
        let added = StudioButton(name: nextSceneName, scene: scene)
        buttons.append(added)
        return added.id
    }

    /// Adds a copy of a scene straight after it.
    @discardableResult
    public mutating func duplicateScene(id: UUID) -> UUID? {
        guard let index = buttons.firstIndex(where: { $0.id == id }) else { return nil }
        let copy = buttons[index].duplicated()
        buttons.insert(copy, at: index + 1)
        return copy.id
    }

    /// Moves a scene to where another is, the rest closing up behind it.
    public mutating func moveScene(id: UUID, toPositionOf target: UUID) {
        guard id != target, let from = buttons.firstIndex(where: { $0.id == id }),
              let to = buttons.firstIndex(where: { $0.id == target })
        else { return }
        buttons.insert(buttons.remove(at: from), at: to)
    }

    /// Removes a scene, unless it is the one on air.
    public mutating func removeScene(id: UUID) {
        // Neither the scene on air nor a locked one can be removed.
        guard id != onAirID, buttons.first(where: { $0.id == id })?.isLocked != true else { return }
        buttons.removeAll { $0.id == id }
        // A scene that handed over to it now stays on air instead.
        for index in buttons.indices where buttons[index].handover?.sceneID == id {
            buttons[index].handover = nil
        }
    }

    public func button(named name: String) -> StudioButton? {
        buttons.first { $0.name == name }
    }

    public func button(forMIDINote note: Int) -> StudioButton? {
        buttons.first { $0.midiNote == note }
    }

    public func button(forShortcut shortcut: SceneShortcut) -> StudioButton? {
        buttons.first { $0.shortcut == shortcut }
    }

    /// Every scene's keyboard shortcut.
    public var shortcuts: [SceneShortcut] {
        buttons.compactMap(\.shortcut)
    }

    /// Gives a scene a keyboard shortcut, taking it from any other scene
    /// that had it, since one shortcut can only put one scene on air.
    public mutating func assign(_ shortcut: SceneShortcut, to id: UUID) {
        guard let target = buttons.firstIndex(where: { $0.id == id }) else { return }
        for index in buttons.indices where buttons[index].shortcut == shortcut {
            buttons[index].shortcut = nil
        }
        buttons[target].shortcut = shortcut
    }

    /// The button whose look is exactly what is on air, if any is.
    public func button(showing scene: SceneConfiguration) -> StudioButton? {
        buttons.first { $0.scene == scene }
    }

    /// Whether switching looks is instant rather than a transition.
    public var cutsInstantly: Bool { transitionName == Self.cutName }

    /// Has the studio switch with one transition, whatever each scene asks
    /// for. It is also the one for a preview that is no saved scene.
    public mutating func choose(transition name: String) {
        transitionName = name
        chosenTransition = name
    }

    /// How the studio puts a preview on air: with the transition chosen
    /// in the studio, or else the way its scene comes on air, or else, for
    /// a preview that is no saved scene, with the studio's usual one.
    public func studioSwitch(to scene: StudioButton?) -> StudioSwitch {
        if let chosenTransition {
            return StudioSwitch(name: chosenTransition, duration: transitionTime)
        }
        guard let scene else { return StudioSwitch(name: transitionName, duration: transitionTime) }
        return StudioSwitch(name: scene.switchName, duration: scene.switchTime)
    }
}

/// A transition and how long it takes.
public struct StudioSwitch: Equatable, Sendable {
    public let name: String
    public let duration: Double

    public init(name: String, duration: Double) {
        self.name = name
        self.duration = duration
    }

    /// Whether the new scene appears at once rather than through a transition.
    public var cutsInstantly: Bool { name == StudioSettings.cutName }
}

/// What is on air and what is lined up next.
public struct StudioBus: Equatable, Sendable {
    public var program: SceneConfiguration
    public var preview: SceneConfiguration?

    public init(program: SceneConfiguration, preview: SceneConfiguration? = nil) {
        self.program = program
        self.preview = preview
    }

    /// Puts the preview on air. In swap mode the old program takes its place
    /// in preview; otherwise the preview stays lined up.
    public func cutting(swapMode: Bool) -> StudioBus {
        guard let preview else { return self }
        return StudioBus(program: preview, preview: swapMode ? program : preview)
    }

    /// The same result as a cut, reached once a transition has landed on `target`.
    public func landing(on target: SceneConfiguration, swapMode: Bool) -> StudioBus {
        StudioBus(program: target, preview: swapMode ? program : preview)
    }
}
