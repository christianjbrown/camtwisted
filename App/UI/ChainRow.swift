import CamTwistControl
import CamTwistCore
import CamTwistRendering
import SwiftUI

/// One step of the chain: a bar with its switch and name, which can be
/// dragged to reorder, and its settings underneath when open.
struct ChainRow<Drag: Gesture>: View {
    @Bindable var model: AppModel
    @Binding var item: ChainItem
    let drag: Drag

    private var isExpanded: Bool { model.expandedSteps.contains(item.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.panelSpacing) {
            HStack(spacing: Layout.stepBarSpacing) {
                Button {
                    if isExpanded {
                        model.expandedSteps.remove(item.id)
                    } else {
                        model.expandedSteps.insert(item.id)
                        model.selectedStepID = item.id
                    }
                } label: {
                    Image(systemName: isExpanded ? SymbolName.chevronOpen : SymbolName.chevronClosed)
                        .font(Layout.stepBarIconFont)
                        .frame(width: Layout.chevronWidth)
                }
                .buttonStyle(.borderless)
                .help(StepRowLogic.settingsHelp(isExpanded: isExpanded))
                Toggle("", isOn: $item.isEnabled).labelsHidden().help("Switch on or off")
                if let problem = model.choices.missingSourceProblem(with: item) {
                    Image(systemName: SymbolName.missing).foregroundStyle(.red).help(problem)
                }
                Text(item.title)
                    .font(Layout.stepBarTitleFont)
                    .fontWeight(model.selectedStepID == item.id ? .semibold : .regular)
                    .foregroundStyle(model.choices.missingSourceProblem(with: item) == nil ? Color.primary : Color.red)
                    .lineLimit(1)
                Spacer()
                if model.steps.canReset(item) {
                    Button {
                        model.steps.reset(id: item.id)
                    } label: {
                        Image(systemName: SymbolName.reset).font(Layout.stepBarIconFont)
                    }
                    .buttonStyle(.borderless)
                    .padding(.trailing, Layout.stepBarHandleGap)
                    .help("Reset its settings. What it shows stays")
                }
                Image(systemName: SymbolName.dragHandle)
                    .font(Layout.stepBarIconFont)
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, Layout.stepBarHandleGap)
                Button {
                    model.editedScene.remove(id: item.id)
                } label: {
                    Image(systemName: SymbolName.delete).font(Layout.stepBarIconFont)
                }
                .buttonStyle(.borderless)
                .help("Remove")
            }
            .padding(.vertical, Layout.stepBarPadding)
            .contentShape(Rectangle())
            .onTapGesture { model.selectedStepID = item.id }
            .gesture(drag)
            .help("Drag to reorder")
            if isExpanded {
                VStack(alignment: .leading, spacing: Layout.panelSpacing) { settings }
                    .padding(.leading, Layout.chevronWidth + Layout.panelSpacing)
            }
        }
        .padding(.vertical, Layout.panelHalfSpacing)
    }

    @ViewBuilder
    private var settings: some View {
        switch item.content {
        case .effect(let name, let values):
            let parameters = model.choices.parameters(forEffectNamed: name)
            if parameters.isEmpty {
                Text("Nothing to adjust").foregroundStyle(.secondary)
            }
            ForEach(parameters) { parameter in
                ParameterControl(parameter: parameter, value: values[parameter.key] ?? parameter.defaultValue) {
                    model.editedScene.setValue($0, forKey: parameter.key, ofEffect: item.id)
                }
            }
            if let credit = EffectCredits.credit(forEffectNamed: name) {
                Text(credit).font(.caption).foregroundStyle(.secondary)
            }
        case .source(let spec):
            if let problem = model.choices.missingSourceProblem(with: item) {
                Label(problem, systemImage: SymbolName.missing).foregroundStyle(.red)
            }
            SourceSettingsView(model: model, spec: spec) { item.content = .source($0) }
            if let startingVolume = SceneSound.startingVolume(for: spec) {
                PercentSlider(
                    title: "Volume",
                    fraction: Binding(
                        get: { StepRowLogic.shownVolume(item.volume, startingAt: startingVolume) }, set: { item.volume = $0 }
                    )
                )
                .help(spec.kind.volumeHelp)
            }
            // A microphone has no picture to colour, place or put effects on.
            if !spec.kind.isSoundOnly {
                if spec.canBeCutOut {
                    CutoutControls(cutout: $item.cutout)
                }
                SourceLookControls(adjustments: $item.adjustments)
                if item.pictureInPicture == nil {
                    Picker("When it is another shape", selection: Binding(
                        get: { StepRowLogic.shownFit(item.fit) }, set: { item.fit = StepRowLogic.storedFit($0) }
                    )) {
                        Text("Fill the picture and crop the rest").tag(SourceFit.fill)
                        Text("Show all of it, with bars").tag(SourceFit.fit)
                        Text("Stretch to fit").tag(SourceFit.stretch)
                    }
                    .help("What happens when this source is not the same shape as the picture")
                }
                PictureInPictureControls(settings: $item.pictureInPicture)
                if let placement = item.pictureInPicture {
                    AnimationControls(animations: $item.animations, placement: placement)
                }
                BranchSection(model: model, item: $item)
            }
        case .script(let source):
            Text("Type AppleScript below. It runs every time this step is switched on, including when a setup or studio button that contains it goes on air.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: Binding(get: { source }, set: { item.content = .script(source: $0) }))
                .font(.body.monospaced())
                .frame(minHeight: Layout.scriptEditorHeight)
                .overlay(RoundedRectangle(cornerRadius: Layout.panelCornerRadius).stroke(.quaternary))
            if source.isEmpty {
                Text("For example: say \"We are live\"").font(.caption).foregroundStyle(.secondary)
            }
            Button("Run now") { model.performOnMain(.runAppleScript(source)) }
                .disabled(source.isEmpty)
        }
    }
}

