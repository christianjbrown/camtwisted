import AppKit
import CamTwistControl
import CamTwistCore

/// A chain step as AppleScript sees it.
@objc(CTScriptEffect)
final class ScriptEffect: NSObject {
    static let containerKey = "scriptEffects"

    let id: UUID
    @objc let name: String

    init(item: ChainItem) {
        id = item.id
        name = item.scriptName
    }

    @MainActor @objc var isEnabled: Bool {
        get { ScriptingBridge.shared.scenes?.scene.items.first { $0.id == id }?.isEnabled ?? false }
        set { ScriptingBridge.shared.scenes?.scene.update(id: id) { $0.isEnabled = newValue } }
    }

    override var objectSpecifier: NSScriptObjectSpecifier? {
        ScriptSpecifier.named(name, key: Self.containerKey)
    }
}

/// A studio button as AppleScript sees it.
@objc(CTScriptStudioButton)
final class ScriptStudioButton: NSObject {
    static let containerKey = "scriptStudioButtons"

    @objc let name: String

    init(name: String) {
        self.name = name
    }

    override var objectSpecifier: NSScriptObjectSpecifier? {
        ScriptSpecifier.named(name, key: Self.containerKey)
    }
}

enum ScriptSpecifier {
    static func named(_ name: String, key: String) -> NSScriptObjectSpecifier? {
        guard let application = NSScriptClassDescription(for: NSApplication.self) else { return nil }
        return NSNameSpecifier(
            containerClassDescription: application, containerSpecifier: nil, key: key, name: name
        )
    }
}

/// Answers AppleScript's questions about the application object.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let scriptKeys: Set<String> = [
        ScriptEffect.containerKey, ScriptStudioButton.containerKey,
        Key.transitionName, Key.transitionTime, Key.swapMode,
    ]

    /// Property names the scripting dictionary uses for the studio settings.
    private enum Key {
        static let transitionName = "scriptTransitionName"
        static let transitionTime = "scriptTransitionTime"
        static let swapMode = "scriptSwapMode"
    }

    /// Files Finder handed over before the window was up to take them.
    private var pendingFiles: [URL] = []
    private var opener: (@MainActor (URL) -> Void)?

    /// Closing the last window quits the app, since there is nothing left to work in.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Decides whether quitting may go ahead, once the model is up.
    private var closingGuard: ClosingGuard?
    /// The start of the main window's identifier, for bringing it back.
    private var mainWindowIdentifier = ""

    /// - Parameter mainWindow: the main window's scene identifier.
    @MainActor func guardClosing(with closingGuard: ClosingGuard, mainWindow: String) {
        self.closingGuard = closingGuard
        mainWindowIdentifier = mainWindow
    }

    /// Asks about unsaved changes first, and only when there are some.
    /// Cancelling brings back the window that was closed to quit.
    @MainActor func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard closingGuard?.mayClose() == false else { return .terminateNow }
        showMainWindow(in: sender)
        return .terminateCancel
    }

    /// Clicking the Dock icon with nothing showing brings the main window back.
    @MainActor func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { showMainWindow(in: sender) }
        return true
    }

    @MainActor private func showMainWindow(in application: NSApplication) {
        application.windows
            .first { $0.identifier?.rawValue.hasPrefix(mainWindowIdentifier) == true }?
            .makeKeyAndOrderFront(nil)
    }

    /// A setup file was double-clicked, or dropped on the Dock icon.
    @MainActor func application(_ application: NSApplication, open urls: [URL]) {
        guard let opener else {
            pendingFiles += urls
            return
        }
        urls.forEach(opener)
    }

    /// Opens what was waiting, and everything handed over from now on.
    @MainActor func handleOpenedFiles(with setups: SetupOpening) {
        opener = { [weak setups] in setups?.open($0) }
        pendingFiles.forEach(setups.open)
        pendingFiles = []
    }

    func application(_ sender: NSApplication, delegateHandlesKey key: String) -> Bool {
        Self.scriptKeys.contains(key)
    }

    @MainActor @objc var scriptEffects: [ScriptEffect] {
        ScriptingBridge.shared.scenes?.scene.items.map(ScriptEffect.init) ?? []
    }

    @MainActor @objc var scriptStudioButtons: [ScriptStudioButton] {
        ScriptingBridge.shared.scenes?.studio.buttons.map { ScriptStudioButton(name: $0.name) } ?? []
    }

    @MainActor @objc var scriptTransitionName: String {
        get { ScriptingBridge.shared.scenes?.studio.transitionName ?? "" }
        set { ScriptingBridge.shared.scenes?.studio.choose(transition: newValue) }
    }

    @MainActor @objc var scriptTransitionTime: Double {
        get { ScriptingBridge.shared.scenes?.studio.transitionTime ?? 0 }
        set { ScriptingBridge.shared.scenes?.studio.transitionTime = newValue }
    }

    @MainActor @objc var scriptSwapMode: Bool {
        get { ScriptingBridge.shared.scenes?.studio.swapMode ?? false }
        set { ScriptingBridge.shared.scenes?.studio.swapMode = newValue }
    }
}
