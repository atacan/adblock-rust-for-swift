// swift-tools-version: 5.10

import PackageDescription

let package = Package(
  name: "AdblockRustIOS",
  platforms: [
    .iOS(.v13),
    .macOS(.v11),
  ],
  products: [
    .library(name: "AdblockRust", targets: ["AdblockRust"])
  ],
  targets: [
    .binaryTarget(
      name: "CAdblockRust",
      path: "Artifacts/CAdblockRust.xcframework"
    ),
    .target(
      name: "AdblockRust",
      dependencies: ["CAdblockRust"]
    )
  ]
)
