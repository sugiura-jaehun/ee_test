#!/usr/bin/env bash
set -euo pipefail

export ANDROID_SERIAL
ANDROID_SERIAL="$(adb devices | awk '$1 ~ /^emulator-/ && $2 == "device" {print $1; exit}')"
: "${ANDROID_SERIAL:?No Android emulator found}"
adb shell pm path com.android.chrome

output="$RUNNER_TEMP/android-appium-recording"
mkdir -p "$output" "$CHROMEDRIVER_CACHE_DIR"

android-appium/node_modules/.bin/appium   --address 127.0.0.1 --allow-insecure uiautomator2:chromedriver_autodownload   --log-no-colors > "$output/appium.log" 2>&1 &
appium_pid=$!

cleanup() {
  if [[ -n "${record_pid:-}" ]]; then
    adb shell 'for pid in $(pidof screenrecord); do kill -INT "$pid"; done' || true
    wait "$record_pid" || true
    adb pull /sdcard/appium-smoke.mp4 "$output/android-chrome.mp4" || true
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

adb shell screenrecord --bit-rate 4000000 --time-limit 180 /sdcard/appium-smoke.mp4 &
record_pid=$!
export BUNDLE_GEMFILE="$PWD/android-appium/Gemfile"
timeout 160s bundle exec ruby android-appium/chrome_smoke.rb 2>&1 | tee "$output/test.log"
