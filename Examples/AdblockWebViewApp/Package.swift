// swift-tools-version: 5.10

import PackageDescription

let package = Package(
  name: "AdblockWebViewApp",
  platforms: [.macOS(.v13)],
  dependencies: [
    .package(path: "../..")
  ],
  targets: [
    .executableTarget(
      name: "AdblockWebViewApp",
      dependencies: [
        .product(name: "AdblockRust", package: "adblock-rust-ios")
      ]
    )
  ]
)
