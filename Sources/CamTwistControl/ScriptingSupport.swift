import CamTwistCore
import CamTwistRendering
import Foundation

/// What scripts need beyond what the window offers: sources found by name
/// and effect controls set from text.
struct ScriptingSupport {
    /// Other names for sources, which some scripts use.
    private static let otherNames = ["movie": "Video", "webcam": "Camera", "desktop": "Screen"]

    let parameters: EffectParameters

    /// The source a script means by a name such as "Webcam" or "Desktop".
    func sourceSpec(
        named given: String, cameras: [CameraChoice], displays: [DisplayChoice]
    ) -> SourceSpec? {
        let name = Self.otherNames[given.lowercased()] ?? given
        let candidates: [SourceSpec?] = [
            cameras.first.map { .camera(deviceID: $0.id) },
            displays.first.map { .display(DisplaySettings(displayID: $0.id)) },
            .movie(MovieSettings()),
            .slideShow(SlideShowSettings()),
            .website(url: ""),
            .stream(StreamSettings()),
            .microphone(deviceID: nil),
            .telestrator(TelestratorSettings()),
            .testCard,
            .image(path: ""),
            .text(TextSettings()),
            .shape(ShapeSettings()),
            .colorBars,
        ]
        return candidates.compactMap { $0 }.first { $0.title.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Sets an effect control from text, as scripts supply it. The control
    /// is found by its key or by the name shown beside it.
    func setEffectProperty(_ property: String, to text: String, ofStep id: UUID, in scene: inout SceneConfiguration) -> Bool {
        guard case .effect(let name, _) = scene.item(id: id)?.content,
              let parameter = parameters.parameters(forEffectNamed: name).first(where: {
                  $0.key.caseInsensitiveCompare(property) == .orderedSame
                      || $0.displayName.caseInsensitiveCompare(property) == .orderedSame
              })
        else { return false }
        let value: EffectValue?
        switch parameter.kind {
        case .number: value = Double(text).map { .number($0) }
        case .boolean: value = .boolean((text as NSString).boolValue)
        case .string: value = .string(text)
        case .color: value = nil
        }
        guard let value else { return false }
        scene.setValue(value, forKey: parameter.key, ofEffect: id)
        return true
    }
}
