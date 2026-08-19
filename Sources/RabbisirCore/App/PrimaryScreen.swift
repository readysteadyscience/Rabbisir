import AppKit
import CoreGraphics

enum RabbisirPrimaryScreen {
  static var current: NSScreen? {
    let mainDisplayID = CGMainDisplayID()
    return NSScreen.screens.first { screen in
      guard
        let number = screen.deviceDescription[
          NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber
      else {
        return false
      }
      return number.uint32Value == mainDisplayID
    }
  }
}
