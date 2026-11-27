#!/usr/bin/env bash
set -euo pipefail

output="$RUNNER_TEMP/ios-appium-recording"
mkdir -p "$output"
xcrun simctl bootstatus "$SIMULATOR_UDID" -b
if [[ "$SMOKE_BROWSER" == safari-webdriver ]]; then
  sudo -n /usr/bin/safaridriver --enable
  open -a "$(xcode-select -p)/Applications/Simulator.app" --args -CurrentDeviceUDID "$SIMULATOR_UDID"
fi

ios-appium/node_modules/.bin/appium --address 127.0.0.1 --log-no-colors \
  > "$output/appium.log" 2>&1 &
appium_pid=$!

cleanup() {
  if [[ -n "${record_pid:-}" ]]; then
    kill -INT "$record_pid" 2>/dev/null || true
    wait "$record_pid" 2>/dev/null || true
  fi
  kill "$appium_pid" 2>/dev/null || true
  wait "$appium_pid" 2>/dev/null || true
}
trap cleanup EXIT

for attempt in {1..30}; do
  if curl --silent --fail http://127.0.0.1:4723/status > /dev/null; then
    break
  fi
  sleep 1
done
curl --silent --fail http://127.0.0.1:4723/status > /dev/null

xcrun simctl io "$SIMULATOR_UDID" recordVideo --codec h264 "$output/iphone-safari.mp4" \
  > "$output/record.log" 2>&1 &
record_pid=$!

export BUNDLE_GEMFILE="$PWD/android-appium/Gemfile"
if [[ "$SMOKE_BROWSER" == safari-webdriver ]]; then
  xcrun simctl launch "$SIMULATOR_UDID" com.apple.mobilesafari
fi
if ! bundle exec ruby android-appium/mobile_smoke.rb 2>&1 | tee "$output/test.log"; then
  xcrun simctl io "$SIMULATOR_UDID" screenshot "$output/failure.png" || true
  tail -60 "$output/appium.log"
  exit 1
fi
