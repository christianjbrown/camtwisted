import AVFoundation
import CoreMedia
import Foundation
import MediaToolbox

/// Hears the sound of something a player is playing, as well as letting it
/// play, and hands it on.
enum PlayerSoundTap {
    /// What a tap keeps: where to hand the sound, and what it is like.
    private final class Context {
        let output: (CMSampleBuffer) -> Void
        var format: AVAudioFormat?

        init(output: @escaping (CMSampleBuffer) -> Void) {
            self.output = output
        }
    }


    /// Starts handing on an item's sound. Does nothing for an item with no
    /// sound, or one played from a live stream, which cannot be listened to
    /// this way.
    static func attach(to item: AVPlayerItem, output: @escaping (CMSampleBuffer) -> Void) {
        Task {
            guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first else { return }
            let context = Context(output: output)
            var callbacks = MTAudioProcessingTapCallbacks(
                version: kMTAudioProcessingTapCallbacksVersion_0,
                clientInfo: Unmanaged.passRetained(context).toOpaque(),
                init: { _, clientInfo, storage in storage.pointee = clientInfo },
                finalize: { tap in
                    Unmanaged<Context>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
                },
                prepare: { tap, _, format in
                    let context = Unmanaged<Context>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                        .takeUnretainedValue()
                    context.format = AVAudioFormat(streamDescription: format)
                },
                unprepare: nil,
                process: { tap, frames, _, buffers, framesOut, flagsOut in
                    guard MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flagsOut, nil, framesOut) == noErr
                    else { return }
                    let context = Unmanaged<Context>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                        .takeUnretainedValue()
                    if let format = context.format,
                       let sound = SoundBuffers.sampleBuffer(
                           buffers: buffers, frames: framesOut.pointee, format: format,
                           atSeconds: SteadyClock.uptime()
                       ) {
                        context.output(sound)
                    }
                }
            )
            var tap: MTAudioProcessingTap?
            guard MTAudioProcessingTapCreate(
                kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &tap
            ) == noErr, let tap else { return }
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.audioTapProcessor = tap
            // Made here and handed to the player once, never touched again
            // from this side, so crossing to the main thread is safe.
            nonisolated(unsafe) let mix = AVMutableAudioMix()
            mix.inputParameters = [parameters]
            await MainActor.run { item.audioMix = mix }
        }
    }
}
