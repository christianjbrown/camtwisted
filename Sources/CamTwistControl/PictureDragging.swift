import CamTwistCore
import CamTwistRendering
import CoreGraphics
import Foundation

/// What a drag on the picture does right now.
public enum DragTarget: Equatable {
    case picture(UUID)
    case overlay(UUID, xKey: String, yKey: String)
    case telestrator(UUID)
}

/// What a drag on the picture does to the thing it has hold of.
public enum DragMode: Equatable {
    case move
    case resize
    case turn
}

/// Where the thing a drag has hold of sits on the picture, for drawing a
/// box round it: in fractions of the picture with up as positive.
public struct SelectionOutline: Equatable {
    public let center: CGPoint
    /// Width as a fraction of the picture's width, height of its height.
    public let size: CGSize
    /// Degrees clockwise.
    public let rotation: Double
    public let canTurn: Bool
    public let canResize: Bool
}

/// Works out what a drag on the picture moves, moves it, and draws strokes
/// on telestrator steps.
struct PictureDragging {
    private static let xPositionName = "X Position"
    private static let yPositionName = "Y Position"
    private static let sizeName = "Size"
    private static let rotationName = "Rotation"
    /// A solid's two angles, which a turning drag changes together.
    private static let turnName = "Turn"
    private static let tiltName = "Tilt"
    /// A drag right across the picture turns a solid this many degrees.
    private static let orbitDegreesAcross = 180.0
    private static let halfTurn = 180.0
    private static let fullTurn = 360.0

    /// An angle brought back between a half turn either way.
    private static func wrapped(_ degrees: Double) -> Double {
        let turned = degrees.truncatingRemainder(dividingBy: fullTurn)
        if turned > halfTurn { return turned - fullTurn }
        if turned < -halfTurn { return turned + fullTurn }
        return turned
    }

    /// A point, in fractions of the picture with up as positive, carried
    /// clockwise round another as the picture shows it.
    private static func turned(_ point: CGPoint, about centre: CGPoint, by degrees: Double, canvas: CGSize) -> CGPoint {
        let radians = degrees * .pi / halfTurn
        let across = (point.x - centre.x) * canvas.width
        let up = (point.y - centre.y) * canvas.height
        return CGPoint(
            x: centre.x + (across * cos(radians) + up * sin(radians)) / canvas.width,
            y: centre.y + (up * cos(radians) - across * sin(radians)) / canvas.height
        )
    }

    /// An effect drawn over the picture, with the controls a drag changes.
    private struct Overlay {
        let id: UUID
        let name: String
        let title: String
        let controls: [EffectParameter]
        let values: [String: EffectValue]
        let xKey: String
        let yKey: String
        let sizeKey: String?
        let rotationKey: String?
        /// The turn and tilt of a solid, when it has both.
        let orbitKeys: (turn: String, tilt: String)?

        var canTurn: Bool { rotationKey != nil || orbitKeys != nil }

        func number(_ key: String) -> Double {
            let fallback = controls.first { $0.key == key }?.defaultValue
            if case .number(let value)? = values[key] ?? fallback { return value }
            return 0
        }

        /// A number held within its control's range, when it has one.
        func held(_ value: Double, for key: String) -> Double {
            guard let range = controls.first(where: { $0.key == key })?.range else { return value }
            return min(max(value, range.lowerBound), range.upperBound)
        }
    }

    /// A target with what moving it needs to know.
    private enum Resolved {
        case picture(id: UUID, title: String, settings: PictureInPictureSettings)
        case overlay(Overlay)
        case telestrator(UUID)
    }

    let parameters: EffectParameters

    func target(in scene: SceneConfiguration, selected: UUID?) -> DragTarget? {
        switch resolve(in: scene, selected: selected) {
        case .picture(let id, _, _): return .picture(id)
        case .overlay(let overlay): return .overlay(overlay.id, xKey: overlay.xKey, yKey: overlay.yKey)
        case .telestrator(let id): return .telestrator(id)
        case nil: return nil
        }
    }

    /// A line telling the user what dragging on the picture will do.
    func hint(in scene: SceneConfiguration, selected: UUID?) -> String? {
        switch resolve(in: scene, selected: selected) {
        case .telestrator: return "Drag on the picture to draw"
        case .picture(_, let title, _):
            return Self.hint(title: title, canResize: true, canTurn: true)
        case .overlay(let overlay):
            return Self.hint(title: overlay.title, canResize: overlay.sizeKey != nil, canTurn: overlay.canTurn)
        case nil: return nil
        }
    }

