#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: XcodeGen is required. Install it with Homebrew: brew install xcodegen" >&2
  exit 1
fi

(cd "$ROOT/ipad-app" && xcodegen generate)
(cd "$ROOT/iphone-companion" && xcodegen generate)

echo "Generated:"
echo "  $ROOT/ipad-app/KalpanaDrive.xcodeproj"
echo "  $ROOT/iphone-companion/KalpanaDrivePhone.xcodeproj"
