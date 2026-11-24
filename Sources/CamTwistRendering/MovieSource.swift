import AVFoundation
import CamTwistCore
import CoreImage

/// Lists the movie files in a folder. Abstracted so the hot folder can be
/// tested without a real directory.
public protocol MovieFolderListing {
    func movies(in folder: String) -> [String]
}

public struct FileManagerMovieFolderListing: MovieFolderListing {
    public init() {}

    public func movies(in folder: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        return names.sorted()
            .map { (folder as NSString).appendingPathComponent($0) }
            .filter(MediaFileTypes.isMovie)
    }
}

/// A playlist of movie files as a source.
public final class MovieSource: FrameSource, SoundSource {
    private let listener = Locked<((CMSampleBuffer) -> Void)?>(nil)

    /// Where the sound of the clip that is playing is heard.
    public var onSound: ((CMSampleBuffer) -> Void)? {
        get { listener.get() }
        set { listener.set(newValue) }
    }

    private enum Tuning {
        /// Caption text height as a fraction of the picture's height.
        static let captionHeight: CGFloat = 0.07
        /// Gap between the caption and the bottom edge, same units.
        static let captionMargin: CGFloat = 0.05
        static let captionFont = "Helvetica-Bold"
        /// Point size the caption is first drawn at, before scaling to fit.
        static let captionPointSize: CGFloat = 96
    }

    private let settings: Locked<MovieSettings>
    private let folderListing: MovieFolderListing
    private let player: AVPlayer
    private let onMain: MainHop
    private let randomIndex: IndexPicker
    private let frames = LatestFrameBox()
    private var output: AVPlayerItemVideoOutput?
    private var playlist: [String] = []
    private var currentIndex = 0
    private var endObserver: NSObjectProtocol?
    private var hotFolderTimer: Cancelling?
    private let timers: RepeatingTimers
    private let notifications: NotificationCenter
    private let currentFile = Locked<String?>(nil)
    private let isStopped = Locked(false)

    private let hotFolderInterval: TimeInterval
    private var caption: (text: String, image: CIImage)?

    public init(
        settings: MovieSettings,
        folderListing: MovieFolderListing,
        timers: RepeatingTimers,
        notifications: NotificationCenter,
        player: AVPlayer,
        onMain: @escaping MainHop,
        randomIndex: @escaping IndexPicker,
        hotFolderInterval: TimeInterval = Pacing.usual.hotFolderInterval
    ) {
        self.player = player
        self.onMain = onMain
        self.randomIndex = randomIndex
        self.timers = timers
        self.notifications = notifications
        self.hotFolderInterval = hotFolderInterval
        self.settings = Locked(settings)
        self.folderListing = folderListing
    }

    /// The path of the clip that is playing, for scripting.
    public var currentTrackFile: String? { currentFile.get() }

