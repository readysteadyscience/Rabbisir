import SwiftUI

struct WorkspaceDrawerView: View {
  @Environment(\.rabbisirCopy) private var copy
  @ObservedObject var model: WorkspaceDrawerModel

  var body: some View {
    let layout = WorkspaceDrawerLayout.addWorkspaceOnly()
    WorkspaceDrawerActionButtonView(
      title: model.failureMessage ?? "\(copy[.newWorkspace])…",
      accessibilityLabel: copy[.newWorkspace],
      enabled: !model.isPerformingInternalOperation,
      action: model.createWorkspace
    )
    .padding(.horizontal, 8)
    .frame(height: WorkspaceDrawerLayout.addWorkspaceActionHeight)
    .padding(.vertical, WorkspaceDrawerLayout.verticalPadding)
    .padding(.horizontal, 12)
    .frame(
      width: InputComposerShape.tabRight,
      height: layout.expansionHeight,
      alignment: .topLeading
    )
    .background(Color.clear)
  }
}
