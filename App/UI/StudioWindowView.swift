import CamTwistControl
import CamTwistCore
import SwiftUI

/// The Window menu's item that opens the studio window.
struct OpenStudioButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Studio") { openWindow(id: StudioWindowView.windowIdentifier) }
            .keyboardShortcut(StudioWindowView.shortcut, modifiers: [.command, .option])
    }
}

/// A window for running a show: what is on air, the scene lined up next,
/// and every scene to switch between. Nothing is changed here, only chosen.
struct StudioWindowView: View {
    static let title = "CamTwisted Studio"
    static let windowIdentifier = "studio"
    static let shortcut: KeyEquivalent = "s"
    private static let nothingLinedUpFont = Font.title2
    private static let tileCaptionFont = Font.caption

    private enum Metrics {
        static let minimumWidth: CGFloat = 760
        static let minimumHeight: CGFloat = 560
        static let tileMinimumWidth: CGFloat = 140
        static let quietBorderWidth: CGFloat = 1
        static let clicksToGoLive = 2
        static let goLiveColumnWidth: CGFloat = 96
        static let goLiveButtonHeight: CGFloat = 56
    }

    private enum Symbol {
        static let scene = "rectangle.on.rectangle"
        static let nothingLinedUp = "eye.slash"
        static let goLive = "arrow.right"
    }

    @Bindable var model: AppModel
    @Environment(PreviewMonitors.self) private var monitors
    /// Starts open: whoever is switching wants the choice one click away.
    @State private var isChoosingTransition = true
    /// Ends the scenes list's hint about this window.
    @AppStorage(StudioHint.openedKey) private var hasOpenedStudio = false

    private var monitorNames: StudioMonitors {
        StudioMonitors(
            scenes: model.studio.buttons, onAirID: model.studio.onAirID, previewedID: model.previewedSceneID,
            hasPreview: model.studioPreview != nil, isTransitioning: model.isTransitioning
        )
    }

