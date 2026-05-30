// swift-tools-version: 5.10

import Foundation
import PackageDescription

let cAdblockRustTarget: Target
if let localXCFrameworkPath = ProcessInfo.processInfo.environment["ADBLOCK_RUST_XCFRAMEWORK_PATH"] {
  cAdblockRustTarget = .binaryTarget(
    name: "CAdblockRust",
    path: localXCFrameworkPath
  )
} else {
  cAdblockRustTarget = .binaryTarget(
    name: "CAdblockRust",
    url: "https://github.com/atacan/adblock-rust-for-swift/releases/download/0.0.1/CAdblockRust.xcframework.zip",
    checksum: "76f3846abf86199f3c3c8fa844c707c246f47b5dd9e4c3272763fa04d691bfbc"
  )
}

let package = Package(
  name: "AdblockRust",
  platforms: [
    .iOS(.v13),
    .macOS(.v11),
  ],
  products: [
    .library(name: "AdblockRust", targets: ["AdblockRust"])
  ],
  targets: [
    cAdblockRustTarget,
    .target(
      name: "AdblockRust",
      dependencies: ["CAdblockRust"]
    )
  ]
)
