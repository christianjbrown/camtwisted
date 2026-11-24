import CamTwistCore
import CamTwistRendering
import Foundation

/// Everything there is to pick from at one moment.
struct Choices {
    var cameras: [CameraChoice]
    var displays: [DisplayChoice]
    var windows: [WindowChoice]
    var audioOutputs: [AudioDeviceChoice]
    var microphones: [MicrophoneChoice]
    var savedPictures: [SavedPicture]
    var effects: [EffectListing]
}

/// Looks around for the cameras, screens, windows, pictures and effects the
/// pickers offer. Pictures come from the person's folder, then the app's own.
final class ChoiceCatalog {
    private let devices: SourceChoiceListing
    private let pictures: PictureCatalog
    private let picturesDirectories: [URL]
    private let effectLibrary: EffectLibrary

    init(
        devices: SourceChoiceListing,
        pictures: PictureCatalog,
        picturesDirectories: [URL],
        effectLibrary: EffectLibrary
    ) {
        self.devices = devices
        self.pictures = pictures
        self.picturesDirectories = picturesDirectories
        self.effectLibrary = effectLibrary
    }

    func current() -> Choices {
        Choices(
            cameras: devices.cameras(),
            displays: devices.displays(),
            windows: devices.windows(),
            audioOutputs: devices.audioOutputs(),
            microphones: devices.microphones(),
            savedPictures: savedPictures(),
            effects: effectLibrary.availableEffects()
        )
    }

    /// The pictures in every folder, the earlier folders first. A picture
    /// in an earlier folder stands in for one of the same name later on,
    /// so the person's own copy wins over the one that comes with the app.
    private func savedPictures() -> [SavedPicture] {
        var names = Set<String>()
        return picturesDirectories.flatMap { pictures.pictures(in: $0) }
            .filter { names.insert($0.name).inserted }
    }
}

/// How the effect pickers group what the library offers.
struct EffectMenu {
    /// The ways of switching looks: at once, a plain fade, then the
    /// transition effects in the effects folder.
    func transitionNames(from effects: [EffectListing]) -> [String] {
        let fromFolder = effects.filter { $0.kind == .transition }.map(\.name)
            .filter { $0 != DissolveTransition.name && $0 != StudioSettings.cutName }
        return [StudioSettings.cutName, DissolveTransition.name] + fromFolder
    }

    func effects(of kind: EffectKind, in effects: [EffectListing]) -> [EffectListing] {
        effects.filter { $0.kind == kind }
    }
}
