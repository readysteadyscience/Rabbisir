import AppKit
import Carbon.HIToolbox

enum RabbisirGlobalHotKeyCommand: UInt32, CaseIterable, Sendable {
  case toggleWorkspace = 1
  case focusInput = 2

  var keyCode: UInt32 {
    switch self {
    case .toggleWorkspace:
      UInt32(kVK_Space)
    case .focusInput:
      UInt32(kVK_Return)
    }
  }

  var modifiers: UInt32 {
    UInt32(controlKey | optionKey)
  }

  var displayName: String {
    switch self {
    case .toggleWorkspace:
      "⌃⌥Space"
    case .focusInput:
      "⌃⌥Return"
    }
  }
}

private let rabbisirGlobalHotKeyHandler: EventHandlerUPP = { _, event, userData in
  guard let event, let userData else { return OSStatus(eventNotHandledErr) }
  var identifier = EventHotKeyID()
  let status = GetEventParameter(
    event,
    EventParamName(kEventParamDirectObject),
    EventParamType(typeEventHotKeyID),
    nil,
    MemoryLayout<EventHotKeyID>.size,
    nil,
    &identifier
  )
  guard status == noErr else { return status }
  let coordinator = Unmanaged<GlobalHotKeyCoordinator>
    .fromOpaque(userData)
    .takeUnretainedValue()
  coordinator.enqueue(commandID: identifier.id)
  return noErr
}

@MainActor
final class GlobalHotKeyCoordinator: @unchecked Sendable {
  typealias Action = @MainActor () -> Void

  private let actions: [RabbisirGlobalHotKeyCommand: Action]
  private var eventHandler: EventHandlerRef?
  private var registrations: [RabbisirGlobalHotKeyCommand: EventHotKeyRef] = [:]

  init(
    toggleWorkspace: @escaping Action,
    focusInput: @escaping Action
  ) {
    actions = [
      .toggleWorkspace: toggleWorkspace,
      .focusInput: focusInput,
    ]
  }

  func start() -> [RabbisirGlobalHotKeyCommand: OSStatus] {
    stop()
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    let installStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      rabbisirGlobalHotKeyHandler,
      1,
      &eventType,
      Unmanaged.passUnretained(self).toOpaque(),
      &eventHandler
    )
    guard installStatus == noErr else {
      return Dictionary(
        uniqueKeysWithValues: RabbisirGlobalHotKeyCommand.allCases.map {
          ($0, installStatus)
        }
      )
    }

    var failures: [RabbisirGlobalHotKeyCommand: OSStatus] = [:]
    for command in RabbisirGlobalHotKeyCommand.allCases {
      var reference: EventHotKeyRef?
      let identifier = EventHotKeyID(
        signature: Self.signature,
        id: command.rawValue
      )
      let status = RegisterEventHotKey(
        command.keyCode,
        command.modifiers,
        identifier,
        GetApplicationEventTarget(),
        0,
        &reference
      )
      if status == noErr, let reference {
        registrations[command] = reference
      } else {
        failures[command] = status
      }
    }
    return failures
  }

  func stop() {
    for registration in registrations.values {
      UnregisterEventHotKey(registration)
    }
    registrations.removeAll()
    if let eventHandler {
      RemoveEventHandler(eventHandler)
      self.eventHandler = nil
    }
  }

  nonisolated func enqueue(commandID: UInt32) {
    Task { @MainActor [weak self] in
      guard let self,
        let command = RabbisirGlobalHotKeyCommand(rawValue: commandID)
      else { return }
      actions[command]?()
    }
  }

  private static let signature: OSType = 0x5242_5831
}
