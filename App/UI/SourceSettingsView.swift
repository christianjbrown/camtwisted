import CamTwistControl
import CamTwistCore
import CamTwistRendering
import SwiftUI

/// The settings of one source step, by kind. Each kind has a section in
/// `SourceSettingsSections.all`; a kind with no section has no settings.
struct SourceSettingsView: View {
    @Environment(\.fileChooser) private var fileChooser
    @Bindable var model: AppModel
    let spec: SourceSpec
    let set: (SourceSpec) -> Void

    var body: some View {
        SourceSettingsSections.view(for: spec, model: model, chooser: fileChooser, set: set)
            ?? AnyView(EmptyView())
    }
}

/// The settings view for one kind of source. A section answers only for the
/// spec it handles, and gives nil for any other.
protocol SourceSettingsSection: Sendable {
    @MainActor
    func view(
        for spec: SourceSpec, model: AppModel, chooser: FileChoosing, set: @escaping (SourceSpec) -> Void
    ) -> AnyView?
}

/// Every section, in one place: a new kind of source is a new section type
/// and one line here.
enum SourceSettingsSections {
    static let all: [any SourceSettingsSection] = [
        CameraSettingsSection(),
        DisplaySettingsSection(),
        WindowSettingsSection(),
        MovieSettingsSection(),
        SlideShowSettingsSection(),
        WebsiteSettingsSection(),
        VNCSettingsSection(),
        StreamSettingsSection(),
        MicrophoneSettingsSection(),
        TelestratorSettingsSection(),
        ImageSettingsSection(),
        TextSettingsSection(),
        ShapeSettingsSection(),
    ]

    /// The first section that handles the spec, or nil when the kind has no settings.
    @MainActor
    static func view(
        for spec: SourceSpec, model: AppModel, chooser: FileChoosing, set: @escaping (SourceSpec) -> Void
    ) -> AnyView? {
        for section in all {
            if let view = section.view(for: spec, model: model, chooser: chooser, set: set) {
                return view
            }
        }
        return nil
    }
}

private func settingsBinding<Settings>(
    _ value: Settings, set: @escaping (SourceSpec) -> Void, wrap: @escaping (Settings) -> SourceSpec
) -> Binding<Settings> {
    Binding(get: { value }, set: { set(wrap($0)) })
}

private struct CameraSettingsSection: SourceSettingsSection {
    @MainActor
    func view(
        for spec: SourceSpec, model: AppModel, chooser: FileChoosing, set: @escaping (SourceSpec) -> Void
    ) -> AnyView? {
        guard case .camera(let deviceID) = spec else { return nil }
        return AnyView(
            Picker("Camera", selection: Binding(get: { deviceID }, set: { set(.camera(deviceID: $0)) })) {
                ForEach(model.choices.cameras) { Text($0.name).tag($0.id) }
            }
        )
    }
}

private struct DisplaySettingsSection: SourceSettingsSection {
    @MainActor
    func view(
        for spec: SourceSpec, model: AppModel, chooser: FileChoosing, set: @escaping (SourceSpec) -> Void
    ) -> AnyView? {
        guard case .display(let settings) = spec else { return nil }
        return AnyView(
            DisplaySettingsView(model: model, settings: settingsBinding(settings, set: set) { .display($0) })
        )
    }
}

private struct WindowSettingsSection: SourceSettingsSection {
    @MainActor
    func view(
        for spec: SourceSpec, model: AppModel, chooser: FileChoosing, set: @escaping (SourceSpec) -> Void
    ) -> AnyView? {
        guard case .window(let settings) = spec else { return nil }
        return AnyView(
            WindowSettingsView(model: model, settings: settingsBinding(settings, set: set) { .window($0) })
        )
    }
}

private struct MovieSettingsSection: SourceSettingsSection {
    @MainActor
    func view(
        for spec: SourceSpec, model: AppModel, chooser: FileChoosing, set: @escaping (SourceSpec) -> Void
    ) -> AnyView? {
        guard case .movie(let settings) = spec else { return nil }
        return AnyView(
            MovieSettingsView(model: model, settings: settingsBinding(settings, set: set) { .movie($0) })
        )
    }
}

private struct SlideShowSettingsSection: SourceSettingsSection {
    @MainActor
    func view(
        for spec: SourceSpec, model: AppModel, chooser: FileChoosing, set: @escaping (SourceSpec) -> Void
    ) -> AnyView? {
        guard case .slideShow(let settings) = spec else { return nil }
        return AnyView(
            SlideShowSettingsView(settings: settingsBinding(settings, set: set) { .slideShow($0) })
        )
    }
}

