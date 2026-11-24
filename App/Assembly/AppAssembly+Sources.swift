import CamTwistControl
import CamTwistCore
import CamTwistRendering
import Foundation

extension AppAssembly {
    /// Everything a scene can be made from, and the lists to pick from.
    struct SourceSet {
        let cameras: CameraSourceProvider
        let displays: DisplaySourceProvider
        let windows: WindowSourceProvider
        let microphones: MicrophoneSourceProvider
        let passwords: KeychainPasswords
        let registry: SourceRegistry

        init(_ basics: Basics) {
            let pacing = basics.pacing
            let queues = basics.queues
            let timers = basics.timers
            cameras = CameraSourceProvider(queues: queues)
            displays = DisplaySourceProvider(queues: queues)
            windows = WindowSourceProvider(
                retryDelay: pacing.screenRetryDelay, ownProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
                sleep: RenderingSystem.sleeper, queues: queues
            )
            microphones = MicrophoneSourceProvider(queues: queues)
            passwords = KeychainPasswords()
            registry = SourceRegistry(providers: [
                cameras,
                displays,
                windows,
                MovieSourceProvider(
                    folderListing: FileManagerMovieFolderListing(), timers: timers,
                    notifications: NotificationCenter.default, hotFolderInterval: pacing.hotFolderInterval,
                    makePlayer: RenderingSystem.makePlayer, onMain: RenderingSystem.mainHop,
                    randomIndex: RenderingSystem.indexPicker
                ),
                SlideShowSourceProvider(folders: DiskSlideFolders(), now: basics.clocks.today),
                WebsiteSourceProvider(
                    snapshotsPerSecond: pacing.websiteSnapshotsPerSecond, timers: timers,
                    onMain: RenderingSystem.mainHop, makeHost: RenderingSystem.makeWebPageHost
                ),
                StreamSourceProvider(),
                VNCSourceProvider(
                    passwords: passwords, retryDelay: pacing.remoteScreenRetryDelay,
                    largestRead: pacing.remoteScreenLargestRead, queues: queues
                ),
                microphones,
                TelestratorSourceProvider(),
                ColorBarsSourceProvider(),
                TestCardSourceProvider(),
                ImageSourceProvider(),
                TextSourceProvider(),
                ShapeSourceProvider(),
            ])
        }

        func parts(_ basics: Basics, effects: EffectSet, thumbnailer: EffectThumbnailing) -> SourceParts {
            SourceParts(
                effectLibrary: effects.library,
                sourceChoices: SystemSourceChoices(
                    cameraProvider: cameras, displayProvider: displays, windowProvider: windows,
                    microphoneProvider: microphones
                ),
                thumbnailer: thumbnailer,
                pictureCatalog: PictureCatalog(listing: FileManagerDirectoryListing()),
                picturesDirectory: basics.configuration.picturesDirectory,
                fileChecker: DiskFileChecker(),
                passwords: passwords
            )
        }
    }
}
