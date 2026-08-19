# Test-tool notices

The public Swift package pins the following development-only tools. They are used to compile and run
the repository test target and are not linked into the Rabbisir application products.

- [Swift Testing](https://github.com/swiftlang/swift-testing), revision
  `swift-6.2.3-RELEASE` (`48a471a`): Apache License 2.0 with Runtime Library Exception.
- [Swift Syntax](https://github.com/swiftlang/swift-syntax), version `602.0.0`: Apache License 2.0
  with Runtime Library Exception; resolved transitively by Swift Testing.

Their complete license texts remain in the resolved source packages fetched by SwiftPM. Nothing in
the Rabbisir source license changes their terms.
