#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="AdblockWebViewApp"
APP_BUNDLE="${ROOT_DIR}/${APP_NAME}.app"
BUILD_MODE="debug"

for arg in "$@"; do
  case "${arg}" in
    --release) BUILD_MODE="release" ;;
    --debug) BUILD_MODE="debug" ;;
    --help|-h)
      echo "Usage: $(basename "$0") [--debug|--release]"
      exit 0
      ;;
  esac
done

pkill -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
pkill -x "${APP_NAME}" 2>/dev/null || true

"${ROOT_DIR}/scripts/package_app.sh" "${BUILD_MODE}" >/dev/null
open "${APP_BUNDLE}"
