enum ComposerGenerationActionState: Equatable, Sendable {
  case send
  case stop
  case stopping
}

enum ComposerGenerationActionPolicy {
  static func state(
    isRunning: Bool,
    isCancellationPending: Bool
  ) -> ComposerGenerationActionState {
    guard isRunning else { return .send }
    return isCancellationPending ? .stopping : .stop
  }
}
