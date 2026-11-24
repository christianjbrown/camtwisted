import CamTwistCore
import CoreGraphics
import CoreImage
import Foundation

/// The parameter keys shared by the effects that can be dragged, resized,
/// turned and given a look. Each matches a name in the effect's own file.
enum EffectParameterKey {
    /// Where the effect sits across the frame.
    static let xPosition = "X_Position"
    /// Where the effect sits up and down the frame.
    static let yPosition = "Y_Position"
    /// The vertical position under the name a rolling effect gives it.
    static let yPositionAlternate = "Y_Position_1"
    /// How big the effect is.
    static let size = "Size"
    /// How far the effect is turned.
    static let rotation = "Rotation"
    /// The typeface of the text.
    static let fontName = "Font_Name"
    /// The text's shadow.
    static let shadow = "Shadow"
    /// The fill behind the text.
    static let background = "Background"
    /// The text's colour under its plain name.
    static let color = "Color"
    /// The text's colour under the name a proxy input gives it.
    static let proxyColor = "inputColor_proxy_1"
    /// The text's colour under the name the scrolling effect gives it.
    static let textColor = "Text_Color"
    /// The shadow's colour under the name the scrolling effect gives it.
    static let shadowColor = "Shadow_Color"
}

/// The text effects the app comes with: a line of text, text that turns
/// about its middle, text that scrolls and lines that roll in one by one.
/// Each can be dragged, resized and turned.
enum TextEffect {
    enum Name {
        static let text = "Text"
        static let rotating = "Spinning Text"
        static let scrolling = "Scrolling Text"
        static let rolling = "Credits Roll"
    }

    enum Key {
        static let string = "String"
        static let rotatingString = "inputString_proxy_1"
        static let rollingText = "Text"
        static let speed = "Speed"
        static let pause = "Pause"
        static let rollTime = "Roll_Time"
        static let transitionMode = "Transition_Mode"
    }

    static let startText = "Hello World!"
    static let startLines = "First line\nSecond line\nThird line"
    private static let lineBreak: Character = "\n"

    private enum Start {
        static let size = 0.5
        static let rollingSize = 0.35
        static let rotatingSpeed = 0.25
        static let scrollSpeed = 1.5
        static let rollTime = 1.0
        static let transitionMode = 1.0
        static let scrollY = 0.0
        static let rollingY = 0.0
    }

    private enum Range {
        static let rotatingSpeed: ClosedRange<Double> = 0...2
        static let scrollSpeed: ClosedRange<Double> = 1...10
        static let rollTime: ClosedRange<Double> = 0.1...3
        static let transitionMode: ClosedRange<Double> = 0...3
    }

    private enum Tuning {
        static let fullTurn = 2 * Double.pi
        /// Picture widths a scrolling line travels each second, for each
        /// step of its speed control.
        static let scrollWidthsPerStep = 0.2
        /// Space between rolled lines, as a share of the line's height.
        static let lineSpacing: CGFloat = 1.35
        /// How far a rolling line travels as it arrives, in line heights.
        static let rollDistance: CGFloat = 1.5
    }

    // MARK: Text

    private static let textPlacement = TextPlacement(
        xKey: EffectParameterKey.xPosition, yKey: EffectParameterKey.yPosition, sizeKey: EffectParameterKey.size, rotationKey: EffectParameterKey.rotation,
        startX: 0, startY: 0, startSize: Start.size
    )
    private static let textLook = TextLook(
        fontKey: EffectParameterKey.fontName, colorKey: EffectParameterKey.color, shadowKey: EffectParameterKey.shadow, backgroundKey: EffectParameterKey.background
    )

    private static func stringControl(_ key: String) -> EffectParameter {
        EffectParameter(key: key, displayName: "String", kind: .string, defaultValue: .string(startText))
    }

    static let text = NativeEffect(
        name: Name.text, kind: .overlay, parameters: [stringControl(Key.string)] + textLook.parameters + textPlacement.parameters
    ) { canvas in
        DrawnOverlay(canvas: canvas, animated: false) { values, _, canvas, context in
            TextStamp.draw(
                values.string(Key.string, default: startText), spanning: textPlacement.width(in: values, canvas: canvas),
                at: textPlacement.centre(in: values, canvas: canvas), rotation: textPlacement.rotation(in: values),
                fontName: textLook.fontName(in: values), color: textLook.color(in: values),
                shadow: textLook.shadow(in: values), background: textLook.background(in: values), context: context
            )
        }
    }

