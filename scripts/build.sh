#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/ipad-app"
PROJECT="$APP_DIR/KalpanaDrive.xcodeproj"
PROJECT_FILE="$PROJECT/project.pbxproj"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: Full Xcode is required to build the live iPad application." >&2
  exit 1
fi

PROJECT_NEEDS_REGEN=0
if [ ! -f "$PROJECT_FILE" ]; then
  PROJECT_NEEDS_REGEN=1
elif ! grep -q 'iPhoneCompanionBridge.swift' "$PROJECT_FILE"; then
  PROJECT_NEEDS_REGEN=1
fi

if [ "$PROJECT_NEEDS_REGEN" -eq 1 ]; then
  if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: The committed Xcode project does not include the latest sources. Install XcodeGen and run: cd ipad-app && xcodegen generate" >&2
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