/// A source's branch: the effects and other sources that apply to this
/// source alone, before it joins the rest of the picture.
private struct BranchSection: View {
    @Bindable var model: AppModel
    @Binding var item: ChainItem

    private static let ruleWidth: CGFloat = 3
    private static let ruleStrength = 0.6

    private var isTarget: Bool { model.branchTarget == item.id }

    var body: some View {
        // A coloured rule down the side sets a source's own chain apart
        // from the scene's.
        HStack(alignment: .top, spacing: Layout.panelSpacing) {
            RoundedRectangle(cornerRadius: Self.ruleWidth / 2)
                .fill(Color.accentColor.opacity(Self.ruleStrength))
                .frame(width: Self.ruleWidth)
            VStack(alignment: .leading, spacing: Layout.panelSpacing) {
                Label("On \(item.title) only", systemImage: SymbolName.dropIntoBranch).font(.subheadline)
                Text("Effects and sources here change \(item.title) alone, and leave everything else as it is.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ChainList(
                    model: model,
                    items: Binding(
                        get: { BranchEditing.shown(item.branch) },
                        set: { item.branch = BranchEditing.stored($0) }
                    ),
                    parent: item.id,
                    parentTitle: item.title
                )
                Button(BranchEditing.buttonTitle(isTarget: isTarget, sourceTitle: item.title)) {
                    model.branchTarget = BranchEditing.target(afterPressingFor: item.id, current: model.branchTarget)
                }
                .help("While this is on, clicking a panel in the picker adds it to this source's branch")
            }
        }
    }
}

/// The same placement controls for every source: where, how big, and at
/// what angle, with a shortcut into each corner.
private struct PictureInPictureControls: View {
    @Binding var settings: PictureInPictureSettings?

    var body: some View {
        Toggle("Picture in picture", isOn: Binding(
            get: { PlacementEditing.isOn(settings) },
            set: { settings = PlacementEditing.settings(whenOn: $0) }
        ))
        .help("Show this source as a small picture over what is behind it. Drag it on the picture to move it.")
        if let current = settings {
            ForEach(PlacementSlider.all, id: \.title) { row in
                NumberSlider(
                    title: row.title,
                    value: Binding(
                        get: { row.value(current) },
                        set: { newValue in
                            guard var changed = settings else { return }
                            row.setValue(&changed, newValue)
                            settings = changed
                        }
                    ),
                    range: row.range
                )
            }
            Menu("Snap to corner") {
                ForEach(Corner.allCases, id: \.self) { corner in
                    Button(corner.label) { settings?.snap(to: corner) }
                }
            }
            .fixedSize()
        }
    }
}
