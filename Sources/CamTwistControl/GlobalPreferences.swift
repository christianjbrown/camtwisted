import CamTwistCore
import Foundation

/// The preferences that belong to this Mac and not to a setup: where
/// snapshots and recordings go, and the stream key, which is a secret. They are kept
/// between launches, follow the person from one setup to the next, and are
/// never written into a setup file, which is meant to be shared.
struct GlobalPreferences: Codable, Equatable {
    var snapshotsFolder: String?
    /// Optional so globals saved before it existed still load.
    var recordingsFolder: String?
    var rtmpStreamKey: String
    /// Optional so globals saved before it existed still load.
    var autosaves: Bool?

    init(_ preferences: AppPreferences) {
        snapshotsFolder = preferences.snapshotsFolder
        recordingsFolder = preferences.recordingsFolder
        rtmpStreamKey = preferences.rtmp.streamKey
        autosaves = preferences.autosavesSetting
    }

    /// The preferences with these on top of them.
    func applied(to preferences: AppPreferences) -> AppPreferences {
        var result = preferences
        result.snapshotsFolder = snapshotsFolder
        result.recordingsFolder = recordingsFolder
        result.rtmp.streamKey = rtmpStreamKey
        result.autosavesSetting = autosaves
        return result
    }

    /// The preferences with the global ones put back to their defaults.
    static func removed(from preferences: AppPreferences) -> AppPreferences {
        GlobalPreferences(AppPreferences()).applied(to: preferences)
    }
}
