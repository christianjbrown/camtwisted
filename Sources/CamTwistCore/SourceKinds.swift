import CoreGraphics
import Foundation

/// What is there for a source to show or hear: the devices connected and
/// the files on this Mac.
public protocol SourceAvailability {
    func hasCamera(_ deviceID: String) -> Bool
    func hasScreen(_ displayID: UInt32) -> Bool
    func hasMicrophone(_ deviceID: String) -> Bool
    func hasFile(atPath path: String) -> Bool
}

/// Everything that differs from one kind of source to the next, apart from
/// how it is drawn and its settings view. Each kind is its own type, so a
/// new kind of source is a new type and one line in `SourceSpec.kind`.
public protocol SourceKind: Sendable {
    /// What a step showing the source is called in the list.
    var title: String { get }
    /// What is wrong when the camera, screen, microphone or file the
    /// source needs is not there, or nil when it is all there.
    func problem(given available: SourceAvailability) -> String?
    /// The source with its settings back to how they start, keeping what it
    /// is a source of. Nil when its settings are all about what it shows.
    var settingsReset: SourceSpec? { get }
    /// Where a new step of this kind starts on the picture. Nil fills it.
    var startingPlacement: PictureInPictureSettings? { get }
    /// Whether the source has sound and no picture.
    var isSoundOnly: Bool { get }
    /// What the volume control says it does.
    var volumeHelp: String { get }
    /// Whether the source brings a picture from outside that can have a
    /// background to take away. What the app draws itself, and a
    /// microphone, cannot.
    var canBeCutOut: Bool { get }
    /// Whether the source is a camera.
    var isCamera: Bool { get }
    /// How loud a source whose volume is set on its step starts out, or
    /// nil for a source with no such volume.
    var startingVolume: Double? { get }
    /// How loud the source is in the mix, given the volume set on its
    /// step. Nil for a source that makes no sound.
    func level(stepVolume: Double?) -> Double?
}

/// What most kinds answer: they need nothing from outside, keep their
/// settings on a reset, fill the picture, and have a picture to show.
extension SourceKind {
    public func problem(given available: SourceAvailability) -> String? { nil }
    public var settingsReset: SourceSpec? { nil }
    public var startingPlacement: PictureInPictureSettings? { nil }
    public var isSoundOnly: Bool { false }
    public var volumeHelp: String { SourceKindText.mixVolumeHelp }
    public var canBeCutOut: Bool { false }
    public var isCamera: Bool { false }
    public var startingVolume: Double? { nil }
    /// A source whose volume is set on its step is as loud as the step
    /// says, or as loud as it starts out. Any other makes no sound.
    public func level(stepVolume: Double?) -> Double? { startingVolume.map { stepVolume ?? $0 } }
}

/// Words and places that more than one kind of source uses.
enum SourceKindText {
    static let mixVolumeHelp = "How loud it is in the mix the web streams and the virtual microphone carry"
    /// The middle of the picture, where a source that sits over it starts.
    static let middle = CGPoint(x: UnitSquare.centre, y: UnitSquare.centre)
    /// Joins a kind's name to what it is showing: "Window: Notes".
    static let detailSeparator = ": "

    static func title(_ name: String, detail: String) -> String {
        name + detailSeparator + detail
    }
}

struct CameraSourceKind: SourceKind {
    var isCamera: Bool { true }
    var canBeCutOut: Bool { true }
    /// A camera starts at full volume.
    var startingVolume: Double? { SceneSound.full }
    private static let name = "Camera"
    private static let missing = "This camera is not connected. Choose another."

    let deviceID: String

    var title: String { Self.name }

    func problem(given available: SourceAvailability) -> String? {
        available.hasCamera(deviceID) ? nil : Self.missing
    }
}

struct DisplaySourceKind: SourceKind {
    var canBeCutOut: Bool { true }
    /// A screen and a window start silent: they carry everything the Mac
    /// or an app is playing, a call's other voices included, so that is
    /// only sent on when asked for.
    var startingVolume: Double? { SceneSound.silent }
    private static let name = "Screen"
    private static let missing = "This screen is not connected. Choose another."
    private static let help = "How loud everything this Mac is playing is in the mix. It starts silent, since on a call it would send the other voices back to them."

    let settings: DisplaySettings

    var title: String { Self.name }
    var volumeHelp: String { Self.help }

    func problem(given available: SourceAvailability) -> String? {
        available.hasScreen(settings.displayID) ? nil : Self.missing
    }
}

struct WindowSourceKind: SourceKind {
    var canBeCutOut: Bool { true }
    /// A screen and a window start silent: they carry everything the Mac
    /// or an app is playing, a call's other voices included, so that is
    /// only sent on when asked for.
    var startingVolume: Double? { SceneSound.silent }
    private static let name = "Window"
    private static let help = "How loud the sound of the app this window belongs to is in the mix. It starts silent."

    let settings: WindowSettings

    var title: String {
        settings.titlePattern.isEmpty ? Self.name : SourceKindText.title(Self.name, detail: settings.titlePattern)
    }
    var volumeHelp: String { Self.help }
}

struct MovieSourceKind: SourceKind {
    var canBeCutOut: Bool { true }

    /// A video is as loud as its own volume, unless muted.
    func level(stepVolume: Double?) -> Double? {
        settings.isMuted ? SceneSound.silent : settings.volume
    }