    private static let resizeHint = "a corner to resize it"
    private static let turnHint = "the knob to turn it"
    private static let hintSeparator = ", "

    private static func hint(title: String, canResize: Bool, canTurn: Bool) -> String {
        let extras = [canResize ? resizeHint : nil, canTurn ? turnHint : nil].compactMap { $0 }
        if extras.isEmpty { return "Drag on the picture to move \(title)" }
        return (["Drag \(title) to move it"] + extras).joined(separator: hintSeparator)
    }

    /// The box round the selected step. A source's box is its picture's. An
    /// overlay's is round what it draws; one that cannot be measured gets a
    /// square as wide as its size when it resizes or turns, and none
    /// otherwise. `pictureSize` is the size of a source's own picture, and
    /// `overlayBounds` where an effect with given control values draws.
    func outline(
        in scene: SceneConfiguration, selected: UUID?, pictureSize: (UUID) -> CGSize?,
        overlayBounds: (String, [String: EffectValue]) -> CGRect?
    ) -> SelectionOutline? {
        let canvas = CameraContract.size
        switch resolve(in: scene, selected: selected) {
        case .picture(let id, _, let settings):
            // With a branch, the source is drawn on a canvas of its own first.
            let hasBranch = scene.item(id: id)?.branch?.isEmpty == false
            guard let content = hasBranch ? canvas : pictureSize(id) else { return nil }
            let frame = PictureInPictureLayout.frame(for: content, in: canvas, settings: settings)
            return SelectionOutline(
                center: settings.center,
                size: CGSize(width: frame.width / canvas.width, height: frame.height / canvas.height),
                rotation: settings.rotation, canTurn: true, canResize: true
            )
        case .overlay(let overlay):
            let position = OverlayPosition.unitPoint(
                x: overlay.number(overlay.xKey), y: overlay.number(overlay.yKey), canvas: canvas
            )
            let rotation = overlay.rotationKey.map(overlay.number) ?? 0
            // Measured standing upright, so the box can be turned with it.
            var upright = overlay.values
            if let key = overlay.rotationKey { upright[key] = .number(0) }
            if let drawn = overlayBounds(overlay.name, upright) {
                return SelectionOutline(
                    center: Self.turned(CGPoint(x: drawn.midX, y: drawn.midY), about: position, by: rotation, canvas: canvas),
                    size: drawn.size, rotation: rotation, canTurn: overlay.canTurn, canResize: overlay.sizeKey != nil
                )
            }
            guard overlay.sizeKey != nil || overlay.canTurn else { return nil }
            let width = overlay.sizeKey.map(overlay.number) ?? PictureInPictureSettings.defaultScale
            return SelectionOutline(
                center: position, size: CGSize(width: width, height: width * canvas.width / canvas.height),
                rotation: rotation, canTurn: overlay.canTurn, canResize: overlay.sizeKey != nil
            )
        case .telestrator, nil:
            return nil
        }
    }

