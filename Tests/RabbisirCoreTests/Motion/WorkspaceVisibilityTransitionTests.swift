import Testing

@testable import RabbisirCore

@Suite("Workspace visibility transition")
struct WorkspaceVisibilityTransitionTests {
  @Test("The crossfade stays monotonic in both directions")
  func monotonicCrossfade() {
    let fadeIn = (0...4).map { step in
      WorkspaceVisibilityTransitionPolicy.opacity(
        from: 0,
        to: 1,
        progress: Double(step) / 4,
        curve: .easeInOut
      )
    }
    let fadeOut = (0...4).map { step in
      WorkspaceVisibilityTransitionPolicy.opacity(
        from: 1,
        to: 0,
        progress: Double(step) / 4,
        curve: .easeInOut
      )
    }

    #expect(fadeIn == fadeIn.sorted())
    #expect(fadeOut == fadeOut.sorted(by: >))
    #expect(fadeIn.first == 0)
    #expect(fadeIn.last == 1)
    #expect(fadeOut.first == 1)
    #expect(fadeOut.last == 0)
  }

  @Test("A replacement fade starts at the currently visible opacity")
  func replacementUsesVisibleOpacity() {
    let current: Double = 0.42
    let first = WorkspaceVisibilityTransitionPolicy.opacity(
      from: current,
      to: 1,
      progress: 0,
      curve: .easeInOut
    )

    #expect(abs(first - current) < 0.0001)
  }
}
