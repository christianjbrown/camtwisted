import AppKit
import CamTwistCore
import CamTwistRendering
import Foundation

// What the source settings controls show and write, kept out of the views.

extension MoviePlayMode {
    public var label: String {
        switch self {
        case .playAllAndStop: return "Play all and stop"
        case .playOneAndRepeat: return "Play one and repeat"
        case .playOneAndStop: return "Play one and stop"
        case .playAllAndRepeat: return "Play all and repeat"
        case .shuffle: return "Shuffle"
        }
    }
}

extension CamTwistCore.TextAlignment {
    public var label: String {
        switch self {
        case .left: return "Left"
        case .center: return "Centre"
        case .right: return "Right"
        case .justified: return "Justify"
        }
    }
}

extension AnimatedProperty {
    public var label: String {
        switch self {
        case .positionX: return "Position X"
        case .positionY: return "Position Y"
        case .size: return "Size"
        case .rotation: return "Rotate"
        case .tilt: return "Tilt"
        case .swing: return "Swing"
        }
    }
}

extension AnimationMode {
    public var label: String {
        switch self {
        case .once: return "Stop at the end"
        case .loop: return "Start again"
        case .backAndForth: return "Go back and forth"
        }
    }
}

extension Corner {
    public var label: String {
        switch self {
        case .topLeft: return "Top left"
        case .topRight: return "Top right"
        case .bottomLeft: return "Bottom left"
        case .bottomRight: return "Bottom right"
        }
    }
}

/// Editing the part of a screen that is captured.
public enum DisplayRegionEditing {
    /// Where a capture area starts when full screen is switched off.
    public static let centreHalf = UnitRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    public static let minimumSide = 0.05

    public static func isFull(_ region: UnitRect) -> Bool { region == .full }

    public static func region(whenFull isFull: Bool) -> UnitRect { isFull ? .full : centreHalf }

    /// The ranges each edge of the area can move over without leaving the screen.
    public static func leftRange(_ region: UnitRect) -> ClosedRange<Double> { 0...(1 - region.width) }
    public static func bottomRange(_ region: UnitRect) -> ClosedRange<Double> { 0...(1 - region.height) }
    public static func widthRange(_ region: UnitRect) -> ClosedRange<Double> { minimumSide...(1 - region.x) }
    public static func heightRange(_ region: UnitRect) -> ClosedRange<Double> { minimumSide...(1 - region.y) }
}

extension WindowSettings {
    /// The settings that pick one window of one application, by its exact title.
    public init(choosing window: WindowChoice) {
        self.init(titlePattern: window.title, isRegularExpression: false, applicationName: window.application)
    }

    /// The application filter as typed: empty means no filter.
    public var applicationText: String {
        get { applicationName ?? "" }
        set { applicationName = newValue.isEmpty ? nil : newValue }
    }

    public var chooserTitle: String {
        titlePattern.isEmpty ? "Choose a window" : "Choose another window"
    }
}

extension WindowChoice {
    public var menuTitle: String { "\(application): \(title)" }
}

extension MovieSettings {
    /// The caption as typed: empty means none.
    public func captionText(for file: String) -> String { captions?[file] ?? "" }

    public mutating func setCaption(_ text: String, for file: String) {
        var all = captions ?? [:]
        all[file] = text.isEmpty ? nil : text
        captions = all.isEmpty ? nil : all
    }

    public mutating func remove(file: String) {
        files.removeAll { $0 == file }
        captions?[file] = nil
    }

    public mutating func add(files added: [String]) {
        files += added.filter { !files.contains($0) }
    }

    public var hotFolderButtonTitle: String { hotFolder == nil ? "Select hot folder" : "Clear hot folder" }

    /// Clears the hot folder when there is one, or takes the one chosen.
    public mutating func toggleHotFolder(choosing choose: () -> String?) {
        hotFolder = hotFolder == nil ? choose() : nil
    }

    /// What the audio output picker stores for the system's default device.
    public static let systemDefaultDevice = ""

    public var audioDeviceChoice: String {
        get { audioDeviceID ?? Self.systemDefaultDevice }
        set { audioDeviceID = newValue == Self.systemDefaultDevice ? nil : newValue }
    }
}

extension SlideShowSettings {
    public mutating func add(paths added: [String]) {
        paths += added.filter { !paths.contains($0) }
    }
}

/// The words on an image source's controls.
public enum ImageSourceText {
    public static func chooseButtonTitle(path: String) -> String {
        path.isEmpty ? "Choose image" : "Choose another image"
    }
}

extension CamTwistCore.RGBColor {
    /// The colour the system's picker gave, in sRGB. A colour that has no
    /// sRGB form is replaced by the fallback.
    public init(picked: NSColor, fallback: CamTwistCore.RGBColor) {
        guard let color = picked.usingColorSpace(.sRGB) else {
            self = fallback
            return
        }
        self.init(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
    }

    /// The opaque sRGB colour to show in a colour well.
    public var wellColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}
