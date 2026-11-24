import CamTwistControl
import CamTwistCore
import CamTwistRendering
import SwiftUI

struct ParameterControl: View {
    @Environment(\.fileChooser) private var fileChooser
    let parameter: EffectParameter
    let value: EffectValue
    let set: (EffectValue) -> Void

    var body: some View {
        switch (ParameterControlKind(parameter: parameter, value: value), value) {
        case (.number(let range), .number(let number)):
            NumberSlider(
                title: parameter.displayName,
                value: Binding(get: { number }, set: { set(.number($0)) }),
                range: range
            )
        case (.toggle, .boolean(let flag)):
            Toggle(parameter.displayName, isOn: Binding(get: { flag }, set: { set(.boolean($0)) }))
        case (.file(let types), .string(let path)):
            LabeledContent(parameter.displayName) {
                Text(FileSettingText.shown(path: path))
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Button(FileSettingText.chooseTitle(path: path)) {
                if let chosen = fileChooser.chooseFiles(
                    allowedExtensions: Set(types), allowsFolders: false, allowsMany: false
                ).first {
                    set(.string(chosen))
                }
            }
        case (.font, .string(let string)):
            FontPicker(fontName: Binding(get: { string }, set: { set(.string($0)) }))
        case (.choices(let choices), .string(let string)):
            Picker(parameter.displayName, selection: Binding(get: { string }, set: { set(.string($0)) })) {
                ForEach(choices, id: \.self) { Text($0).tag($0) }
            }
        case (_, .string(let string)):
            // Several lines are allowed: some effects show one line at a time.
            TextField(
                parameter.displayName,
                text: Binding(get: { string }, set: { set(.string($0)) }),
                axis: .vertical
            )
            .help("Press Option and Return for a new line")
        case (_, .color(let red, let green, let blue, let alpha)):
            ColorRow(
                title: parameter.displayName,
                color: NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
            ) { picked in
                set(EffectValue(picked: picked))
            }
        default:
            EmptyView()
        }
    }
}
