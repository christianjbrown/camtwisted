import CamTwistCore
import Foundation

/// How the window is laid out when the app opens, for anybody who wants it
/// to open ready for a particular job. Each is a default that can also be
/// given on the command line, as in `-OpenOnPane Output`.
public struct LaunchOptions: Equatable {
    /// The tab to open on, by its name. Nil opens on the first.
    public let pane: String?
    /// Whether the studio window opens alongside the main one.
    public let opensStudioWindow: Bool
    /// Whether the list of sources to add starts open.
    public let opensPicker: Bool
    /// Whether the list of effects to add starts open.
    public let showsEffects: Bool
    /// Whether every step of the scene on air starts with its settings showing.
    public let opensStepSettings: Bool
    /// Whether the Settings window is open from the start.
    public let opensSettings: Bool
    /// Whether the recording's options start unfolded in the Output pane.
    public let opensRecordingOptions: Bool
    /// The step of the scene on air that starts selected, counting from one.
    /// Nought selects none.
    public let selectedStep: Int
    /// A setup file to open before anything else, so the other options
    /// apply to its scene. A file handed over by Finder or `open` can arrive
    /// after they have been applied, to the empty scene the app starts with.
    public let setupToOpen: URL?

    private enum Key {
        static let pane = "OpenOnPane"
        static let studioWindow = "OpenStudioWindow"
        static let picker = "OpenPicker"
        static let effects = "ShowEffects"
        static let stepSettings = "OpenStepSettings"
        static let settings = "OpenSettings"
        static let recordingOptions = "OpenRecordingOptions"
        static let selectedStep = "SelectStep"
        static let setup = "OpenSetup"
    }

    public init(
        pane: String? = nil, opensStudioWindow: Bool = false, opensPicker: Bool = false, showsEffects: Bool = false,
        opensStepSettings: Bool = false, opensSettings: Bool = false, opensRecordingOptions: Bool = false,
        selectedStep: Int = 0, setupToOpen: URL? = nil
    ) {
        self.setupToOpen = setupToOpen
        self.opensRecordingOptions = opensRecordingOptions
        self.pane = pane
        self.opensStudioWindow = opensStudioWindow
        self.opensPicker = opensPicker
        self.showsEffects = showsEffects
        self.opensStepSettings = opensStepSettings
        self.opensSettings = opensSettings
        self.selectedStep = selectedStep
    }

    public static func load(defaults: UserDefaults = .standard) -> LaunchOptions {
        LaunchOptions(
            pane: defaults.string(forKey: Key.pane),
            opensStudioWindow: defaults.bool(forKey: Key.studioWindow),
            opensPicker: defaults.bool(forKey: Key.picker),
            showsEffects: defaults.bool(forKey: Key.effects),
            opensStepSettings: defaults.bool(forKey: Key.stepSettings),
            opensSettings: defaults.bool(forKey: Key.settings),
            opensRecordingOptions: defaults.bool(forKey: Key.recordingOptions),
            selectedStep: defaults.integer(forKey: Key.selectedStep),
            setupToOpen: defaults.string(forKey: Key.setup).map { URL(fileURLWithPath: $0) }
        )
    }

    /// The step of a scene that starts selected, if the option names one it has.
    public func stepToSelect(in scene: SceneConfiguration) -> UUID? {
        let index = selectedStep - 1
        return scene.items.indices.contains(index) ? scene.items[index].id : nil
    }
}

/// How setup files are named.
public enum SetupFileName {
    /// The extension of a setup file.
    public static let fileExtension = "camtwisted"
    private static let untitled = "Untitled"

    /// The name the save panel starts with: the open file's own name, or a plain one.
    public static func suggested(forOpenFile current: String?) -> String {
        current ?? "\(untitled).\(fileExtension)"
    }
}
