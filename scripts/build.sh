#!/bin/sh
set -eu
cd "$(dirname "$0")/../ipad-app"
swift build --scratch-path "${TMPDIR:-/tmp}/kalpana-drive-swift-build"
