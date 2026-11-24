import CamTwistCore
import Foundation

/// How a scene's tile in the studio window is outlined.
public enum TileOutline: Equatable {
    case onAir
    case linedUp
    case quiet
}

/// What a scene's tile in the studio window shows.
public struct StudioTile: Equatable {
    public let outline: TileOutline
    public let help: String

    public init(sceneName: String, isOnAir: Bool, isLinedUp: Bool) {
        if isOnAir {
            outline = .onAir
        } else {
            outline = isLinedUp ? .linedUp : .quiet
        }
        help = isOnAir ? "\(sceneName) is on air" : "Click to preview \(sceneName), double click to put it on air"
    }

    /// Whether the outline is drawn heavy: on air or lined up.
    public var isEmphasised: Bool { outline != .quiet }
}

/// The names over the studio window's two pictures, and its buttons' state.
public struct StudioMonitors: Equatable {
    public let onAirName: String
    public let previewedName: String
    public let goLiveTitle: String
    public let canSwitch: Bool

    public init(
        scenes: [StudioButton], onAirID: UUID?, previewedID: UUID?, hasPreview: Bool, isTransitioning: Bool
    ) {
        onAirName = scenes.first { $0.id == onAirID }?.name ?? ""
        previewedName = scenes.first { $0.id == previewedID }?.name ?? ""
        goLiveTitle = isTransitioning ? "Switching" : "Go live"
        canSwitch = hasPreview && !isTransitioning
    }
}

/// What the studio window's transition choice shows and says.
public struct StudioTransitionChoice: Equatable {
    /// The choice that leaves each scene to come on air its own way.
    public static let scenesOwnTitle = "Scene's own"

    /// Whether a time can be set: a cut takes none, and each scene keeps its own.
    public let showsSeconds: Bool
    public let goLiveHelp: String
    /// What is chosen, as said beside "Go live with".
    public let title: String
    /// What the Go live button will do, said under it: the transition and
    /// its time, or that each scene comes on air its own way.
    public let caption: String

    /// What separates a transition from its time under the Go live button.
    private static let captionSeparator = " · "
    private static let scenesOwnCaption = "Each scene its own way"
    /// Written after a number of seconds.
    private static let secondsUnit = " s"

    public init(chosen: String?, seconds: Double) {
        let shown = chosen.map(EffectNaming.title(for:))
        let timed = chosen.map { $0 != StudioSettings.cutName } ?? false
        title = shown ?? Self.scenesOwnTitle
        showsSeconds = timed
        caption = shown.map { timed ? $0 + Self.captionSeparator + Self.secondsText(seconds) : $0 }
            ?? Self.scenesOwnCaption
        goLiveHelp = chosen.map { "Put the scene in the preview on air with \(EffectNaming.title(for: $0))" }
            ?? "Put the scene in the preview on air the way that scene comes on air"
    }

    /// A time in seconds, with a tenth shown only when there is one.
    private static func secondsText(_ seconds: Double) -> String {
        seconds.formatted(.number.precision(.fractionLength(0...1))) + secondsUnit
    }
}

/// The strip under the picture.
public enum PictureBarText {
    /// A space still takes a line, so the strip keeps its height with no hint.
    public static let blankHint = " "

    /// A setup file that would not open or save says why, in the hint's place.
    public static func hint(setupProblem: String?, dragHint: String?) -> String {
        setupProblem ?? dragHint ?? blankHint
    }

    public static func snapshotHelp(folderName: String) -> String {
        "Save the picture to \(folderName)"
    }
}

/// When the scenes list points people at the studio window. The studio is
/// for switching between scenes, so the hint waits until there is more than
/// one, and stops once the studio has been opened.
public enum StudioHint {
    /// Where whether the studio has ever been opened is kept.
    public static let openedKey = "StudioHasBeenOpened"
    /// The fewest scenes worth switching between.
    static let fewestScenesToSwitch = 2

    public static func shows(sceneCount: Int, hasOpenedStudio: Bool) -> Bool {
        !hasOpenedStudio && sceneCount >= fewestScenesToSwitch
    }
}
