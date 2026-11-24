import CoreGraphics
import Foundation

/// How a movie playlist moves on when a clip ends.
public enum MoviePlayMode: String, Codable, CaseIterable, Sendable {
    case playAllAndStop
    case playOneAndRepeat
    case playOneAndStop
    case playAllAndRepeat
    case shuffle
}

public struct MovieSettings: Codable, Equatable, Sendable {
    public static let fullVolume = 1.0

    /// Paths of the clips, in playlist order.
    public var files: [String]
    /// A folder whose movies join the playlist as they appear.
    public var hotFolder: String?
    public var playMode: MoviePlayMode
    public var isPlaying: Bool
    public var hidesWhenStopped: Bool
    public var isMuted: Bool
    public var volume: Double
    /// Text shown over a clip while it plays, by the clip's path.
    public var captions: [String: String]?
    /// The audio device the sound goes to. Nil is the system's default.
    public var audioDeviceID: String?

    public init(
        files: [String] = [],
        hotFolder: String? = nil,
        playMode: MoviePlayMode = .playAllAndRepeat,
        isPlaying: Bool = true,
        hidesWhenStopped: Bool = false,
        isMuted: Bool = false,
        volume: Double = MovieSettings.fullVolume,
        captions: [String: String]? = nil,
        audioDeviceID: String? = nil
    ) {
        self.files = files
        self.hotFolder = hotFolder
        self.playMode = playMode
        self.isPlaying = isPlaying
        self.hidesWhenStopped = hidesWhenStopped
        self.isMuted = isMuted
        self.volume = volume
        self.captions = captions
        self.audioDeviceID = audioDeviceID
    }
}

public struct SlideShowSettings: Codable, Equatable, Sendable {
    public static let defaultDelay = 5.0
    public static let delayRange: ClosedRange<Double> = 1...60

    /// Image files and folders of images.
    public var paths: [String]
    /// Seconds each image stays up.
    public var delay: Double
    public var isPaused: Bool
    /// Whether the show starts again after the last image, or stays on it.
    public var loops: Bool

    public init(
        paths: [String] = [], delay: Double = SlideShowSettings.defaultDelay, isPaused: Bool = false,
        loops: Bool = true
    ) {
        self.paths = paths
        self.delay = delay
        self.isPaused = isPaused
        self.loops = loops
    }

    /// Shows saved before looping was a choice looped, and still do.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        paths = try values.decode([String].self, forKey: .paths)
        delay = try values.decode(Double.self, forKey: .delay)
        isPaused = try values.decode(Bool.self, forKey: .isPaused)
        loops = try values.decodeIfPresent(Bool.self, forKey: .loops) ?? true
    }
}

/// A rectangle in fractions of a picture: 0 to 1 on both axes, origin bottom left.
public struct UnitRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public static let full = UnitRect(x: 0, y: 0, width: 1, height: 1)

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct DisplaySettings: Codable, Equatable, Sendable {
    public static let defaultFollowFraction = 0.5
    public static let followFractionRange: ClosedRange<Double> = 0.2...1

    public var displayID: UInt32
    /// The part of the display to show.
    public var region: UnitRect
    /// Show a window around the pointer instead of a fixed region.
    public var followsMouse: Bool
    /// Size of that window as a fraction of the display.
    public var followFraction: Double
    public var showsCursor: Bool

    public init(
        displayID: UInt32,
        region: UnitRect = .full,
        followsMouse: Bool = false,
        followFraction: Double = DisplaySettings.defaultFollowFraction,
        showsCursor: Bool = true
    ) {
        self.displayID = displayID
        self.region = region
        self.followsMouse = followsMouse
        self.followFraction = followFraction
        self.showsCursor = showsCursor
    }
}

public struct WindowSettings: Codable, Equatable, Sendable {
    /// Text the window's title must contain, or a regular expression.
    public var titlePattern: String
    public var isRegularExpression: Bool
    /// Only windows of this application, when set.
    public var applicationName: String?

    public init(titlePattern: String, isRegularExpression: Bool = false, applicationName: String? = nil) {
        self.titlePattern = titlePattern
        self.isRegularExpression = isRegularExpression
        self.applicationName = applicationName
    }
}

/// A stroke drawn on the picture, in unit coordinates.
public struct DrawingStroke: Codable, Equatable, Sendable {
    public var points: [CGPoint]
    public var color: RGBColor
    /// Line width as a fraction of the picture's width.
    public var width: Double

    public init(points: [CGPoint], color: RGBColor, width: Double) {
        self.points = points
        self.color = color
        self.width = width
    }
}

public struct TelestratorSettings: Codable, Equatable, Sendable {
    public static let defaultPenWidth = 0.008
    public static let penWidthRange: ClosedRange<Double> = 0.002...0.04
    public static let defaultColor = RGBColor(red: 1, green: 0, blue: 0)

    public var strokes: [DrawingStroke]
    public var penColor: RGBColor
    public var penWidth: Double

    public init(
        strokes: [DrawingStroke] = [],
        penColor: RGBColor = TelestratorSettings.defaultColor,
        penWidth: Double = TelestratorSettings.defaultPenWidth
    ) {
        self.strokes = strokes
        self.penColor = penColor
        self.penWidth = penWidth
    }
}

