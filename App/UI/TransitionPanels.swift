import CamTwistControl
import CamTwistCore
import SwiftUI

/// The ways a scene can come on air, as panels like the effects in the
/// picker. The one in use is outlined. With a title for it, a first panel
/// stands for leaving each scene to come on air its own way.
struct TransitionPanels: View {
    @Bindable var model: AppModel
    @Binding var selection: String?
    /// The first panel's title, which chooses no transition; nil leaves it out.
    var scenesOwnTitle: String?

    private let columns = [
        GridItem(.adaptive(minimum: Layout.panelMinimumWidth), spacing: Layout.panelSpacing, alignment: .top),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Layout.panelSpacing) {
            if let scenesOwnTitle {
                panel(for: nil, title: scenesOwnTitle) {
                    SymbolTile(name: TransitionPanel.scenesOwnSymbol)
                }
            }
            ForEach(model.choices.transitionNames, id: \.self) { name in
                panel(for: name, title: EffectNaming.title(for: name)) {
                    if let image = model.choices.thumbnails[name] {
                        Image(decorative: image, scale: 1).resizable()
                    } else {
                        SymbolTile(name: TransitionPanel.fallbackSymbol(for: name))
                    }
                }
            }
        }
    }

    private func panel<Picture: View>(
        for name: String?, title: String, @ViewBuilder picture: @escaping () -> Picture
    ) -> some View {
        PanelLabel(title: title, picture: picture)
            .padding(Layout.panelHalfSpacing)
            .overlay(
                RoundedRectangle(cornerRadius: Layout.panelCornerRadius)
                    .stroke(selection == name ? Color.accentColor : .clear, lineWidth: Layout.onAirBorderWidth)
            )
            .onTapGesture { selection = name }
            .help(title)
    }
}
