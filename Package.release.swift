// swift-tools-version: 5.10
//
// Copy this file to Package.swift for tagged releases after uploading
// CAdblockRust.xcframework.zip to GitHub Releases and replacing the URL and
// checksum placeholders below.

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
      url: "https://github.com/OWNER/REPO/releases/download/VERSION/CAdblockRust.xcframework.zip",
      checksum: "CHECKSUM"
    ),
    .target(
      name: "AdblockRust",
      dependencies: ["CAdblockRust"]
    )
  ]
)
