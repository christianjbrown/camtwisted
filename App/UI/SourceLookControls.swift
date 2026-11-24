import CamTwistControl
import CamTwistCore
import SwiftUI

/// Colour, zoom and flip for one source. Every source has the same set.
struct SourceLookControls: View {
    @Binding var adjustments: SourceAdjustments?
    @State private var isExpanded = false

    /// The adjustments being shown: the source's own, or untouched ones.
    private var current: SourceAdjustments { adjustments ?? SourceAdjustments() }

    var body: some View {
        DisclosureGroup("Colour, zoom, flip and noise", isExpanded: $isExpanded) {
            slider("Brightness", \.brightness, SourceAdjustments.brightnessRange)
            slider("Contrast", \.contrast, SourceAdjustments.contrastRange)
            slider("Saturation", \.saturation, SourceAdjustments.saturationRange)
            slider("Gamma", \.gamma, SourceAdjustments.gammaRange)
            slider("Red", \.red, SourceAdjustments.gainRange)
            slider("Green", \.green, SourceAdjustments.gainRange)
            slider("Blue", \.blue, SourceAdjustments.gainRange)
            slider("Zoom", \.zoom, SourceAdjustments.zoomRange)
            Toggle("Flip left to right", isOn: binding(\.flipsHorizontally))
            Toggle("Flip upside down", isOn: binding(\.flipsVertically))
            slider("Noise reduction", \.noiseReduction, SourceAdjustments.noiseReductionRange)
            if current.reducesNoise {
                slider("Sharpness", \.sharpness, SourceAdjustments.sharpnessRange)
            }
            Button("Reset") { adjustments = nil }
                .disabled(current.isNeutral)
        }
    }

    private func slider(
        _ title: String,
        _ keyPath: WritableKeyPath<SourceAdjustments, Double>,
        _ range: ClosedRange<Double>
    ) -> some View {
        NumberSlider(title: title, value: binding(keyPath), range: range)
    }

    /// A binding to one control. Untouched adjustments are stored as none
    /// at all, so a source nobody has adjusted costs nothing to draw.
    private func binding<Value>(_ keyPath: WritableKeyPath<SourceAdjustments, Value>) -> Binding<Value> {
        Binding(
            get: { current[keyPath: keyPath] },
            set: { newValue in
                adjustments = SourceAdjustments.stored(afterEditing: adjustments) { $0[keyPath: keyPath] = newValue }
            }
        )
    }
}

/// The movements of one source's placement over time.
struct AnimationControls: View {
    @Binding var animations: [SourceAnimation]?
    let placement: PictureInPictureSettings

    var body: some View {
        ForEach(animations ?? []) { animation in
            AnimationRow(animation: binding(for: animation)) {
                animations = AnimationList.removing(animation.id, from: animations)
            }
        }
        Menu("Add animation") {
            ForEach(AnimatedProperty.allCases, id: \.self) { property in
                Button(property.label) {
                    animations = AnimationList.adding(property, around: placement.value(of: property), to: animations)
                }
            }
        }
        .fixedSize()
        .help("Move, resize or turn this source over time, once or on a loop")
    }

    private func binding(for animation: SourceAnimation) -> Binding<SourceAnimation> {
        Binding(
            get: { AnimationList.current(animation, in: animations) },
            set: { animations = AnimationList.replacing($0, in: animations) }
        )
    }
}

private struct AnimationRow: View {
    @Binding var animation: SourceAnimation
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.panelHalfSpacing) {
            HStack {
                Picker("Animate", selection: $animation.property) {
                    ForEach(AnimatedProperty.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Button(action: remove) { Image(systemName: SymbolName.remove) }
                    .buttonStyle(.borderless)
                    .help("Remove this animation")
            }
            HStack {
                Text("From")
                numberField($animation.from)
                Text("to")
                numberField($animation.to)
            }
            NumberSlider(title: "Seconds", value: $animation.duration, range: SourceAnimation.durationRange)
            Picker("Then", selection: $animation.mode) {
                ForEach(AnimationMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
        }
    }

    private func numberField(_ value: Binding<Double>) -> some View {
        TextField("", value: value, format: .number.precision(.fractionLength(Self.fractionDigits)))
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: Layout.numberFieldWidth)
    }

    private static let fractionDigits = 0...3
}
