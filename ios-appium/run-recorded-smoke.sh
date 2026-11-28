#!/usr/bin/env bash
set -euo pipefail

output="$RUNNER_TEMP/ios-appium-recording"
mkdir -p "$output"

cleanup() {
  if [[ -n "${record_pid:-}" ]]; then
    kill -INT "$record_pid" 2>/dev/null || true
    wait "$record_pid" 2>/dev/null || true
  fi
  if [[ -n "${appium_pid:-}" ]]; then
    kill "$appium_pid" 2>/dev/null || true
    wait "$appium_pid" 2>/dev/null || true
  fi
  if [[ -n "${wda_pid:-}" ]]; then
    kill "$wda_pid" 2>/dev/null || true
    wait "$wda_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

wda_file=$(find "$APPIUM_HOME/node_modules" -path '*/WebDriverAgent.xcodeproj/project.pbxproj' -print -quit)
: "${wda_file:?WebDriverAgent Xcode project missing}"
wda_project=$(dirname "$wda_file")
wda_build="$RUNNER_TEMP/wda"
if ! xcodebuild build-for-testing -project "$wda_project" -scheme WebDriverAgentRunner \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$wda_build" \
    CODE_SIGNING_ALLOWED=NO -quiet > "$output/wda-build.log" 2>&1; then
  tail -60 "$output/wda-build.log"
  exit 1
fi
echo 'WebDriverAgent build complete'
xcrun simctl bootstatus "$SIMULATOR_UDID" -b
TEST_RUNNER_USE_PORT=8100 xcodebuild test-without-building \
  -project "$wda_project" -scheme WebDriverAgentRunner \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath "$wda_build" -parallel-testing-enabled NO > "$output/wda.log" 2>&1 &
wda_pid=$!
deadline=$((SECONDS + 420))
until curl --silent --fail --max-time 3 http://127.0.0.1:8100/status > /dev/null; do
  if ! kill -0 "$wda_pid" 2>/dev/null || (( SECONDS >= deadline )); then
    echo 'WebDriverAgent did not become ready'
    tail -60 "$output/wda.log"
    exit 1
  fi
  sleep 2
done
echo 'WebDriverAgent is ready; starting Appium and the recorded test'

ios-appium/node_modules/.bin/appium --address 127.0.0.1 --log-no-colors \
  > "$output/appium.log" 2>&1 &
appium_pid=$!

for attempt in {1..30}; do
  if curl --silent --fail http://127.0.0.1:4723/status > /dev/null; then
    break
  fi
  sleep 1
done
curl --silent --fail http://127.0.0.1:4723/status > /dev/null

xcrun simctl io "$SIMULATOR_UDID" recordVideo --codec h264 "$RUNNER_TEMP/iphone-safari-original.mp4" \
  > "$output/record.log" 2>&1 &
record_pid=$!

export BUNDLE_GEMFILE="$PWD/android-appium/Gemfile"
if ! bundle exec ruby ios-appium/safari_smoke.rb 2>&1 | tee "$output/test.log"; then
  xcrun simctl io "$SIMULATOR_UDID" screenshot "$output/failure.png" || true
  tail -60 "$output/appium.log"
  exit 1
fi
