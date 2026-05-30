#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRATE_DIR="$ROOT_DIR/Native/adblock-rust-ffi"
ARTIFACTS_DIR="$ROOT_DIR/Artifacts"
BUILD_DIR="$ROOT_DIR/.build"
INCLUDE_DIR="$ROOT_DIR/include"
XCFRAMEWORK="$ARTIFACTS_DIR/CAdblockRust.xcframework"

if ! command -v rustup >/dev/null 2>&1; then
  if [[ -f "$HOME/.cargo/env" ]]; then
    # Xcode and GUI-launched shells often do not inherit ~/.cargo/bin.
    # shellcheck source=/dev/null
    source "$HOME/.cargo/env"
  fi
fi

IOS_DEVICE_TARGET="aarch64-apple-ios"
IOS_SIM_ARM_TARGET="aarch64-apple-ios-sim"
IOS_SIM_X86_TARGET="x86_64-apple-ios"
MACOS_ARM_TARGET="aarch64-apple-darwin"
MACOS_X86_TARGET="x86_64-apple-darwin"

rustup toolchain install stable \
  --target "$IOS_DEVICE_TARGET" \
  --target "$IOS_SIM_ARM_TARGET" \
  --target "$IOS_SIM_X86_TARGET" \
  --target "$MACOS_ARM_TARGET" \
  --target "$MACOS_X86_TARGET"

rm -rf "$XCFRAMEWORK" "$BUILD_DIR"
mkdir -p "$ARTIFACTS_DIR" "$BUILD_DIR"

build_target() {
  local target="$1"
  cargo +stable build \
    --manifest-path "$CRATE_DIR/Cargo.toml" \
    --release \
    --target "$target"
}

build_target "$IOS_DEVICE_TARGET"
build_target "$IOS_SIM_ARM_TARGET"
build_target "$IOS_SIM_X86_TARGET"
build_target "$MACOS_ARM_TARGET"
build_target "$MACOS_X86_TARGET"

DEVICE_LIB="$CRATE_DIR/target/$IOS_DEVICE_TARGET/release/libadblock_rust_ffi.a"
SIM_ARM_LIB="$CRATE_DIR/target/$IOS_SIM_ARM_TARGET/release/libadblock_rust_ffi.a"
SIM_X86_LIB="$CRATE_DIR/target/$IOS_SIM_X86_TARGET/release/libadblock_rust_ffi.a"
MACOS_ARM_LIB="$CRATE_DIR/target/$MACOS_ARM_TARGET/release/libadblock_rust_ffi.a"
MACOS_X86_LIB="$CRATE_DIR/target/$MACOS_X86_TARGET/release/libadblock_rust_ffi.a"
SIM_UNIVERSAL_LIB="$BUILD_DIR/libadblock_rust_ffi_simulator.a"
MACOS_UNIVERSAL_LIB="$BUILD_DIR/libadblock_rust_ffi_macos.a"

lipo -create "$SIM_ARM_LIB" "$SIM_X86_LIB" -output "$SIM_UNIVERSAL_LIB"
lipo -create "$MACOS_ARM_LIB" "$MACOS_X86_LIB" -output "$MACOS_UNIVERSAL_LIB"

xcrun xcodebuild -create-xcframework \
  -library "$DEVICE_LIB" -headers "$INCLUDE_DIR" \
  -library "$SIM_UNIVERSAL_LIB" -headers "$INCLUDE_DIR" \
  -library "$MACOS_UNIVERSAL_LIB" -headers "$INCLUDE_DIR" \
  -output "$XCFRAMEWORK"

echo "Created $XCFRAMEWORK"
