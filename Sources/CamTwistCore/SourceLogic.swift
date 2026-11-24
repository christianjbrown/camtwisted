import CoreGraphics
import Foundation

/// Decides which clip of a playlist comes next.
public enum PlaylistSequencer {
    /// The index to play after `current` ends, or nil to stop.
    /// `shuffled` supplies a random index below the count it is given.
    public static func next(
        after current: Int,
        count: Int,
        mode: MoviePlayMode,
        shuffled: (Int) -> Int
    ) -> Int? {
        guard count > 0 else { return nil }
        switch mode {
        case .playOneAndStop:
            return nil
        case .playOneAndRepeat:
            return current
        case .playAllAndStop:
            return current + 1 < count ? current + 1 : nil
        case .playAllAndRepeat:
            return (current + 1) % count
        case .shuffle:
            return shuffled(count)
        }
    }
}

/// Which slide is up at a given moment.
public enum SlideShowClock {
    public static func index(at elapsed: TimeInterval, delay: TimeInterval, count: Int, loops: Bool) -> Int? {
        guard count > 0 else { return nil }
        guard delay > 0, elapsed > 0 else { return 0 }
        let passed = Int(elapsed / delay)
        // Without looping the show stays on its last image.
        return loops ? passed % count : min(passed, count - 1)
    }
}

/// Picks the part of a captured display to show.
public enum CaptureRegion {
    /// A fixed region, as pixels of a frame.
    public static func rect(for region: UnitRect, in frame: CGSize) -> CGRect {
        CGRect(
            x: region.x * frame.width,
            y: region.y * frame.height,
            width: region.width * frame.width,
            height: region.height * frame.height
        ).intersection(CGRect(origin: .zero, size: frame))
    }

    /// A window of `fraction` of the frame centred on the pointer, pushed
    /// back inside the frame at the edges. `pointer` is in unit coordinates.
    public static func rect(following pointer: CGPoint, fraction: Double, in frame: CGSize) -> CGRect {
        let size = CGSize(width: frame.width * fraction, height: frame.height * fraction)
        let x = min(max(pointer.x * frame.width - size.width / halvingDivisor, 0), frame.width - size.width)
        let y = min(max(pointer.y * frame.height - size.height / halvingDivisor, 0), frame.height - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private static let halvingDivisor: CGFloat = 2
}

/// Tests a window's title against what the user asked for.
public enum WindowMatcher {
    public static func matches(title: String, application: String, settings: WindowSettings) -> Bool {
        if let wanted = settings.applicationName, !wanted.isEmpty, wanted != application {
            return false
        }
        guard !settings.titlePattern.isEmpty else { return true }
        guard settings.isRegularExpression else {
            return title.localizedCaseInsensitiveContains(settings.titlePattern)
        }
        guard let expression = try? NSRegularExpression(pattern: settings.titlePattern, options: [.caseInsensitive])
        else { return false }
        return expression.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil
    }
}

/// File types the file based sources accept.
public enum MediaFileTypes {
    public static let movieExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "mpg", "mpeg"]
    public static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "tiff", "tif", "heic", "bmp"]

    public static func isMovie(_ path: String) -> Bool {
        movieExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    public static func isImage(_ path: String) -> Bool {
        imageExtensions.contains((path as NSString).pathExtension.lowercased())
    }
}
