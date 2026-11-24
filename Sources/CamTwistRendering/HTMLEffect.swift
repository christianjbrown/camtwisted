import CamTwistCore
import CoreImage
import Foundation

/// A web page drawn over the picture, with the page's background left clear.
public final class HTMLEffect: ImageEffect {
    private let camera: WebPageCamera
    private let canvas: CGSize

    public init(
        file: URL, canvas: CGSize, snapshotsPerSecond: TimeInterval, timers: RepeatingTimers,
        onMain: @escaping MainHop, makeHost: @escaping WebPageHostMaker
    ) {
        self.canvas = canvas
        camera = WebPageCamera(
            url: file, canvas: canvas, isTransparent: true, snapshotsPerSecond: snapshotsPerSecond, timers: timers,
            onMain: onMain, makeHost: makeHost
        )
        camera.start()
    }

    deinit {
        camera.stop()
    }

    public func setValues(_ values: [String: EffectValue]) {}

    public func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        guard let page = camera.latestFrame, page.extent.width > 0, page.extent.height > 0 else { return image }
        let scale = CGAffineTransform(
            scaleX: canvas.width / page.extent.width, y: canvas.height / page.extent.height
        )
        return page.transformed(by: scale).composited(over: image)
    }
}

/// The `.html` overlay effects in the effects folder.
public final class HTMLEffectLibrary: EffectLibrary, ImageEffectFactory {
    public let directory: URL
    private let catalog: EffectCatalog
    private let snapshotsPerSecond: TimeInterval
    private let timers: RepeatingTimers
    private let onMain: MainHop
    private let makeHost: WebPageHostMaker

    public init(
        directory: URL, snapshotsPerSecond: TimeInterval, timers: RepeatingTimers, listing: DirectoryListing,
        onMain: @escaping MainHop, makeHost: @escaping WebPageHostMaker
    ) {
        self.onMain = onMain
        self.makeHost = makeHost
        self.directory = directory
        self.snapshotsPerSecond = snapshotsPerSecond
        self.timers = timers
        catalog = EffectCatalog(listing: listing, fileExtension: EffectCatalog.webPageExtension)
    }

    public func availableEffects() -> [EffectListing] {
        catalog.effects(in: directory).map { EffectListing(name: $0.name, kind: .overlay) }
    }

    public func parameters(forEffectNamed name: String) -> [EffectParameter] { [] }

    public func makeEffect(named name: String, canvas: CGSize) -> ImageEffect? {
        catalog.effects(in: directory).first { $0.name == name }.map {
            HTMLEffect(
                file: $0.url, canvas: canvas, snapshotsPerSecond: snapshotsPerSecond, timers: timers,
                onMain: onMain, makeHost: makeHost
            )
        }
    }
}

/// Several effect libraries presented as one. The first that knows a name wins.
public final class CombinedEffectLibrary: EffectLibrary, ImageEffectFactory {
    public typealias Member = EffectLibrary & ImageEffectFactory

    private let primary: Member
    private let members: [Member]

    /// - Parameters:
    ///   - primary: the first member, whose folder is the one shown to the user.
    ///   - others: the members after it, in the order they are asked.
    public init(primary: Member, others: [Member]) {
        self.primary = primary
        members = [primary] + others
    }

    public var directory: URL { primary.directory }

    /// Every member's effects in name order. When two members offer the
    /// same name, the earlier member's is the one listed and made.
    public func availableEffects() -> [EffectListing] {
        var seen: Set<String> = []
        return members.flatMap { $0.availableEffects() }
            .filter { seen.insert($0.name).inserted }
            // In the order of the names they are shown under, not their files'.
            .sorted {
                EffectNaming.title(for: $0.name).localizedCaseInsensitiveCompare(EffectNaming.title(for: $1.name))
                    == .orderedAscending
            }
    }

    public func parameters(forEffectNamed name: String) -> [EffectParameter] {
        for member in members {
            let parameters = member.parameters(forEffectNamed: name)
            if !parameters.isEmpty { return parameters }
        }
        return []
    }

    public func makeEffect(named name: String, canvas: CGSize) -> ImageEffect? {
        for member in members {
            if let effect = member.makeEffect(named: name, canvas: canvas) { return effect }
        }
        return nil
    }
}
