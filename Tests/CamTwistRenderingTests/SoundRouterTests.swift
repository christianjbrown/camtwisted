import CamTwistCore
import CoreMedia
import XCTest
@testable import CamTwistRendering

private final class FakeMixer: SoundMixing {
    var fed: [UUID] = []
    var levels: [UUID: Double] = [:]
    var removed: [UUID] = []

    func feed(_ sound: CMSampleBuffer, from input: UUID) { fed.append(input) }
    func setLevel(_ level: Double, for input: UUID) { levels[input] = level }
    func remove(_ input: UUID) {
        removed.append(input)
        levels[input] = nil
    }
}

private final class FakeSoundSource: SoundSource {
    var onSound: ((CMSampleBuffer) -> Void)?
}

/// Collects the sound it is sent.
private final class RecordingSink: SoundSink {
    private let lock = NSLock()
    private var buffers: [CMSampleBuffer] = []

    func send(_ sound: CMSampleBuffer) {
        lock.lock()
        buffers.append(sound)
        lock.unlock()
    }

    /// The loudest sample heard so far.
    var peak: Float {
        lock.lock()
        defer { lock.unlock() }
        return buffers.reduce(Float(0)) { loudest, buffer in
            guard let block = buffer.dataBuffer, let data = try? block.dataBytes() else { return loudest }
            return data.withUnsafeBytes { bytes in
                max(loudest, bytes.bindMemory(to: Float.self).map(abs).max() ?? 0)
            }
        }
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffers.count
    }
}

final class SoundRouterTests: XCTestCase {
    private let mixer = FakeMixer()
    private var sources: [UUID: FakeSoundSource] = [:]
    private lazy var router = SoundRouter(mixer: mixer) { [unowned self] in self.sources[$0] }

    func testSourcesInTheSceneAreHeardAtTheirLevels() {
        let camera = UUID()
        let video = UUID()
        sources = [camera: FakeSoundSource(), video: FakeSoundSource()]
        router.apply(levels: [camera: 0.8, video: 0.5])
        XCTAssertEqual(mixer.levels, [camera: 0.8, video: 0.5])

        sources[camera]?.onSound?(TestSound.buffer(at: 0))
        XCTAssertEqual(mixer.fed, [camera])

        // The same again only changes the levels.
        let listener = sources[camera]?.onSound
        router.apply(levels: [camera: 0.2, video: 0.5])
        XCTAssertEqual(mixer.levels[camera], 0.2)
        XCTAssertNotNil(listener)
        XCTAssertTrue(mixer.removed.isEmpty)
    }

    func testASourceNotRunningYetIsConnectedOnceItIs() {
        let camera = UUID()
        router.apply(levels: [camera: 1])
        XCTAssertEqual(mixer.levels[camera], 1, "its level is set ready")
        let late = FakeSoundSource()
        sources[camera] = late
        router.apply(levels: [camera: 1])
        XCTAssertNotNil(late.onSound)
    }

    func testASourceThatLeavesTheSceneFallsSilent() {
        let camera = UUID()
        let gone = UUID()
        sources = [camera: FakeSoundSource()]
        router.apply(levels: [camera: 1, gone: 1])
        router.apply(levels: [:])
        XCTAssertNil(sources[camera]?.onSound)
        XCTAssertEqual(Set(mixer.removed), [camera, gone])
        // Back in the scene, it is connected afresh.
        router.apply(levels: [camera: 0.5])
        XCTAssertNotNil(sources[camera]?.onSound)
    }

    func testARouterThatHasGoneLeavesItsSourcesHarmless() {
        let camera = UUID()
        let source = FakeSoundSource()
        var lost: FakeMixer? = FakeMixer()
        let router = SoundRouter(mixer: lost!) { _ in source }
        router.apply(levels: [camera: 1])
        lost = nil
        source.onSound?(TestSound.buffer(at: 0))
        XCTAssertNotNil(source.onSound)
    }
}

final class EngineSoundMixerTests: XCTestCase {
    func testWhatIsFedInComesOutMixedAtItsLevel() {
        let sink = RecordingSink()
        let mixer = makeEngineSoundMixer(sinks: [sink])
        let input = UUID()
        mixer.setLevel(1, for: input)
        let packet = 1024.0 / TestSound.rate
        // A second of tone, fed as it would arrive.
        for index in 0..<47 {
            mixer.feed(TestSound.buffer(at: Double(index) * packet), from: input)
            Thread.sleep(forTimeInterval: packet)
        }
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertGreaterThan(sink.count, 5, "the mix keeps coming out")
        XCTAssertGreaterThan(sink.peak, 0.1, "and the tone is in it")

        // Turned down to nothing, what comes out is silence.
        let quiet = RecordingSink()
        let silent = makeEngineSoundMixer(sinks: [quiet])
        let muted = UUID()
        silent.setLevel(0, for: muted)
        for index in 0..<30 {
            silent.feed(TestSound.buffer(at: Double(index) * packet), from: muted)
            Thread.sleep(forTimeInterval: packet)
        }
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertLessThan(quiet.peak, 0.001)
        silent.remove(muted)
        mixer.remove(input)
        mixer.remove(UUID())
    }
}
