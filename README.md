# AdblockRust

This is a small standalone Apple-platform wrapper for Brave's
[adblock-rust](https://github.com/brave/adblock-rust) engine. It builds a
Swift Package for iOS, iOS Simulator, and macOS that exposes a Swift
`AdblockEngine` backed by a Rust static library inside
`CAdblockRust.xcframework`.

It intentionally does not depend on BraveCore, Chromium, GN, or Brave's iOS
repository layout.

## What It Includes

- Network request matching with Brave's `adblock-rust` engine.
- Engine serialization/deserialization for cache files.
- Conversion from adblock filter syntax to WebKit `WKContentRuleList` JSON.
- A C module (`CAdblockRust`) plus a small Swift wrapper (`AdblockRust`).

This package does not currently expose cosmetic filtering, scriptlet resources,
or Brave's full Shields integration. Those can be added later by extending the
Rust FFI surface.

## Build

Requirements:

- macOS with Xcode command line tools
- Rust via `rustup`

From this directory:

```sh
./Scripts/build-xcframework.sh
```

The script creates:

```text
Artifacts/CAdblockRust.xcframework
```

The script builds these Rust targets:

- `aarch64-apple-ios`
- `aarch64-apple-ios-sim`
- `x86_64-apple-ios`
- `aarch64-apple-darwin`
- `x86_64-apple-darwin`

## Swift Package Use

For app consumers, add the GitHub package URL in Xcode or in `Package.swift`:

```swift
.package(url: "https://github.com/atacan/adblock-rust-for-swift.git", from: "0.0.1")
```

Then add the product to your target:

```swift
.product(name: "AdblockRust", package: "adblock-rust-for-swift")
```

For local Rust/XCFramework development, build the XCFramework first:

```sh
./Scripts/build-xcframework.sh
```

Then point SwiftPM at the local binary while building this package:

```sh
ADBLOCK_RUST_XCFRAMEWORK_PATH=Artifacts/CAdblockRust.xcframework swift build
```

Or use the same environment variable while running the example app:

```sh
cd Examples/AdblockWebViewApp
ADBLOCK_RUST_XCFRAMEWORK_PATH=Artifacts/CAdblockRust.xcframework ./scripts/run.sh
```

The default manifest uses the GitHub Release binary so consumers do not need
Rust installed.

## Filter Lists

`adblock-rust` is the engine. It does not ship a default rule list inside this
package. Your app must provide rules by downloading, bundling, or allowing users
to subscribe to filter lists.

Common starting points:

- EasyList: `https://easylist.to/easylist/easylist.txt`
- EasyPrivacy: `https://easylist.to/easylist/easyprivacy.txt`
- Brave list metadata and resources:
  `https://github.com/brave/adblock-resources`
- Brave supplemental lists:
  `https://github.com/brave/adblock-lists`

Minimal loader:

```swift
let listURLs = [
  URL(string: "https://easylist.to/easylist/easylist.txt")!,
  URL(string: "https://easylist.to/easylist/easyprivacy.txt")!,
]

var lists: [String] = []
for url in listURLs {
  let (data, _) = try await URLSession.shared.data(from: url)
  lists.append(String(decoding: data, as: UTF8.self))
}

let rules = lists.joined(separator: "\n")
let engine = try AdblockEngine(rules: rules)
```

In production, cache downloaded list text and/or serialized engine data. Do not
download and compile large lists on every page load.

Import it from Swift:

```swift
import AdblockRust

let rules = "||example.com^"
let engine = try AdblockEngine(rules: rules)

let blocked = engine.shouldBlock(
  requestURL: URL(string: "https://example.com/ad.js")!,
  sourceURL: URL(string: "https://site.test")!,
  resourceType: .script
)
```

For `WKContentRuleListStore` on iOS or macOS:

```swift
let converted = try AdblockEngine.contentBlockingRules(fromFilterSet: rules)
try await WKContentRuleListStore.default().compileContentRuleList(
  forIdentifier: "adblock",
  encodedContentRuleList: converted.json
)
```

## Direct Xcode Project Use

Drag `Artifacts/CAdblockRust.xcframework` into the app target, then import the C
module:

```swift
import CAdblockRust
```

For a nicer Swift API, use the Swift Package target in `Sources/AdblockRust`.

## Example App

`Examples/AdblockWebViewApp` is a small macOS AppKit app with a `WKWebView`.
It downloads EasyList and EasyPrivacy, converts them to a WebKit content-blocker
rule list, and loads a URL in the web view.

Run it without creating an Xcode project:

```sh
cd Examples/AdblockWebViewApp
./scripts/run.sh
```

The packaging scripts follow the SwiftPM-plus-`.app` bundle approach described
in [Running a SwiftUI macOS App Without an Xcode Project](https://actondon.com/blog/running-swift-apps-without-xcode).

## Updating adblock-rust

The Rust crate currently depends on the upstream repository directly:

```toml
adblock = { git = "https://github.com/brave/adblock-rust", ... }
```

The exact upstream revision is pinned in
`Native/adblock-rust-ffi/Cargo.lock`. To update it:

```sh
cd Native/adblock-rust-ffi
cargo update -p adblock
cd ../..
./Scripts/build-xcframework.sh
```

For a fork, change that URL in `Native/adblock-rust-ffi/Cargo.toml`. For
reproducible releases, pin a tag or revision:

```toml
adblock = { git = "https://github.com/yourname/adblock-rust", rev = "...", ... }
```

## Verify

After rebuilding the XCFramework, verify all supported platforms:

```sh
xcodebuild -scheme AdblockRust -destination 'generic/platform=iOS' build
xcodebuild -scheme AdblockRust -destination 'generic/platform=iOS Simulator' build
xcodebuild -scheme AdblockRust -destination 'generic/platform=macOS' build
```

## Repository Layout

Commit these files in an independent repository:

```text
Package.swift
README.md
rust-toolchain.toml
Scripts/
Sources/
Native/
include/
```

Do not commit `Artifacts/` or `Release/` to normal Git history. The XCFramework
is a binary artifact and will make the repository grow permanently every time it
changes.

## GitHub Releases

For distribution, publish the XCFramework as a GitHub Release asset:

```sh
./Scripts/build-xcframework.sh
./Scripts/package-release.sh 0.0.1 atacan/adblock-rust-for-swift
```

Upload `Release/CAdblockRust.xcframework.zip` to a GitHub Release, usually under
a tag such as `0.0.1`.

Then update the binary target in `Package.swift` with the release URL and
checksum printed by the script:

```swift
.binaryTarget(
  name: "CAdblockRust",
  url: "https://github.com/atacan/adblock-rust-for-swift/releases/download/0.0.1/CAdblockRust.xcframework.zip",
  checksum: "..."
)
```

`package-release.sh` prints the checksum. You can also recompute it with:

```sh
swift package compute-checksum Release/CAdblockRust.xcframework.zip
```

Important: GitHub Release asset URLs should be immutable for each tag. Do not
replace the zip behind an existing tag unless you also update `Package.swift`
with the new checksum and retag appropriately.
