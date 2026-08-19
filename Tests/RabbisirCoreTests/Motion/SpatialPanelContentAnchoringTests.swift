import AppKit
import SwiftUI
import Testing

@testable import RabbisirCore

@Suite("Spatial panel content anchoring")
struct SpatialPanelContentAnchoringTests {
  @Test("A resizing panel redraws while keeping its hosted content bottom anchored")
  @MainActor
  func resizingKeepsHostedContentBottomAnchored() {
    let container = SpatialPanelContentContainer(rootView: AnyView(Color.clear))
    container.frame = CGRect(x: 0, y: 0, width: 700, height: 129)
    container.layoutSubtreeIfNeeded()

    #expect(container.layerContentsRedrawPolicy == .duringViewResize)
    #expect(container.layerContentsPlacement == .bottomLeft)
    #expect(container.slidingContentView.layerContentsRedrawPolicy == .duringViewResize)
    #expect(container.slidingContentView.layerContentsPlacement == .bottomLeft)
    #expect(container.slidingContentView.frame == container.bounds)

    container.frame.size.height = 310
    container.layoutSubtreeIfNeeded()

    #expect(container.slidingContentView.frame == container.bounds)
    #expect(container.slidingContentView.frame.minY == 0)
  }
}
