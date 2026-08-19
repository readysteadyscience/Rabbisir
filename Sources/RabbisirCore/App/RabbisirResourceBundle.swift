import Foundation

enum RabbisirResourceBundle {
  static let current: Bundle = {
    if let resourceURL = Bundle.main.resourceURL?
      .appendingPathComponent("Rabbisir_RabbisirCore.bundle"),
      let packagedBundle = Bundle(url: resourceURL)
    {
      return packagedBundle
    }
    return Bundle.module
  }()
}
