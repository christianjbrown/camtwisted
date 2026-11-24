import CamTwistCore
import CoreImage

/// What sits at a path on disk.
public enum DiskEntryKind {
    case missing
    case file
    case folder
}

/// Asks the disk the two questions a slide show has: what is at a path, and
/// what is in a folder. Abstracted so slide shows can be tested without a disk.
public protocol SlideFolders {
    func kind(of path: String) -> DiskEntryKind
    /// The names inside a folder, in any order; none when it cannot be read.
    func names(in folder: String) -> [String]
}

/// Slide folders read from the real disk.
public struct DiskSlideFolders: SlideFolders {
    public init() {}

    public func kind(of path: String) -> DiskEntryKind {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return .missing }
        return isDirectory.boolValue ? .folder : .file
    }

    public func names(in folder: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
    }
}

/// Images shown one after another as a source.
public final class SlideShowSource: FrameSource {
    private let settings: Locked<SlideShowSettings>
    private let folders: SlideFolders
    private let now: () -> Date
    private var images: [String] = []
    private var elapsedBeforePause: TimeInterval = 0
    private var resumedAt: Date?
    private var shown: (index: Int, image: CIImage)?
    private let lock = NSLock()

    public init(settings: SlideShowSettings, folders: SlideFolders, now: @escaping () -> Date) {
        self.settings = Locked(settings)
        self.folders = folders
        self.now = now
        images = Self.expand(settings.paths, in: folders)
    }

    public var latestFrame: CIImage? {
        lock.lock()
        defer { lock.unlock() }
        let settings = settings.get()
        let running = resumedAt.map { now().timeIntervalSince($0) } ?? 0
        guard let index = SlideShowClock.index(
            at: elapsedBeforePause + running, delay: settings.delay, count: images.count, loops: settings.loops
        ) else { return nil }
        if shown?.index != index {
            let url = URL(fileURLWithPath: images[index])
            shown = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]).map { (index, $0) }
        }
        return shown?.image
    }

    public func start() {
        lock.lock()
        resumedAt = settings.get().isPaused ? nil : now()
        lock.unlock()
    }

    public func stop() {
        lock.lock()
        resumedAt = nil
        elapsedBeforePause = 0
        shown = nil
        lock.unlock()
    }

    public func update(to spec: SourceSpec) -> Bool {
        guard case .slideShow(let new) = spec else { return false }
        lock.lock()
        defer { lock.unlock() }
        let old = settings.get()
        if new.paths != old.paths {
            images = Self.expand(new.paths, in: folders)
            shown = nil
        }
        if new.isPaused, let resumedAt {
            elapsedBeforePause += now().timeIntervalSince(resumedAt)
            self.resumedAt = nil
        } else if !new.isPaused, resumedAt == nil {
            resumedAt = now()
        }
        settings.set(new)
        return true
    }

    /// Image files as given, and the images inside any folders, in name order.
    static func expand(_ paths: [String], in folders: SlideFolders) -> [String] {
        paths.flatMap { path -> [String] in
            switch folders.kind(of: path) {
            case .missing:
                return []
            case .file:
                return MediaFileTypes.isImage(path) ? [path] : []
            case .folder:
                return folders.names(in: path).sorted()
                    .map { (path as NSString).appendingPathComponent($0) }
                    .filter(MediaFileTypes.isImage)
            }
        }
    }
}

public struct SlideShowSourceProvider: SourceProvider {
    private let folders: SlideFolders
    private let now: () -> Date

    public init(folders: SlideFolders, now: @escaping () -> Date) {
        self.folders = folders
        self.now = now
    }

    public func makeSource(for spec: SourceSpec) -> FrameSource? {
        guard case .slideShow(let settings) = spec else { return nil }
        return SlideShowSource(settings: settings, folders: folders, now: now)
    }
}
