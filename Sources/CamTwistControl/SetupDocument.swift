import CamTwistCore
import Foundation

/// Everything a setup file holds: the scenes with their sources and
/// effects, the outputs' settings and the window's.
struct SetupDocument: Codable, Equatable {
    /// The version of the file format this app writes and reads.
    static let formatVersion = 1

    var version: Int
    var studio: StudioSettings
    /// Without the settings that stay on this Mac, see `GlobalPreferences`.
    var preferences: AppPreferences
    /// Nil when there was no window to measure.
    var windowSize: SetupWindowSize?

    init(studio: StudioSettings, preferences: AppPreferences, windowSize: SetupWindowSize?) {
        version = Self.formatVersion
        self.studio = studio
        self.preferences = GlobalPreferences.removed(from: preferences)
        self.windowSize = windowSize
    }

    /// The scene to put on air when the file is opened: the one that was on
    /// air, or the first when that one is gone. Nil for a file with no scenes.
    var sceneToShow: SceneConfiguration? {
        (studio.sceneOnAir ?? studio.buttons.first)?.scene
    }
}

/// Why a setup file was not opened.
enum SetupFileError: Error, Equatable, LocalizedError {
    case notASetup
    case newerVersion
    case noScenes

    var errorDescription: String? {
        switch self {
        case .notASetup: "That file is not a CamTwisted setup."
        case .newerVersion: "That setup was saved by a newer CamTwisted. Update the app to open it."
        case .noScenes: "That setup has no scenes in it."
        }
    }
}

/// Turns a setup into the bytes of a file and back.
struct SetupDocumentCoder {
    /// Just enough of a file to know whether it is one of ours, and which version.
    private struct Header: Decodable {
        var version: Int
    }

    func encode(_ document: SetupDocument) throws -> Data {
        let encoder = JSONEncoder()
        // Sorted and indented, so two saves of the same setup diff cleanly.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    func decode(_ data: Data) throws -> SetupDocument {
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data) else {
            throw SetupFileError.notASetup
        }
        guard header.version <= SetupDocument.formatVersion else {
            throw SetupFileError.newerVersion
        }
        guard let document = try? decoder.decode(SetupDocument.self, from: data) else {
            throw SetupFileError.notASetup
        }
        return document
    }
}
