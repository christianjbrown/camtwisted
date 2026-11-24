import CamTwistCore
import CoreGraphics
import Foundation

/// What a step's row in the chain says and offers, by what the step is.
public enum StepRowLogic {
    public static func settingsHelp(isExpanded: Bool) -> String {
        isExpanded ? "Hide settings" : "Show settings"
    }

    /// The fit a step shows: none stored means fill.
    public static func shownFit(_ stored: SourceFit?) -> SourceFit {
        stored ?? .fill
    }

    /// The fit to store: fill is the default, so it is stored as nothing.
    public static func storedFit(_ shown: SourceFit) -> SourceFit? {
        shown == .fill ? nil : shown
    }

    /// The volume a step shows: none stored means the source's own starting level.
    public static func shownVolume(_ stored: Double?, startingAt start: Double) -> Double {
        stored ?? start
    }

    /// What the box at the foot of a chain says about dropping a step on it.
    public static func endDropText(parentTitle: String?, isEmpty: Bool) -> String {
        if let parentTitle {
            return "Drop here to add to \(parentTitle) only"
        }
        return isEmpty ? "Nothing in this scene yet. Add a source or effect below." : "Drop here to add to the whole scene"
    }
}

/// Works out what dragging a row in the chain does to the order.
public enum ChainReordering {
    /// The row whose middle the pointer has just passed, if any, which the
    /// dragged row then takes the place of.
    public static func passedRow(dragging id: UUID, frames: [UUID: CGRect], pointerY: CGFloat) -> UUID? {
        frames.first { other, frame in
            other != id && frame.minY < pointerY && pointerY < frame.maxY
                && crossesMiddle(of: frame, from: frames[id], pointer: pointerY)
        }?.key
    }

    /// Whether the pointer has gone past the middle of a row, coming from
    /// the side the dragged row is on.
    static func crossesMiddle(of frame: CGRect, from own: CGRect?, pointer: CGFloat) -> Bool {
        guard let own else { return false }
        return own.minY < frame.minY ? pointer > frame.midY : pointer < frame.midY
    }

    /// Where in its row the press landed, so the row does not jump to centre on the pointer.
    public static func grabOffset(pressY: CGFloat, rowTop: CGFloat?) -> CGFloat {
        pressY - (rowTop ?? 0)
    }

    /// How far a dragged row sits from where its place in the list puts it.
    public static func dragOffset(pointerY: CGFloat, grabOffset: CGFloat, rowTop: CGFloat?) -> CGFloat {
        pointerY - grabOffset - (rowTop ?? 0)
    }
}
