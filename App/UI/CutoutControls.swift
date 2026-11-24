import AppKit
import CamTwistControl
import CamTwistCore
import SwiftUI

/// What is cut out of one source's picture: everything but the people in
/// it, a colour, or both.
struct CutoutControls: View {
    /// Fully opaque, for the swatch of the key colour.
    private static let opaque: CGFloat = 1

    @Binding var cutout: SourceCutout?
    /// Whether the group is open, once somebody has opened or closed it.
    /// Until then it is open when the source has something cut out.
    @State private var isOpen: Bool?

    private var isExpanded: Binding<Bool> {
        Binding(get: { ChromaKeyEditing.isGroupOpen(chosen: isOpen, cutout: cutout) }, set: { isOpen = $0 })
    }

    /// The cutout being shown: the source's own, or none.
    private var current: SourceCutout { cutout ?? SourceCutout() }
    /// The key being shown: the source's own, or the one it would start with.
    private var key: ChromaKeySettings { ChromaKeyEditing.shown(cutout) }

    var body: some View {
        DisclosureGroup("Remove background and chroma key", isExpanded: isExpanded) {
            Toggle("Remove background", isOn: binding(\.removesBackground))
                .help("Keeps the people in the picture and clears everything behind them")
            Toggle("Chroma key", isOn: Binding(
                get: { ChromaKeyEditing.isOn(cutout) },
                set: { isOn in change { $0.chromaKey = ChromaKeyEditing.switched(on: isOn) } }
            ))
            .help("Clears one colour, such as a green screen, so what is beneath shows through")
            if ChromaKeyEditing.isOn(cutout) {
                ColorRow(
                    title: "Key colour",
                    color: NSColor(srgbRed: key.red, green: key.green, blue: key.blue, alpha: Self.opaque)
                ) { picked in
                    guard let color = picked.usingColorSpace(.sRGB) else { return }
                    changeKey {
                        $0.red = color.redComponent
                        $0.green = color.greenComponent
                        $0.blue = color.blueComponent
                    }
                }
                slider("Similarity", \.similarity)
                slider("Smoothness", \.smoothness)
                slider("Spill reduction", \.spillReduction)
            }
        }
    }

    private func slider(_ title: String, _ keyPath: WritableKeyPath<ChromaKeySettings, Double>) -> some View {
        NumberSlider(
            title: title,
            value: Binding(get: { key[keyPath: keyPath] }, set: { value in changeKey { $0[keyPath: keyPath] = value } }),
            range: ChromaKeySettings.range
        )
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<SourceCutout, Value>) -> Binding<Value> {
        Binding(get: { current[keyPath: keyPath] }, set: { value in change { $0[keyPath: keyPath] = value } })
    }

    private func changeKey(_ edit: (inout ChromaKeySettings) -> Void) {
        var changed = key
        edit(&changed)
        change { $0.chromaKey = changed }
    }

    /// Everything is written in one go. A cutout that cuts nothing is
    /// stored as none at all, so it costs nothing to draw.
    private func change(_ edit: (inout SourceCutout) -> Void) {
        cutout = SourceCutout.stored(afterEditing: cutout, edit)
    }
}
