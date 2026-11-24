import Foundation

// What AppleScript's studio button commands do to the list of scenes. They
// work by name, and unlike the window they ignore which scene is on air.

extension StudioSettings {
    /// Removes every scene with this name.
    public mutating func removeButtons(named name: String) {
        buttons.removeAll { $0.name == name }
    }

    /// Adds a copy of the scene with this name at the end. Nothing happens when there is none.
    public mutating func appendDuplicate(ofButtonNamed name: String) {
        guard let button = button(named: name) else { return }
        buttons.append(button.duplicated())
    }
}
