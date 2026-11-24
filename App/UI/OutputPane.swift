import AVKit
import CamTwistControl
import CamTwistCore
import CamTwistRendering
import SwiftUI

/// Where the picture goes: the virtual camera, a stream on the local
/// network, and a screen.
struct OutputPane: View {
    @Bindable var model: AppModel
    @Environment(\.airPlay) private var airPlay
    @Environment(\.cast) private var cast
    @Environment(\.fileChooser) private var fileChooser
    /// Whether the recording's options are unfolded.
    @State private var isChoosingRecordingOptions: Bool

    init(model: AppModel, opensRecordingOptions: Bool) {
        self.model = model
        _isChoosingRecordingOptions = State(initialValue: opensRecordingOptions)
    }

    var body: some View {
        // An output that is off shows its switch alone; switched on, it
        // opens to show everything about it.
        Section {
            OutputBar(title: "Virtual camera (for Google Meet, Zoom, Teams, FaceTime, WhatsApp, etc)", isOn: $model.preferences.sendsToCamera)
            if model.preferences.sendsToCamera {
                note("\(CameraContract.cameraName) appears in other apps as a camera. It has to be installed once, and macOS will ask you to allow it.")
                StatusLineView(line: .camera(camera.installState, watchers: camera.watchers, isSending: camera.isSending))
                HStack {
                    Button(cameraControls.installTitle) { camera.install() }
                    if cameraControls.canRemove {
                        Button("Remove camera") { camera.remove() }
                    }
                }
                .disabled(cameraControls.isBusy)
                note("Its picture is always \(CameraContract.width) by \(CameraContract.height), whatever the other outputs are set to: that is the one size the camera offers other apps.")
            }
        }
        Section {
            OutputBar(
                title: "Virtual microphone (for Google Meet, Zoom, Teams, FaceTime, WhatsApp, etc)", isOn: $model.preferences.sendsToMicrophone
            )
            if model.preferences.sendsToMicrophone {
                #if STORE
                // The store does not let an app install an audio driver,
                // so the microphone is a separate download.
                note("\(MicrophoneContract.deviceName) appears in other apps as a microphone. It carries the microphones, cameras and videos in the scene on air, mixed, each at the volume set on its step. It is a separate add-on: get it once, and this switch does the rest.")
                StatusLineView(line: .microphone(microphone.state))
                if microphoneControls.offersAddOn {
                    Button("Get the microphone add-on") { microphone.install() }
                }
                #else
                note("\(MicrophoneContract.deviceName) appears in other apps as a microphone. It carries the microphones, cameras and videos in the scene on air, mixed, each at the volume set on its step. It has to be installed once, and macOS will ask for an administrator's password.")
                StatusLineView(line: .microphone(microphone.state))
                HStack {
                    Button(microphoneControls.installTitle) { microphone.install() }
                    if microphoneControls.canRemove {
                        Button("Remove microphone") { microphone.remove() }
                    }
                }
                .disabled(microphoneControls.isBusy)
                #endif
            }
        }
        Section {
            OutputBar(title: "Another screen", isOn: Binding(
                get: { model.fullScreen.displayID != nil },
                set: { model.fullScreen.displayID = screens.screen(whenSwitched: $0) }
            ))
            .disabled(!screens.canSwitch)
            if screens.needsSecondScreen {
                note("Connect a second screen to use this: this one is kept for the app.")
            }
            if model.fullScreen.displayID != nil {
                note("Fills another screen with the picture. Press Escape to close it.")
                Picker("Screen", selection: Bindable(model.fullScreen).displayID) {
                    ForEach(screens.otherDisplays) { Text($0.name).tag(UInt32?.some($0.id)) }
                }
            }
        }
        Section {
            OutputBar(title: "Recording", isOn: Bindable(model.capture).isRecording)
            if model.capture.isRecording {
                note("Saves the picture and its sound as a movie, with a chapter for each scene that goes on air. Switch it off to finish the movie.")
                StatusLineView(line: .recording(model.capture.recordingStatus))
            }
            // The options are there before a recording starts, folded away
            // until wanted, and are left alone while one is under way.
            DisclosureGroup(isExpanded: $isChoosingRecordingOptions) {
                RecordingFolderRow(
                    capture: model.capture, folder: $model.preferences.recordingsFolder, chooser: fileChooser
                )
                RecordingOptionsEditor(options: $model.preferences.recording)
                    .disabled(model.capture.isRecording)
                if model.capture.isRecording {
                    note("Changes wait for the next recording.")
                }
            } label: {
                LabeledContent("Options") {
                    Text(RecordingWording.summary(of: model.preferences.recording)).foregroundStyle(.secondary)
                }
            }
        }
        Section {
            OutputBar(title: "Web stream: HLS", isOn: $model.preferences.webStream.isOn)
            if model.preferences.webStream.isOn {
                note("An HLS stream in fragmented MP4, for browsers and players on this network. It comes with a page that plays it.")
                WebStreamPort(port: $model.preferences.webStream.port)
                WebStreamStatusView(status: streams.webStreamStatus, links: streams.webStreamLinks)
                StreamOptionsEditor(
                    options: $model.preferences.webStream.options, keyFrameTitle: "Seconds in each piece"
                )
            }
        }
        Section {
            OutputBar(title: "Web stream: MP4", isOn: $model.preferences.webMovie.isOn)
            if model.preferences.webMovie.isOn {
                note("One endless MP4, for players that take a plain video address.")
                WebStreamPort(port: $model.preferences.webMovie.port)
                WebStreamStatusView(status: streams.webMovieStatus, links: streams.webMovieLinks)
                StreamOptionsEditor(
                    options: $model.preferences.webMovie.options, keyFrameTitle: "Seconds between key frames"
                )
            }
        }
        Section {
            OutputBar(title: "Web stream: RTMP", isOn: $model.preferences.rtmp.isOn)
            if model.preferences.rtmp.isOn {
                note("Sends the picture to a streaming service or server that takes RTMP, such as a live channel.")
                StreamTargetFields(settings: $model.preferences.rtmp)
                if let line = StatusLine.rtmp(streams.rtmpStatus) { StatusLineView(line: line) }
                StreamOptionsEditor(
                    options: $model.preferences.rtmp.options, keyFrameTitle: "Seconds between key frames",
                    offersCodec: false
                )
            }
        }
        Section {
            OutputBar(title: "AirPlay", isOn: $model.preferences.sendsToAirPlay)
            if model.preferences.sendsToAirPlay {
                note("Plays the picture on an Apple TV or another AirPlay screen on this network. It plays the HLS stream, so it runs a few seconds behind.")
                LabeledContent(OutputChoices.airPlayTitle(isOnDevice: airPlay.isOnDevice)) {
                    AirPlayPicker(player: airPlay.player)
                        .frame(width: Layout.airPlayButtonSize, height: Layout.airPlayButtonSize)
                }
            }
        }
        Section {
            OutputBar(title: "Cast (Chromecast and Google TV)", isOn: $model.preferences.sendsToCast)
            if model.preferences.sendsToCast {
                note("Plays the picture on a Chromecast or another Cast device on this network. It plays the HLS stream, so it runs a few seconds behind.")
                Picker("Device", selection: $model.preferences.castDeviceName) {
                    Text(OutputChoices.castPlaceholder(deviceCount: cast.devices.count)).tag(String?.none)
                    ForEach(cast.devices) { Text($0.name).tag(String?.some($0.name)) }
                }
                if let line = StatusLine.cast(cast.state) { StatusLineView(line: line) }
            }
        }
    }

