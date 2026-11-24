import Foundation

/// Says when to look again at what there is: once the person has answered
/// about the camera, and then every so often.
@MainActor
struct RefreshTriggers {
    let permissions: CameraPermissionRequesting
    let scheduler: Scheduling
    /// How often to re-check cameras, displays, windows and the camera.
    let interval: TimeInterval
    let queue: WorkQueueing

    func start(_ refresh: @escaping @MainActor () -> Void) {
        let queue = self.queue
        permissions.requestVideoAccess {
            queue.main(refresh)
        }
        scheduler.repeating(every: interval, refresh)
    }
}
