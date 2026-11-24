import CamTwistCore
import CamTwistRendering
import Foundation

/// One panel in the list of sources to add.
public struct SourceOffer: Equatable {
    public let title: String
    public let symbol: String
    public let detail: String?
    public let content: ChainItem.Content

    /// The tooltip: the title, and what the source is when that needs saying.
    public var help: String { detail.map { "\(title): \($0)" } ?? title }
}

/// The sources the picker offers, in order.
public enum SourceCatalog {
    private enum Symbol {
        static let camera = "web.camera"
        static let screen = "display"
        static let window = "macwindow"
        static let image = "photo"
        static let text = "textformat"
        static let shape = "square.on.circle"
        static let video = "film"
        static let slideShow = "photo.on.rectangle"
        static let website = "globe"
        static let microphone = "mic"
        static let stream = "dot.radiowaves.left.and.right"
        static let computer = "desktopcomputer"
        static let telestrator = "pencil.tip"
        static let colorBars = "rectangle.split.3x1.fill"
        static let effect = "sparkles"
    }

    /// The symbol on an effect's panel while it has no picture.
    public static let effectSymbol = Symbol.effect

    /// - Parameters:
    ///   - camera: a new camera source, when this Mac has a camera to offer.
    ///   - firstDisplayID: the first screen, when there is one.
    ///   - image: a new image source.
    public static func offers(camera: SourceSpec?, firstDisplayID: UInt32?, image: SourceSpec) -> [SourceOffer] {
        var list: [SourceOffer] = []
        // One panel each for cameras and screens: which one is chosen in the step.
        if let camera {
            list.append(SourceOffer(
                title: "Camera", symbol: Symbol.camera, detail: "a webcam: pick which in its settings",
                content: .source(camera)
            ))
        }
        if let firstDisplayID {
            list.append(SourceOffer(
                title: "Screen", symbol: Symbol.screen, detail: "a screen, or part of one: pick which in its settings",
                content: .source(.display(DisplaySettings(displayID: firstDisplayID)))
            ))
        }
        // Which window is chosen afterwards, in the step's settings.
        list += [
            SourceOffer(
                title: "Window", symbol: Symbol.window, detail: "one window, even when covered",
                content: .source(.window(WindowSettings(titlePattern: "")))
            ),
            SourceOffer(
                title: "Image", symbol: Symbol.image, detail: "a picture, a logo or a backdrop", content: .source(image)
            ),
            SourceOffer(
                title: "Text", symbol: Symbol.text, detail: "a title, a name or a caption",
                content: .source(.text(TextSettings()))
            ),
            SourceOffer(
                title: "Shape", symbol: Symbol.shape, detail: "a rectangle, circle, triangle, star and more",
                content: .source(.shape(ShapeSettings()))
            ),
            SourceOffer(title: "Video", symbol: Symbol.video, detail: nil, content: .source(.movie(MovieSettings()))),
            SourceOffer(
                title: "Slide show", symbol: Symbol.slideShow, detail: nil, content: .source(.slideShow(SlideShowSettings()))
            ),
            SourceOffer(title: "Website", symbol: Symbol.website, detail: nil, content: .source(.website(url: ""))),
            SourceOffer(
                title: "Microphone", symbol: Symbol.microphone, detail: "sound only: pick which in its settings",
                content: .source(.microphone(deviceID: nil))
            ),
            SourceOffer(
                title: "Stream", symbol: Symbol.stream, detail: "a live stream or a video, from its address",
                content: .source(.stream(StreamSettings()))
            ),
            SourceOffer(
                title: "Computer", symbol: Symbol.computer, detail: "another computer's screen, over VNC",
                content: .source(.vnc(VNCSettings()))
            ),
            SourceOffer(
                title: "Telestrator", symbol: Symbol.telestrator, detail: "draw on the picture",
                content: .source(.telestrator(TelestratorSettings()))
            ),
            SourceOffer(title: "Colour bars", symbol: Symbol.colorBars, detail: nil, content: .source(.colorBars)),
        ]
        return list
    }
}

/// Which effects the picker shows for what has been typed in its search.
public struct EffectOffers: Equatable {
    public let shown: [EffectListing]
    public let emptyMessage: String?

    public init(effects: [EffectListing], search: String) {
        shown = effects.filter { effect in
            effect.kind != .transition
                && (search.isEmpty || EffectNaming.title(for: effect.name).localizedCaseInsensitiveContains(search))
        }
        if !shown.isEmpty {
            emptyMessage = nil
        } else {
            emptyMessage = effects.isEmpty ? "No effects yet." : "No effect matches."
        }
    }
}