/// Words as a source: a title, a name, a caption. Placed, sized, turned and
/// animated like any other source.
/// How the lines of a text sit in its box.
public enum TextAlignment: String, Codable, CaseIterable, Sendable {
    case left
    case center
    case right
    /// Every line but the last stretched to both edges.
    case justified
}

public struct TextSettings: Codable, Equatable, Sendable {
    public static let defaultText = "Text"
    public static let defaultFontName = "Helvetica-Bold"
    public static let defaultColor = RGBColor(red: 1, green: 1, blue: 1)
    /// Font sizes are in points of the picture, which is 720 points tall.
    public static let defaultFontSize = 96.0
    public static let fontSizeRange: ClosedRange<Double> = 12...400
    /// Line heights are multiples of the font's own line height.
    public static let defaultLineHeight = 1.0
    public static let lineHeightRange: ClosedRange<Double> = 0.5...3

    /// May run over several lines.
    public var text: String
    public var fontName: String
    public var color: RGBColor
    public var fontSize: Double
    public var lineHeight: Double
    public var hasShadow: Bool
    public var alignment: TextAlignment

    public init(
        text: String = TextSettings.defaultText,
        fontName: String = TextSettings.defaultFontName,
        color: RGBColor = TextSettings.defaultColor,
        fontSize: Double = TextSettings.defaultFontSize,
        lineHeight: Double = TextSettings.defaultLineHeight,
        hasShadow: Bool = false,
        alignment: TextAlignment = .center
    ) {
        self.text = text
        self.fontName = fontName
        self.color = color
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.hasShadow = hasShadow
        self.alignment = alignment
    }

    /// Scenes saved before text had a size, a line height and a shadow
    /// carry none of them, and get the starting values.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        text = try values.decode(String.self, forKey: .text)
        fontName = try values.decode(String.self, forKey: .fontName)
        color = try values.decode(RGBColor.self, forKey: .color)
        fontSize = try values.decodeIfPresent(Double.self, forKey: .fontSize) ?? Self.defaultFontSize
        lineHeight = try values.decodeIfPresent(Double.self, forKey: .lineHeight) ?? Self.defaultLineHeight
        hasShadow = try values.decodeIfPresent(Bool.self, forKey: .hasShadow) ?? false
        alignment = try values.decodeIfPresent(TextAlignment.self, forKey: .alignment) ?? .center
    }
}

extension SourceSpec {
    /// The same source with its settings back to how they start, keeping
    /// what it is a source of: the words of a text, the kind of a shape.
    /// Sources whose settings are all about what they show are left alone.
    public var withSettingsReset: SourceSpec { kind.settingsReset ?? self }
}

/// The outline of a shape source.
public enum ShapeKind: String, Codable, CaseIterable, Sendable {
    case rectangle
    case square
    case circle
    case ellipse
    case triangle
    case diamond
    case star
}

/// A flat coloured shape as a source: a backdrop, a panel behind text, a
/// mask. Placed, sized, turned and animated like any other source.
public struct ShapeSettings: Codable, Equatable, Sendable {
    public static let defaultColor = RGBColor(red: 0.1, green: 0.4, blue: 0.9)
    public static let opaque = 1.0
    public static let opacityRange: ClosedRange<Double> = 0...1

    public var kind: ShapeKind
    public var color: RGBColor
    /// How solid the shape is: 0 is invisible, 1 hides what is behind it.
    public var opacity: Double

    public init(
        kind: ShapeKind = .rectangle,
        color: RGBColor = ShapeSettings.defaultColor,
        opacity: Double = ShapeSettings.opaque
    ) {
        self.kind = kind
        self.color = color
        self.opacity = opacity
    }
}

/// The points of a shape, as fractions of the box it is drawn in, with
/// the origin bottom left. Round shapes have none: they are ellipses.
public enum ShapeGeometry {
    /// Width over height of the box a shape is drawn in. Squares and
    /// circles are as wide as they are tall; the rest take the picture's shape.
    public static func aspect(of kind: ShapeKind, canvasAspect: Double) -> Double {
        ShapeOutlines.outline(for: kind).aspect(canvasAspect: canvasAspect)
    }

    public static func isRound(_ kind: ShapeKind) -> Bool {
        ShapeOutlines.outline(for: kind).isRound
    }

    /// The corners of a straight-sided shape, in drawing order.
    public static func corners(of kind: ShapeKind) -> [CGPoint] {
        ShapeOutlines.outline(for: kind).corners
    }
}

/// What a source in the chain is, with the settings that kind needs.
public enum SourceSpec: Codable, Equatable, Sendable {
    case camera(deviceID: String)
    case display(DisplaySettings)
    case window(WindowSettings)
    case movie(MovieSettings)
    case slideShow(SlideShowSettings)
    case website(url: String)
    case stream(StreamSettings)
    /// Another computer's screen, watched over VNC.
    case vnc(VNCSettings)
    /// A microphone, which has sound and no picture. Nil is the system's own choice.
    case microphone(deviceID: String?)
    case telestrator(TelestratorSettings)
    case colorBars
    case testCard
    /// One picture file, such as a logo or a backdrop.
    case image(path: String)
    case text(TextSettings)
    case shape(ShapeSettings)
}
