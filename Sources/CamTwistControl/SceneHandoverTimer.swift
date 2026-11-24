import CamTwistCore
import Foundation

/// Hands over to the next scene once the one on air has been on for as
/// long as it asks. Putting another scene on air first calls it off.
@MainActor
final class SceneHandoverTimer {
    /// The scene on air and the handover it asked for.
    private struct Countdown: Equatable {
        let sceneID: UUID
        let handover: SceneHandover
    }

    /// The model owns this, so it is not held on to from here.
    private unowned let state: KeyPlayedState
    private let timers: OneShotScheduling
    private var running: (countdown: Countdown, work: ScheduledWork)?

    init(state: KeyPlayedState, timers: OneShotScheduling) {
        self.state = state
        self.timers = timers
    }

    private func finished(_ countdown: Countdown) {
        running = nil
        state.goLive(withScene: countdown.handover.sceneID)
    }
}

extension SceneHandoverTimer: StudioFollowing {
    /// Starts the countdown for the scene on air, starting again when the
    /// scene or its handover changes.
    func follow(_ studio: StudioSettings) {
        let wanted = studio.sceneOnAir.flatMap { scene in
            scene.handover.map { Countdown(sceneID: scene.id, handover: $0) }
        }
        guard wanted != running?.countdown else { return }
        running?.work.cancel()
        running = wanted.map { countdown in
            (countdown, timers.after(countdown.handover.seconds) { [weak self] in self?.finished(countdown) })
        }
    }
}
