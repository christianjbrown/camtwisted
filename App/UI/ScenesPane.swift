import CamTwistControl
import CamTwistCore
import CamTwistRendering
import SwiftUI

/// Every scene, each holding its sources and effects. One is on air; any
/// can be opened and changed, and put on air when it is ready.
struct ScenesPane: View {
    @Bindable var model: AppModel
    /// Whether the scene on air has been folded away.
    @State private var isOnAirFolded = false
    /// The folded scene being looked at in the preview, without opening it.
    @State private var peekedID: UUID?
    @Environment(\.openWindow) private var openWindow
    /// Set once the studio window has been opened, which ends the hint.
    @AppStorage(StudioHint.openedKey) private var hasOpenedStudio = false

    var body: some View {
        ForEach($model.studio.buttons) { $scene in
            Section {
                SceneCard(model: model, scene: $scene, isOnAirFolded: $isOnAirFolded, peekedID: $peekedID)
            }
        }
        Section {
            HStack {
                Button {
                    model.addScene()
                } label: {
                    Label("New scene", systemImage: SymbolName.add)
                }
                Spacer()
                Button {
                    openWindow(id: StudioWindowView.windowIdentifier)
                } label: {
                    Label("Studio", systemImage: SymbolName.studio)
                }
                .help("Line up the next scene beside what is on air, then go live")
            }
            .buttonStyle(.borderless)
            if StudioHint.shows(sceneCount: model.studio.buttons.count, hasOpenedStudio: hasOpenedStudio) {
                Label(
                    "Switching scenes live? The Studio shows what is on air beside what is next.",
                    systemImage: SymbolName.hint
                )
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// One scene: a bar with its name and what can be done with it and, when
/// open, how it comes on air and the steps in it.
private struct SceneCard: View {
    @Bindable var model: AppModel
    @Environment(PreviewMonitors.self) private var monitors
    @Binding var scene: StudioButton
    @Binding var isOnAirFolded: Bool
    @Binding var peekedID: UUID?
    @State private var isAddingSource = false
    @State private var isAddingEffect = false
    @State private var isChoosingSwitch = false
    @State private var isConfirmingRemoval = false

    private var barState: SceneBarState {
        SceneBarState(
            sceneID: scene.id, onAirID: model.studio.onAirID, isEditingOnAir: model.isEditingOnAir,
            isOnAirFolded: isOnAirFolded, editedSceneID: model.editedSceneID, peekedID: peekedID
        )
    }

    private var isOnAir: Bool { barState.isOnAir }
    private var isOpen: Bool { barState.isOpen }
    private var isPeeked: Bool { barState.isPeeked }

    var body: some View {
        bar
            // On a fresh start the picker is open, ready for the first thing to be added.
            .onAppear {
                openPickerIfWanted()
            }
            // The bar is what is dragged to put scenes in a new order.
            .draggable(ScenePayload.text(for: scene.id))
            .dropDestination(for: String.self) { dropped, _ in
                guard let id = dropped.first.flatMap(ScenePayload.id(from:)) else { return false }
                model.studio.moveScene(id: id, toPositionOf: scene.id)
                return true
            }
        if isPeeked {
            PreviewView(sink: monitors.preview)
                .frame(height: Layout.studioMonitorHeight)
        }
        if isOpen {
            if scene.isLocked {
                Label("Locked. Unlock it to change or remove it.", systemImage: SymbolName.locked)
                    .foregroundStyle(.secondary)
            }
            openContents.disabled(scene.isLocked)
        }
    }

    /// Everything about an open scene that can be changed.
    @ViewBuilder
    private var openContents: some View {
        Group {
            TextField("Name", text: $scene.name)
            DisclosureGroup(isExpanded: $isChoosingSwitch) {
                TransitionPanels(model: model, selection: Binding(
                    get: { scene.switchName },
                    set: { chosen in chosen.map { scene.switchName = $0 } }
                ))
                if !scene.cutsInstantly {
                    NumberSlider(
                        title: "Seconds", value: $scene.switchTime, range: StudioSettings.transitionTimeRange
                    )
                }
            } label: {
                LabeledContent("Comes on air with") {
                    Text(EffectNaming.title(for: scene.switchName)).foregroundStyle(.secondary)
                }
            }
            MIDIKeyControl(model: model, id: scene.id, note: $scene.midiNote)
            ShortcutKeyControl(model: model, id: scene.id, shortcut: $scene.shortcut)
            HandoverControl(scene: $scene, all: model.studio.buttons)
            if !isOnAir {
                PreviewView(sink: monitors.preview)
                    .frame(height: Layout.studioMonitorHeight)
            }
            ChainList(model: model, items: $model.editedScene.items, parent: nil)
            BranchTargetBanner(model: model)
            DisclosureGroup(isExpanded: $isAddingSource) {
                AddPicker(model: model, kind: .sources)
            } label: {
                Label("Add a source", systemImage: SymbolName.add)
            }
            DisclosureGroup(isExpanded: $isAddingEffect) {
                AddPicker(model: model, kind: .effects)
            } label: {
                Label("Add an effect", systemImage: SymbolName.add)
            }
        }
    }

    private var bar: some View {
        let content = SceneBarContent(scene: scene, state: barState, isTransitioning: model.isTransitioning)
        return HStack(spacing: Layout.stepBarSpacing) {
            Button(action: toggle) {
                Image(systemName: isOpen ? SymbolName.chevronOpen : SymbolName.chevronClosed)
                    .font(Layout.stepBarIconFont)
                    .frame(width: Layout.chevronWidth)
            }
            .buttonStyle(.borderless)
            .help(content.foldHelp)
            if model.choices.isAnythingMissing(in: scene.scene) {
                Image(systemName: SymbolName.missing)
                    .foregroundStyle(.red)
                    .help("Something in this scene is not connected or has moved. Open it to see what.")
            }
            Text(scene.name).font(Layout.stepBarTitleFont).fontWeight(.semibold).lineLimit(1)
            if isOnAir {
                Text("On air")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, Layout.panelSpacing)
                    .overlay(Capsule().stroke(Color.red, lineWidth: Layout.onAirOutlineWidth))
            } else if content.showsSummary {
                Text(content.summary).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if content.showsPeek {
                Button {
                    peek()
                } label: {
                    Image(systemName: isPeeked ? SymbolName.peeking : SymbolName.peek).font(Layout.stepBarIconFont)
                }
                .buttonStyle(.borderless)
                .help(content.peekHelp)
            }
            if content.showsGoLive {
                Button(content.goLiveTitle) { model.goLive(withScene: scene.id) }
                    .disabled(model.isTransitioning)
                    .help("Put \(scene.name) on air")
            }
            Button {
                scene.isLocked.toggle()
            } label: {
                Image(systemName: scene.isLocked ? SymbolName.locked : SymbolName.unlocked).font(Layout.stepBarIconFont)
            }
            .buttonStyle(.borderless)
            .help(content.lockHelp)
            Image(systemName: SymbolName.dragHandle)
                .font(Layout.stepBarIconFont)
                .foregroundStyle(.tertiary)
                .help("Drag to reorder")
            Button {
                model.duplicateScene(id: scene.id)
            } label: {
                Image(systemName: SymbolName.copy).font(Layout.stepBarIconFont)
            }
            .buttonStyle(.borderless)
            .help("Make a copy")
            Button {
                isConfirmingRemoval = true
            } label: {
                Image(systemName: SymbolName.delete).font(Layout.stepBarIconFont)
            }
            .buttonStyle(.borderless)
            .disabled(!content.canRemove)
            .padding(.leading, Layout.stepBarHandleGap)
            .help(content.removalHelp)
            // A scene is a lot of work to lose to a slip, so this one asks.
            .confirmationDialog("Remove \(scene.name)?", isPresented: $isConfirmingRemoval) {
                Button("Remove scene", role: .destructive) { model.removeScene(id: scene.id) }
            } message: {
                Text("Everything in it goes with it.")
            }
        }
        .padding(.vertical, Layout.stepBarPadding)
    }

    /// On a fresh start one list is open, ready for the first thing to be
    /// added: effects when the scene has its camera already, sources when not.
    private func openPickerIfWanted() {
        let launch = LaunchOptions.load()
        switch StartingPicker.choose(
            startsAfresh: model.startsAfresh, opensPicker: launch.opensPicker, showsEffects: launch.showsEffects,
            isOnAir: isOnAir, hasCamera: scene.scene.hasCamera
        ) {
        case .effects: isAddingEffect = true
        case .sources: isAddingSource = true
        case .none: break
        }
    }

    /// Shows a folded scene in the preview, or stops showing it.
    private func peek() {
        if isPeeked {
            peekedID = nil
            model.performOnMain(.studioClear)
        } else {
            // Looking at one scene closes whichever other was open for changing.
            model.editScene(id: nil)
            peekedID = scene.id
            model.performOnMain(.studioPreview(button: scene.name))
        }
    }

    private func toggle() {
        peekedID = nil
        let folding = SceneFolding(
            isOnAir: isOnAir, isOpen: isOpen, isEditingOnAir: model.isEditingOnAir, isOnAirFolded: isOnAirFolded,
            isEmpty: scene.scene.items.isEmpty
        )
        isOnAirFolded = folding.isOnAirFolded
        switch folding.edit {
        case .leaveAlone: break
        case .closeAll: model.editScene(id: nil)
        case .open:
            model.editScene(id: scene.id)
            isAddingSource = folding.opensSourcePicker
        }
    }
}

/// Shows a MIDI key and learns a new one from the next note played.
struct MIDIKeyControl: View {
    @Bindable var model: AppModel
    let id: UUID
    @Binding var note: Int?

    private var row: MIDIKeyRow { MIDIKeyRow(note: note, isLearning: model.midi.learningFor == id) }

    var body: some View {
        HStack {
            Text(row.title).foregroundStyle(.secondary)
            Spacer()
            Button(row.buttonTitle) {
                model.midi.learningFor = MIDIKeyRow.learning(after: id, current: model.midi.learningFor)
            }
            if row.showsClear {
                Button("Clear") { note = nil }
            }
        }
        .controlSize(.small)
    }
}

/// Shows a scene's keyboard shortcut and records a new one from the next
/// keys pressed. The shortcut works whichever app is in front.
struct ShortcutKeyControl: View {
    @Bindable var model: AppModel
    let id: UUID
    @Binding var shortcut: SceneShortcut?

    private var isLearning: Bool { model.shortcuts.learningFor == id }
    private var row: ShortcutKeyRow { ShortcutKeyRow(shortcut: shortcut, isLearning: isLearning) }

    var body: some View {
        HStack {
            Text(row.title).foregroundStyle(.secondary)
            Spacer()
            Button(row.buttonTitle) {
                model.shortcuts.learningFor = KeyLearning.learning(after: id, current: model.shortcuts.learningFor)
            }
            .help(isLearning ? ShortcutKeyRow.learningHelp : "Record a shortcut that puts this scene on air from any app")
            if row.showsClear {
                Button("Clear") { shortcut = nil }
            }
        }
        .controlSize(.small)
    }
}

/// Which scene this one hands over to by itself, and after how long on air.
struct HandoverControl: View {
    @Binding var scene: StudioButton
    let all: [StudioButton]

    var body: some View {
        let choices = HandoverChoices(for: scene, among: all)
        Picker("Then hands over to", selection: Binding(
            get: { choices.chosen },
            set: { scene.handover = HandoverChoices.picking($0, current: scene.handover) }
        )) {
            Text("Nothing, it stays on air").tag(UUID?.none)
            ForEach(choices.scenes) { other in
                Text(other.name).tag(UUID?.some(other.id))
            }
        }
        .help("Puts another scene on air by itself once this one has been on for a while")
        if let handover = scene.handover, choices.chosen != nil {
            NumberSlider(
                title: "Seconds on air",
                value: Binding(get: { handover.seconds }, set: { scene.handover?.seconds = $0 }),
                range: SceneHandover.secondsRange
            )
        }
    }
}
