# AdblockWebViewApp

This is a minimal macOS AppKit example that uses `AdblockRust` with a
`WKWebView`.

On launch it downloads:

- EasyList: `https://easylist.to/easylist/easylist.txt`
- EasyPrivacy: `https://easylist.to/easylist/easyprivacy.txt`

It joins both lists, converts them to WebKit content-blocker JSON with
`AdblockEngine.contentBlockingRules(fromFilterSet:)`, compiles a
`WKContentRuleList`, and attaches it to the web view.

## Run Without Xcode

From this directory:

```sh
./scripts/run.sh
```

The scripts use SwiftPM, create a small `.app` bundle, and launch it with
`open`.

## Build Only

```sh
swift build
```

The parent package must have `Artifacts/CAdblockRust.xcframework` available.
Run this first from the repository root if needed:

```sh
./Scripts/build-xcframework.sh
```
