import CoreMedia
import XCTest
@testable import CamTwistRendering

final class SoundTapsTests: XCTestCase {
    private var sources: [UUID: FakeSoundSource] = [:]
    private lazy var taps = SoundTaps { [unowned self] in self.sources[$0] }
    private let camera = UUID()
    private let mix = ObjectIdentifier(NSObject.self)
    private let captions = ObjectIdentifier(NSString.self)

    func testEveryListenerHearsTheSourceUntilTheLastOneStops() {
        sources = [camera: FakeSoundSource()]
        var mixHeard = 0
        var captionsHeard = 0
        taps.listen(to: camera, as: mix) { _ in mixHeard += 1 }
        taps.listen(to: camera, as: captions) { _ in captionsHeard += 1 }
        sources[camera]?.onSound?(TestSound.buffer(at: 0))
        XCTAssertEqual([mixHeard, captionsHeard], [1, 1])

        // Listening again replaces the handler rather than adding one.
        taps.listen(to: camera, as: mix) { _ in mixHeard += 10 }
        sources[camera]?.onSound?(TestSound.buffer(at: 0))
        XCTAssertEqual([mixHeard, captionsHeard], [11, 2])

        taps.stopListening(to: camera, as: mix)
        XCTAssertNotNil(sources[camera]?.onSound, "still connected for the captions")
        sources[camera]?.onSound?(TestSound.buffer(at: 0))
        XCTAssertEqual([mixHeard, captionsHeard], [11, 3])

        taps.stopListening(to: camera, as: captions)
        XCTAssertNil(sources[camera]?.onSound)
        taps.stopListening(to: camera, as: captions)
        taps.stopListening(to: UUID(), as: mix)
    }

    func testASourceThatStartsLateOrAfreshIsConnectedWhenListenedToAgain() {
        var heard = 0
        taps.listen(to: camera, as: mix) { _ in heard += 1 }
        let late = FakeSoundSource()
        sources[camera] = late
        taps.listen(to: camera, as: mix) { _ in heard += 1 }
        late.onSound?(TestSound.buffer(at: 0))
        XCTAssertEqual(heard, 1)

        let fresh = FakeSoundSource()
        sources[camera] = fresh
        taps.listen(to: camera, as: mix) { _ in heard += 1 }
        fresh.onSound?(TestSound.buffer(at: 0))
        XCTAssertEqual(heard, 2)

        // The one it replaced, still sending after everyone stopped, reaches nobody.
        taps.stopListening(to: camera, as: mix)
        late.onSound?(TestSound.buffer(at: 0))
        XCTAssertEqual(heard, 2)
    }

    func testTapsThatHaveGoneLeaveTheirSourcesHarmless() {
        let source = FakeSoundSource()
        var gone: SoundTaps? = SoundTaps { _ in source }
        gone?.listen(to: camera, as: mix) { _ in XCTFail("nobody is left to hear it") }
        gone = nil
        source.onSound?(TestSound.buffer(at: 0))
    }
}

/// Counts what it is asked to do, and hands sound to whoever listens.
final class FakeTaps: SoundTapping {
    private(set) var handlers: [UUID: (CMSampleBuffer) -> Void] = [:]
    private(set) var listens = 0
    private(set) var stopped: [UUID] = []

    func listen(to source: UUID, as key: ObjectIdentifier, _ handler: @escaping (CMSampleBuffer) -> Void) {
        handlers[source] = handler
        listens += 1
    }

    func stopListening(to source: UUID, as key: ObjectIdentifier) {
        handlers[source] = nil
        stopped.append(source)
    }
}

final class FakeTranscriber: SpeechTranscribing {
    var heard = HeardSpeech.nothing
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var sent = 0

    func send(_ sound: CMSampleBuffer) { sent += 1 }
    func start() { starts += 1 }
    func stop() { stops += 1 }
}

/// A session that counts its starts, stops and refreshes.
final class FakeSession: CaptionSession {
    var heard = HeardSpeech.nothing
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var refreshes = 0

    func start() { starts += 1 }
    func refresh() { refreshes += 1 }
    func stop() { stops += 1 }
}

final class CaptionsHubTests: XCTestCase {
    private let camera = UUID()
    private let video = UUID()
    private var made: [HeardSources: FakeSession] = [:]
    private lazy var hub = CaptionsHub { [unowned self] sources in
        let session = FakeSession()
        self.made[sources] = session
        return session
    }

