import CamTwistCore
import CamTwistRendering
import Foundation

/// Prepares steps before they join the chain.
struct StepBuilder {
    let parameters: EffectParameters

    /// The step for some content. A fresh effect starts with its drop
    /// shadows switched off.
    func item(for content: ChainItem.Content) -> ChainItem {
        guard case .effect(let name, let values) = content, values.isEmpty else {
            return ChainItem(content: content, pictureInPicture: startingPlacement(for: content))
        }
        let starting = EffectStartingValues.values(for: parameters.parameters(forEffectNamed: name))
        return ChainItem(content: .effect(name: name, values: starting))
    }

    /// The scene a fresh start, or a new scene, begins with: the camera
    /// with the most detail, or with no camera the test card the app draws.
    /// A camera starts as it is, with its background left in.
    func startingScene(cameras: [CameraChoice]) -> SceneConfiguration {
        let source = bestCamera(among: cameras) ?? .testCard
        return SceneConfiguration(items: [item(for: .source(source))])
    }

    /// The camera a new camera source starts on: the one with the most detail.
    func bestCamera(among cameras: [CameraChoice]) -> SourceSpec? {
        cameras.max { $0.pixels < $1.pixels }.map { .camera(deviceID: $0.id) }
    }

    /// What a file dropped on the picture becomes: an image, a video, or
    /// nothing when it is neither.
    func content(forFile path: String) -> ChainItem.Content? {
        if MediaFileTypes.isImage(path) {
            return .source(.image(path: path))
        }
        if MediaFileTypes.isMovie(path) {
            return .source(.movie(MovieSettings(files: [path])))
        }
        return nil
    }

    /// Whether a step has settings a reset would put back. Scripts have
    /// nothing but their text, which a reset keeps.
    func canReset(_ content: ChainItem.Content) -> Bool {
        if case .script = content { return false }
        return true
    }

    /// A step with its settings back to how a fresh one starts. What the
    /// step is of stays (its file, its words, its effect), as do the steps
    /// in its branch and whether it is switched on.
    func reset(_ item: ChainItem) -> ChainItem {
        var content = item.content
        switch item.content {
        case .source(let spec): content = .source(spec.withSettingsReset)
        case .effect(let name, _): content = .effect(name: name, values: [:])
        case .script: break
        }
        let fresh = self.item(for: content)
        return ChainItem(
            id: item.id, isEnabled: item.isEnabled, content: fresh.content,
            pictureInPicture: fresh.pictureInPicture, branch: item.branch
        )
    }

    /// Where a new step starts on the picture: a source's kind says, and
    /// anything else fills it.
    private func startingPlacement(for content: ChainItem.Content) -> PictureInPictureSettings? {
        guard case .source(let spec) = content else { return nil }
        return spec.kind.startingPlacement
    }

    /// The source whose branch additions go into, forgotten when that
    /// source is no longer in the scene.
    func branchTarget(_ target: UUID?, in scene: SceneConfiguration) -> UUID? {
        guard let target, scene.item(id: target) != nil else { return nil }
        return target
    }
}
