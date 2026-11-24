import Foundation

/// One step of the chain: a source that supplies a picture, or an effect
/// that changes the picture so far.
public struct ChainItem: Codable, Equatable, Identifiable, Sendable {
    public enum Content: Codable, Equatable, Sendable {
        case source(SourceSpec)
        case effect(name: String, values: [String: EffectValue])
        /// AppleScript that runs each time the step is switched on.
        case script(source: String)
    }

    public let id: UUID
    public var isEnabled: Bool
    public var content: Content
    /// When set, a source sits over the picture so far instead of
    /// replacing it. Effects ignore it.
    public var pictureInPicture: PictureInPictureSettings?
    /// Steps that apply to this source's own picture only, before it joins
    /// the picture so far: effects on it, and other sources laid over it.
    /// Nil when there are none.
    public var branch: [ChainItem]?
    /// Colour correction for this source alone. Nil leaves it as it is.
    public var adjustments: SourceAdjustments?
    /// Movements of this source's placement over time. Nil when it is still.
    public var animations: [SourceAnimation]?
    /// How loud this source's own sound is in the streams, from 0 to 1,
    /// for a source that has a level of its own to set. Nil is full volume.
    public var volume: Double?
    /// What is cut out of this source's own picture. Nil cuts nothing.
    public var cutout: SourceCutout?
    /// How a source that covers the picture copes with being another
    /// shape. Nil fills the picture and crops what overflows.
    public var fit: SourceFit?

    public init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        content: Content,
        pictureInPicture: PictureInPictureSettings? = nil,
        branch: [ChainItem]? = nil,
        adjustments: SourceAdjustments? = nil,
        animations: [SourceAnimation]? = nil,
        volume: Double? = nil,
        cutout: SourceCutout? = nil,
        fit: SourceFit? = nil
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.content = content
        self.pictureInPicture = pictureInPicture
        self.branch = branch
        self.adjustments = adjustments
        self.animations = animations
        self.volume = volume
        self.cutout = cutout
        self.fit = fit
    }

    public var source: SourceSpec? {
        if case .source(let spec) = content { return spec }
        return nil
    }

    public var isSource: Bool { source != nil }

    /// The same step, and its whole branch, under fresh identities, for
    /// copies and merges.
    public func duplicated() -> ChainItem {
        ChainItem(
            isEnabled: isEnabled, content: content, pictureInPicture: pictureInPicture,
            branch: branch?.map { $0.duplicated() },
            adjustments: adjustments,
            animations: animations?.map {
                SourceAnimation(
                    property: $0.property, from: $0.from, to: $0.to, duration: $0.duration, mode: $0.mode
                )
            },
            volume: volume,
            cutout: cutout,
            fit: fit
        )
    }
}

/// Everything that decides what a picture shows: the chain, top to bottom,
/// with any branches hanging off its sources.
public struct SceneConfiguration: Codable, Equatable, Sendable {
    public var items: [ChainItem]

    public init(items: [ChainItem] = []) {
        self.items = items
    }

    /// The scene a first launch starts with.
    public static let initial = SceneConfiguration(items: [ChainItem(content: .source(.colorBars))])

    // MARK: Finding steps

    /// Every step, branches included, each parent before its branch.
    public var allItems: [ChainItem] {
        Self.flattened(items, enabledOnly: false)
    }

    /// The step with an identity, wherever in the chain or a branch it is.
    public func item(id: UUID) -> ChainItem? {
        allItems.first { $0.id == id }
    }

    private static func flattened(_ items: [ChainItem], enabledOnly: Bool) -> [ChainItem] {
        items.flatMap { item -> [ChainItem] in
            if enabledOnly, !item.isEnabled { return [] }
            return [item] + flattened(item.branch ?? [], enabledOnly: enabledOnly)
        }
    }

    // MARK: Changing steps

    public mutating func add(_ content: ChainItem.Content) {
        items.append(ChainItem(content: content))
    }

