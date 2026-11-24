import AppKit
import CamTwistControl
import SwiftUI

/// Lists the fonts and gives the font each family's name is drawn in.
protocol MenuFontListing: FontListing {
    /// A font of a family to draw its own name with, when there is one.
    func menuFont(forFamily family: String) -> NSFont?
}

/// The fonts installed on this Mac.
struct SystemFonts: MenuFontListing {
    /// NSFontManager's weight for a regular face, on its scale of 0 to 15.
    private static let regularWeight = 5

    func menuFont(forFamily family: String) -> NSFont? {
        NSFont(name: family, size: NSFont.systemFontSize)
            ?? NSFontManager.shared.font(
                withFamily: family, traits: [], weight: Self.regularWeight, size: NSFont.systemFontSize
            )
    }

    func families() -> [String] {
        NSFontManager.shared.availableFontFamilies
    }

    func styles(ofFamily family: String) -> [FontStyleChoice] {
        (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).compactMap(FontStyleChoice.init(member:))
    }

    func family(ofFontNamed fontName: String) -> String? {
        NSFont(name: fontName, size: NSFont.systemFontSize)?.familyName
    }
}

/// Chooses a font: the family from a menu where each name is drawn in its
/// own font, then the style within it.
struct FontPicker: View {
    @Binding var fontName: String
    @Environment(\.fonts) private var fonts

    private var selection: FontSelection { FontSelection(fonts: fonts) }
    private var family: String { selection.family(ofFontNamed: fontName) }

    var body: some View {
        LabeledContent("Font") {
            FontFamilyMenu(fonts: fonts, families: fonts.families(), selection: family) { chosen in
                if let next = selection.fontName(choosing: chosen, whileUsing: fontName) { fontName = next }
            }
        }
        let styles = selection.stylesToOffer(forFontNamed: fontName)
        if !styles.isEmpty {
            Picker("Style", selection: $fontName) {
                ForEach(styles) { Text($0.styleName).tag($0.fontName) }
            }
        }
    }
}

/// A pop-up menu of font families. AppKit's, because a SwiftUI menu draws
/// every item in the system font.
private struct FontFamilyMenu: NSViewRepresentable {
    let fonts: MenuFontListing
    let families: [String]
    let selection: String
    let choose: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.chosen(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.choose = choose
        if context.coordinator.families != families {
            context.coordinator.families = families
            button.removeAllItems()
            for family in families {
                let item = NSMenuItem(title: family, action: nil, keyEquivalent: "")
                if let font = fonts.menuFont(forFamily: family) {
                    item.attributedTitle = NSAttributedString(string: family, attributes: [.font: font])
                }
                button.menu?.addItem(item)
            }
        }
        if button.titleOfSelectedItem != selection {
            button.selectItem(withTitle: selection)
        }
    }

    final class Coordinator: NSObject {
        var families: [String] = []
        var choose: (String) -> Void = { _ in }

        @objc func chosen(_ sender: NSPopUpButton) {
            if let title = sender.titleOfSelectedItem { choose(title) }
        }
    }
}

/// Lists no fonts. It is what a view gets when no list was handed down to it.
private struct NoFonts: MenuFontListing {
    func families() -> [String] { [] }
    func styles(ofFamily family: String) -> [FontStyleChoice] { [] }
    func family(ofFontNamed fontName: String) -> String? { nil }
    func menuFont(forFamily family: String) -> NSFont? { nil }
}

private struct FontsKey: EnvironmentKey {
    static let defaultValue: MenuFontListing = NoFonts()
}

extension EnvironmentValues {
    /// The fonts there are to choose from.
    var fonts: MenuFontListing {
        get { self[FontsKey.self] }
        set { self[FontsKey.self] = newValue }
    }
}
