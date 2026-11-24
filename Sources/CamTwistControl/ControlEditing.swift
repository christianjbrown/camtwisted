import CamTwistCore
import Foundation

// How the look, cutout, animation and font controls turn what a person does
// into what is stored.

/// A setting that is stored as nothing at all while it is untouched, so a
/// source nobody has changed costs nothing to draw.
public protocol NeutralStorable {
    static var untouched: Self { get }
    var isNeutral: Bool { get }
}

extension SourceAdjustments: NeutralStorable {
    public static var untouched: SourceAdjustments { SourceAdjustments() }
}

extension SourceCutout: NeutralStorable {
    public static var untouched: SourceCutout { SourceCutout() }
}

extension NeutralStorable {
    /// What to store after `edit` is applied to the stored value, or to an
    /// untouched one when nothing is stored.
    public static func stored(afterEditing stored: Self?, _ edit: (inout Self) -> Void) -> Self? {
        var changed = stored ?? untouched
        edit(&changed)
        return changed.isNeutral ? nil : changed
    }
}

/// A share of something shown and typed as a percentage from 0 to 100 and
/// kept as a fraction from 0 to 1.
public enum Percent {
    public static let whole = 100.0

    public static func shown(_ fraction: Double) -> Double { (fraction * whole).rounded() }
    public static func fraction(_ shown: Double) -> Double { shown / whole }
    public static var range: ClosedRange<Double> { 0...whole }
}

/// A typed number is pulled back to the nearest end of the range.
public func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
    min(max(value, range.lowerBound), range.upperBound)
}

/// The key a source's chroma key controls show and change.
public enum ChromaKeyEditing {
    /// The key shown: the source's own, or the one it would start with.
    public static func shown(_ cutout: SourceCutout?) -> ChromaKeySettings {
        cutout?.chromaKey ?? .greenScreen
    }

    /// Whether the key switch is on.
    public static func isOn(_ cutout: SourceCutout?) -> Bool { cutout?.chromaKey != nil }

    /// Switching on starts from the green screen key; off clears it.
    public static func switched(on isOn: Bool) -> ChromaKeySettings? { isOn ? .greenScreen : nil }

    /// Whether the group of controls starts open: when somebody has opened
    /// or closed it, as they left it, and otherwise when something is cut out.
    public static func isGroupOpen(chosen: Bool?, cutout: SourceCutout?) -> Bool { chosen ?? (cutout != nil) }
}

/// The list of animations on a source's placement, stored as nothing when empty.
public enum AnimationList {
    public static func adding(
        _ property: AnimatedProperty, around value: Double, to list: [SourceAnimation]?
    ) -> [SourceAnimation] {
        (list ?? []) + [SourceAnimation.starter(for: property, around: value)]
    }

    public static func removing(_ id: UUID, from list: [SourceAnimation]?) -> [SourceAnimation]? {
        let rest = (list ?? []).filter { $0.id != id }
        return rest.isEmpty ? nil : rest
    }

    /// The animation as it is now in the list, or the one given while it is not there.
    public static func current(_ animation: SourceAnimation, in list: [SourceAnimation]?) -> SourceAnimation {
        list?.first { $0.id == animation.id } ?? animation
    }

    /// The list with one animation replaced. A change to one that is gone is dropped.
    public static func replacing(_ changed: SourceAnimation, in list: [SourceAnimation]?) -> [SourceAnimation]? {
        guard var all = list, let index = all.firstIndex(where: { $0.id == changed.id }) else { return list }
        all[index] = changed
        return all
    }
}

/// One weight or slant of a font family.
public struct FontStyleChoice: Identifiable, Equatable {
    /// The name drawing code asks for, such as "Helvetica-Bold".
    public let fontName: String
    /// What the family calls it, such as "Bold".
    public let styleName: String

    public var id: String { fontName }

    public init(fontName: String, styleName: String) {
        self.fontName = fontName
        self.styleName = styleName
    }

    /// Where the font name and the style name sit in a family member's record.
    private enum MemberField {
        static let fontName = 0
        static let styleName = 1
    }

    /// Reads a family member's record from the system's font list.
    public init?(member: [Any]) {
        guard member.count > MemberField.styleName,
              let fontName = member[MemberField.fontName] as? String,
              let styleName = member[MemberField.styleName] as? String
        else { return nil }
        self.init(fontName: fontName, styleName: styleName)
    }
}

/// The fonts a text source can be set in.
public protocol FontListing {
    func families() -> [String]
    func styles(ofFamily family: String) -> [FontStyleChoice]
    func family(ofFontNamed fontName: String) -> String?
}

/// Works out which font a font picker holds and what choosing a family sets.
public struct FontSelection {
    private let fonts: FontListing

    public init(fonts: FontListing) {
        self.fonts = fonts
    }

    /// The family a font belongs to: its own name when the system does not know it.
    public func family(ofFontNamed fontName: String) -> String {
        fonts.family(ofFontNamed: fontName) ?? fontName
    }

    /// The font to use after another family is chosen. The style stays when
    /// the new family has it too, such as Bold. Nil when the family has no fonts.
    public func fontName(choosing family: String, whileUsing fontName: String) -> String? {
        let styles = fonts.styles(ofFamily: family)
        let current = fonts.styles(ofFamily: self.family(ofFontNamed: fontName)).first { $0.fontName == fontName }?.styleName
        return (styles.first { $0.styleName == current } ?? styles.first)?.fontName
    }

    /// The styles to offer: none when the family has only one.
    public func stylesToOffer(forFontNamed fontName: String) -> [FontStyleChoice] {
        let styles = fonts.styles(ofFamily: family(ofFontNamed: fontName))
        return styles.count > 1 ? styles : []
    }
}
