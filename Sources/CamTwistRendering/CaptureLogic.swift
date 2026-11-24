import CamTwistCore
import CoreGraphics
import CoreImage
import Foundation

/// The decisions behind capturing a display, kept apart from the system
/// calls that do the capturing so they can be tested.
enum DisplayCapture {
    /// Where the pointer is when nothing says: the middle.
    static let centre = 0.5

    /// The part of a captured frame the source shows. A region with no area
    /// shows the whole frame.
    static func framed(_ frame: CIImage, settings: DisplaySettings, pointer: () -> CGPoint) -> CIImage {
        let size = frame.extent.size
        let crop = settings.followsMouse
            ? CaptureRegion.rect(following: pointer(), fraction: settings.followFraction, in: size)
            : CaptureRegion.rect(for: settings.region, in: size)
        guard crop.width > 0, crop.height > 0 else { return frame }
        return frame.cropped(to: crop.offsetBy(dx: frame.extent.minX, dy: frame.extent.minY))
    }

    /// The pointer's place on a screen as shares of its width and height,
    /// or the middle when the screen is not known or has no area.
    static func unitPosition(of pointer: CGPoint, on screen: CGRect?) -> CGPoint {
        guard let screen, screen.width > 0, screen.height > 0 else { return CGPoint(x: centre, y: centre) }
        return CGPoint(x: (pointer.x - screen.minX) / screen.width, y: (pointer.y - screen.minY) / screen.height)
    }

    /// Whether the running stream still suits new settings. A different
    /// display or cursor setting needs a new stream.
    static func keepsStream(from old: DisplaySettings, to new: DisplaySettings) -> Bool {
        new.displayID == old.displayID && new.showsCursor == old.showsCursor
    }

    /// A length in points as whole pixels.
    static func pixels(_ points: CGFloat, scale: CGFloat) -> Int {
        Int(points * scale)
    }
}

/// Lets an attempt through only when enough time has passed since the last
/// one that was let through, so a missing device is not asked for on every
/// frame. Times are seconds on any steady clock.
struct AttemptThrottle {
    private static let never = -TimeInterval.infinity

    let interval: TimeInterval
    private var lastAttempt = never

    init(interval: TimeInterval) {
        self.interval = interval
    }

    mutating func permits(at now: TimeInterval) -> Bool {
        guard now - lastAttempt > interval else { return false }
        lastAttempt = now
        return true
    }

    /// Forgets the last attempt, so the next one is let through.
    mutating func reset() {
        lastAttempt = Self.never
    }
}

/// The steady clock devices are timed by.
public enum SteadyClock {
    public static func uptime() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}

/// The decisions behind listing cameras.
enum CameraListing {
    /// The most pixels any of a camera's formats gives in a frame, or none
    /// for a camera that lists no formats.
    static func mostPixels(of sizes: [(width: Int, height: Int)]) -> Int {
        sizes.map { $0.width * $0.height }.max() ?? 0
    }

    /// Whether a device is one to offer: not our own virtual camera, which
    /// would feed back.
    static func isOffered(uniqueID: String) -> Bool {
        uniqueID != CameraContract.deviceID.uuidString
    }
}

/// The decisions behind finding windows to capture.
enum WindowSelection {
    /// Layer of ordinary application windows in the window list.
    private static let normalWindowLayer = 0

    /// Whether a window is the one the settings name. Until a window has
    /// been chosen, and for a window with no title, nothing matches.
    static func isMatch(title: String?, application: String?, settings: WindowSettings) -> Bool {
        guard !settings.titlePattern.isEmpty || settings.applicationName != nil else { return false }
        guard let title, !title.isEmpty else { return false }
        return WindowMatcher.matches(title: title, application: application ?? "", settings: settings)
    }

    /// The titled, ordinary windows in a system window list, each once,
    /// without the ones that belong to a process.
    static func choices(from list: [[String: Any]], excludingProcess ownProcess: Int32) -> [WindowChoice] {
        var seen = Set<String>()
        return list.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == normalWindowLayer,
                  info[kCGWindowOwnerPID as String] as? Int32 != ownProcess,
                  let title = info[kCGWindowName as String] as? String, !title.isEmpty,
                  let application = info[kCGWindowOwnerName as String] as? String
            else { return nil }
            let choice = WindowChoice(title: title, application: application)
            return seen.insert(choice.id).inserted ? choice : nil
        }
    }
}
