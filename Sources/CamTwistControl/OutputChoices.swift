import CamTwistRendering
import Foundation

/// The choices the output pane offers about screens and Cast devices.
public struct OutputChoices: Equatable {
    /// The screens the picture may fill: every one but the screen the
    /// window is on, which would leave no way back to the app.
    public let otherDisplays: [DisplayChoice]
    /// The screen the picture fills now, if any.
    public let selected: UInt32?

    public init(displays: [DisplayChoice], windowDisplayID: UInt32?, selected: UInt32?) {
        otherDisplays = displays.filter { $0.id != windowDisplayID }
        self.selected = selected
    }

    /// Whether the "Another screen" switch can be used. A screen already
    /// in use can always be switched off.
    public var canSwitch: Bool { !otherDisplays.isEmpty || selected != nil }

    /// Whether to tell the person they need a second screen.
    public var needsSecondScreen: Bool { !canSwitch }

    /// The screen to fill when the switch is set: the last one listed.
    public func screen(whenSwitched isOn: Bool) -> UInt32? {
        isOn ? otherDisplays.last?.id : nil
    }

    /// The title a Cast device picker shows while nothing is chosen.
    public static func castPlaceholder(deviceCount: Int) -> String {
        deviceCount == 0 ? "Looking for devices" : "Choose a device"
    }

    /// The title of the AirPlay row.
    public static func airPlayTitle(isOnDevice: Bool) -> String {
        isOnDevice ? "Playing on a screen" : "Choose a screen"
    }
}
