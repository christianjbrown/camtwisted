import CamTwistCore
import Foundation
import Observation

/// The MIDI keys: the last note played, and the scene waiting to learn one.
@MainActor
@Observable
public final class MIDIModel {
    public private(set) var lastNote: Int?
    /// The scene waiting for the next MIDI note to become its key.
    public var learningFor: UUID?

    /// The model owns this, so it is not held on to from here.
    private unowned let state: KeyPlayedState
    private let listener: MIDINoteListening
    private let learner: MIDIKeyAssigning
    private nonisolated let queue: WorkQueueing

    init(state: KeyPlayedState, listener: MIDINoteListening, learner: MIDIKeyAssigning, queue: WorkQueueing) {
        self.state = state
        self.listener = listener
        self.learner = learner
        self.queue = queue
    }

    /// Starts listening for notes.
    func start() {
        let queue = self.queue
        listener.onNote = { [weak self] note in
            queue.main { self?.received(note: note) }
        }
        listener.start()
    }

    private func received(note: Int) {
        lastNote = note
        if let id = learningFor {
            learningFor = nil
            learner.assign(note: note, to: id, studio: &state.studio)
            return
        }
        // A scene's key puts that scene on air.
        if let button = state.studio.button(forMIDINote: note) {
            state.goLive(withScene: button.id)
        }
    }
}
