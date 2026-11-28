#!/usr/bin/env bash
set -euo pipefail

export TEST_RUNNER_SMOKE_LINK_LABEL="$SMOKE_START_LABEL"
log="$RUNNER_TEMP/ios-appium-recording/safari-tap.log"
if ! xcodebuild test-without-building -project native/SafariSmoke.xcodeproj -scheme SafariSmoke \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -parallel-testing-enabled NO \
  -only-testing:SafariTests/SafariTests/testTapConfiguredLinkInOpenSafari > "$log" 2>&1; then
  tail -70 "$log"
  exit 1
fi
grep -E 'Safari toolbar tip|XCTest tapped|TEST SUCCEEDED' "$log" || true
