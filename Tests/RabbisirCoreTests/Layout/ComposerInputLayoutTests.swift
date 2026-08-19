import Testing

@testable import RabbisirCore

@Suite("Composer input layout")
struct ComposerInputLayoutTests {
  @Test("The complete control row uses one downward layout offset")
  func controlRowOffset() {
    #expect(ComposerInputLayout.controlRowOffsetY == 8)
  }

  @Test("Short drafts keep the composer at its collapsed height")
  func shortDraftUsesCollapsedHeight() {
    let layout = ComposerInputLayout.resolve(measuredTextHeight: 12, visibleHeight: 1_050)

    #expect(layout.textViewportHeight == 20)
    #expect(layout.surfaceHeight == InputComposerShape.collapsedSurfaceHeight)
    #expect(layout.panelExpansionHeight == 0)
  }

  @Test("Long drafts grow upward until the viewport limit")
  func longDraftIsBounded() {
    let growing = ComposerInputLayout.resolve(measuredTextHeight: 180, visibleHeight: 1_050)
    let bounded = ComposerInputLayout.resolve(measuredTextHeight: 900, visibleHeight: 1_050)

    #expect(growing.textViewportHeight == 180)
    #expect(growing.panelExpansionHeight == 160)
    #expect(bounded.textViewportHeight == 260)
    #expect(bounded.panelExpansionHeight == 240)
  }

  @Test("Small displays use a proportional maximum")
  func smallDisplayUsesProportionalMaximum() {
    let layout = ComposerInputLayout.resolve(measuredTextHeight: 900, visibleHeight: 600)

    #expect(layout.textViewportHeight == 180)
  }
}
