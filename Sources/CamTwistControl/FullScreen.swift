import CamTwistRendering
import Foundation

/// Decides which display the full screen output covers.
@MainActor
final class FullScreenController {
    private let output: FullScreenPresenting

    init(output: FullScreenPresenting) {
        self.output = output
    }

    /// Covers a display, or uncovers all of them when none is asked for.
    /// Returns the display that ended up covered: nil when the display
    /// asked for is not there.
    func cover(_ displayID: UInt32?) -> UInt32? {
        guard let displayID else {
            output.hide()
            return nil
        }
        return output.show(onDisplay: displayID) ? displayID : nil
    }

    /// The covered display if it is still connected, nil once it is gone.
    func stillConnected(_ displayID: UInt32?, among displays: [DisplayChoice]) -> UInt32? {
        guard let displayID, displays.contains(where: { $0.id == displayID }) else { return nil }
        return displayID
    }
}