    /// A quiet line that says what an output is for.
    private func note(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private var camera: CameraOutputModel { model.outputs.camera }
    private var microphone: MicrophoneOutputModel { model.outputs.microphone }
    private var streams: StreamsModel { model.outputs.streams }

    private var cameraControls: CameraInstallControls { CameraInstallControls(camera.installState) }
    private var microphoneControls: MicrophoneInstallControls { MicrophoneInstallControls(microphone.state) }

    private var screens: OutputChoices {
        let window = NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible }
        let own = window?.screen?.displayID
        return OutputChoices(displays: model.choices.displays, windowDisplayID: own, selected: model.fullScreen.displayID)
    }
}

/// The system's button for choosing an AirPlay device for a player.
private struct AirPlayPicker: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.player = player
        return picker
    }

    func updateNSView(_ picker: AVRoutePickerView, context: Context) {
        picker.player = player
    }
}

/// The top of an output: a switch and its name, like a step in a scene.
private struct OutputBar: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: Layout.stepBarSpacing) {
            Toggle("", isOn: $isOn).labelsHidden().help("Switch on or off")
            Text(title).font(Layout.stepBarTitleFont).fontWeight(.semibold)
        }
        .padding(.vertical, Layout.stepBarPadding)
    }
}

/// Shows one status line: its picture, its words and its colour.
private struct StatusLineView: View {
    let line: StatusLine

