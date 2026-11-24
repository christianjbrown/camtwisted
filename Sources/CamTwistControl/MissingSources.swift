import CamTwistCore
import Foundation

/// Says whether a path leads to something on this Mac.
public protocol FileChecking {
    func exists(atPath path: String) -> Bool
}

/// Finds the sources in a scene whose camera, screen, microphone or file
/// is not there, which draw nothing until something else is chosen.
struct MissingSources {
    /// What is connected right now, by identifier.
    let cameras: Set<String>
    let screens: Set<UInt32>
    let microphones: Set<String>
    let files: FileChecking

    /// What is wrong with a step's source, or nil when it is all there.
    /// Effects, and sources that need nothing from outside, are never
    /// missing: each kind of source says what it needs.
    func problem(with item: ChainItem) -> String? {
        item.source?.kind.problem(given: self)
    }

    /// Whether anything in a scene is missing, its branches included.
    func isAnythingMissing(in scene: SceneConfiguration) -> Bool {
        scene.allItems.contains { problem(with: $0) != nil }
    }
}

extension MissingSources: SourceAvailability {
    func hasCamera(_ deviceID: String) -> Bool { cameras.contains(deviceID) }

    func hasScreen(_ displayID: UInt32) -> Bool { screens.contains(displayID) }

    func hasMicrophone(_ deviceID: String) -> Bool { microphones.contains(deviceID) }

    func hasFile(atPath path: String) -> Bool { files.exists(atPath: path) }
}
