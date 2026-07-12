#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/ipad-app"
PROJECT="$APP_DIR/KalpanaDrive.xcodeproj"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: Full Xcode is required to build the live iPad application." >&2
  exit 1
fi

if [ ! -d "$PROJECT" ]; then
  if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: KalpanaDrive.xcodeproj is missing. Install XcodeGen and run: cd ipad-app && xcodegen generate" >&2
    exit 1
  fi
  (cd "$APP_DIR" && xcodegen generate)
fi

xcodebuild \
  -project "$PROJECT" \
  -scheme KalpanaDriveApp \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
