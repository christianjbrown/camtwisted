import Foundation

/// The kind of file a recording is. Each is known by its file extension.
public enum RecordingContainer: String, Codable, CaseIterable, Sendable {
    case quickTime = "mov"
    case mpeg4 = "mp4"

    public var fileExtension: String { rawValue }

    /// What the container is called in a list of them.
    public var title: String {
        switch self {
        case .quickTime: "QuickTime (.\(fileExtension))"
        case .mpeg4: "MPEG-4 (.\(fileExtension))"
        }
    }
}

/// How a recording's picture is compressed.
public enum RecordingPictureCodec: String, Codable, CaseIterable, Sendable {
    /// Plays on everything.
    case h264
    /// The same picture in about half the data, for newer players.
    case hevc
    /// Barely compressed, for editing. It is as big as it needs to be, so
    /// it has no bit rate to set.
    case proRes422

    /// The encoding's name, and what it is good for.
    private var wording: PictureCodecWording {
        switch self {
        case .h264: .h264
        case .hevc: .hevc
        case .proRes422: .proRes422
        }
    }

    public var name: String { wording.name }

    /// What the encoding is called in a list of them.
    public var title: String { wording.title }
}

/// What a picture encoding is called and what it is good for, the same
/// wherever it is offered: a stream and a recording name H.264 alike.
public struct PictureCodecWording: Equatable, Sendable {
    public let name: String
    public let use: String

    private static let separator = ", "

    /// The name and the use, as a list of encodings shows them.
    public var title: String { name + Self.separator + use }

    public static let h264 = PictureCodecWording(name: "H.264", use: "which plays on everything")
    public static let hevc = PictureCodecWording(name: "HEVC", use: "smaller, for newer players")
    public static let proRes422 = PictureCodecWording(name: "Apple ProRes 422", use: "large, for editing")
}

/// How a recording's sound is kept.
public enum RecordingSoundCodec: String, Codable, CaseIterable, Sendable {
    case aac
    /// Uncompressed, so it has no bit rate to set.
    case linearPCM

    /// What the encoding is called in a list of them.
    public var title: String {
        switch self {
        case .aac: "AAC"
        case .linearPCM: "Uncompressed (Linear PCM)"
        }
    }
}

/// How a recording is made: the kind of file, how its picture and sound
/// are encoded, how big its picture is and how much data each takes.
public struct RecordingOptions: Codable, Equatable, Sendable {
    public var container: RecordingContainer
    public var pictureCodec: RecordingPictureCodec
    /// The picture's height in pixels; its width follows from its shape.
    public var height: Int
    /// Thousands of bits a second for the picture. Nil leaves it to the
    /// app, which works it out from the picture's size.
    public var pictureKilobits: Int?
    public var soundCodec: RecordingSoundCodec
    /// Thousands of bits a second for the sound.
    public var soundKilobits: Int

    /// What a new recording's sound has.
    public static let usualSoundKilobits = 192

    public init(
        container: RecordingContainer = .mpeg4, pictureCodec: RecordingPictureCodec = .h264,
        height: Int = PictureHeight.fullHD, pictureKilobits: Int? = nil,
        soundCodec: RecordingSoundCodec = .aac, soundKilobits: Int = RecordingOptions.usualSoundKilobits
    ) {
        self.container = container
        self.pictureCodec = pictureCodec
        self.height = height
        self.pictureKilobits = pictureKilobits
        self.soundCodec = soundCodec
        self.soundKilobits = soundKilobits
    }
}

/// A recording worked out in full, ready to be written: the options with
/// the rules applied, for a picture of a known shape.
public struct RecordingPlan: Equatable, Sendable {
    public var container: RecordingContainer
    public var pictureCodec: RecordingPictureCodec
    public var width: Int
    public var height: Int
    /// Bits a second for the picture, or nil for an encoding that has none to set.
    public var pictureBitsPerSecond: Int?
    public var soundCodec: RecordingSoundCodec
    /// Bits a second for the sound, or nil for an encoding that has none to set.
    public var soundBitsPerSecond: Int?

    public init(
        container: RecordingContainer, pictureCodec: RecordingPictureCodec, width: Int, height: Int,
        pictureBitsPerSecond: Int?, soundCodec: RecordingSoundCodec, soundBitsPerSecond: Int?
    ) {
        self.container = container
        self.pictureCodec = pictureCodec
        self.width = width
        self.height = height
        self.pictureBitsPerSecond = pictureBitsPerSecond
        self.soundCodec = soundCodec
        self.soundBitsPerSecond = soundBitsPerSecond
    }
}

