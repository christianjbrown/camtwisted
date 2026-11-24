import Foundation

/// An effect file found on disk.
public struct EffectFile: Equatable, Identifiable, Sendable {
    public let name: String
    public let url: URL

    public var id: String { name }

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
    }
}

/// Lists the files in a folder. Abstracted so the catalog can be tested
/// without touching the disk.
public protocol DirectoryListing: Sendable {
    func files(in directory: URL) throws -> [URL]
}

public struct FileManagerDirectoryListing: DirectoryListing {
    public init() {}

    public func files(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
    }
}

/// A picture file kept ready to use as a source.
public struct SavedPicture: Equatable, Identifiable, Sendable {
    /// The file's name without its extension, which is what it is shown as.
    public let name: String
    public let path: String

    public var id: String { path }

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

/// Finds the pictures in the folder the app keeps for ready-made sources:
/// anything dropped in there shows up in the picker under its own name.
public struct PictureCatalog: Sendable {
    private let listing: DirectoryListing

    public init(listing: DirectoryListing) {
        self.listing = listing
    }

    /// Every picture in the folder, sorted by name. A missing folder has none.
    public func pictures(in directory: URL) -> [SavedPicture] {
        let urls = (try? listing.files(in: directory)) ?? []
        return urls
            .filter { MediaFileTypes.isImage($0.path) }
            .map { SavedPicture(name: $0.deletingPathExtension().lastPathComponent, path: $0.path) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Finds the effect files of one type in a folder.
public struct EffectCatalog: Sendable {
    public static let webPageExtension = "html"
    /// Editors leave backup copies named like `Clock~.html` beside the real file.
    public static let backupSuffix = "~"

    private let listing: DirectoryListing
    private let fileExtension: String

    public init(
        listing: DirectoryListing,
        fileExtension: String
    ) {
        self.listing = listing
        self.fileExtension = fileExtension
    }

    /// Every effect in the folder, sorted by name. A missing folder is an
    /// empty catalog, not an error: effects are optional.
    public func effects(in directory: URL) -> [EffectFile] {
        let urls = (try? listing.files(in: directory)) ?? []
        return urls
            .filter { $0.pathExtension.lowercased() == fileExtension }
            .map { EffectFile(name: $0.deletingPathExtension().lastPathComponent, url: $0) }
            .filter { !$0.name.hasSuffix(Self.backupSuffix) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
