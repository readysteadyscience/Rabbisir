import Testing

@testable import RabbisirCore

@Suite("Composer generation action policy")
struct ComposerGenerationActionPolicyTests {
  @Test("Idle, running, and cancelling states expose only their valid action")
  func stateResolution() {
    #expect(
      ComposerGenerationActionPolicy.state(
        isRunning: false,
        isCancellationPending: false
      ) == .send
    )
    #expect(
      ComposerGenerationActionPolicy.state(
        isRunning: true,
        isCancellationPending: false
      ) == .stop
    )
    #expect(
      ComposerGenerationActionPolicy.state(
        isRunning: true,
        isCancellationPending: true
      ) == .stopping
    )
  }
}
