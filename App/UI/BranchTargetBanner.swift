import CamTwistControl
import CamTwistCore
import CamTwistRendering
import SwiftUI

/// Says which source additions are going to, while it is one source's own
/// steps rather than the scene's.
struct BranchTargetBanner: View {
    @Bindable var model: AppModel

    var body: some View {
        if let target = model.branchTarget.flatMap(model.editedScene.item(id:)) {
            HStack {
                Label("Adding to \(target.title) only", systemImage: SymbolName.dropIntoBranch)
                Spacer()
                Button("Add to the main chain") { model.branchTarget = nil }
            }
        }
    }
}
