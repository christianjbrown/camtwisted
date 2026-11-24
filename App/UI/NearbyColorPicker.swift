import AppKit
import SwiftUI

/// A colour swatch whose palette opens right beside it, instead of in the
/// shared colour window that may be anywhere on the screen.
struct NearbyColorPicker: NSViewRepresentable {
    let color: NSColor
    let set: (NSColor) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(set: set)
    }

    func makeNSView(context: Context) -> NSColorWell {
        // The minimal style shows its swatches in a popover at the well.
        let well = NSColorWell(style: .minimal)
        well.color = color
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        context.coordinator.set = set
        if well.color != color {
            well.color = color
        }
    }

    final class Coordinator: NSObject {
        var set: (NSColor) -> Void

        init(set: @escaping (NSColor) -> Void) {
            self.set = set
        }

        @objc func colorChanged(_ sender: NSColorWell) {
            set(sender.color)
        }
    }
}

/// A labelled row with a nearby colour picker.
struct ColorRow: View {
    private static let wellWidth: CGFloat = 44
    private static let wellHeight: CGFloat = 24
    private static let eyedropperSymbol = "eyedropper"

    let title: String
    let color: NSColor
    let set: (NSColor) -> Void

    var body: some View {
        LabeledContent(title) {
            HStack {
                // The system's eyedropper: click anywhere on screen, the
                // picture included, to take the colour there.
                Button {
                    NSColorSampler().show { picked in
                        if let picked { set(picked) }
                    }
                } label: {
                    Image(systemName: Self.eyedropperSymbol)
                }
                .buttonStyle(.borderless)
                .help("Pick a colour from the picture, or anywhere on screen")
                NearbyColorPicker(color: color, set: set)
                    .frame(width: Self.wellWidth, height: Self.wellHeight)
            }
        }
    }
}
