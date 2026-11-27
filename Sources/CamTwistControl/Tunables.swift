import CamTwistCore
import CamTwistRendering
import Foundation

/// The settings that can be turned without a new build, read once at
/// launch. Each is a default that can also be given on the command line,
/// as in `-SlowMotionLongestLag 4`.
public struct Tunables: Equatable {
    /// How the effects behave.
    public let effects: EffectTuning
    /// Seconds between looks at what cameras, screens and outputs there are.
    public let refreshInterval: TimeInterval
    /// How quickly things are retried, polled, read and buffered.
    public let pacing: Pacing

    /// The names the settings go by.
    public enum Key {
        public static let slowMotionFramesPerSecond = "SlowMotionFramesPerSecond"
        public static let slowMotionLongestLag = "SlowMotionLongestLag"
        public static let slowMotionWidestFrame = "SlowMotionWidestFrame"
        public static let faceFramesHeld = "FaceFramesHeld"
        public static let characterSmoothing = "CharacterSmoothing"
        public static let wornSmoothing = "WornSmoothing"
        public static let framingSmoothing = "FramingSmoothing"
        public static let refreshInterval = "RefreshInterval"
    }

    /// What each setting is when nobody has set it.
    private enum Default {
        /// Enough frames to blend smoothly between when played slowly.
        static let slowMotionFramesPerSecond = 12.0
        static let slowMotionLongestLag = 2.5
        /// Keeps the tape a reasonable size in memory even on a 4K picture.
        static let slowMotionWidestFrame = 1280.0
        /// About a third of a second, as long as a quick turn of the head hides a face.
        static let faceFramesHeld = 10
        /// Quick enough that a blink still shows.
        static let characterSmoothing = 0.6
        static let wornSmoothing = 0.85
        /// Slow enough that following a face looks like a smooth pan.
        static let framingSmoothing = 0.06
        static let refreshInterval: TimeInterval = 2
    }

    public init(effects: EffectTuning, refreshInterval: TimeInterval, pacing: Pacing) {
        self.effects = effects
        self.refreshInterval = refreshInterval
        self.pacing = pacing
    }

    public static func load(defaults: UserDefaults) -> Tunables {
        /// A number that has been set, or its usual value. Nought and
        /// below are never usable here, so they count as not set.
        func number(_ key: String, _ usual: Double) -> Double {
            let set = defaults.double(forKey: key)
            return set > 0 ? set : usual
        }
        /// A count that has been set, or its usual value. Nought is a
        /// count like any other; less than nought is taken as nought.
        func count(_ key: String, _ usual: Int) -> Int {
            (defaults.object(forKey: key) as? NSNumber).map { max($0.intValue, 0) } ?? usual
        }
        return Tunables(
            effects: EffectTuning(
                slowMotionFramesPerSecond: number(Key.slowMotionFramesPerSecond, Default.slowMotionFramesPerSecond),
                slowMotionLongestLag: number(Key.slowMotionLongestLag, Default.slowMotionLongestLag),
                slowMotionWidestFrame: number(Key.slowMotionWidestFrame, Default.slowMotionWidestFrame),
                faceFramesHeld: count(Key.faceFramesHeld, Default.faceFramesHeld),
                characterSmoothing: number(Key.characterSmoothing, Default.characterSmoothing),
                wornSmoothing: number(Key.wornSmoothing, Default.wornSmoothing),
                framingSmoothing: number(Key.framingSmoothing, Default.framingSmoothing)
            ),
            refreshInterval: number(Key.refreshInterval, Default.refreshInterval),
            pacing: Pacing.load(defaults: defaults)
        )
    }
}
