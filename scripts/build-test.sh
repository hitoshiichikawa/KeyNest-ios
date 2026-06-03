#!/usr/bin/env bash
#
# Build & test KeyNest (iOS) on macOS.
#
# Requirements:
#   - macOS with Xcode 15+ (iOS 17 SDK)
#   - XcodeGen:  brew install xcodegen
#
# The unit tests (KeyNestKitTests) run on the iOS Simulator and need NO code
# signing / DEVELOPMENT_TEAM. A real Apple Team ID is only required for *device*
# builds, never for running these tests.
#
# Usage:
#   scripts/build-test.sh                       # generate project + run KeyNestKitTests
#   KEYNEST_DEVICE="iPhone 16" scripts/build-test.sh   # override the simulator device
#
# If the chosen simulator name does not exist, xcodebuild prints the available
# destinations — set KEYNEST_DEVICE to one of them and re-run.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen not found — install with:  brew install xcodegen" >&2
  exit 1
fi

echo "==> xcodegen generate"
xcodegen generate

DEVICE="${KEYNEST_DEVICE:-iPhone 15}"
echo "==> xcodebuild test (KeyNestKitTests) on iOS Simulator: ${DEVICE}"
set -x
xcodebuild test \
  -project KeyNest.xcodeproj \
  -scheme KeyNest \
  -destination "platform=iOS Simulator,name=${DEVICE}" \
  -only-testing:KeyNestKitTests \
  CODE_SIGNING_ALLOWED=NO