    func testCaptionsHearingTheSameSourcesShareOneSessionThatStopsWithTheLast() throws {
        let sources = HeardSources(levels: [camera: 1])
        hub.join(sources)
        hub.join(sources)
        let session = try XCTUnwrap(made[sources])
        XCTAssertEqual(made.count, 1)
        XCTAssertEqual(session.starts, 1)

        session.heard = HeardSpeech(words: "Hello", when: .distantFuture)
        XCTAssertEqual(hub.heard(from: sources).words, "Hello")
        XCTAssertEqual(session.refreshes, 1, "reading connects sources that started since")

        hub.leave(sources)
        XCTAssertEqual(session.stops, 0, "still heard by the other")
        hub.leave(sources)
        XCTAssertEqual(session.stops, 1)
        XCTAssertEqual(hub.heard(from: sources), .nothing, "nothing once nobody listens")
        hub.leave(sources)
        XCTAssertEqual(session.stops, 1, "leaving again changes nothing")
    }

    func testDifferentSourcesOrLevelsAreHeardApart() {
        hub.join(HeardSources(levels: [camera: 1]))
        hub.join(HeardSources(levels: [camera: 0.5]))
        hub.join(HeardSources(levels: [camera: 1, video: 1]))
        XCTAssertEqual(made.count, 3)
    }

    func testASourceTurnedRightDownIsNotHeard() {
        XCTAssertEqual(HeardSources(levels: [camera: 0, video: 0.4]).levels, [video: 0.4])
        XCTAssertTrue(HeardSources(levels: [camera: 0]).isEmpty)
        XCTAssertTrue(HeardSources.none.isEmpty)
    }

    func testTheSilentHubHearsNothing() {
        let sources = HeardSources(levels: [camera: 1])
        CaptionsHub.silent.join(sources)
        XCTAssertEqual(CaptionsHub.silent.heard(from: sources), .nothing)
        CaptionsHub.silent.leave(sources)
        XCTAssertTrue(RenderingSupplies.system().speech === CaptionsHub.silent)
    }
}

final class MixedCaptionSessionTests: XCTestCase {
    private let camera = UUID()
    private let video = UUID()
    private let taps = FakeTaps()
    private let mixer = FakeMixer()
    private let transcriber = FakeTranscriber()

    func testTheSourcesAreMixedAtTheirLevelsAndWrittenDown() {
        let session = MixedCaptionSession(
            sources: HeardSources(levels: [camera: 1, video: 0.5]), taps: taps, mixer: mixer, transcriber: transcriber
        )
        session.start()
        XCTAssertEqual(transcriber.starts, 1)
        XCTAssertEqual(mixer.levels, [camera: 1, video: 0.5])
        taps.handlers[camera]?(TestSound.buffer(at: 0))
        XCTAssertEqual(mixer.fed, [camera])

        transcriber.heard = HeardSpeech(words: "Hello", when: .distantFuture)
        XCTAssertEqual(session.heard.words, "Hello")

        session.refresh()
        XCTAssertEqual(taps.listens, 4, "each source is listened to again")

        session.stop()
        XCTAssertEqual(Set(taps.stopped), [camera, video])
        XCTAssertEqual(Set(mixer.removed), [camera, video])
        XCTAssertEqual(transcriber.stops, 1)
    }
}

final class TranscriptTailTests: XCTestCase {
    func testSettledWordsAreFollowedByTheOnesStillBeingWorkedOut() {
        var tail = TranscriptTail()
        XCTAssertEqual(tail.words, "")
        tail.take("Good evening", isFinal: false)
        XCTAssertEqual(tail.words, "Good evening")
        tail.take("Good evening and welcome.", isFinal: true)
        tail.take(" Tonight we ", isFinal: false)
        XCTAssertEqual(tail.words, "Good evening and welcome. Tonight we")
        tail.take("Tonight we are live.", isFinal: true)
        XCTAssertEqual(tail.words, "Good evening and welcome. Tonight we are live.")
        tail.take("", isFinal: false)
        XCTAssertEqual(tail.words, "Good evening and welcome. Tonight we are live.")
    }

    func testOnlyTheEndIsKeptAndNoWordIsCutInHalf() {
        var tail = TranscriptTail()
        for index in 0..<200 {
            tail.take("word\(index)", isFinal: true)
        }
        XCTAssertLessThanOrEqual(tail.words.count, TranscriptTail.keptCharacters)
        XCTAssertTrue(tail.words.hasSuffix("word199"))
        XCTAssertTrue(tail.words.hasPrefix("word"), "it starts at a whole word")

        var unbroken = TranscriptTail()
        unbroken.take(String(repeating: "a", count: TranscriptTail.keptCharacters + 10), isFinal: false)
        XCTAssertEqual(unbroken.words.count, TranscriptTail.keptCharacters, "with no space to start at, just the end")
        XCTAssertEqual(TranscriptTail(), TranscriptTail())
    }
}