/// What goes with what in a recording: which encodings each kind of file
/// takes, which of them have a bit rate to set, and what is chosen
/// instead when a choice does not fit. The one place these are decided.
/// Chapters are not among them: both kinds of file take a chapter track.
public enum RecordingRules {
    /// The usual steps for a recording's picture, which is given more
    /// data than a stream's because it is kept.
    public static let pictureKilobitChoices = [2000, 4000, 6000, 8000, 12000, 16000, 24000, 32000, 50000, 80000]
    public static let soundKilobitChoices = [96, 128, 192, 256, 320]

    private static let bitsPerKilobit = 1000

    /// The encodings a kind of file cannot take. A kind of file not listed
    /// takes every one, so a new one with limits of its own adds a line here.
    private static let refused: [RecordingContainer: (pictures: Set<RecordingPictureCodec>, sounds: Set<RecordingSoundCodec>)] = [
        .mpeg4: (pictures: [.proRes422], sounds: [.linearPCM]),
    ]
    /// The encodings that are as big as they need to be.
    private static let picturesWithoutBitRate: Set<RecordingPictureCodec> = [.proRes422]
    private static let soundsWithoutBitRate: Set<RecordingSoundCodec> = [.linearPCM]

    /// The picture encodings a kind of file takes.
    public static func pictureCodecs(in container: RecordingContainer) -> [RecordingPictureCodec] {
        let refusing = refused[container]?.pictures ?? []
        return RecordingPictureCodec.allCases.filter { !refusing.contains($0) }
    }

    /// The sound encodings a kind of file takes.
    public static func soundCodecs(in container: RecordingContainer) -> [RecordingSoundCodec] {
        let refusing = refused[container]?.sounds ?? []
        return RecordingSoundCodec.allCases.filter { !refusing.contains($0) }
    }

    /// Whether a picture encoding has a bit rate to set.
    public static func hasBitRate(_ codec: RecordingPictureCodec) -> Bool {
        !picturesWithoutBitRate.contains(codec)
    }

    /// Whether a sound encoding has a bit rate to set.
    public static func hasBitRate(_ codec: RecordingSoundCodec) -> Bool {
        !soundsWithoutBitRate.contains(codec)
    }

    /// The same options with anything that does not fit swapped for what
    /// does: an encoding the file cannot take for the usual one, and a
    /// size or rate not on offer for what a new recording has.
    public static func usable(_ options: RecordingOptions) -> RecordingOptions {
        let fresh = RecordingOptions()
        func choice<Value: Equatable>(_ value: Value, among choices: [Value], else fallback: Value) -> Value {
            choices.contains(value) ? value : fallback
        }
        return RecordingOptions(
            container: options.container,
            pictureCodec: choice(
                options.pictureCodec, among: pictureCodecs(in: options.container), else: fresh.pictureCodec
            ),
            height: choice(options.height, among: PictureHeight.all, else: fresh.height),
            pictureKilobits: options.pictureKilobits.flatMap { pictureKilobitChoices.contains($0) ? $0 : nil },
            soundCodec: choice(options.soundCodec, among: soundCodecs(in: options.container), else: fresh.soundCodec),
            soundKilobits: choice(options.soundKilobits, among: soundKilobitChoices, else: fresh.soundKilobits)
        )
    }

    /// The recording to write for a picture of some shape.
    /// - Parameter automaticBitsPerPixelPerSecond: bits a second for each
    ///   pixel of the picture, when its bit rate is left to the app.
    public static func plan(
        for options: RecordingOptions, canvasAspect: Double, automaticBitsPerPixelPerSecond: Int
    ) -> RecordingPlan {
        let fitting = usable(options)
        let size = PictureHeight.size(height: fitting.height, canvasAspect: canvasAspect)
        let automatic = size.width * size.height * automaticBitsPerPixelPerSecond
        let chosen = fitting.pictureKilobits.map { $0 * bitsPerKilobit }
        return RecordingPlan(
            container: fitting.container,
            pictureCodec: fitting.pictureCodec,
            width: size.width,
            height: size.height,
            pictureBitsPerSecond: hasBitRate(fitting.pictureCodec) ? chosen ?? automatic : nil,
            soundCodec: fitting.soundCodec,
            soundBitsPerSecond: hasBitRate(fitting.soundCodec) ? fitting.soundKilobits * bitsPerKilobit : nil
        )
    }
}

/// What the recording options are called where they are shown.
public enum RecordingWording {
    /// What the picker shows for leaving the picture's bit rate to the app.
    public static let automaticTitle = "Automatic"
    private static let summarySeparator = ", "

    /// What a picture bit rate is called in the list of them.
    public static func pictureBitRateTitle(_ kilobits: Int?) -> String {
        kilobits.map(String.init) ?? automaticTitle
    }

    /// The options in a few words, for when they are folded away.
    public static func summary(of options: RecordingOptions) -> String {
        let fitting = RecordingRules.usable(options)
        return [
            fitting.container.title, fitting.pictureCodec.name,
            PictureHeight.label(for: fitting.height),
        ].joined(separator: summarySeparator)
    }
}
