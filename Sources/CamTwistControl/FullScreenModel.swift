import CamTwistRendering
import Foundation
import Observation

/// The full screen output: which display the picture covers.
@MainActor
@Observable
public final class FullScreenModel {
    /// The display the full screen output covers, or nil while it is off.
    /// Not saved: the app never opens by covering a screen.
    public var displayID: UInt32? {
        didSet {
            guard displayID != oldValue else { return }
            let covered = covering.cover(displayID)
            if covered != displayID {
                displayID = covered
            }
        }
    }

    private let covering: FullScreenCovering
    private let output: FullScreenPresenting

    init(covering: FullScreenCovering, output: FullScreenPresenting) {
        self.covering = covering
        self.output = output
    }

    /// Listens for the output closing by itself, which clears the choice.
    func start() {
        // The output keeps this, so it must not hold the model in turn.
        output.onClose = { [weak self] in self?.displayID = nil }
    }

    /// Uncovers the display once it is no longer among those connected.
    func refresh(among displays: [DisplayChoice]) {
        let stillShown = covering.stillConnected(displayID, among: displays)
        if stillShown != displayID {
            displayID = stillShown
        }
    }
}
