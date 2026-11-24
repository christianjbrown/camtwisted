import Foundation

/// Saves the picture on air as a file.
struct SnapshotTaker {
    let frames: ProgramFrameProviding
    let writer: SnapshotWriting
    let folders: DefaultFolders
    let files: FileRevealing

    /// The folder snapshots go to: the one chosen in Settings, or the
    /// Desktop when none has been chosen.
    func directory(for preferences: AppPreferences) -> URL {
        if let folder = preferences.snapshotsFolder, !folder.isEmpty {
            return URL(fileURLWithPath: folder)
        }
        return folders.desktopDirectory
    }

    /// Saves the program picture and says where it went.
    func write(to directory: URL) -> URL? {
        guard let frame = frames.latestProgramFrame else { return nil }
        return writer.write(frame, to: directory)
    }

    /// Saves the program picture and shows the file in Finder.
    func take(to directory: URL) {
        guard let url = write(to: directory) else { return }
        files.reveal(url)
    }
}
