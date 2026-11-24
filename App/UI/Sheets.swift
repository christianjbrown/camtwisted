import CamTwistControl
import CamTwistCore
import SwiftUI
import UniformTypeIdentifiers

/// The File menu: new, open, save and preferences.
struct SetupCommands: Commands {
    private enum Shortcut {
        static let new: KeyEquivalent = "n"
        static let open: KeyEquivalent = "o"
        static let save: KeyEquivalent = "s"
    }

    @Bindable var model: AppModel
    let chooser: SetupFileChoosing
    /// The example show that comes with the app.
    let exampleShow: URL

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") { model.setups.startNew() }
                .keyboardShortcut(Shortcut.new)
            Button("Open…") {
                if let url = chooser.chooseSetupToOpen() { model.setups.open(url) }
            }
            .keyboardShortcut(Shortcut.open)
            Button("Open Example Show") { model.setups.openCopy(of: exampleShow) }
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                if !model.setups.saveToCurrentFile() { saveAs() }
            }
            .keyboardShortcut(Shortcut.save)
            Button("Save As…") { saveAs() }
                .keyboardShortcut(Shortcut.save, modifiers: [.command, .shift])
        }
    }

    private func saveAs() {
        if let url = chooser.chooseSetupToSave(suggestedName: model.documentURL?.lastPathComponent) {
            model.setups.save(to: url)
        }
    }
}

/// The Window menu's switches for the window itself.
struct WindowCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Toggle("Mirror the Picture", isOn: $model.preferences.mirrorsPreview)
            Toggle("Keep on Top", isOn: $model.preferences.keepsWindowOnTop)
            Divider()
            OpenStudioButton()
        }
    }
}

/// How the app itself behaves on this Mac: the Settings window, reached
/// from the app menu or with Command-comma.
struct SettingsView: View {
    private enum Size {
        static let width: CGFloat = 460
    }

    @Bindable var model: AppModel
    @Environment(\.fileChooser) private var fileChooser

    var body: some View {
        Form {
            Section {
                LabeledContent("Snapshots and recordings") {
                    Text(model.capture.snapshotsDirectory.lastPathComponent).foregroundStyle(.secondary)
                }
                .help(model.capture.snapshotsDirectory.path)
                HStack {
                    Button("Choose Folder…") {
                        if let folder = fileChooser.chooseFiles(
                            allowedExtensions: [], allowsFolders: true, allowsMany: false
                        ).first {
                            model.preferences.snapshotsFolder = folder
                        }
                    }
                    Button("Use the Usual Folder") { model.preferences.snapshotsFolder = nil }
                        .disabled(model.preferences.snapshotsFolder == nil)
                }
            } footer: {
                Text("The folder belongs to this Mac, so it is not kept in a setup file.")
            }
            Section {
                Toggle("Save changes automatically", isOn: $model.preferences.autosaves)
            } footer: {
                Text("Once a setup has been saved or opened, every change is saved to its file straight away.")
            }
        }
        .formStyle(.grouped)
        // Everything fits, so no scroll bar, which the app otherwise always shows.
        .scrollDisabled(true)
        .frame(width: Size.width)
        .fixedSize(horizontal: false, vertical: true)
    }
}
