// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "Rabbisir",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "RabbisirOpen", targets: ["RabbisirOpenApp"])
  ],
  dependencies: [
    .package(
      url: "https://github.com/swiftlang/swift-testing",
      revision: "swift-6.2.3-RELEASE"
    )
  ],
  targets: [
    .target(
      name: "RabbisirCore",
      dependencies: [],
      resources: [
        .copy("Resources/Brand"),
        .copy("Resources/VendorRuntime"),
      ],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("Carbon"),
        .linkedFramework("WebKit"),
      ]
    ),
    .executableTarget(
      name: "RabbisirOpenApp",
      dependencies: ["RabbisirCore"]
    ),
    .testTarget(
      name: "RabbisirCoreTests",
      dependencies: [
        "RabbisirCore",
        .product(name: "Testing", package: "swift-testing"),
      ]
    ),
  ]
)
