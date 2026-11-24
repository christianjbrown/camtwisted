import CamTwistControl
import CamTwistCore
import CamTwistRendering
import CoreImage
import Foundation

extension AppAssembly {
    /// Where the picture goes: the virtual camera and microphone, the
    /// streams, the recorder and the full-screen picture.
    struct OutputSet {
        let webStream: WebStreamOutput
        let webMovie: WebStreamOutput
        let rtmp: RTMPOutput
        let cameraSink: VirtualCameraSink
        let microphoneSink: VirtualMicrophoneSink
        let recorder: RecordingOutput
        let fullScreenMonitor: PreviewSink

        init(_ basics: Basics) {
            let pacing = basics.pacing
            let queues = basics.queues
            let clocks = basics.clocks
            let framesPerSecond = Int32(CameraContract.framesPerSecond)
            webStream = WebStreamOutput(
                kind: .hls, title: CameraContract.deviceName, canvas: CameraContract.size,
                framesPerSecond: framesPerSecond,
                piecesKept: pacing.streamPiecesKept, longestWaitForSound: pacing.longestWaitForSound,
                largestRequest: pacing.webLargestRequest, queues: queues, clocks: clocks
            )
            webMovie = WebStreamOutput(
                kind: .movie, title: CameraContract.deviceName, canvas: CameraContract.size,
                framesPerSecond: framesPerSecond,
                piecesKept: pacing.streamPiecesKept, longestWaitForSound: pacing.longestWaitForSound,
                largestRequest: pacing.webLargestRequest, queues: queues, clocks: clocks
            )
            rtmp = RTMPOutput(
                canvas: CameraContract.size, framesPerSecond: framesPerSecond, chunkSize: pacing.streamChunkSize,
                largestRead: pacing.streamLargestRead, queues: queues, clocks: clocks
            )
            cameraSink = VirtualCameraSink(reconnectInterval: pacing.cameraReconnectInterval, clock: clocks.uptime)
            microphoneSink = VirtualMicrophoneSink(
                lookInterval: pacing.microphoneLookInterval, clock: clocks.uptime,
                queue: queues.makeQueue(label: VirtualMicrophoneSink.queueLabel, qos: .default)
            )
            recorder = RecordingOutput(
                soundRate: pacing.recordingSoundRate,
                bitsPerPixelPerSecond: pacing.recordingBitsPerPixelPerSecond, clocks: clocks
            )
            fullScreenMonitor = PreviewSink(main: .main)
        }

        /// Those sent the picture on air, beside the window's own monitors.
        var programSinks: [FrameSink] { [fullScreenMonitor, webStream, webMovie, rtmp, recorder] }

        /// Those that hear the mix.
        var soundSinks: [SoundSink] { [webStream, webMovie, rtmp, microphoneSink, recorder] }

        func parts(airPlay: AirPlayOutput, cast: CastOutput) -> OutputParts {
            OutputParts(
                installer: CameraExtensionInstaller(
                    extensionIdentifier: Bundle.main.object(
                        forInfoDictionaryKey: CameraExtensionInstaller.bundleIdentifierInfoKey
                    ) as? String ?? "",
                    requests: SystemExtensionRequests()
                ),
                cameraConnection: cameraSink,
                processes: RunningProcesses(),
                webStream: webStream,
                webMovie: webMovie,
                rtmp: rtmp,
                airPlay: airPlay,
                cast: cast,
                addresses: SystemAddresses()
            )
        }

        func captureParts(_ basics: Basics) -> CaptureParts {
            CaptureParts(
                recorder: recorder,
                snapshots: PNGSnapshotWriter(context: CIContext(), files: .default, clock: basics.clocks.today),
                folders: SystemFolders()
            )
        }
    }
}
