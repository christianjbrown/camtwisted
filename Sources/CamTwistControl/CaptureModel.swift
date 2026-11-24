import CamTwistCore
import Foundation
import Observation

/// Keeping the picture on air: recording it to a movie and saving
/// snapshots of it.
@MainActor
@Observable
public final class CaptureModel {
    /// Whether the picture on air is being recorded to a movie. It is a
    /// thing done now, not a setting, so it is not kept in a setup.
    public var isRecording = false {
        didSet {
            // Said first, so the picture is drawn with the detail the
            // recording asks for by the time its first frame comes.
            onRecordingChanged?()
            recorder.apply(
                isOn: isRecording, folder: recordingsDirectory, sceneName: sceneOnAirName,
                options: preferences.recording
            )
            recordingStatus = recorder.status
        }
    }
    /// Called each time a recording starts or stops.
    @ObservationIgnored var onRecordingChanged: (() -> Void)?
    /// How the recording is getting on.
    public private(set) var recordingStatus = RecordingStatus.off
    /// The settings that say which folders to save into and how a recording is made.
    private var preferences: AppPreferences
    /// What a recording is named after: the scene on air, as last said.
    /// Empty when there is none.
    @ObservationIgnored private var sceneOnAirName = ""

    private let recorder: RecordingSwitching
    private let snapshotTaker: SnapshotTaking
    private let files: FileRevealing

    init(
        preferences: AppPreferences, recorder: RecordingSwitching, snapshotTaker: SnapshotTaking,
        files: FileRevealing
    ) {
        self.preferences = preferences
        self.recorder = recorder
        self.snapshotTaker = snapshotTaker
        self.files = files
    }

    /// Looks again at how the recording is getting on.
    func refresh() {
        if recordingStatus != recorder.status {
            recordingStatus = recorder.status
        }
    }

    /// Saves the program picture and shows the file in Finder.
    public func takeSnapshot() {
        snapshotTaker.take(to: snapshotsDirectory)
    }

    /// Saves the program picture and says where it went.
    public func writeSnapshot() -> URL? {
        snapshotTaker.write(to: snapshotsDirectory)
    }

    /// The folder snapshots go to: the one chosen in Settings, or the
    /// Desktop when none has been chosen.
    public var snapshotsDirectory: URL { snapshotTaker.directory(for: preferences) }

    /// The folder recordings go to: the one chosen for them, or wherever
    /// snapshots go when none has been chosen.
    public var recordingsDirectory: URL {
        guard let folder = preferences.recordingsFolder, !folder.isEmpty else { return snapshotsDirectory }
        return URL(fileURLWithPath: folder)
    }

    /// Shows the folder recordings go to.
    public func openRecordingsFolder() {
        files.openFolder(recordingsDirectory)
    }
}

extension CaptureModel: PreferenceFollowing, StudioFollowing, SceneMarking {
    /// Takes the settings as they now are.
    func follow(_ preferences: AppPreferences) {
        self.preferences = preferences
    }

    /// Takes the name of the scene on air as it now is.
    func follow(_ studio: StudioSettings) {
        sceneOnAirName = [studio.sceneOnAir?.name].compactMap { $0 }.joined()
    }

    /// Marks, in the recording, that a different scene is on air.
    func markScene(named name: String) {
        recorder.markScene(named: name)
    }
}
