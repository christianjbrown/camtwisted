import CamTwistControl
import CamTwistCore
import CamTwistRendering
import Foundation

extension AppAssembly {
    /// The effects and transitions there are to pick from.
    struct EffectSet {
        let supplies: RenderingSupplies
        let transitions: NativeTransitionLibrary
        let library: CombinedEffectLibrary

        init(_ basics: Basics, taps: SoundTapping) {
            let configuration = basics.configuration
            let pacing = basics.pacing
            supplies = RenderingSupplies.system(speech: Self.captions(basics, taps: taps))
            transitions = BuiltInEffects.transitionLibrary(directory: configuration.effectsDirectory)
            // Built-in effects and transitions come first, so one takes the
            // place of a file of the same name.
            library = CombinedEffectLibrary(
                primary: BuiltInEffects.library(
                    directory: configuration.effectsDirectory, tuning: configuration.tunables.effects,
                    supplies: supplies
                ),
                others: [
                    transitions,
                    HTMLEffectLibrary(
                        directory: configuration.effectsDirectory, snapshotsPerSecond: pacing.websiteSnapshotsPerSecond,
                        timers: basics.timers, listing: FileManagerDirectoryListing(),
                        onMain: RenderingSystem.mainHop, makeHost: RenderingSystem.makeWebPageHost
                    ),
                    HTMLEffectLibrary(
                        directory: configuration.bundledWebEffectsDirectory,
                        snapshotsPerSecond: pacing.websiteSnapshotsPerSecond,
                        timers: basics.timers, listing: FileManagerDirectoryListing(),
                        onMain: RenderingSystem.mainHop, makeHost: RenderingSystem.makeWebPageHost
                    ),
                ]
            )
        }

        /// Captions that hear the sources above them: each set of sources
        /// gets a mix of its own, written down on this Mac.
        private static func captions(_ basics: Basics, taps: SoundTapping) -> CaptionsListening {
            CaptionsHub { heard in
                let transcriber = transcriber()
                return MixedCaptionSession(
                    sources: heard, taps: taps,
                    mixer: EngineSoundMixer(
                        sinks: [transcriber],
                        tapFrames: basics.pacing.soundTapFrames,
                        queue: basics.queues.makeQueue(label: captionsQueueLabel, qos: .userInitiated),
                        makeNode: RenderingSystem.makePlayerNode
                    ),
                    transcriber: transcriber
                )
            }
        }

        private static let captionsQueueLabel = "captions.sound.mixer"

        /// The newer speech analysis where there is one, since it works with
        /// Siri and Dictation switched off; the older recognition before it.
        private static func transcriber() -> SpeechTranscribing {
            if #available(macOS 26, *) {
                return AnalyzerSpeechTranscriber(now: Date.init)
            }
            return AppleSpeechTranscriber(now: Date.init)
        }
    }
}
