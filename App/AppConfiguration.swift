import CamTwistControl
import CamTwistCore
import Foundation

/// Settings that can change without a new build, read once at launch.
struct AppConfiguration {
    /// Folder the effect files the user adds are loaded from.
    let effectsDirectory: URL
    /// Folder of pictures offered as ready-made sources.
    let picturesDirectory: URL
    /// Folder of web page effects that come with the app.
    let bundledWebEffectsDirectory: URL
    /// The example show that comes with the app, opened from the File menu.
    let exampleShow: URL
    /// The numbers that can be turned without a new build.
    let tunables: Tunables

    private enum Key {
        static let effectsDirectory = "effectsDirectory"
        static let picturesDirectory = "picturesDirectory"
    }

    private enum Default {
        static let effectsFolderName = "Effects"
        static let bundledWebEffectsFolderName = "WebEffects"
        static let picturesFolderName = "Pictures"
        static let fallbackAppFolderName = "CamTwisted"
        static let exampleShowFileName = "Demo show.camtwisted"
    }

    static func load(defaults: UserDefaults = .standard, bundle: Bundle = .main) -> AppConfiguration {
        let appFolder = bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
            ?? Default.fallbackAppFolderName
        let support = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).appendingPathComponent(appFolder)
        func directory(key: String, folder: String) -> URL {
            if let path = defaults.string(forKey: key), !path.isEmpty {
                return URL(fileURLWithPath: path)
            }
            return support.appendingPathComponent(folder)
        }
        return AppConfiguration(
            effectsDirectory: directory(key: Key.effectsDirectory, folder: Default.effectsFolderName),
            picturesDirectory: directory(key: Key.picturesDirectory, folder: Default.picturesFolderName),
            bundledWebEffectsDirectory: (bundle.resourceURL ?? support)
                .appendingPathComponent(Default.bundledWebEffectsFolderName),
            exampleShow: (bundle.resourceURL ?? support).appendingPathComponent(Default.exampleShowFileName),
            tunables: Tunables.load(defaults: defaults)
        )
    }
}

extension UserDefaults: @retroactive KeyValueStore {
    public func set(_ data: Data?, forKey key: String) {
        set(data as Any?, forKey: key)
    }
}
