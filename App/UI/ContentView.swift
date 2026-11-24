import CamTwistControl
import CamTwistCore
import CamTwistRendering
import SwiftUI
import UniformTypeIdentifiers

enum Layout {
    static let sidebarWidth: CGFloat = 400
    static let minimumSidebarWidth: CGFloat = 340
    static let maximumSidebarWidth: CGFloat = 900
    static let pickerHeight: CGFloat = 300
    static let panelMinimumWidth: CGFloat = 104
    static let panelSpacing: CGFloat = 8
    static let panelCornerRadius: CGFloat = 6
    static let chevronWidth: CGFloat = 18
    static let scriptEditorHeight: CGFloat = 90
    static let textEditorHeight: CGFloat = 60
    static let onAirBorderWidth: CGFloat = 2
    static let minimumPreviewWidth: CGFloat = 480
    static let padding: CGFloat = 16
    static let aspectRatio = CameraContract.size.width / CameraContract.size.height
    static let studioMonitorHeight: CGFloat = 150
    static let numberFieldWidth: CGFloat = 60
    static let portFieldWidth: CGFloat = 80
    static let airPlayButtonSize: CGFloat = 28
    static let onAirOutlineWidth: CGFloat = 1
    /// The window's size on a fresh start, in points: 3200 by 1800 pixels
    /// on a Retina screen. A smaller screen gets as much of it as fits.
    static let windowSize = CGSize(width: 1600, height: 900)
    /// The bar at the top of each step in "Arrange and adjust".
    static let stepBarSpacing: CGFloat = 10
    static let stepBarPadding: CGFloat = 4
    /// Room between the drag handle and the remove button, so one is not hit for the other.
    static let stepBarHandleGap: CGFloat = 12
    static let stepBarIconFont = Font.title3
    static let stepBarTitleFont = Font.title3
    /// Half a gap, for the breathing room around a divider or inside a panel.
    static let panelHalfSpacing: CGFloat = panelSpacing / 2
}

/// SF Symbols used in more than one place.
enum SymbolName {
    static let remove = "minus.circle"
    static let delete = "trash"
    static let dragHandle = "line.3.horizontal"
    static let reset = "arrow.counterclockwise"
    static let copy = "doc.on.doc"
    static let add = "plus"
    static let studio = "rectangle.split.2x1"
    static let hint = "lightbulb"
    static let dropIntoScene = "arrow.down.to.line"
    static let dropIntoBranch = "arrow.turn.down.right"
    static let peek = "eye"
    static let peeking = "eye.fill"
    static let locked = "lock.fill"
    static let missing = "exclamationmark.triangle.fill"
    static let unlocked = "lock.open"
    static let chevronOpen = "chevron.down"
    static let chevronClosed = "chevron.right"
}

/// The groups of controls the sidebar can show.
enum SidebarPane: String, CaseIterable, Identifiable {
    case scenes = "Input"
    case output = "Output"

    var id: String { rawValue }
}

struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var pane: SidebarPane
    private let launch: LaunchOptions

    init(model: AppModel, launch: LaunchOptions = .load()) {
        self.model = model
        self.launch = launch
        _pane = State(initialValue: launch.pane.flatMap(SidebarPane.init(rawValue:)) ?? .scenes)
    }

    var body: some View {
        // A split view, so the divider between the picture and the controls drags.
        HSplitView {
            VStack(spacing: 0) {
                ProgramView(model: model)
                    .frame(minWidth: Layout.minimumPreviewWidth, maxWidth: .infinity, maxHeight: .infinity)
                    .padding(Layout.padding)
                PictureBar(model: model)
            }
            .background(Color.black)
            VStack(spacing: 0) {
                Picker("Controls", selection: $pane) {
                    ForEach(SidebarPane.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(Layout.padding)
                Form {
                    switch pane {
                    case .scenes: ScenesPane(model: model)
                    case .output: OutputPane(model: model, opensRecordingOptions: launch.opensRecordingOptions)
                    }
                }
                .formStyle(.grouped)
                // A bezel on every box that takes typing, so none reads as a label.
                .textFieldStyle(.roundedBorder)
            }
            .frame(minWidth: Layout.minimumSidebarWidth, idealWidth: Layout.sidebarWidth, maxWidth: Layout.maximumSidebarWidth)
        }
        .navigationTitle(model.documentURL?.lastPathComponent ?? CameraContract.deviceName)
        .onAppear {
            if launch.opensStudioWindow { openWindow(id: StudioWindowView.windowIdentifier) }
            if launch.opensSettings { openSettings() }
        }
    }
}

/// The strip under the picture: what a drag will do, and the snapshot button.
private struct PictureBar: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack {
            // A setup file that would not open or save says why, in the hint's place.
            Text(PictureBarText.hint(setupProblem: model.setupProblem, dragHint: model.picture.dragHint)).foregroundStyle(.secondary)
            Spacer()
            Button("Take snapshot") { model.capture.takeSnapshot() }
                .help(PictureBarText.snapshotHelp(folderName: model.capture.snapshotsDirectory.lastPathComponent))
        }
        .padding([.horizontal, .bottom], Layout.padding)
    }
}

