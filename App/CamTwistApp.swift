import CamTwistControl
import CamTwistCore
import CamTwistRendering
import CoreImage
import AVFoundation
import SwiftUI

@main
struct CamTwistApp: App {
    private static let windowIdentifier = "main"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    @State private var monitors: PreviewMonitors
    @State private var airPlay: AirPlayOutput
    @State private var cast: CastOutput

    init() {
        let monitors = PreviewMonitors(main: .main)
        let configuration = AppConfiguration.load()
        exampleShow = configuration.exampleShow
        let pacing = configuration.tunables.pacing
        let airPlay = AirPlayOutput(player: AVPlayer(), main: .main, retryDelay: pacing.airPlayRetryDelay)
        _airPlay = State(initialValue: airPlay)
        let cast = CastOutput(
            browser: BonjourCastBrowser(), connections: TLSCastConnections(),
            queue: DispatchQueues().makeQueue(label: CastOutput.queueLabel, qos: .default), main: DispatchWorkQueue(),
            clock: Clocks.system.today,
            retryDelay: pacing.castRetryDelay, pingInterval: pacing.castPingInterval,
            largestRead: pacing.castLargestRead
        )
        _cast = State(initialValue: cast)
        // Scroll bars show whenever there is more to scroll to, whatever the
        // system is set to: ones that hide until hovered over hide the fact
        // that there is more. Set for this app alone, before any view is made.
        UserDefaults.standard.set(Self.alwaysShowScrollBars, forKey: Self.scrollBarsKey)
        _monitors = State(initialValue: monitors)
        let fileAccess = FileAccessKeeper(
            handler: SecurityScopedBookmarks(), store: DefaultsBookmarkStore(defaults: .standard)
        )
        fileChooser = PanelFileChooser(access: fileAccess)
        self.fileAccess = fileAccess
        // Before anything opens a file: take up again the permission to read what was chosen before.
        fileAccess.restore()
        _model = State(initialValue: AppAssembly.model(
            configuration: configuration, monitors: monitors, airPlay: airPlay, cast: cast
        ))
    }

    /// The system's setting for when scroll bars show, and its "always" value.
    private static let scrollBarsKey = "AppleShowScrollBars"
    private static let alwaysShowScrollBars = "Always"

    /// The example show that comes with the app.
    private let exampleShow: URL
    /// The system's panels, for everything that picks a file.
    private let fileChooser: PanelFileChooser
    /// Keeps the permission to read what has been chosen or dropped.
    private let fileAccess: FileAccessKeeping
    /// Listens for the keys that act on the picture.
    private let pictureKeys = PictureKeyWatcher()
    /// The fonts on this Mac.
    private let fonts = SystemFonts()
    /// What the About window says, from the app's own information.
    private let about = AboutDetails(information: Bundle.main.infoDictionary ?? [:])

    var body: some Scene {
        Window(CameraContract.deviceName, id: Self.windowIdentifier) {
            ContentView(model: model)
                .environment(\.fileChooser, fileChooser)
                .environment(\.fileDrops, DroppedFileLoader(receiver: FileDropReceiver(access: fileAccess, scene: model.steps)))
                .environment(\.pictureKeys, pictureKeys)
                .environment(\.fonts, fonts)
                .environment(monitors)
                .environment(\.airPlay, airPlay)
                .environment(\.cast, cast)
                .onAppear {
                    ScriptingBridge.shared.slices = model.scripts
                    model.start()
                }
                // The window exists a moment after its content appears, which
                // is when a task attached to the content runs.
                .task {
                    if model.startsAfresh { AppKitWindowKeeper().resetSize() }
                    appDelegate.handleOpenedFiles(with: model.setups)
                    appDelegate.guardClosing(
                        with: ClosingGuard(setups: model.setups, asker: SaveAlert(), chooser: fileChooser),
                        mainWindow: Self.windowIdentifier
                    )
                    let launch = LaunchOptions.load()
                    if let setup = launch.setupToOpen { model.setups.open(setup) }
                    if launch.opensStepSettings {
                        model.expandedSteps = Set(model.scene.items.map(\.id))
                    }
                    if let step = launch.stepToSelect(in: model.scene) { model.selectedStepID = step }
                }
        }
        Window(StudioWindowView.title, id: StudioWindowView.windowIdentifier) {
            StudioWindowView(model: model)
                .environment(monitors)
        }
        .commands {
            AboutCommands(details: about)
            SetupCommands(model: model, chooser: fileChooser, exampleShow: exampleShow)
            WindowCommands(model: model)
            CommandGroup(after: .appSettings) {
                Button("Reinstall Camera") { model.outputs.camera.install() }
            }
            CommandMenu("Scenes") {
                ForEach(model.studio.buttons) { scene in
                    Button(scene.name) { model.goLive(withScene: scene.id) }
                        .disabled(model.studio.onAirID == scene.id)
                }
                if !model.studio.buttons.isEmpty {
                    Divider()
                }
                Button("Go Live with Preview") { model.performOnMain(.studioTransition) }
                    .disabled(model.studioPreview == nil)
                Button("Clear Preview") { model.performOnMain(.studioClear) }
                    .disabled(model.studioPreview == nil)
                Divider()
                Button("Take snapshot") { model.capture.takeSnapshot() }
                Menu("Full Screen") {
                    Button("Off") { model.fullScreen.displayID = nil }
                    ForEach(model.choices.displays) { display in
                        Button(display.name) { model.fullScreen.displayID = display.id }
                    }
                }
            }
        }
        Settings { SettingsView(model: model).environment(\.fileChooser, fileChooser) }
        // The main window is first, so it is the one that opens at launch.
        Window("About \(about.name)", id: AboutView.windowIdentifier) {
            AboutView(details: about)
        }
        .windowResizability(.contentSize)
    }
}
