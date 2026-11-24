import CamTwistCore
import Foundation
import Observation

/// The scenes' keyboard shortcuts: listening for them from any app, and
/// recording a new one for the scene waiting for it.
@MainActor
@Observable
public final class ShortcutModel {
    /// The scene waiting for the next shortcut pressed to become its own.
    public var learningFor: UUID?

    /// The model owns this, so it is not held on to from here.
    @ObservationIgnored private unowned let state: KeyPlayedState
    @ObservationIgnored private let listener: ShortcutListening
    @ObservationIgnored private let recorder: ShortcutRecording
    /// The shortcuts the listener was last told about.
    @ObservationIgnored private var listenedFor: [SceneShortcut]?

    init(state: KeyPlayedState, listener: ShortcutListening, recorder: ShortcutRecording) {
        self.state = state
        self.listener = listener
        self.recorder = recorder
    }

    /// Starts listening for the scenes' shortcuts.
    func start() {
        listener.onPress = { [weak self] shortcut in self?.pressed(shortcut) }
        follow(state.studio)
    }

    /// A shortcut pressed in any app puts its scene on air, unless a scene
    /// is waiting for one, which then takes it.
    private func pressed(_ shortcut: SceneShortcut) {
        if let id = learningFor {
            learningFor = nil
            state.studio.assign(shortcut, to: id)
            return
        }
        if let scene = state.studio.button(forShortcut: shortcut) {
            state.goLive(withScene: scene.id)
        }
    }
}

extension ShortcutModel: KeyPressHandling {
    /// While a scene waits for its shortcut, every key goes to it, so none
    /// of them does its usual job by mistake.
    public func handle(_ press: KeyPress) -> Bool {
        guard learningFor != nil else { return false }
        switch recorder.outcome(of: press) {
        case let .record(shortcut): pressed(shortcut)
        case .cancel: learningFor = nil
        case .ignore: break
        }
        return true
    }
}

extension ShortcutModel: StudioFollowing {
    /// Listens for the shortcuts the scenes have now.
    func follow(_ studio: StudioSettings) {
        let shortcuts = studio.shortcuts
        guard shortcuts != listenedFor else { return }
        listenedFor = shortcuts
        listener.listen(for: shortcuts)
    }
}