    // MARK: Rotating text

    private static let rotatingPlacement = TextPlacement(
        xKey: EffectParameterKey.xPosition, yKey: EffectParameterKey.yPosition, sizeKey: EffectParameterKey.size, rotationKey: EffectParameterKey.rotation,
        startX: 0, startY: 0, startSize: Start.size
    )
    private static let rotatingLook = TextLook(
        fontKey: EffectParameterKey.fontName, colorKey: EffectParameterKey.proxyColor, shadowKey: EffectParameterKey.shadow, backgroundKey: EffectParameterKey.background
    )
    private static let rotatingSpeed = NumberControl(
        key: Key.speed, displayName: "Speed", start: Start.rotatingSpeed, range: Range.rotatingSpeed
    )

    static let rotating = NativeEffect(
        name: Name.rotating, kind: .overlay,
        parameters: [stringControl(Key.rotatingString)] + rotatingLook.parameters + rotatingPlacement.parameters
            + [rotatingSpeed.parameter]
    ) { canvas in
        DrawnOverlay(canvas: canvas, animated: true) { values, time, canvas, context in
            // Turning about its upright middle shows the text ever narrower,
            // then from behind, as a sign on a pole would.
            let turn = cos(time * rotatingSpeed.value(in: values) * Tuning.fullTurn)
            TextStamp.draw(
                values.string(Key.rotatingString, default: startText),
                spanning: rotatingPlacement.width(in: values, canvas: canvas),
                at: rotatingPlacement.centre(in: values, canvas: canvas), rotation: rotatingPlacement.rotation(in: values),
                fontName: rotatingLook.fontName(in: values), color: rotatingLook.color(in: values),
                shadow: rotatingLook.shadow(in: values), background: rotatingLook.background(in: values),
                squeeze: CGFloat(turn), context: context
            )
        }
    }

    // MARK: Scrolling text

    private static let scrollPlacement = TextPlacement(
        xKey: EffectParameterKey.xPosition, yKey: EffectParameterKey.yPositionAlternate, sizeKey: EffectParameterKey.size, rotationKey: EffectParameterKey.rotation,
        startX: 0, startY: Start.scrollY, startSize: Start.size
    )
    private static let scrollLook = TextLook(
        fontKey: EffectParameterKey.fontName, colorKey: EffectParameterKey.proxyColor, shadowKey: EffectParameterKey.shadow, backgroundKey: nil
    )
    private static let scrollSpeed = NumberControl(
        key: Key.speed, displayName: "Speed", start: Start.scrollSpeed, range: Range.scrollSpeed
    )
    private static let pauseControl = SwitchControl(key: Key.pause, displayName: "Paused")

    /// How far a scrolling line has gone, kept between frames so pausing
    /// holds it where it is.
    private final class Travel {
        private var distance = 0.0
        /// The line starts its journey at time zero.
        private var lastTime: TimeInterval = 0

        func advance(to time: TimeInterval, widthsPerSecond: Double, paused: Bool) -> Double {
            if !paused { distance += max(time - lastTime, 0) * widthsPerSecond }
            lastTime = time
            return distance
        }
    }

    static let scrolling = NativeEffect(
        name: Name.scrolling, kind: .overlay,
        parameters: [stringControl(Key.string)] + scrollLook.parameters + scrollPlacement.parameters
            + [scrollSpeed.parameter, pauseControl.parameter]
    ) { canvas in
        let travel = Travel()
        return DrawnOverlay(canvas: canvas, animated: true) { values, time, canvas, context in
            let width = scrollPlacement.width(in: values, canvas: canvas)
            let travelled = travel.advance(
                to: time, widthsPerSecond: scrollSpeed.value(in: values) * Tuning.scrollWidthsPerStep,
                paused: pauseControl.isOn(in: values)
            ) * canvas.width
            // The line enters just past the right edge and leaves just past the left.
            let lane = canvas.width + width
            var centre = scrollPlacement.centre(in: values, canvas: canvas)
            centre.x += lane / 2 - CGFloat(travelled).truncatingRemainder(dividingBy: lane)
            TextStamp.draw(
                values.string(Key.string, default: startText), spanning: width, at: centre,
                rotation: scrollPlacement.rotation(in: values), fontName: scrollLook.fontName(in: values),
                color: scrollLook.color(in: values), shadow: scrollLook.shadow(in: values), context: context
            )
        }
    }

