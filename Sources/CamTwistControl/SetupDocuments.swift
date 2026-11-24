import CamTwistCore
import Foundation

/// Reads and writes the bytes of setup files.
public protocol SetupFiling {
    func read(from url: URL) throws -> Data
    func write(_ data: Data, to url: URL) throws
}

/// The slice of the model that setup files work on.
@MainActor
protocol SetupDocumentState: StudioState {
    var preferences: AppPreferences { get set }
    var documentURL: URL? { get set }
    var setupProblem: String? { get set }
    var startsAfresh: Bool { get set }
    /// Puts one scene with the first source on air, as a fresh start does.
    func startFreshScene()
}

/// Opens a setup file.
@MainActor
public protocol SetupOpening: AnyObject {
    func open(_ url: URL)
}

/// Starting, opening and saving setup files.
@MainActor
public final class SetupDocuments: SetupOpening, ClosingSetups {
    /// The model owns this helper, so it is not held on to from here.
    private unowned let state: SetupDocumentState
    private let filing: SetupFiling
    private let windows: WindowKeeping
    private let coder: SetupDocumentCoder

    init(state: SetupDocumentState, filing: SetupFiling, windows: WindowKeeping, coder: SetupDocumentCoder) {
        self.coder = coder
        self.state = state
        self.filing = filing
        self.windows = windows
    }

    /// Starts again from nothing: one scene, the usual settings and window.
    /// What stays on this Mac, such as the snapshot folder, is kept.
    public func startNew() {
        isApplying = true
        defer { isApplying = false }
        forgetWhatWasOpen()
        state.studio = StudioSettings()
        state.preferences = globals.applied(to: AppPreferences())
        state.documentURL = nil
        state.setupProblem = nil
        state.startsAfresh = true
        state.startFreshScene()
        windows.resetSize()
        markSaved()
    }

    public func open(_ url: URL) {
        isApplying = true
        defer { isApplying = false }
        attempt {
            let document = try coder.decode(try filing.read(from: url))
            guard let scene = document.sceneToShow else { throw SetupFileError.noScenes }
            forgetWhatWasOpen()
            state.studio = document.studio
            state.preferences = globals.applied(to: document.preferences)
            state.scene = scene
            state.documentURL = url
            state.startsAfresh = false
            if let size = document.windowSize {
                windows.resize(to: CGSize(width: size.width, height: size.height))
            }
            markSaved()
        }
    }

    /// Opens a setup as a new, unsaved one, so saving asks where to put it
    /// and the original, such as the example show inside the app, is never
    /// written over.
    public func openCopy(of url: URL) {
        open(url)
        guard state.documentURL == url else { return }
        state.documentURL = nil
        markSaved()
    }

    public func save(to url: URL) {
        attempt {
            let document = SetupDocument(
                studio: state.studio,
                preferences: state.preferences,
                windowSize: windows.contentSize.map { SetupWindowSize(width: $0.width, height: $0.height) }
            )
            try filing.write(try coder.encode(document), to: url)
            state.documentURL = url
            markSaved()
        }
    }

    /// Saves over the file the setup came from. False, saving nothing, when
    /// it has none yet and a place has to be chosen.
    @discardableResult
    public func saveToCurrentFile() -> Bool {
        guard let url = state.documentURL else { return false }
        save(to: url)
        return true
    }

    /// The file the setup came from or was last saved to.
    public var documentURL: URL? { state.documentURL }

    /// Whether the setup has changed since it was started, opened or saved.
    /// Putting another scene on air is running the show, not changing it.
    public var hasUnsavedChanges: Bool {
        saved.map { $0 != contents } ?? false
    }

    /// Saves over the setup's file after a change, when autosave is on. A
    /// setup that has never been saved or opened has no file, so it waits.
    public func autosave() {
        guard !isApplying, state.preferences.autosaves, hasUnsavedChanges else { return }
        saveToCurrentFile()
    }

    /// Takes what is there now as what was last saved.
    func markSaved() {
        saved = contents
    }

    /// What the setup was when it was last started, opened or saved.
    private var saved: SetupDocument?
    /// True while a setup is being put in place, part by part, so a half
    /// changed setup is never written over the file it is replacing.
    private var isApplying = false

    /// What would go into the file, less what does not count as a change.
    private var contents: SetupDocument {
        var studio = state.studio
        studio.onAirID = nil
        return SetupDocument(studio: studio, preferences: state.preferences, windowSize: nil)
    }

    private var globals: GlobalPreferences { GlobalPreferences(state.preferences) }

    private func forgetWhatWasOpen() {
        state.editedSceneID = nil
        state.studioPreview = nil
    }

    /// Runs a step and keeps the reason it failed, for the window to show.
    private func attempt(_ step: () throws -> Void) {
        do {
            state.setupProblem = nil
            try step()
        } catch {
            state.setupProblem = error.localizedDescription
        }
    }
}
