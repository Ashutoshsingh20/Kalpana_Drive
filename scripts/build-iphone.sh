#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/iphone-companion"
PROJECT="$APP_DIR/KalpanaDrivePhone.xcodeproj"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: Full Xcode is required to build the iPhone companion." >&2
  exit 1
fi

if [ ! -d "$PROJECT" ]; then
  if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: KalpanaDrivePhone.xcodeproj is missing. Install XcodeGen and run: cd iphone-companion && xcodegen generate" >&2
    exit 1
  fi
  (cd "$APP_DIR" && xcodegen generate)
fi

xcodebuild \
  -quiet \
  -project "$PROJECT" \
  -scheme KalpanaDrivePhone \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
