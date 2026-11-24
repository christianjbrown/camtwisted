import AppKit
import Carbon.HIToolbox
import CamTwistControl
import CamTwistCore

/// Listens for the scenes' keyboard shortcuts whichever app is in front,
/// as system-wide hot keys, which need no permission from the person.
@MainActor
final class HotKeyListener: ShortcutListening {
    /// Marks the hot keys as this app's own.
    private static let signature: OSType = 0x4354_5732 // "CTW2"
    /// The Carbon modifier for each of the app's own.
    private static let carbonModifiers: [(modifier: ShortcutModifiers, carbon: Int)] = [
        (.control, controlKey), (.option, optionKey), (.shift, shiftKey), (.command, cmdKey),
    ]

    var onPress: ((SceneShortcut) -> Void)?

    /// Each registered hot key by its number, with the shortcut it stands for.
    private var registered: [UInt32: (reference: EventHotKeyRef, shortcut: SceneShortcut)] = [:]
    private var handler: EventHandlerRef?

    func listen(for shortcuts: [SceneShortcut]) {
        installHandler()
        registered.values.forEach { UnregisterEventHotKey($0.reference) }
        registered = [:]
        for (index, shortcut) in shortcuts.enumerated() {
            let number = UInt32(index)
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(shortcut.keyCode), Self.carbon(shortcut.modifiers),
                EventHotKeyID(signature: Self.signature, id: number), GetApplicationEventTarget(), OptionBits(),
                &reference
            )
            // Another app may own the shortcut already, in which case it stays theirs.
            if status == noErr, let reference {
                registered[number] = (reference, shortcut)
            }
        }
    }

    private func pressed(number: UInt32) {
        registered[number].map { onPress?($0.shortcut) }
    }

    private func installHandler() {
        guard handler == nil else { return }
        var handled = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))]
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, listener in
                guard let event, let listener else { return OSStatus(eventNotHandledErr) }
                var hotKey = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hotKey
                )
                let number = hotKey.id
                let me = Unmanaged<HotKeyListener>.fromOpaque(listener).takeUnretainedValue()
                // Hot keys arrive on the main thread, through the app's own event loop.
                MainActor.assumeIsolated { me.pressed(number: number) }
                return noErr
            },
            handled.count, &handled, Unmanaged.passUnretained(self).toOpaque(), &handler
        )
    }

    private static func carbon(_ modifiers: ShortcutModifiers) -> UInt32 {
        UInt32(carbonModifiers.filter { modifiers.contains($0.modifier) }.reduce(0) { $0 | $1.carbon })
    }
}

extension ShortcutModifiers {
    /// The keys held, from the ones AppKit reports.
    init(_ flags: NSEvent.ModifierFlags) {
        let pairs: [(NSEvent.ModifierFlags, ShortcutModifiers)] = [
            (.control, .control), (.option, .option), (.shift, .shift), (.command, .command),
        ]
        self = pairs.reduce(into: []) { held, pair in
            if flags.contains(pair.0) { held.insert(pair.1) }
        }
    }
}
