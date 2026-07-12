#!/bin/sh
set -eu
cd "$(dirname "$0")/../ipad-app"
SCRATCH_PATH="${TMPDIR:-/tmp}/kalpana-drive-swift-build"
rm -rf "$SCRATCH_PATH"
swift run --scratch-path "$SCRATCH_PATH" KalpanaDriveChecks
