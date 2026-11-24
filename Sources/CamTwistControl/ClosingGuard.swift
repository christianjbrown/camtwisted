import Foundation

/// What somebody chose when asked whether to save a changed setup.
public enum SaveAnswer: Equatable {
    case save
    case discard
    case cancel
}

/// Asks whether to save a changed setup before the app quits.
@MainActor
public protocol SaveAsking {
    /// - Parameter setupName: the setup's file name, nil when it has none yet.
    func askToSave(setupName: String?) -> SaveAnswer
}

/// The part of the setup documents that closing needs.
@MainActor
public protocol ClosingSetups: AnyObject {
    var hasUnsavedChanges: Bool { get }
    var documentURL: URL? { get }
    @discardableResult func saveToCurrentFile() -> Bool
    func save(to url: URL)
}

/// Decides whether the app may quit, asking first only when the setup has
/// changes that are not saved.
@MainActor
public final class ClosingGuard {
    private let setups: ClosingSetups
    private let asker: SaveAsking
    private let chooser: SetupFileChoosing

    public init(setups: ClosingSetups, asker: SaveAsking, chooser: SetupFileChoosing) {
        self.setups = setups
        self.asker = asker
        self.chooser = chooser
    }

    /// True when quitting can go ahead. Saving that fails, or a save panel
    /// that is cancelled, keeps the app open so nothing is lost.
    public func mayClose() -> Bool {
        guard setups.hasUnsavedChanges else { return true }
        switch asker.askToSave(setupName: setups.documentURL?.lastPathComponent) {
        case .discard:
            return true
        case .cancel:
            return false
        case .save:
            if !setups.saveToCurrentFile() {
                guard let url = chooser.chooseSetupToSave(suggestedName: nil) else { return false }
                setups.save(to: url)
            }
            return !setups.hasUnsavedChanges
        }
    }
}
