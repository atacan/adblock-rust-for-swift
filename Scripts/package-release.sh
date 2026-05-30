#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACTS_DIR="$ROOT_DIR/Artifacts"
RELEASE_DIR="$ROOT_DIR/Release"
XCFRAMEWORK="$ARTIFACTS_DIR/CAdblockRust.xcframework"
ZIP_PATH="$RELEASE_DIR/CAdblockRust.xcframework.zip"
VERSION="${1:-0.0.1}"
REPOSITORY="${2:-atacan/adblock-rust-for-swift}"
ASSET_URL="https://github.com/$REPOSITORY/releases/download/$VERSION/CAdblockRust.xcframework.zip"

if [[ ! -d "$XCFRAMEWORK" ]]; then
  echo "Missing $XCFRAMEWORK"
  echo "Run ./Scripts/build-xcframework.sh first."
  exit 1
fi

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

ditto -c -k --sequesterRsrc --keepParent "$XCFRAMEWORK" "$ZIP_PATH"

CHECKSUM="$(swift package compute-checksum "$ZIP_PATH")"

cat <<EOF
Created:
  $ZIP_PATH

SwiftPM checksum:
  $CHECKSUM

Use this binary target in Package.swift after uploading the zip to GitHub Releases:

.binaryTarget(
  name: "CAdblockRust",
  url: "$ASSET_URL",
  checksum: "$CHECKSUM"
)
EOF