    /// Carries out a drag between two points, in fractions of the picture
    /// with up as positive. What cannot be resized or turned is moved.
    func drag(
        from start: CGPoint, to end: CGPoint, mode: DragMode, in scene: inout SceneConfiguration, selected: UUID?
    ) {
        func reshaped(_ settings: PictureInPictureSettings) -> PictureInPictureSettings {
            var settings = settings
            if mode == .resize {
                settings.resize(draggingFrom: start, to: end)
            } else {
                settings.turn(draggingFrom: start, to: end)
            }
            return settings
        }
        let resolved = resolve(in: scene, selected: selected)
        if mode == .turn, case .overlay(let overlay)? = resolved, let keys = overlay.orbitKeys {
            // A solid turns with the drag across and tilts with the drag up,
            // like rolling a ball under the pointer.
            let turn = overlay.number(keys.turn) + (end.x - start.x) * Self.orbitDegreesAcross
            let tilt = overlay.number(keys.tilt) - (end.y - start.y) * Self.orbitDegreesAcross
            scene.setValue(.number(Self.wrapped(turn)), forKey: keys.turn, ofEffect: overlay.id)
            scene.setValue(.number(Self.wrapped(tilt)), forKey: keys.tilt, ofEffect: overlay.id)
            return
        }
        switch (mode, resolved) {
        case (.resize, .picture(let id, _, let settings)), (.turn, .picture(let id, _, let settings)):
            scene.update(id: id) { $0.pictureInPicture = reshaped(settings) }
        case (.resize, .overlay(let overlay)) where overlay.sizeKey != nil,
             (.turn, .overlay(let overlay)) where overlay.rotationKey != nil:
            // The same sums as a placed source, on the overlay's own controls.
            let centre = OverlayPosition.unitPoint(
                x: overlay.number(overlay.xKey), y: overlay.number(overlay.yKey), canvas: CameraContract.size
            )
            let size = overlay.sizeKey.map(overlay.number) ?? PictureInPictureSettings.defaultScale
            let rotation = overlay.rotationKey.map(overlay.number) ?? 0
            let changed = reshaped(PictureInPictureSettings(center: centre, scale: size, rotation: rotation))
            if mode == .resize, let key = overlay.sizeKey {
                scene.setValue(.number(overlay.held(changed.scale, for: key)), forKey: key, ofEffect: overlay.id)
            }
            if mode == .turn, let key = overlay.rotationKey {
                scene.setValue(.number(overlay.held(changed.rotation, for: key)), forKey: key, ofEffect: overlay.id)
            }
        default:
            drag(by: CGPoint(x: end.x - start.x, y: end.y - start.y), in: &scene, selected: selected)
        }
    }

    /// Moves the selected step by a drag, given in fractions of the picture
    /// with up as positive.
    func drag(by delta: CGPoint, in scene: inout SceneConfiguration, selected: UUID?) {
        switch resolve(in: scene, selected: selected) {
        case .picture(let id, _, var settings):
            settings.center = OverlayPosition.moved(center: settings.center, by: delta)
            scene.update(id: id) { $0.pictureInPicture = settings }
        case .overlay(let overlay):
            let moved = OverlayPosition.moved(
                x: overlay.number(overlay.xKey), y: overlay.number(overlay.yKey), by: delta, canvas: CameraContract.size
            )
            scene.setValue(.number(moved.x), forKey: overlay.xKey, ofEffect: overlay.id)
            scene.setValue(.number(moved.y), forKey: overlay.yKey, ofEffect: overlay.id)
        case .telestrator, nil:
            break
        }
    }

    /// Adds a stroke to a telestrator step, in unit coordinates.
    func addStroke(_ points: [CGPoint], to id: UUID, in scene: inout SceneConfiguration) {
        scene.update(id: id) { item in
            guard case .source(.telestrator(var settings)) = item.content else { return }
            settings.strokes.append(
                DrawingStroke(points: points, color: settings.penColor, width: settings.penWidth)
            )
            item.content = .source(.telestrator(settings))
        }
    }

    /// The telestrator step that drawing on the picture goes to.
    func activeTelestrator(in scene: SceneConfiguration) -> UUID? {
        scene.allItems.last { item in
            if case .source(.telestrator) = item.content { return item.isEnabled }
            return false
        }?.id
    }

    private func resolve(in scene: SceneConfiguration, selected: UUID?) -> Resolved? {
        guard let item = selected.flatMap(scene.item(id:)), item.isEnabled else {
            return activeTelestrator(in: scene).map { .telestrator($0) }
        }
        switch item.content {
        case .source(.telestrator):
            return .telestrator(item.id)
        case .source:
            guard let settings = item.pictureInPicture else { return nil }
            return .picture(id: item.id, title: item.title, settings: settings)
        case .effect(let name, let values):
            let controls = parameters.parameters(forEffectNamed: name)
            guard let x = controls.first(where: { $0.displayName == Self.xPositionName && $0.kind == .number }),
                  let y = controls.first(where: { $0.displayName == Self.yPositionName && $0.kind == .number })
            else { return nil }
            func numberKey(named wanted: String) -> String? {
                controls.first { $0.displayName == wanted && $0.kind == .number }?.key
            }
            return .overlay(Overlay(
                id: item.id, name: name, title: item.title, controls: controls, values: values, xKey: x.key, yKey: y.key,
                sizeKey: numberKey(named: Self.sizeName), rotationKey: numberKey(named: Self.rotationName),
                orbitKeys: numberKey(named: Self.turnName).flatMap { turn in
                    numberKey(named: Self.tiltName).map { (turn, $0) }
                }
            ))
        case .script:
            return nil
        }
    }
}
