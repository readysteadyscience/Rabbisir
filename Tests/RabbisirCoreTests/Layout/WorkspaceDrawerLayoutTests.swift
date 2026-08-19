import CoreGraphics
import Testing

@testable import RabbisirCore

@Suite("Workspace drawer layout")
struct WorkspaceDrawerLayoutTests {
  @Test("The add-only drawer grows only enough for its single action")
  func addOnlyDrawerHasNoWorkspaceListHole() {
    let layout = WorkspaceDrawerLayout.addWorkspaceOnly()

    #expect(layout.listHeight == 0)
    #expect(layout.expansionHeight == 62)
  }

  @Test("The input window grows upward while its bottom and width remain fixed")
  func expansionUsesAFixedBottomAnchor() {
    let base = CGRect(x: 1_574, y: 10, width: 701, height: 129)
    let expanded = WorkspaceDrawerLayout.expandedInputPanelFrame(
      baseFrame: base,
      expansionHeight: 175
    )

    #expect(expanded.minX == base.minX)
    #expect(expanded.minY == base.minY)
    #expect(expanded.width == base.width)
    #expect(expanded.height == 304)
    #expect(expanded.maxY == base.maxY + 175)
  }

  @Test("The expanded shape keeps the composer body at the same bottom-relative position")
  func expandedShapeKeepsComposerAtTheBottom() {
    let collapsed = CGRect(
      x: 0,
      y: 0,
      width: 701,
      height: InputComposerShape.collapsedSurfaceHeight
    )
    let expanded = CGRect(
      x: 0,
      y: 0,
      width: 701,
      height: InputComposerShape.collapsedSurfaceHeight + 175
    )
    let collapsedBodyTop = InputComposerShape.mainTop
    let expandedBodyTop = InputComposerShape.mainTop + 175

    #expect(collapsed.maxY - collapsedBodyTop == expanded.maxY - expandedBodyTop)
    #expect(
      InputComposerShape().path(in: expanded).contains(
        CGPoint(x: InputComposerShape.tabRadius + 1, y: 1)
      )
    )
    #expect(
      InputComposerShape().path(in: expanded).contains(
        CGPoint(x: 400, y: expandedBodyTop + 1)
      )
    )
  }

  @Test("The current container height alone anchors composer and drawer content")
  func currentHeightAnchorsContent() {
    let composerHeight: CGFloat = InputComposerShape.collapsedSurfaceHeight
    let drawerHeight: CGFloat = 175
    let collapsedHeight = composerHeight
    let expandedHeight = composerHeight + drawerHeight

    #expect(
      WorkspaceDrawerLayout.composerOriginY(
        containerHeight: collapsedHeight,
        composerHeight: composerHeight
      ) == 0
    )
    #expect(
      WorkspaceDrawerLayout.composerOriginY(
        containerHeight: expandedHeight,
        composerHeight: composerHeight
      ) == drawerHeight
    )
    #expect(
      WorkspaceDrawerLayout.drawerOriginY(
        containerHeight: collapsedHeight,
        composerHeight: composerHeight,
        drawerHeight: drawerHeight
      ) == -drawerHeight
    )
    #expect(
      WorkspaceDrawerLayout.drawerOriginY(
        containerHeight: expandedHeight,
        composerHeight: composerHeight,
        drawerHeight: drawerHeight
      ) == 0
    )
  }
}