    public var latestFrame: CIImage? {
        let settings = settings.get()
        if settings.hidesWhenStopped, isStopped.get() || !settings.isPlaying { return nil }
        if let output {
            let time = player.currentTime()
            if output.hasNewPixelBuffer(forItemTime: time),
               let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                frames.store(CIImage(cvPixelBuffer: buffer))
            }
        }
        guard let frame = frames.load() else { return nil }
        guard let file = currentFile.get(), let text = settings.captions?[file], !text.isEmpty else { return frame }
        return captioned(frame, with: text)
    }

    /// Draws caption text along the bottom of a frame.
    private func captioned(_ frame: CIImage, with text: String) -> CIImage {
        if caption?.text != text {
            let generated = CIFilter(name: CIFilterName.textImageGenerator, parameters: [
                CIInputKey.text: text,
                CIInputKey.fontName: Tuning.captionFont,
                CIInputKey.fontSize: Tuning.captionPointSize,
            ])?.outputImage
            caption = generated.map { (text, $0.applyingFilter(CIFilterName.colorInvert)) }
        }
        guard let image = caption?.image, image.extent.height > 0 else { return frame }
        let extent = frame.extent
        let scale = extent.height * Tuning.captionHeight / image.extent.height
        let width = image.extent.width * scale
        let placed = image.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(
                translationX: extent.minX + (extent.width - width) / 2,
                y: extent.minY + extent.height * Tuning.captionMargin
            ))
        )
        return placed.composited(over: frame)
    }

    public func start() {
        onMain { [self] in
            self.endObserver = self.notifications.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: nil
            ) { [weak self] notification in
                let item = notification.object as? AVPlayerItem
                self?.onMain { [weak self] in
                    guard let self, item === self.player.currentItem else { return }
                    self.clipEnded()
                }
            }
            self.hotFolderTimer = self.timers.every(self.hotFolderInterval) { [weak self] in self?.refreshPlaylist() }
            self.refreshPlaylist()
            self.applyPlaybackSettings()
        }
    }

    public func stop() {
        onMain {
            self.hotFolderTimer?.cancel()
            self.hotFolderTimer = nil
            if let endObserver = self.endObserver {
                self.notifications.removeObserver(endObserver)
            }
            self.player.pause()
            self.player.replaceCurrentItem(with: nil)
            self.output = nil
            self.frames.store(nil)
        }
    }

    public func update(to spec: SourceSpec) -> Bool {
        guard case .movie(let new) = spec else { return false }
        settings.set(new)
        onMain {
            self.refreshPlaylist()
            self.applyPlaybackSettings()
        }
        return true
    }

    // MARK: Playlist, on the main queue

    private func refreshPlaylist() {
        let settings = settings.get()
        var files = settings.files
        if let folder = settings.hotFolder, !folder.isEmpty {
            files += folderListing.movies(in: folder).filter { !files.contains($0) }
        }
        guard files != playlist else { return }
        let playing = currentFile.get()
        playlist = files
        if let playing, let index = files.firstIndex(of: playing) {
            currentIndex = index
        } else {
            play(index: 0)
        }
    }

    private func play(index: Int) {
        guard playlist.indices.contains(index) else {
            player.replaceCurrentItem(with: nil)
            output = nil
            currentFile.set(nil)
            frames.store(nil)
            return
        }
        currentIndex = index
        let item = AVPlayerItem(url: URL(fileURLWithPath: playlist[index]))
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(output)
        self.output = output
        PlayerSoundTap.attach(to: item) { [weak self] in self?.listener.get()?($0) }
        player.replaceCurrentItem(with: item)
        currentFile.set(playlist[index])
        isStopped.set(false)
        applyPlaybackSettings()
    }

    private func clipEnded() {
        let next = PlaylistSequencer.next(
            after: currentIndex, count: playlist.count, mode: settings.get().playMode
        ) { randomIndex(0..<$0) }
        if let next {
            play(index: next)
        } else {
            isStopped.set(true)
        }
    }

    private func applyPlaybackSettings() {
        let settings = settings.get()
        player.isMuted = settings.isMuted
        player.volume = Float(settings.volume)
        player.audioOutputDeviceUniqueID = settings.audioDeviceID
        if settings.isPlaying, !isStopped.get() {
            player.play()
        } else {
            player.pause()
        }
    }
}

public struct MovieSourceProvider: SourceProvider {
    private let folderListing: MovieFolderListing
    private let timers: RepeatingTimers
    private let notifications: NotificationCenter
    private let hotFolderInterval: TimeInterval
    private let makePlayer: () -> AVPlayer
    private let onMain: MainHop
    private let randomIndex: IndexPicker

    public init(
        folderListing: MovieFolderListing, timers: RepeatingTimers, notifications: NotificationCenter,
        hotFolderInterval: TimeInterval, makePlayer: @escaping () -> AVPlayer, onMain: @escaping MainHop,
        randomIndex: @escaping IndexPicker
    ) {
        self.makePlayer = makePlayer
        self.onMain = onMain
        self.randomIndex = randomIndex
        self.folderListing = folderListing
        self.timers = timers
        self.notifications = notifications
        self.hotFolderInterval = hotFolderInterval
    }

    public func makeSource(for spec: SourceSpec) -> FrameSource? {
        guard case .movie(let settings) = spec else { return nil }
        return MovieSource(
            settings: settings, folderListing: folderListing, timers: timers, notifications: notifications,
            player: makePlayer(), onMain: onMain, randomIndex: randomIndex, hotFolderInterval: hotFolderInterval
        )
    }
}
