import AppKit
import AVFoundation
import CoreImage
import WebKit

/// Hands a piece of work to the main thread.
public typealias MainHop = (@escaping () -> Void) -> Void

/// Waits for a number of seconds.
public typealias Sleeper = (TimeInterval) async throws -> Void

/// Picks a number from a range, for the choices that are left to chance.
public typealias IndexPicker = (Range<Int>) -> Int

/// A web view with the window it is kept in.
public struct WebPageHost {
    let webView: WKWebView
    let window: NSWindow
}

/// Makes the web view for a page of a size, and its window. The flag says
/// whether the page's own background is left clear.
public typealias WebPageHostMaker = (CGRect, Bool) -> WebPageHost

/// The system's own versions of what the sources and renderers are handed,
/// which is what the app runs with.
public enum RenderingSystem {
    /// WebKit's switch for painting a page background, reached by key
    /// because macOS has no public property for it.
    private static let drawsBackgroundKey = "drawsBackground"

    public static let mainHop: MainHop = { work in DispatchQueue.main.async(execute: work) }

    public static let sleeper: Sleeper = { seconds in try await Task.sleep(for: .seconds(seconds)) }

    public static let indexPicker: IndexPicker = { Int.random(in: $0) }

    /// A context that does not hold on to what it drew, as frames are never drawn twice.
    public static func makeContext() -> CIContext {
        CIContext(options: [.cacheIntermediates: false])
    }

    public static func makePlayer() -> AVPlayer {
        AVPlayer()
    }

    public static func makePlayerNode() -> AVAudioPlayerNode {
        AVAudioPlayerNode()
    }

    /// A web view only draws while it is in a window, so it lives in one
    /// that is never shown.
    public static let makeWebPageHost: WebPageHostMaker = { frame, isTransparent in
        let webView = WKWebView(frame: frame)
        if isTransparent {
            webView.setValue(false, forKey: drawsBackgroundKey)
        }
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isOpaque = !isTransparent
        window.backgroundColor = isTransparent ? .clear : .white
        window.contentView = webView
        return WebPageHost(webView: webView, window: window)
    }
}
