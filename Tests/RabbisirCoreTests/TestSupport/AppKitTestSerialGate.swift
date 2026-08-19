import Foundation

/// Serializes tests that temporarily own AppKit windows. AppKit may re-enter the
/// main run loop while ordering a window, so MainActor alone is not mutual exclusion.
final class AppKitTestSerialGate: @unchecked Sendable {
  static let shared = AppKitTestSerialGate()

  private let lock = NSLock()
  private var isHeld = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func acquire() async {
    await withCheckedContinuation { continuation in
      lock.lock()
      if isHeld {
        waiters.append(continuation)
        lock.unlock()
      } else {
        isHeld = true
        lock.unlock()
        continuation.resume()
      }
    }
  }

  func release() {
    // Window ordering/closing can enqueue AppKit transform cleanup after the
    // test body returns. Keep the lease briefly so the next window owner cannot overlap it.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
      completeRelease()
    }
  }

  private func completeRelease() {
    lock.lock()
    let waiter = waiters.isEmpty ? nil : waiters.removeFirst()
    if waiter == nil { isHeld = false }
    lock.unlock()
    waiter?.resume()
  }
}
