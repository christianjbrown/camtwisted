import CamTwistControl
import CamTwistCore
import CamTwistRendering
import Foundation

extension AppAssembly {
    /// The mix of what is heard, and the virtual microphone it is played to.
    static func soundParts(_ basics: Basics, sources: SourceSet, outputs: OutputSet) -> SoundParts {
        let registry = sources.registry
        return SoundParts(
            sound: SoundDesk(
                router: SoundRouter(
                    mixer: EngineSoundMixer(
                        sinks: outputs.soundSinks,
                        tapFrames: basics.pacing.soundTapFrames,
                        queue: basics.queues.makeQueue(label: EngineSoundMixer.queueLabel, qos: .default),
                        makeNode: RenderingSystem.makePlayerNode
                    ),
                    source: { registry.source(for: $0) as? SoundSource }
                ),
                microphoneAccess: CaptureMicrophoneAccess()
            ),
            microphone: outputs.microphoneSink,
            microphoneInstaller: microphoneInstaller(queue: basics.work)
        )
    }

    /// The store build may not install the microphone's driver itself.
    private static func microphoneInstaller(queue: WorkQueueing) -> MicrophoneInstalling {
        #if STORE
        AddOnMicrophoneInstaller(
            address: Bundle.main.object(forInfoDictionaryKey: AddOnMicrophoneInstaller.addressInfoKey) as? String,
            opener: WorkspaceAddressOpener(), queue: queue
        )
        #else
        SystemMicrophoneInstaller(
            resources: Bundle.main.resourceURL, files: DiskFileChecker(), commands: ProcessCommandRunner(),
            queue: queue
        )
        #endif
    }
}
