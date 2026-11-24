import AppKit
import CamTwistCore

/// Shows the program picture filling one screen, for a projector or a
/// second monitor. Escape closes it.
@MainActor
final class FullScreenOutput {
    /// Far enough above the menu bar to cover it.
    private static let levelsAboveMenuBar = 1

    /// Called when the output closes by itself, on Escape or when its
    /// screen goes away.
    var onClose: (() -> Void)?

    private let monitor: PreviewSink
    private var window: NSWindow?
    private var keyMonitor: Any?

    init(monitor: PreviewSink) {
        self.monitor = monitor
    }

    /// Covers the given display with the picture. Returns false when that
    /// display is not connected.
    @discardableResult
    func show(onDisplay displayID: UInt32) -> Bool {
        hide()
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else { return false }

        let window = NSWindow(
            contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.backgroundColor = .black
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + Self.levelsAboveMenuBar)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.layer?.addSublayer(monitor.layer)
        monitor.layer.frame = view.bounds
        monitor.layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        window.contentView = view
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        self.window = window

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard FullScreenKeys.closes(keyCode: event.keyCode) else { return event }
            self?.hide()
            self?.onClose?()
            return nil
        }
        return true
    }

    func hide() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        monitor.layer.removeFromSuperlayer()
        window?.close()
        window = nil
    }
}

extension NSScreen {
    /// The number the system gives this screen, which a display choice carries.
    var displayID: UInt32? {
        DisplayIdentity.displayID(inDescription: Dictionary(uniqueKeysWithValues: deviceDescription.map { ($0.key.rawValue, $0.value) }))
    }
}
