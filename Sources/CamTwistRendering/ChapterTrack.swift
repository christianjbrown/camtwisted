import AVFoundation
import CoreMedia
import Foundation

/// A recording's chapters: a track of titles, as text, each running from
/// when its scene came on air to when the next did. It is not a track of
/// its own to be shown; the picture track points at it.
final class ChapterTrack {
    /// The shortest a chapter can be, so one that ends as it starts still exists.
    private static let shortestChapter = 0.01

    /// What the movie writer adds to its file.
    let input: AVAssetWriterInput
    private let format: CMFormatDescription
    private let timescale: CMTimeScale
    /// The chapter under way, written once it is known where it ends.
    private var open: (name: String, start: Double)?

    /// - Parameter timescale: ticks a second the chapters are timed in.
    init(timescale: CMTimeScale) throws {
        self.timescale = timescale
        format = try CMFormatDescription(
            mediaType: .text, mediaSubType: .init(rawValue: kCMTextFormatType_QTText),
            extensions: .init(base: (Self.textStyle as NSDictionary as! [CFString: CFPropertyList]))
        )
        input = AVAssetWriterInput(mediaType: .text, outputSettings: nil, sourceFormatHint: format)
        input.marksOutputTrackAsEnabled = false
    }

    /// Starts a chapter, which runs until the next one or the end.
    func start(named name: String, at seconds: Double) {
        close(at: seconds)
        open = (name, seconds)
    }

    /// Writes the last chapter and says the track is done.
    func finish(at seconds: Double) {
        close(at: seconds)
        input.markAsFinished()
    }

    /// Writes the chapter under way, now that it is known where it ends.
    private func close(at seconds: Double) {
        guard let chapter = open else { return }
        open = nil
        let length = max(seconds - chapter.start, Self.shortestChapter)
        var timing = CMSampleTimingInfo(
            duration: time(length), presentationTimeStamp: time(chapter.start), decodeTimeStamp: .invalid
        )
        let text = Self.textSample(chapter.name)
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: text.count, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: text.count, flags: 0, blockBufferOut: &block
        )
        // With no memory to hold the title, the chapter is left out.
        if let block {
            text.withUnsafeBytes { bytes in
                _ = CMBlockBufferReplaceDataBytes(
                    with: bytes.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: text.count
                )
            }
            var size = text.count
            var sample: CMSampleBuffer?
            CMSampleBufferCreate(
                allocator: nil, dataBuffer: block, dataReady: true, makeDataReadyCallback: nil, refcon: nil,
                formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 1,
                sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample
            )
            if let sample {
                input.append(sample)
            }
        }
    }

    private func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: timescale)
    }

    /// A title as a QuickTime text sample: its length in two bytes, most
    /// significant first, its text, then a note that the text is UTF-8.
    static func textSample(_ title: String) -> Data {
        let text = Data(title.utf8.prefix(Int(UInt16.max)))
        var sample = Data([UInt8(text.count >> Text.bitsPerByte), UInt8(text.count & Text.lowByte)])
        sample.append(text)
        sample.append(contentsOf: Text.encodingNote)
        return sample
    }

    /// How the text would look if it were shown, which a text track has to
    /// say even though this one never is: plain, in black on clear, in a
    /// box of no size.
    private static var textStyle: [CFString: Any] {
        let clear: [CFString: Any] = [
            kCMTextFormatDescriptionColor_Red: Style.noLevel, kCMTextFormatDescriptionColor_Green: Style.noLevel,
            kCMTextFormatDescriptionColor_Blue: Style.noLevel, kCMTextFormatDescriptionColor_Alpha: Style.noLevel,
        ]
        let noBox: [CFString: Any] = [
            kCMTextFormatDescriptionRect_Top: Style.noSize, kCMTextFormatDescriptionRect_Left: Style.noSize,
            kCMTextFormatDescriptionRect_Bottom: Style.noSize, kCMTextFormatDescriptionRect_Right: Style.noSize,
        ]
        let plain: [CFString: Any] = [
            kCMTextFormatDescriptionStyle_StartChar: Style.firstCharacter,
            kCMTextFormatDescriptionStyle_Height: Style.noSize,
            kCMTextFormatDescriptionStyle_Ascent: Style.noSize,
            kCMTextFormatDescriptionStyle_Font: Style.defaultFont,
            kCMTextFormatDescriptionStyle_FontFace: Style.plainFace,
            kCMTextFormatDescriptionStyle_FontSize: Style.noSize,
            kCMTextFormatDescriptionStyle_ForegroundColor: clear,
        ]
        return [
            kCMTextFormatDescriptionExtension_DisplayFlags: Style.noFlags,
            kCMTextFormatDescriptionExtension_TextJustification: Style.leftJustified,
            kCMTextFormatDescriptionExtension_BackgroundColor: clear,
            kCMTextFormatDescriptionExtension_DefaultTextBox: noBox,
            kCMTextFormatDescriptionExtension_DefaultStyle: plain,
            kCMTextFormatDescriptionExtension_DefaultFontName: Text.fontName,
        ]
    }

    /// The values a QuickTime text description is filled in with.
    private enum Style {
        /// A colour component that is not there at all.
        static let noLevel = 0
        static let noSize = 0
        /// The style starts with the first character of the text.
        static let firstCharacter = 0
        /// The font numbered zero, which is the default one.
        static let defaultFont = 0
        /// No bold, italic or underline.
        static let plainFace = 0
        /// None of the display options, such as scrolling, are on.
        static let noFlags = 0
        static let leftJustified = 0
    }

    private enum Text {
        static let fontName = "Helvetica"
        static let bitsPerByte = 8
        static let lowByte = 0xFF
        /// A twelve byte atom, "encd", saying the text before it is UTF-8.
        static let encodingNote: [UInt8] = [0, 0, 0, 12, 0x65, 0x6E, 0x63, 0x64, 0, 0, 1, 0]
    }
}
