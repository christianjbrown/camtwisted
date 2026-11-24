import AppKit
import CamTwistControl

/// The usual Mac question about unsaved changes, asked before quitting.
struct SaveAlert: SaveAsking {
    private enum Wording {
        static let unnamedSetup = "this setup"
        static let save = "Save"
        static let discard = "Don't Save"
        static let cancel = "Cancel"
        static let loss = "Your changes will be lost if you don't save them."
    }

    func askToSave(setupName: String?) -> SaveAnswer {
        let alert = NSAlert()
        let name = setupName.map { "“\($0)”" } ?? Wording.unnamedSetup
        alert.messageText = "Do you want to save the changes to \(name)?"
        alert.informativeText = Wording.loss
        alert.addButton(withTitle: Wording.save)
        alert.addButton(withTitle: Wording.discard)
        alert.addButton(withTitle: Wording.cancel)
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertSecondButtonReturn: return .discard
        default: return .cancel
        }
    }
}
