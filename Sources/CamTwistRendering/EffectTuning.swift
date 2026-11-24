import CoreGraphics
import Foundation

/// The numbers somebody might want to turn in how the effects behave. They
/// are settings, not laws: the app reads them from its configuration and
/// hands them in, so one can be changed without changing the code.
public struct EffectTuning: Equatable {
    /// How many frames a second the slow motion tape keeps.
    public var slowMotionFramesPerSecond: Double
    /// How many seconds slow motion may fall behind before it cuts forward.
    public var slowMotionLongestLag: Double
    /// The most points across a frame kept on the slow motion tape has.
    public var slowMotionWidestFrame: Double
    /// How many frames a face may go unseen before it counts as gone.
    public var faceFramesHeld: Int
    /// How far each frame moves a character towards the face just seen, 0 to 1.
    public var characterSmoothing: Double
    /// The same for something worn, which must keep closer to the head.
    public var wornSmoothing: Double

    public init(
        slowMotionFramesPerSecond: Double, slowMotionLongestLag: Double, slowMotionWidestFrame: Double,
        faceFramesHeld: Int, characterSmoothing: Double, wornSmoothing: Double
    ) {
        self.slowMotionFramesPerSecond = slowMotionFramesPerSecond
        self.slowMotionLongestLag = slowMotionLongestLag
        self.slowMotionWidestFrame = slowMotionWidestFrame
        self.faceFramesHeld = faceFramesHeld
        self.characterSmoothing = characterSmoothing
        self.wornSmoothing = wornSmoothing
    }
}
