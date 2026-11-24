import AppKit
import CamTwistControl
import CamTwistCore
import SwiftUI

/// Watches the keyboard on behalf of the window: a scene waiting for its
/// shortcut, and the picture.
protocol PictureKeyWatching {
    @MainActor func start(for keys: KeyPressHandling)
    @MainActor func stop()
}

/// Hands each key pressed in the window to whatever takes keys. What each
/// key means is their business; this listens and passes it on.
@MainActor
final class PictureKeyWatcher: PictureKeyWatching {
    private var monitor: Any?

    func start(for keys: KeyPressHandling) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let press = KeyPress(
                keyCode: event.keyCode, characters: event.charactersIgnoringModifiers ?? "",
                modifiers: ShortcutModifiers(event.modifierFlags),
                isTyping: event.window?.firstResponder is NSText,
                isSheetUp: event.window?.isSheet == true || event.window?.attachedSheet != nil
            )
            return MainActor.assumeIsolated { keys.handle(press) } ? nil : event
        }
    }

    func stop() {
        monitor.map(NSEvent.removeMonitor)
        monitor = nil
    }
}

/// Watches nothing. It is what a view gets when no watcher was handed down to it.
private struct NoPictureKeys: PictureKeyWatching {
    func start(for keys: KeyPressHandling) {}
    func stop() {}
}

private struct PictureKeysKey: EnvironmentKey {
    static let defaultValue: PictureKeyWatching = NoPictureKeys()
}

extension EnvironmentValues {
    /// What listens for the keys that act on the picture.
    var pictureKeys: PictureKeyWatching {
        get { self[PictureKeysKey.self] }
        set { self[PictureKeysKey.self] = newValue }
    }
}
