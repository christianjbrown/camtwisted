import CamTwistControl
import CamTwistCore
import CamTwistRendering
import SwiftUI

/// One of the two lists of things to add: sources, or effects. Click a
/// panel to add it at the end, or drag it into the scene to put it where
/// you want it. Only the effects are searched: there are few sources.
struct AddPicker: View {
    enum Kind {
        case sources
        case effects
    }

    @Bindable var model: AppModel
    let kind: Kind
    @State private var search = ""

    private let columns = [
        GridItem(.adaptive(minimum: Layout.panelMinimumWidth), spacing: Layout.panelSpacing, alignment: .top),
    ]

    var body: some View {
        switch kind {
        case .sources:
            list { sourcePanels }
            Button("Open pictures folder") { model.choices.openPicturesFolder() }
                .help("Pictures put here appear above as sources, under their own names")
        case .effects:
            TextField("Search effects", text: $search)
            list { effectPanels }
            Button("Open effects folder") { model.choices.openEffectsFolder() }
                .help("Put web page effects (.html files) here")
        }
    }

    /// One list's panels in a scrolling area of its own.
    private func list<Panels: View>(@ViewBuilder _ panels: () -> Panels) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Layout.panelSpacing) { panels() }
                .padding(.vertical, Layout.panelHalfSpacing)
        }
        .frame(height: Layout.pickerHeight)
    }

    /// The sources on offer, with the symbol each is shown with.
    private var sources: [SourceOffer] {
        SourceCatalog.offers(
            camera: model.steps.newCameraSource, firstDisplayID: model.choices.displays.first?.id,
            image: model.steps.newImageSource
        )
    }

    @ViewBuilder
    private var sourcePanels: some View {
        let shown = sources
        ForEach(shown.indices, id: \.self) { index in
            let source = shown[index]
            panel(
                title: source.title,
                help: source.help,
                content: source.content
            ) { SymbolTile(name: source.symbol) }
        }
    }

    @ViewBuilder
    private var effectPanels: some View {
        let offers = EffectOffers(effects: model.choices.effects, search: search)
        if let message = offers.emptyMessage {
            Text(message).foregroundStyle(.secondary)
        }
        ForEach(offers.shown) { effect in
            let name = EffectNaming.title(for: effect.name)
            panel(
                title: name,
                help: name,
                content: .effect(name: effect.name, values: [:])
            ) {
                if let image = model.choices.thumbnails[effect.name] {
                    Image(decorative: image, scale: 1).resizable()
                } else {
                    SymbolTile(name: SourceCatalog.effectSymbol)
                }
            }
        }
    }

    /// A panel that adds its step on a click and can be dragged into the scene.
    private func panel<Picture: View>(
        title: String,
        help: String,
        content: ChainItem.Content,
        @ViewBuilder picture: @escaping () -> Picture
    ) -> some View {
        PanelLabel(title: title, picture: picture)
            .onTapGesture { model.steps.add(content) }
            .draggable(StepPayload.text(for: content)) {
                PanelLabel(title: title, picture: picture)
                    .frame(width: Layout.panelMinimumWidth)
            }
            .help("\(help). Click to add, or drag into the scene.")
    }
}

/// A picker panel: a small picture with a name under it. Every panel is
/// the same height whatever its text, so rows of panels line up.
struct PanelLabel<Picture: View>: View {
    let title: String
    @ViewBuilder let picture: () -> Picture

    var body: some View {
        VStack(spacing: Layout.panelHalfSpacing) {
            picture()
                .aspectRatio(Layout.aspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Layout.panelCornerRadius))
            Text(title).font(.caption).lineLimit(1).truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .contentShape(Rectangle())
    }
}

/// A symbol on a plain tile, for panels that have no picture.
struct SymbolTile: View {
    let name: String

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: name).font(.title2).foregroundStyle(.secondary)
        }
    }
}
