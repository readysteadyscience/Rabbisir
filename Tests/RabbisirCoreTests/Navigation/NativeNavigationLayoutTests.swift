import CoreGraphics
import Testing

@testable import RabbisirCore

@Suite("Native navigation layout")
struct NativeNavigationLayoutTests {
  @Test("Four project actions share one deterministic material surface width")
  func hoverActionSurfaceWidth() {
    #expect(
      NativeNavigationLayout.hoverActionSurfaceWidth
        == CGFloat(NativeNavigationLayout.hoverActionCount)
        * NativeNavigationLayout.hoverActionDiameter
        + CGFloat(NativeNavigationLayout.hoverActionCount - 1)
        * NativeNavigationLayout.hoverActionSpacing
    )
  }
  @Test("Cold launch leaves every project collapsed")
  func coldLaunchCollapsesProjects() {
    #expect(NativeNavigationLayout.initialExpandedProjectIDs.isEmpty)
  }

  @Test("Project spacing is halved without changing row height")
  func compactProjectSpacing() {
    #expect(NativeNavigationLayout.projectSpacing == 4)
    #expect(NativeNavigationLayout.projectRowHeight == 34)

    let projects = [
      RuntimeNavigationProject(id: "one", title: "One", sessions: []),
      RuntimeNavigationProject(id: "two", title: "Two", sessions: []),
    ]
    #expect(
      NativeNavigationLayout.contentHeight(projects: projects, expandedProjectIDs: [])
        == 2 * NativeNavigationLayout.projectRowHeight
        + NativeNavigationLayout.projectSpacing
    )
  }

  @Test("Hover controls fit entirely outside the navigation row")
  func hoverControlsFitReservedWidth() {
    #expect(NativeNavigationLayout.hoverActionCount == 4)
    #expect(
      NativeNavigationLayout.trailingInteractionReserve
        >= NativeNavigationLayout.requiredTrailingInteractionWidth
    )
  }

  @Test("Short trees occupy the centered safe region")
  func centeredSafeRegion() {
    #expect(
      NativeNavigationLayout.safeVerticalInset
        == NativeNavigationLayout.overflowControlOuterInset
        + NativeNavigationLayout.overflowControlDiameter
        + NativeNavigationLayout.projectRowHeight
    )
    #expect(NativeNavigationLayout.scrollViewportHeight(totalViewportHeight: 800) == 660)
    #expect(NativeNavigationLayout.minimumContentHeight(viewportHeight: 660) == 660)
  }

  @Test("Scroll hit region follows navigation width and includes every row gap")
  func scrollInteractionRegion() {
    let viewport = CGSize(width: 388, height: 800)
    let bounds = NativeNavigationLayout.scrollInteractionBounds(
      viewportSize: viewport,
      navigationWidth: 264
    )

    #expect(bounds.minX == 0)
    #expect(bounds.maxX == 264)
    #expect(bounds.minY == NativeNavigationLayout.safeVerticalInset)
    #expect(bounds.maxY == viewport.height - NativeNavigationLayout.safeVerticalInset)
    #expect(bounds.contains(CGPoint(x: 120, y: 401)))
    #expect(!bounds.contains(CGPoint(x: 300, y: 401)))
    #expect(!bounds.contains(CGPoint(x: 120, y: 20)))
  }

  @Test("Overflow controls appear only toward hidden project content")
  func overflowControlVisibility() {
    let viewportHeight: CGFloat = 800
    let top = NativeNavigationLayout.safeVerticalInset
    let bottom = viewportHeight - NativeNavigationLayout.safeVerticalInset

    #expect(
      NativeNavigationLayout.overflowVisibility(
        contentBounds: CGRect(x: 0, y: top, width: 264, height: 900),
        viewportHeight: viewportHeight
      ) == NativeNavigationOverflowVisibility(hasHiddenAbove: false, hasHiddenBelow: true)
    )
    #expect(
      NativeNavigationLayout.overflowVisibility(
        contentBounds: CGRect(x: 0, y: -120, width: 264, height: 1_100),
        viewportHeight: viewportHeight
      ) == NativeNavigationOverflowVisibility(hasHiddenAbove: true, hasHiddenBelow: true)
    )
    #expect(
      NativeNavigationLayout.overflowVisibility(
        contentBounds: CGRect(x: 0, y: bottom - 900, width: 264, height: 900),
        viewportHeight: viewportHeight
      ) == NativeNavigationOverflowVisibility(hasHiddenAbove: true, hasHiddenBelow: false)
    )
  }

  @Test("Overflow arrows occupy the added navigation-row boundary bands")
  func overflowControlPlacement() {
    let viewportHeight: CGFloat = 800
    let expectedInset =
      NativeNavigationLayout.overflowControlOuterInset
      + NativeNavigationLayout.overflowControlDiameter / 2

    #expect(
      NativeNavigationLayout.overflowControlCenterY(edge: .top, viewportHeight: viewportHeight)
        == expectedInset
    )
    #expect(
      NativeNavigationLayout.overflowControlCenterY(edge: .bottom, viewportHeight: viewportHeight)
        == viewportHeight - expectedInset
    )
    let topArrowInnerEdge =
      NativeNavigationLayout.overflowControlCenterY(edge: .top, viewportHeight: viewportHeight)
      + NativeNavigationLayout.overflowControlDiameter / 2
    let bottomArrowInnerEdge =
      NativeNavigationLayout.overflowControlCenterY(edge: .bottom, viewportHeight: viewportHeight)
      - NativeNavigationLayout.overflowControlDiameter / 2
    let topArrowOuterEdge =
      NativeNavigationLayout.overflowControlCenterY(edge: .top, viewportHeight: viewportHeight)
      - NativeNavigationLayout.overflowControlDiameter / 2
    let bottomArrowOuterEdge =
      NativeNavigationLayout.overflowControlCenterY(edge: .bottom, viewportHeight: viewportHeight)
      + NativeNavigationLayout.overflowControlDiameter / 2
    #expect(topArrowOuterEdge == NativeNavigationLayout.overflowControlOuterInset)
    #expect(
      viewportHeight - bottomArrowOuterEdge
        == NativeNavigationLayout.overflowControlOuterInset
    )
    #expect(
      NativeNavigationLayout.safeVerticalInset - topArrowInnerEdge
        == NativeNavigationLayout.projectRowHeight
    )
    #expect(
      bottomArrowInnerEdge - (viewportHeight - NativeNavigationLayout.safeVerticalInset)
        == NativeNavigationLayout.projectRowHeight
    )
  }

  @Test("Children always add height below their parent")
  func downwardExpansion() {
    let project = RuntimeNavigationProject(
      id: "workspace",
      title: "Project",
      sessions: [session("one"), session("two")]
    )
    let collapsed = NativeNavigationLayout.contentHeight(
      projects: [project],
      expandedProjectIDs: []
    )
    let expanded = NativeNavigationLayout.contentHeight(
      projects: [project],
      expandedProjectIDs: [project.id]
    )

    #expect(collapsed == NativeNavigationLayout.projectRowHeight)
    #expect(expanded > collapsed)
    #expect(
      expanded - collapsed
        == 2 * (NativeNavigationLayout.sessionRowHeight + NativeNavigationLayout.childSpacing)
    )
  }

  @Test("Child reveal keeps the parent edge while its height opens")
  func parentAnchoredReveal() {
    let sessionCount = 4
    let expandedHeight = NativeNavigationLayout.childSectionHeight(
      sessionCount: sessionCount
    )

    #expect(
      NativeNavigationLayout.visibleChildSectionHeight(
        sessionCount: sessionCount,
        isExpanded: false
      ) == 0
    )
    #expect(
      NativeNavigationLayout.visibleChildSectionHeight(
        sessionCount: sessionCount,
        isExpanded: true
      ) == expandedHeight
    )
    #expect(
      expandedHeight
        == CGFloat(sessionCount) * NativeNavigationLayout.sessionRowHeight
        + CGFloat(sessionCount) * NativeNavigationLayout.childSpacing
    )
  }

  @Test("Overflow requests a bottom reveal instead of reversing child order")
  func overflowReveal() {
    let project = RuntimeNavigationProject(
      id: "workspace",
      title: "Project",
      sessions: (0..<20).map { session("session-\($0)") }
    )
    #expect(
      NativeNavigationLayout.expansionNeedsBottomReveal(
        projects: [project],
        expandedProjectIDs: [project.id],
        viewportHeight: 420
      )
    )
    #expect(
      !NativeNavigationLayout.expansionNeedsBottomReveal(
        projects: [project],
        expandedProjectIDs: [],
        viewportHeight: 420
      )
    )
  }

  private func session(_ id: String) -> RuntimeNavigationSession {
    RuntimeNavigationSession(id: id, title: id, isSelected: false, updatedAt: 0)
  }
}
