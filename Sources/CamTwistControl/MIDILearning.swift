import CamTwistCore
import Foundation

/// Gives the next MIDI note to the scene that is waiting for one.
struct MIDILearner {
    func assign(note: Int, to id: UUID, studio: inout StudioSettings) {
        if let index = studio.buttons.firstIndex(where: { $0.id == id }) {
            studio.buttons[index].midiNote = note
        }
    }
}