    private let columns = [
        GridItem(.adaptive(minimum: Metrics.tileMinimumWidth), spacing: Layout.panelSpacing, alignment: .top),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.padding) {
            HStack(alignment: .center, spacing: Layout.padding) {
                monitor("Preview", name: monitorNames.previewedName, tint: .secondary, border: .accentColor) {
                    if model.studioPreview == nil {
                        nothingLinedUp
                    } else {
                        PreviewView(sink: monitors.studioPreview)
                    }
                }
                goLiveColumn
                monitor("On air", name: monitorNames.onAirName, tint: .red, border: .red) {
                    PreviewView(sink: monitors.studioProgram)
                }
            }
            // The two pictures come first: the scenes scroll in what is left.
            .layoutPriority(1)
            transitionPicker
            Divider()
            Text("Scenes: click to line one up in the preview, double click to put it on air")
                .foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: columns, spacing: Layout.panelSpacing) {
                    ForEach(model.studio.buttons) { scene in
                        tile(for: scene)
                    }
                }
            }
        }
        .padding(Layout.padding)
        .frame(minWidth: Metrics.minimumWidth, minHeight: Metrics.minimumHeight)
        // The scenes' pictures are only taken while this window is there to show them.
        .onAppear {
            model.gallery.showsSceneThumbnails = true
            hasOpenedStudio = true
        }
        .onDisappear { model.gallery.showsSceneThumbnails = false }
    }

    private var transitionChoice: StudioTransitionChoice {
        StudioTransitionChoice(chosen: model.studio.chosenTransition, seconds: model.studio.transitionTime)
    }

    /// Between the two pictures, where the scene goes from one to the
    /// other: the button that takes it, and how it will arrive.
    private var goLiveColumn: some View {
        VStack(spacing: Layout.panelHalfSpacing) {
            Button {
                model.goLiveWithPreview()
            } label: {
                VStack(spacing: Layout.panelHalfSpacing) {
                    Image(systemName: Symbol.goLive).font(.title2)
                    Text(monitorNames.goLiveTitle)
                }
                .frame(maxWidth: .infinity, minHeight: Metrics.goLiveButtonHeight)
            }
            .keyboardShortcut(.defaultAction)
            .help(transitionChoice.goLiveHelp)
            .disabled(!monitorNames.canSwitch)
            Text(transitionChoice.caption)
                .font(Self.tileCaptionFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: Metrics.goLiveColumnWidth)
    }

    /// How Go live switches: the way each scene comes on air, or one
    /// transition for every scene, for a time set here. Panels, as a scene
    /// chooses how it comes on air.
    private var transitionPicker: some View {
        DisclosureGroup(isExpanded: $isChoosingTransition) {
            TransitionPanels(
                model: model, selection: $model.studio.chosenTransition,
                scenesOwnTitle: StudioTransitionChoice.scenesOwnTitle
            )
            if transitionChoice.showsSeconds {
                NumberSlider(
                    title: "Seconds", value: $model.studio.transitionTime, range: StudioSettings.transitionTimeRange
                )
            }
        } label: {
            LabeledContent("Go live with") {
                Text(transitionChoice.title).foregroundStyle(.secondary)
            }
        }
        .help("Switch every scene the same way from here, or leave each to come on air its own way")
    }

    private var nothingLinedUp: some View {
        VStack(spacing: Layout.panelHalfSpacing) {
            Image(systemName: Symbol.nothingLinedUp).font(Self.nothingLinedUpFont)
            Text("Click a scene to line it up")
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// One of the two pictures, with what it is and which scene it shows.
    private func monitor<Picture: View>(
        _ title: String, name: String, tint: Color, border: Color, @ViewBuilder picture: () -> Picture
    ) -> some View {
        VStack(alignment: .leading, spacing: Layout.panelHalfSpacing) {
            HStack {
                Text(title).foregroundStyle(tint)
                Spacer()
                Text(name).foregroundStyle(.secondary).lineLimit(1)
            }
            // The frame is the picture's own shape, so the outline hugs it.
            Color.black
                .aspectRatio(Layout.aspectRatio, contentMode: .fit)
                .overlay(picture())
                .clipShape(RoundedRectangle(cornerRadius: Layout.panelCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.panelCornerRadius)
                        .stroke(border, lineWidth: Layout.onAirBorderWidth)
                )
        }
    }

    /// One scene: outlined red while on air, in the accent colour while lined up.
    private func tile(for scene: StudioButton) -> some View {
        let tile = StudioTile(
            sceneName: scene.name, isOnAir: model.studio.onAirID == scene.id, isLinedUp: model.previewedSceneID == scene.id
        )
        return VStack(spacing: Layout.panelHalfSpacing) {
            ZStack {
                RoundedRectangle(cornerRadius: Layout.panelCornerRadius).fill(Color.black)
                if let picture = model.gallery.sceneThumbnails[scene.id] {
                    Image(decorative: picture, scale: 1).resizable()
                } else {
                    // Until its picture has been taken.
                    Image(systemName: Symbol.scene)
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
                if model.choices.isAnythingMissing(in: scene.scene) {
                    Image(systemName: SymbolName.missing)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(Layout.panelHalfSpacing)
                        .help("Something in this scene is not connected or has moved")
                }
            }
            .aspectRatio(Layout.aspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Layout.panelCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Layout.panelCornerRadius)
                    .stroke(outlineColor(tile.outline), lineWidth: tile.isEmphasised ? Layout.onAirBorderWidth : Metrics.quietBorderWidth)
            )
            Text(scene.name).font(Self.tileCaptionFont).lineLimit(1)
        }
        .contentShape(Rectangle())
        // The double click is asked about first, so it is not taken for two single ones.
        .onTapGesture(count: Metrics.clicksToGoLive) { model.goLiveFromStudio(withScene: scene.id) }
        .onTapGesture { model.previewScene(id: scene.id) }
        .help(tile.help)
    }

    private func outlineColor(_ outline: TileOutline) -> Color {
        switch outline {
        case .onAir: return .red
        case .linedUp: return .accentColor
        case .quiet: return .secondary
        }
    }
}
