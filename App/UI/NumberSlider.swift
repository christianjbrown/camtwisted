import CamTwistControl
import SwiftUI

/// A slider with the number beside it. The number follows the slider, and
/// typing a number moves the slider; anything typed outside the range is
/// pulled back to the nearest end.
struct NumberSlider: View {
    private static let fieldWidth: CGFloat = 64
    private static let fractionDigits = 0...3

    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack {
            Slider(value: $value, in: range) { Text(title) }
            TextField(
                title,
                value: Binding(
                    get: { value },
                    set: { value = clamped($0, to: range) }
                ),
                format: .number.precision(.fractionLength(Self.fractionDigits))
            )
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: Self.fieldWidth)
        }
    }
}

/// A slider for a share of something, shown and typed as a percentage
/// from 0 to 100 and kept as a fraction from 0 to 1.
struct PercentSlider: View {
    let title: String
    @Binding var fraction: Double

    var body: some View {
        NumberSlider(
            title: title + " (%)",
            value: Binding(
                get: { Percent.shown(fraction) },
                set: { fraction = Percent.fraction($0) }
            ),
            range: Percent.range
        )
    }
}