    private static let name = "Video"
    private static let missing = "A video's file has moved or gone. Choose it again."

    let settings: MovieSettings

    var title: String { Self.name }

    func problem(given available: SourceAvailability) -> String? {
        settings.files.allSatisfy(available.hasFile) ? nil : Self.missing
    }
}

struct SlideShowSourceKind: SourceKind {
    var canBeCutOut: Bool { true }
    private static let name = "Slide show"
    private static let missing = "A picture or folder in this show has moved or gone. Choose it again."

    let settings: SlideShowSettings

    var title: String { Self.name }

    func problem(given available: SourceAvailability) -> String? {
        settings.paths.allSatisfy(available.hasFile) ? nil : Self.missing
    }
}

struct WebsiteSourceKind: SourceKind {
    var canBeCutOut: Bool { true }
    private static let name = "Website"

    var title: String { Self.name }
}

struct StreamSourceKind: SourceKind {
    var canBeCutOut: Bool { true }
    let settings: StreamSettings

    /// A stream is as loud as its own volume.
    func level(stepVolume: Double?) -> Double? { settings.volume }

    private static let name = "Stream"

    var title: String { Self.name }
}

struct VNCSourceKind: SourceKind {
    var canBeCutOut: Bool { true }
    private static let name = "Computer"
    private static let unnamed = "Another computer"

    let settings: VNCSettings

    var title: String {
        settings.host.isEmpty ? Self.unnamed : SourceKindText.title(Self.name, detail: settings.host)
    }
}

struct MicrophoneSourceKind: SourceKind {
    /// A microphone starts at full volume.
    var startingVolume: Double? { SceneSound.full }
    private static let name = "Microphone"
    private static let missing = "This microphone is not connected. Choose another."

    /// Nil is the system's own choice, which is always there.
    let deviceID: String?

    var title: String { Self.name }
    var isSoundOnly: Bool { true }

    func problem(given available: SourceAvailability) -> String? {
        guard let deviceID else { return nil }
        return available.hasMicrophone(deviceID) ? nil : Self.missing
    }
}

struct TelestratorSourceKind: SourceKind {
    private static let name = "Telestrator"

    var title: String { Self.name }
}

struct ColorBarsSourceKind: SourceKind {
    private static let name = "Colour bars"

    var title: String { Self.name }
}

struct TestCardSourceKind: SourceKind {
    private static let name = "Test card"

    var title: String { Self.name }
}

struct ImageSourceKind: SourceKind {
    var canBeCutOut: Bool { true }
    private static let name = "Image"
    private static let missing = "This picture's file has moved or gone. Choose it again."

    let path: String

    var title: String {
        path.isEmpty ? Self.name : SourceKindText.title(Self.name, detail: (path as NSString).lastPathComponent)
    }

    func problem(given available: SourceAvailability) -> String? {
        // No picture chosen yet is not a picture gone missing.
        path.isEmpty || available.hasFile(atPath: path) ? nil : Self.missing
    }
}

/// Text sits over the picture, so it starts placed in the middle of it,
/// ready to be dragged.
struct TextSourceKind: SourceKind {
    private static let name = "Text"
    private static let lineBreak: Character = "\n"
    /// A text box starts as wide as the picture, so its font size is true.
    private static let boxScale = 1.0

    let settings: TextSettings

    /// Named after its first line.
    var title: String {
        SourceKindText.title(
            Self.name, detail: settings.text.split(separator: Self.lineBreak).first.map(String.init) ?? ""
        )
    }
    var settingsReset: SourceSpec? { .text(TextSettings(text: settings.text)) }
    var startingPlacement: PictureInPictureSettings? {
        PictureInPictureSettings(center: SourceKindText.middle, scale: Self.boxScale)
    }
}

/// A shape sits over the picture, so it starts placed in the middle of it,
/// ready to be dragged.
struct ShapeSourceKind: SourceKind {
    private static let name = "Shape"

    let settings: ShapeSettings

    var title: String {
        SourceKindText.title(Self.name, detail: ShapeOutlines.outline(for: settings.kind).name)
    }
    var settingsReset: SourceSpec? { .shape(ShapeSettings(kind: settings.kind)) }
    var startingPlacement: PictureInPictureSettings? { PictureInPictureSettings(center: SourceKindText.middle) }
}

extension SourceSpec {
    /// The one place a source is matched to what its kind says about it.
    public var kind: SourceKind {
        switch self {
        case .camera(let deviceID): return CameraSourceKind(deviceID: deviceID)
        case .display(let settings): return DisplaySourceKind(settings: settings)
        case .window(let settings): return WindowSourceKind(settings: settings)
        case .movie(let settings): return MovieSourceKind(settings: settings)
        case .slideShow(let settings): return SlideShowSourceKind(settings: settings)
        case .website: return WebsiteSourceKind()
        case .stream(let settings): return StreamSourceKind(settings: settings)
        case .vnc(let settings): return VNCSourceKind(settings: settings)
        case .microphone(let deviceID): return MicrophoneSourceKind(deviceID: deviceID)
        case .telestrator: return TelestratorSourceKind()
        case .colorBars: return ColorBarsSourceKind()
        case .testCard: return TestCardSourceKind()
        case .image(let path): return ImageSourceKind(path: path)
        case .text(let settings): return TextSourceKind(settings: settings)
        case .shape(let settings): return ShapeSourceKind(settings: settings)
        }
    }
}