private struct WebsiteSettingsSection: SourceSettingsSection {
    @MainActor
    func view(
        for spec: SourceSpec, model: AppModel, chooser: FileChoosing, set: @escaping (SourceSpec) -> Void
    ) -> AnyView? {
        guard case .website(let address) = spec else { return nil }
        return AnyView(WebsiteField(address: address) { set(.website(url: $0)) })
    }
}

private struct VNCSettingsSection: SourceSettingsSection {
    @MainActor
    func view(
        for spec: SourceSpec, model: AppModel, chooser: FileChoosing, set: @escaping (SourceSpec) -> Void
    ) -> AnyView? {
        guard case .vnc(let settings) = spec else { return nil }
        return AnyView(VNCFields(model: model, settings: settings) { set(.vnc($0)) })
    }
}

private struct StreamSettingsSection: SourceSettingsSection {
    @MainActor
    func view(
        for spec: SourceSpec, model: AppModel, chooser: FileChoosing, set: @escaping (SourceSpec) -> Void
    ) -> AnyView? {
        guard case .stream(let settings) = spec else { return nil }
        return AnyView(
            Group {
                WebsiteField(address: settings.address) {
                    set(.stream(StreamSettings(address: $0, volume: settings.volume)))
                }
                PercentSlider(
                    title: "Volume",
                    fraction: Binding(
                        get: { settings.volume },
                        set: { set(.stream(StreamSettings(address: settings.address, volume: $0))) }
                    )
                )
                Text("Takes an HLS stream (.m3u8) or a video file, from a web address or a path.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        )
    }
}

private struct MicrophoneSettingsSection: SourceSettingsSection {
    @MainActor
    func view(
        for spec: SourceSpec, model: AppModel, chooser: FileChoosing, set: @escaping (SourceSpec) -> Void
    ) -> AnyView? {
        guard case .microphone(let deviceID) = spec else { return nil }
        return AnyView(
            Group {
                Picker("Microphone", selection: Binding(get: { deviceID }, set: { set(.microphone(deviceID: $0)) })) {
                    Text("The system's choice").tag(String?.none)
                    ForEach(model.choices.microphones) { Text($0.name).tag(String?.some($0.id)) }
                }
                Text("A microphone has no picture. Its sound joins the mix the web streams carry, when sound is switched on in the Output tab.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        )
    }
}

private struct TelestratorSettingsSection: SourceSettingsSection {
    @MainActor
    func view(
        for spec: SourceSpec, model: AppModel, chooser: FileChoosing, set: @escaping (SourceSpec) -> Void
    ) -> AnyView? {
        guard case .telestrator(let settings) = spec else { return nil }
        return AnyView(
            TelestratorSettingsView(settings: settingsBinding(settings, set: set) { .telestrator($0) })
        )
    }
}

private struct ImageSettingsSection: SourceSettingsSection {
    @MainActor
    func view(
        for spec: SourceSpec, model: AppModel, chooser: FileChoosing, set: @escaping (SourceSpec) -> Void
    ) -> AnyView? {
        guard case .image(let path) = spec else { return nil }
        return AnyView(
            Group {
                if path.isEmpty {
                    Text("No picture chosen yet.").foregroundStyle(.secondary)
                } else {
                    LabeledContent("Picture") {
                        Text((path as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                }
                if !model.choices.savedPictures.isEmpty {
                    // The pictures kept in the app's pictures folder, a click away.
                    Picker("From your pictures", selection: Binding(get: { path }, set: { set(.image(path: $0)) })) {
                        if !model.choices.savedPictures.contains(where: { $0.path == path }) {
                            Text("Choose").tag(path)
                        }
                        ForEach(model.choices.savedPictures, id: \.path) { Text($0.name).tag($0.path) }
                    }
                }
                Button(ImageSourceText.chooseButtonTitle(path: path)) {
                    if let chosen = chooser.chooseFiles(
                        allowedExtensions: MediaFileTypes.imageExtensions, allowsFolders: false, allowsMany: false
                    ).first {
                        set(.image(path: chosen))
                    }
                }
                Text("Switch on Picture in picture below to place and size it, for a logo or a watermark.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        )
    }
}

private struct TextSettingsSection: SourceSettingsSection {
    @MainActor
    func view(
        for spec: SourceSpec, model: AppModel, chooser: FileChoosing, set: @escaping (SourceSpec) -> Void
    ) -> AnyView? {
        guard case .text(let settings) = spec else { return nil }
        return AnyView(
            TextSourceSettingsView(settings: settingsBinding(settings, set: set) { .text($0) })
        )
    }
}

private struct ShapeSettingsSection: SourceSettingsSection {
    @MainActor
    func view(
        for spec: SourceSpec, model: AppModel, chooser: FileChoosing, set: @escaping (SourceSpec) -> Void
    ) -> AnyView? {
        guard case .shape(let settings) = spec else { return nil }
        return AnyView(
            ShapeSettingsView(settings: settingsBinding(settings, set: set) { .shape($0) })
        )
    }
}

private struct DisplaySettingsView: View {
    @Bindable var model: AppModel
    @Binding var settings: DisplaySettings

    var body: some View {
        Picker("Screen", selection: $settings.displayID) {
            ForEach(model.choices.displays) { Text($0.name).tag($0.id) }
        }
        Toggle("Show mouse pointer", isOn: $settings.showsCursor)
        Toggle("Follow mouse", isOn: $settings.followsMouse)
        if settings.followsMouse {
            NumberSlider(title: "Area", value: $settings.followFraction, range: DisplaySettings.followFractionRange)
        } else {
            Toggle("Full screen", isOn: Binding(
                get: { DisplayRegionEditing.isFull(settings.region) },
                set: { settings.region = DisplayRegionEditing.region(whenFull: $0) }
            ))
            if !DisplayRegionEditing.isFull(settings.region) {
                NumberSlider(title: "Left", value: $settings.region.x, range: DisplayRegionEditing.leftRange(settings.region))
                NumberSlider(
                    title: "Bottom", value: $settings.region.y, range: DisplayRegionEditing.bottomRange(settings.region)
                )
                NumberSlider(
                    title: "Width", value: $settings.region.width, range: DisplayRegionEditing.widthRange(settings.region)
                )
                NumberSlider(
                    title: "Height", value: $settings.region.height,
                    range: DisplayRegionEditing.heightRange(settings.region)
                )
            }
        }
    }
}

private struct WindowSettingsView: View {
    @Bindable var model: AppModel
    @Binding var settings: WindowSettings

    var body: some View {
        Menu(settings.chooserTitle) {
            ForEach(model.choices.windows) { window in
                Button(window.menuTitle) {
                    // One assignment: each write through the binding starts
                    // from the settings as drawn, so separate writes would
                    // undo one another and leave the title empty.
                    settings = WindowSettings(choosing: window)
                }
            }
        }
        TextField("Window title", text: $settings.titlePattern)
        Toggle("Regex search", isOn: $settings.isRegularExpression)
        TextField("Only this application", text: $settings.applicationText)
    }
}

private struct MovieSettingsView: View {
    @Environment(\.fileChooser) private var fileChooser
    @Bindable var model: AppModel
    @Binding var settings: MovieSettings

    var body: some View {
        ForEach(settings.files, id: \.self) { file in
            HStack {
                Text((file as NSString).lastPathComponent).lineLimit(1)
                TextField("Caption", text: Binding(
                    get: { settings.captionText(for: file) }, set: { settings.setCaption($0, for: file) }
                ))
                Button {
                    settings.remove(file: file)
                } label: {
                    Image(systemName: SymbolName.remove)
                }
                .buttonStyle(.borderless)
            }
        }
        HStack {
            Button("Add video") {
                settings.add(files: fileChooser.chooseFiles(
                    allowedExtensions: MediaFileTypes.movieExtensions, allowsFolders: false, allowsMany: true
                ))
            }
            Button(settings.hotFolderButtonTitle) {
                settings.toggleHotFolder {
                    fileChooser.chooseFiles(allowedExtensions: [], allowsFolders: true, allowsMany: false).first
                }
            }
        }
        if let folder = settings.hotFolder {
            Text("Hot folder: \((folder as NSString).lastPathComponent)").foregroundStyle(.secondary)
        }
        Picker("Playback", selection: $settings.playMode) {
            ForEach(MoviePlayMode.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        Toggle("Play", isOn: $settings.isPlaying)
        Toggle("Hide video when stopped", isOn: $settings.hidesWhenStopped)
        Toggle("Muted", isOn: $settings.isMuted)
        PercentSlider(title: "Volume", fraction: $settings.volume)
        Picker("Audio output", selection: $settings.audioDeviceChoice) {
            Text("System default").tag(MovieSettings.systemDefaultDevice)
            ForEach(model.choices.audioOutputs) { Text($0.name).tag($0.id) }
        }
    }
}

private struct SlideShowSettingsView: View {
    @Environment(\.fileChooser) private var fileChooser
    @Binding var settings: SlideShowSettings

    var body: some View {
        ForEach(settings.paths, id: \.self) { path in
            Text((path as NSString).lastPathComponent).lineLimit(1)
        }
        HStack {
            Button("Add images or folders") {
                settings.add(paths: fileChooser.chooseFiles(
                    allowedExtensions: MediaFileTypes.imageExtensions, allowsFolders: true, allowsMany: true
                ))
            }
            Button("Clear") { settings.paths = [] }
        }
        NumberSlider(title: "Delay in seconds", value: $settings.delay, range: SlideShowSettings.delayRange)
        Toggle("Pause", isOn: $settings.isPaused)
        Toggle("Start again after the last image", isOn: $settings.loops)
    }
}

/// The address is only applied when the user finishes typing, so the page
/// is not reloaded on every keystroke.
private struct WebsiteField: View {
    let address: String
    let commit: (String) -> Void
    @State private var draft = ""

    var body: some View {
        TextField("Address", text: $draft)
            .onAppear { draft = address }
            .onSubmit { commit(draft) }
        Button("Load") { commit(draft) }
    }
}

/// Where another computer is, and its VNC password. What is typed is only
/// taken when it is finished, so the connection is not remade on every keystroke.
private struct VNCFields: View {
    @Bindable var model: AppModel
    let settings: VNCSettings
    let commit: (VNCSettings) -> Void
    @State private var address = ""
    @State private var password = ""

    var body: some View {
        TextField("Computer", text: $address, prompt: Text("studio.local or 192.0.2.10:5901"))
            .onSubmit(connect)
        SecureField("Password", text: $password)
            .onSubmit(connect)
        Button("Connect", action: connect)
            .onAppear {
                address = settings.address
                password = model.remoteScreens.password(for: settings) ?? ""
            }
        Text("Shows another computer's screen over VNC. On a Mac, switch on Screen Sharing in System Settings, and under its options allow VNC viewers with a password. The password is kept in your keychain, not in a setup file.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func connect() {
        let changed = VNCSettings(address: address)
        model.remoteScreens.setPassword(password, for: changed)
        commit(changed)
    }
}

private struct TelestratorSettingsView: View {
    private static let fallbackColor = CamTwistCore.RGBColor(red: 1, green: 0, blue: 0)

    @Binding var settings: TelestratorSettings

    var body: some View {
        Text("Drag on the picture to draw.").foregroundStyle(.secondary)
        ColorRow(
            title: "Pen colour",
            color: settings.penColor.wellColor
        ) { picked in
            settings.penColor = RGBColor(picked: picked, fallback: Self.fallbackColor)
        }
        NumberSlider(title: "Pen size", value: $settings.penWidth, range: TelestratorSettings.penWidthRange)
        HStack {
            Button("Undo") { _ = settings.strokes.popLast() }
                .disabled(settings.strokes.isEmpty)
            Button("Clear") { settings.strokes = [] }
        }
    }
}

private struct TextSourceSettingsView: View {
    private static let fallbackColor = CamTwistCore.RGBColor(red: 1, green: 1, blue: 1)

    @Binding var settings: TextSettings

    var body: some View {
        TextEditor(text: $settings.text)
            .font(.body)
            .frame(minHeight: Layout.textEditorHeight)
            .overlay(RoundedRectangle(cornerRadius: Layout.panelCornerRadius).stroke(.tertiary))
            .help("Return starts a new line")
        FontPicker(fontName: $settings.fontName)
        NumberSlider(title: "Font size", value: $settings.fontSize, range: TextSettings.fontSizeRange)
        NumberSlider(title: "Line height", value: $settings.lineHeight, range: TextSettings.lineHeightRange)
        Picker("Align", selection: $settings.alignment) {
            ForEach(CamTwistCore.TextAlignment.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        Toggle("Drop shadow", isOn: $settings.hasShadow)
        ColorRow(
            title: "Colour",
            color: settings.color.wellColor
        ) { picked in
            settings.color = RGBColor(picked: picked, fallback: Self.fallbackColor)
        }
        Text("Drag it on the picture to place it. Picture in picture below sizes, turns and animates it.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ShapeSettingsView: View {
    private static let fallbackColor = CamTwistCore.RGBColor(red: 0, green: 0, blue: 1)

    @Binding var settings: ShapeSettings

    var body: some View {
        Picker("Shape", selection: $settings.kind) {
            ForEach(ShapeKind.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        ColorRow(
            title: "Colour",
            color: settings.color.wellColor
        ) { picked in
            settings.color = RGBColor(picked: picked, fallback: Self.fallbackColor)
        }
        NumberSlider(title: "Opacity", value: $settings.opacity, range: ShapeSettings.opacityRange)
        Text("Switch on Picture in picture below to place, size, turn and animate it.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