    // MARK: Rolling text

    private static let rollPlacement = TextPlacement(
        xKey: EffectParameterKey.xPosition, yKey: EffectParameterKey.yPosition, sizeKey: EffectParameterKey.size, rotationKey: EffectParameterKey.rotation,
        startX: 0, startY: Start.rollingY, startSize: Start.rollingSize
    )
    private static let rollLook = TextLook(
        fontKey: EffectParameterKey.fontName, colorKey: EffectParameterKey.textColor, shadowKey: EffectParameterKey.shadowColor, backgroundKey: nil
    )
    private static let rollTime = NumberControl(
        key: Key.rollTime, displayName: "Roll Time", start: Start.rollTime, range: Range.rollTime
    )
    private static let rollMode = NumberControl(
        key: Key.transitionMode, displayName: "Transition Mode", start: Start.transitionMode,
        range: Range.transitionMode
    )

    /// The ways a line arrives, by the number the control holds.
    private enum Arrival: Int, CaseIterable {
        case fade, rise, drop, slide

        /// Where a line is, in line heights from its place, `remaining` of
        /// the way from arriving (1 just starting, 0 arrived).
        func offset(remaining: CGFloat) -> CGPoint {
            switch self {
            case .fade: return .zero
            case .rise: return CGPoint(x: 0, y: -remaining * Tuning.rollDistance)
            case .drop: return CGPoint(x: 0, y: remaining * Tuning.rollDistance)
            case .slide: return CGPoint(x: -remaining * Tuning.rollDistance * Tuning.lineSpacing * 2, y: 0)
            }
        }
    }

    static let rolling = NativeEffect(
        name: Name.rolling, kind: .overlay,
        parameters: [
            EffectParameter(key: Key.rollingText, displayName: "Text", kind: .string, defaultValue: .string(startLines)),
        ] + rollLook.parameters + rollPlacement.parameters + [rollTime.parameter, rollMode.parameter]
    ) { canvas in
        DrawnOverlay(canvas: canvas, animated: true) { values, time, canvas, context in
            let lines = values.string(Key.rollingText, default: startLines).split(separator: lineBreak).map(String.init)
            let longest = lines.max { $0.count < $1.count } ?? ""
            let fontName = rollLook.fontName(in: values)
            guard let size = TextStamp.fontSize(
                for: longest, spanning: rollPlacement.width(in: values, canvas: canvas), fontName: fontName
            ) else { return }
            let arrival = Arrival(rawValue: Int(rollMode.value(in: values).rounded())) ?? .fade
            let centre = rollPlacement.centre(in: values, canvas: canvas)
            let turn = rollPlacement.rotation(in: values) * .pi / 180
            let step = size * Tuning.lineSpacing
            let seconds = max(rollTime.value(in: values), Range.rollTime.lowerBound)
            for (index, line) in lines.enumerated() {
                // Each line starts arriving as the one before it has arrived.
                let arrived = CGFloat(min(max((time - Double(index) * seconds) / seconds, 0), 1))
                guard arrived > 0 else { continue }
                let slot = (CGFloat(lines.count - 1) / 2 - CGFloat(index)) * step
                let moved = arrival.offset(remaining: 1 - arrived)
                // The block of lines turns about the point it is placed at.
                let local = CGPoint(x: moved.x * size, y: slot + moved.y * size)
                let point = CGPoint(
                    x: centre.x + local.x * CGFloat(cos(turn)) + local.y * CGFloat(sin(turn)),
                    y: centre.y - local.x * CGFloat(sin(turn)) + local.y * CGFloat(cos(turn))
                )
                context.setAlpha(arrived)
                TextStamp.drawLine(
                    line, fontSize: size, at: point, rotation: rollPlacement.rotation(in: values), fontName: fontName,
                    color: rollLook.color(in: values), shadow: rollLook.shadow(in: values), context: context
                )
            }
        }
    }

    static let all: [NativeEffect] = [text, rotating, scrolling, rolling]
}

public extension NativeEffect {
    /// A line of text, and text that turns, scrolls or rolls.
    static var textEffects: [NativeEffect] { TextEffect.all }
}