    /// Puts a new step in just before another, or at the end when no other
    /// is given or it is not there. With a parent, the step goes into that
    /// source's branch instead of the main chain.
    public mutating func insert(_ item: ChainItem, before target: UUID? = nil, inBranchOf parent: UUID? = nil) {
        guard let parent else {
            Self.insert(item, before: target, into: &items)
            return
        }
        update(id: parent) { owner in
            var branch = owner.branch ?? []
            Self.insert(item, before: target, into: &branch)
            owner.branch = branch
        }
    }

    private static func insert(_ item: ChainItem, before target: UUID?, into list: inout [ChainItem]) {
        list.insert(item, at: list.firstIndex { $0.id == target } ?? list.endIndex)
    }

    /// Swaps the first source for another, or adds one when there is none.
    public mutating func setMainSource(_ spec: SourceSpec) {
        if let index = items.firstIndex(where: \.isSource) {
            items[index].content = .source(spec)
        } else {
            items.insert(ChainItem(content: .source(spec)), at: 0)
        }
    }

    /// Removes a step, with its branch, from wherever it is.
    public mutating func remove(id: UUID) {
        Self.remove(id: id, from: &items)
    }

    private static func remove(id: UUID, from list: inout [ChainItem]) {
        list.removeAll { $0.id == id }
        for index in list.indices {
            guard var branch = list[index].branch else { continue }
            remove(id: id, from: &branch)
            list[index].branch = branch.isEmpty ? nil : branch
        }
    }

    /// Moves a step into the place another holds, as dragging it over that
    /// one does: dragged down it lands after the other, dragged up before
    /// it. Both must be in the same list: the main chain, or one branch.
    public mutating func move(id: UUID, toPositionOf target: UUID) {
        guard id != target else { return }
        Self.move(id: id, toPositionOf: target, in: &items)
    }

    private static func move(id: UUID, toPositionOf target: UUID, in list: inout [ChainItem]) {
        if let from = list.firstIndex(where: { $0.id == id }), let to = list.firstIndex(where: { $0.id == target }) {
            list.insert(list.remove(at: from), at: to)
            return
        }
        for index in list.indices {
            guard var branch = list[index].branch else { continue }
            move(id: id, toPositionOf: target, in: &branch)
            list[index].branch = branch
        }
    }

    /// Changes a step in place, wherever it is.
    public mutating func update(id: UUID, _ change: (inout ChainItem) -> Void) {
        Self.update(id: id, in: &items, change)
    }

    private static func update(id: UUID, in list: inout [ChainItem], _ change: (inout ChainItem) -> Void) {
        for index in list.indices {
            if list[index].id == id {
                change(&list[index])
                return
            }
            guard var branch = list[index].branch else { continue }
            update(id: id, in: &branch, change)
            list[index].branch = branch
        }
    }

    public mutating func setValue(_ value: EffectValue, forKey key: String, ofEffect id: UUID) {
        update(id: id) { item in
            guard case .effect(let name, var values) = item.content else { return }
            values[key] = value
            item.content = .effect(name: name, values: values)
        }
    }

    // MARK: What the scene needs

    /// The sources that have to be running, by the step that uses them.
    /// A step that is off takes its whole branch with it.
    public var sourcesInUse: [UUID: SourceSpec] {
        var sources: [UUID: SourceSpec] = [:]
        for item in Self.flattened(items, enabledOnly: true) {
            if let spec = item.source {
                sources[item.id] = spec
            }
        }
        return sources
    }

    /// The scripts of steps that are on in this scene and were not on, or
    /// not there, in the scene before it.
    public func scriptsToRun(after previous: SceneConfiguration) -> [String] {
        let wasOn = Set(Self.flattened(previous.items, enabledOnly: true).map(\.id))
        return Self.flattened(items, enabledOnly: true).compactMap { item in
            guard !wasOn.contains(item.id), case .script(let source) = item.content else { return nil }
            return source
        }
    }

}

/// Keeps values by key. `UserDefaults` in the app, a dictionary in tests.
public protocol KeyValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}
