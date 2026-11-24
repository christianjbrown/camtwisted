import CamTwistControl
import CamTwistCore
import CamTwistRendering
import SwiftUI

/// Reports where each row of the chain sits, so a dragged row knows what
/// it is passing over.
private struct RowFrames: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The chain as a stack of rows that can be dragged into a new order. The
/// dragged row follows the pointer and the others slide aside for it.
struct ChainList: View {
    /// How far the pointer must move before a press on a row becomes a drag.
    private static let dragThreshold: CGFloat = 5
    private static let liftedScale: CGFloat = 1.02
    private static let liftedShadow: CGFloat = 6
    private static let spacePrefix = "chain-"
    private static let mainChainName = "main"

    @Bindable var model: AppModel
    /// The steps this list shows: the main chain, or one source's branch.
    @Binding var items: [ChainItem]
    /// The source whose branch this is, or nil for the main chain.
    let parent: UUID?
    /// That source's name, for saying where a drop will land.
    var parentTitle: String?
    @State private var frames: [UUID: CGRect] = [:]
    @State private var draggedID: UUID?

    /// Each list measures its rows in a space of its own.
    private var coordinateSpace: String { Self.spacePrefix + (parent?.uuidString ?? Self.mainChainName) }
    @State private var pointerY: CGFloat = 0
    /// Where in the row the press landed, so the row does not jump to centre on the pointer.
    @State private var grabOffset: CGFloat = 0
    /// The row a panel from the picker is being dragged over.
    @State private var dropTarget: UUID?
    @State private var isEndTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach($items) { $item in
                let isDragged = draggedID == item.id
                ChainRow(model: model, item: $item, drag: drag(for: item.id))
                    .background(GeometryReader { geometry in
                        Color.clear.preference(
                            key: RowFrames.self,
                            value: [item.id: geometry.frame(in: .named(coordinateSpace))]
                        )
                    })
                    .background(isDragged ? AnyShapeStyle(.background) : AnyShapeStyle(.clear))
                    .scaleEffect(isDragged ? Self.liftedScale : 1)
                    .shadow(radius: isDragged ? Self.liftedShadow : 0)
                    .offset(y: isDragged ? ChainReordering.dragOffset(pointerY: pointerY, grabOffset: grabOffset, rowTop: frames[item.id]?.minY) : 0)
                    .zIndex(isDragged ? 1 : 0)
                    .overlay(alignment: .top) {
                        // A line shows where a panel dragged from the picker will land.
                        if dropTarget == item.id {
                            Rectangle().fill(Color.accentColor).frame(height: Self.insertionLineHeight)
                        }
                    }
                    .dropDestination(for: String.self) { dropped, _ in
                        add(dropped, before: item.id)
                    } isTargeted: { targeted in
                        if targeted {
                            dropTarget = item.id
                        } else if dropTarget == item.id {
                            dropTarget = nil
                        }
                    }
                if item.id != items.last?.id {
                    Divider()
                }
            }
            // Dropping below the last row, or on an empty chain, adds at the
            // end. The box says which chain that is, so a branch's is not
            // mistaken for the scene's.
            Label(endDropText, systemImage: parent == nil ? SymbolName.dropIntoScene : SymbolName.dropIntoBranch)
                .font(.caption)
                .foregroundStyle(isEndTargeted ? Color.accentColor : .secondary)
                .frame(maxWidth: .infinity, minHeight: Self.endDropHeight)
                .background(
                    RoundedRectangle(cornerRadius: Layout.panelCornerRadius)
                        .fill(isEndTargeted ? Color.accentColor.opacity(Self.targetedWash) : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.panelCornerRadius)
                        .strokeBorder(
                            isEndTargeted ? Color.accentColor : Color.secondary.opacity(Self.restingBorder),
                            style: StrokeStyle(lineWidth: Self.dropBorderWidth, dash: Self.dropDash)
                        )
                )
                .padding(.top, Layout.panelHalfSpacing)
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { dropped, _ in
                    add(dropped, before: nil)
                } isTargeted: { isEndTargeted = $0 }
        }
        .coordinateSpace(name: coordinateSpace)
        .onPreferenceChange(RowFrames.self) { frames = $0 }
        // A branch's rows are its own business: the list it sits in must
        // not mistake them for rows of its own.
        .transformPreference(RowFrames.self) { $0 = [:] }
    }

    private var endDropText: String {
        StepRowLogic.endDropText(parentTitle: parentTitle, isEmpty: items.isEmpty)
    }

    private func add(_ dropped: [String], before target: UUID?) -> Bool {
        guard let content = dropped.first.flatMap(StepPayload.content(from:)) else { return false }
        model.steps.add(content, before: target, inBranchOf: parent)
        return true
    }

    private static let insertionLineHeight: CGFloat = 2
    private static let dropBorderWidth: CGFloat = 1
    private static let endDropHeight: CGFloat = 32
    private static let dropDash: [CGFloat] = [4, 3]
    private static let targetedWash = 0.15
    private static let restingBorder = 0.5

    private func drag(for id: UUID) -> some Gesture {
        DragGesture(minimumDistance: Self.dragThreshold, coordinateSpace: .named(coordinateSpace))
            .onChanged { value in
                if draggedID != id {
                    draggedID = id
                    grabOffset = ChainReordering.grabOffset(pressY: value.startLocation.y, rowTop: frames[id]?.minY)
                    model.selectedStepID = id
                }
                pointerY = value.location.y
                // Passing the middle of another row takes its place.
                if let target = ChainReordering.passedRow(dragging: id, frames: frames, pointerY: value.location.y) {
                    withAnimation(.easeInOut(duration: Self.reorderDuration)) {
                        model.editedScene.move(id: id, toPositionOf: target)
                    }
                }
            }
            .onEnded { _ in
                withAnimation(.easeInOut(duration: Self.reorderDuration)) {
                    draggedID = nil
                }
            }
    }

    private static let reorderDuration = 0.18
}