/// The program picture. Dragging on it moves the selected step when that
/// step can be placed, or draws when it is a telestrator.
private struct ProgramView: View {
    @Bindable var model: AppModel
    @Environment(PreviewMonitors.self) private var monitors
    @Environment(\.pictureKeys) private var keys
    @Environment(\.fileDrops) private var drops

    var body: some View {
        GeometryReader { geometry in
            let frame = AspectFitter.fit(CameraContract.size, in: geometry.size)
            PreviewView(sink: monitors.program)
                // The picture is an AppKit view, which would keep mouse events
                // to itself, so a clear layer on top takes the drags.
                .overlay {
                    ZStack {
                        Color.clear.contentShape(Rectangle())
                        if let box = model.picture.selectionBox(in: frame.size) {
                            SelectionBox(box: box)
                        }
                        if let pen = penBeingUsed {
                            Path { path in path.addLines(model.pictureDrag.stroke) }
                                .stroke(pen.color, style: StrokeStyle(
                                    lineWidth: pen.width * frame.width, lineCap: .round, lineJoin: .round
                                ))
                        }
                    }
                    .gesture(dragging(in: frame.size), including: model.picture.dragTarget == nil ? .none : .all)
                    // A picture or video file dropped on the picture joins the scene.
                    .onDrop(of: [.fileURL], isTargeted: nil) { drops.receive($0) }
                }
                .frame(width: frame.width, height: frame.height)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .onAppear { keys.start(for: model.keys) }
        .onDisappear { keys.stop() }
    }

    /// The pen of the telestrator being drawn with, if one is.
    private var penBeingUsed: (color: Color, width: Double)? {
        guard let settings = model.picture.pen else { return nil }
        let pen = settings.penColor
        return (Color(.sRGB, red: pen.red, green: pen.green, blue: pen.blue), settings.penWidth)
    }

    /// The drag itself is the model's business: this passes on where the pointer is.
    private func dragging(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { model.pictureDrag.changed(to: $0.location, start: $0.startLocation, in: size) }
            .onEnded { _ in model.pictureDrag.ended(in: size) }
    }
}

/// The box drawn round the selected step: an outline, a handle at each
/// corner when it resizes and, when it turns, a knob on a stalk.
private struct SelectionBox: View {
    let box: SelectionBoxLayout

    private static let lineWidth: CGFloat = 1.5
    private static let corners: [UnitPoint] = [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing]

    var body: some View {
        let width = box.size.width
        let height = box.size.height
        let handle = SelectionBoxLayout.handleSize
        // The knob, measured down from the top edge of the box.
        let knob = height / 2 + box.knobOffset
        ZStack {
            Rectangle().stroke(Color.accentColor, lineWidth: Self.lineWidth)
            if box.canResize {
                ForEach(Self.corners.indices, id: \.self) { index in
                    Rectangle()
                        .fill(Color.white)
                        .overlay(Rectangle().stroke(Color.accentColor, lineWidth: Self.lineWidth))
                        .frame(width: handle, height: handle)
                        .position(x: Self.corners[index].x * width, y: Self.corners[index].y * height)
                }
            }
            if box.canTurn {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: Self.lineWidth, height: abs(knob))
                    .position(x: width / 2, y: knob / 2)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: Self.lineWidth))
                    .frame(width: handle, height: handle)
                    .position(x: width / 2, y: knob)
            }
        }
        .frame(width: width, height: height)
        .rotationEffect(.degrees(box.rotation))
        .position(box.center)
        .allowsHitTesting(false)
    }
}
