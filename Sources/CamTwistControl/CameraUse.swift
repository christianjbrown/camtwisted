import Foundation

/// Says where on disk the app behind a running process is.
public protocol ProcessLocating {
    /// The path of the process's bundle, or nil when it has none or has gone.
    func bundlePath(ofProcess process: Int32) -> String?
}

/// Works out which apps have the virtual camera's picture open, by name.
struct CameraUse {
    private static let appExtension = ".app"
    private static let pathSeparator: Character = "/"
    private static let listSeparator = ", "
    private static let lastSeparator = " and "

    let processes: ProcessLocating

    /// The names of the apps behind some processes, each once, in order.
    /// A helper buried inside an app goes by that app's name: a browser's
    /// camera helper is the browser.
    func appNames(for watchers: [Int32]) -> [String] {
        var names: [String] = []
        for name in watchers.compactMap(processes.bundlePath).compactMap(Self.owningApp) where !names.contains(name) {
            names.append(name)
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// The outermost app a path lies in, without its extension.
    static func owningApp(ofBundleAt path: String) -> String? {
        path.split(separator: pathSeparator).first { $0.hasSuffix(appExtension) }
            .map { String($0.dropLast(appExtension.count)) }
    }

    /// Names as they are read out: "Zoom", "Zoom and Safari", "Zoom, Safari and Teams".
    /// The apps behind some processes, named as one phrase. Empty with none.
    func sentence(for watchers: [Int32]) -> String {
        Self.sentence(listing: appNames(for: watchers))
    }

    static func sentence(listing names: [String]) -> String {
        guard let last = names.last, names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: listSeparator) + lastSeparator + last
    }
}
