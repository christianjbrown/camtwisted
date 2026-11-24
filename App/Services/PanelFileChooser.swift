import AppKit
import CamTwistControl
import SwiftUI
import UniformTypeIdentifiers

/// Picks files, folders and setup files with the system's own panels.
struct PanelFileChooser: FileChoosing, SetupFileChoosing {
    /// Keeps the permission to read what is chosen, for the next launch.
    let access: FileAccessKeeping

    private var setupTypes: [UTType] { [UTType(filenameExtension: SetupFileName.fileExtension)].compactMap { $0 } }

    func chooseFiles(allowedExtensions: Set<String>, allowsFolders: Bool, allowsMany: Bool) -> [String] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = allowsMany
        panel.canChooseDirectories = allowsFolders
        panel.canChooseFiles = !allowedExtensions.isEmpty
        if !allowedExtensions.isEmpty {
            // Folders are named too, or the panel opens them instead of choosing them.
            panel.allowedContentTypes = allowedExtensions.compactMap { UTType(filenameExtension: $0) }
                + (allowsFolders ? [.folder] : [])
        }
        guard panel.runModal() == .OK else { return [] }
        let chosen = panel.urls.map(\.path)
        // So what was chosen can still be read the next time the app opens.
        access.remember(chosen)
        return chosen
    }

    func chooseSetupToOpen() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = setupTypes
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    func chooseSetupToSave(suggestedName: String?) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = setupTypes
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = SetupFileName.suggested(forOpenFile: suggestedName)
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Chooses nothing. It is what a view gets when no chooser was handed
/// down to it, so a missing one shows as a button that does nothing
/// and not as a panel from nowhere.
private struct NoFileChooser: FileChoosing {
    func chooseFiles(allowedExtensions: Set<String>, allowsFolders: Bool, allowsMany: Bool) -> [String] { [] }
}

private struct FileChooserKey: EnvironmentKey {
    static let defaultValue: FileChoosing = NoFileChooser()
}

extension EnvironmentValues {
    /// What the views pick files and folders with.
    var fileChooser: FileChoosing {
        get { self[FileChooserKey.self] }
        set { self[FileChooserKey.self] = newValue }
    }
}

/// Takes what was dropped on the picture, as the system hands it over.
protocol ItemDropReceiving {
    /// Whether there was anything to take.
    @MainActor func receive(_ providers: [NSItemProvider]) -> Bool
}

/// Reads the file out of each thing dropped and hands its path on.
struct DroppedFileLoader: ItemDropReceiving {
    let receiver: FileDropReceiving

    @MainActor func receive(_ providers: [NSItemProvider]) -> Bool {
        let receiver = self.receiver
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in receiver.receive([url.path]) }
            }
        }
        return !providers.isEmpty
    }
}

/// Takes nothing. It is what a view gets when no receiver was handed down to it.
private struct NoItemDrops: ItemDropReceiving {
    func receive(_ providers: [NSItemProvider]) -> Bool { false }
}

private struct FileDropsKey: EnvironmentKey {
    static let defaultValue: ItemDropReceiving = NoItemDrops()
}

extension EnvironmentValues {
    /// Where files dropped on the picture go.
    var fileDrops: ItemDropReceiving {
        get { self[FileDropsKey.self] }
        set { self[FileDropsKey.self] = newValue }
    }
}