    var body: some View {
        Label(line.text, systemImage: line.icon.rawValue)
            .foregroundStyle(line.tint == .alert ? Color.red : Color.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Where an RTMP stream goes. What is typed is only taken when it is
/// finished, so the stream does not reconnect on every keystroke.
private struct StreamTargetFields: View {
    @Binding var settings: RTMPSettings
    @State private var address = ""
    @State private var key = ""

    var body: some View {
        TextField("Server", text: $address, prompt: Text("rtmp://example.com/live"))
            .onSubmit(commit)
        SecureField("Stream key", text: $key)
            .onSubmit(commit)
        Button("Use these") { commit() }
            .disabled(address == settings.address && key == settings.streamKey)
            .onAppear {
                address = settings.address
                key = settings.streamKey
            }
    }

    private func commit() {
        settings.address = address
        settings.streamKey = key
    }
}

/// How a stream is encoded: its picture's size and data rate, and its sound.
private struct StreamOptionsEditor: View {
    @Binding var options: StreamOptions
    /// What the key frame spacing means for this kind of stream.
    let keyFrameTitle: String
    /// Whether the stream can be anything but H.264. RTMP, as streaming
    /// services take it, cannot.
    var offersCodec = true
    private static let monoChannels = 1
    private static let wholeNumber = "%.0f"

    var body: some View {
        if offersCodec {
            Picker("Encoding", selection: $options.codec) {
                ForEach(StreamCodec.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        }
        PictureHeightPicker(height: $options.height, whose: "this stream's")
        Picker("Picture kilobits a second", selection: $options.videoKilobits) {
            ForEach(StreamOptions.videoKilobitChoices, id: \.self) {
                Text(String(format: Self.wholeNumber, $0)).tag($0)
            }
        }
        NumberSlider(title: keyFrameTitle, value: $options.keyFrameSeconds, range: StreamOptions.keyFrameSecondsRange)
        Picker("Sound kilobits a second", selection: $options.soundKilobits) {
            ForEach(StreamOptions.soundKilobitChoices, id: \.self) { Text("\($0)").tag($0) }
        }
        Picker("Sound channels", selection: $options.soundChannels) {
            ForEach(StreamOptions.channelChoices, id: \.self) {
                Text($0 == Self.monoChannels ? "Mono" : "Stereo").tag($0)
            }
        }
        Picker("Sound samples a second", selection: $options.sampleRate) {
            ForEach(StreamOptions.sampleRates, id: \.self) { Text("\($0)").tag($0) }
        }
        Toggle("Mark each scene change in the stream", isOn: $options.marksScenes)
            .help("Puts a marker with the scene's name into the stream when a different scene goes on air")
        Button("Reset") { options = StreamOptions(keyFrameSeconds: options.keyFrameSeconds) }
            .help("Puts the sizes and rates back to how they started")
    }
}

/// Where recordings go: the folder, and the ways to change it and to see it.
private struct RecordingFolderRow: View {
    let capture: CaptureModel
    /// The folder chosen for recordings, or nil while they go with the snapshots.
    @Binding var folder: String?
    let chooser: FileChoosing

    var body: some View {
        LabeledContent("Folder") {
            Text(capture.recordingsDirectory.lastPathComponent).foregroundStyle(.secondary)
        }
        .help(capture.recordingsDirectory.path)
        HStack {
            Group {
                Button("Choose Folder…") {
                    if let chosen = chooser.chooseFiles(
                        allowedExtensions: [], allowsFolders: true, allowsMany: false
                    ).first {
                        folder = chosen
                    }
                }
                Button("Use the Snapshots Folder") { folder = nil }
                    .disabled(folder == nil)
            }
            .disabled(capture.isRecording)
            Button("Open folder") { capture.openRecordingsFolder() }
        }
    }
}

/// How a recording is made: the kind of file, how its picture and sound
/// are encoded, its size and its data rates. What is on offer in each
/// list is whatever `RecordingRules` says goes with the rest.
private struct RecordingOptionsEditor: View {
    @Binding var options: RecordingOptions

    var body: some View {
        Picker("Container", selection: $options.container) {
            ForEach(RecordingContainer.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        Picker("Picture encoding", selection: $options.pictureCodec) {
            ForEach(RecordingRules.pictureCodecs(in: options.container), id: \.self) { Text($0.title).tag($0) }
        }
        PictureHeightPicker(height: $options.height, whose: "the recording's")
        if RecordingRules.hasBitRate(options.pictureCodec) {
            Picker("Picture kilobits a second", selection: $options.pictureKilobits) {
                Text(RecordingWording.pictureBitRateTitle(nil)).tag(Int?.none)
                ForEach(RecordingRules.pictureKilobitChoices, id: \.self) {
                    Text(RecordingWording.pictureBitRateTitle($0)).tag(Int?.some($0))
                }
            }
            .help("Automatic gives a bigger picture more data")
        }
        Picker("Sound encoding", selection: $options.soundCodec) {
            ForEach(RecordingRules.soundCodecs(in: options.container), id: \.self) { Text($0.title).tag($0) }
        }
        if RecordingRules.hasBitRate(options.soundCodec) {
            Picker("Sound kilobits a second", selection: $options.soundKilobits) {
                ForEach(RecordingRules.soundKilobitChoices, id: \.self) { Text("\($0)").tag($0) }
            }
        }
        Button("Reset") { options = RecordingOptions() }
            .help("Puts the file, encodings, size and rates back to how they started")
    }
}

/// How big an output's picture is, from the one list every output shares.
private struct PictureHeightPicker: View {
    @Binding var height: Int
    /// Whose picture it is, as the help says it: "this stream's".
    let whose: String

    var body: some View {
        Picker("Resolution", selection: $height) {
            ForEach(PictureHeight.all, id: \.self) { Text(PictureHeight.label(for: $0)).tag($0) }
        }
        .help("How big \(whose) picture is. Anything above Full HD has the whole picture drawn in 4K, which is four times the work for this Mac.")
    }
}

/// The port a web stream is served on.
private struct WebStreamPort: View {
    @Binding var port: Int

    var body: some View {
        LabeledContent("Port") {
            TextField("Port", value: $port, format: .number.grouping(.never))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: Layout.portFieldWidth)
        }
    }
}

/// Says whether a web stream is up, and where to watch it.
private struct WebStreamStatusView: View {
    let status: WebStreamStatus
    let links: [WebStreamLink]

    var body: some View {
        if let line = StatusLine.webStream(status) {
            StatusLineView(line: line)
        } else if status == .running {
            ForEach(links) { link in
                LabeledContent(link.title) {
                    HStack {
                        Text(link.address).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(link.address, forType: .string)
                        } label: {
                            Image(systemName: SymbolName.copy)
                        }
                        .buttonStyle(.borderless)
                        .help("Copy")
                    }
                }
            }
        }
    }
}
