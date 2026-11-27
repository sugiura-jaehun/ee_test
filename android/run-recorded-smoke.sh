#!/usr/bin/env bash
set -euo pipefail

: "${SMOKE_START_URL:?Missing start URL}"
: "${SMOKE_START_LABEL:?Missing start link label}"
: "${SMOKE_DESTINATION_LABEL:?Missing destination label}"

adb shell pm path com.android.chrome
adb install -r android/build/outputs/apk/debug/*-debug.apk
adb install -r android/build/outputs/apk/androidTest/debug/*-debug-androidTest.apk

output="$RUNNER_TEMP/android-smoke"
mkdir -p "$output"
remote_video=/sdcard/chrome-smoke.mp4
adb shell screenrecord --bit-rate 4000000 --time-limit 180 "$remote_video" &
record_command=$!

save_recording() {
  adb shell dumpsys activity activities | grep -E 'topResumedActivity|mResumedActivity' || true
  adb logcat -d -s ActivityTaskManager AndroidRuntime chromium > "$output/device.log" || true
  adb shell 'for pid in $(pidof screenrecord); do kill -INT "$pid"; done' || true
  wait "$record_command" || true
  adb pull "$remote_video" "$output/chrome-smoke.mp4" || true
}
trap save_recording EXIT

# Escape each argument for the device shell that executes the command.
printf -v test_command '%q ' am instrument -w -r \
  -e startUrl "$SMOKE_START_URL" \
  -e startLabel "$SMOKE_START_LABEL" \
  -e destinationLabel "$SMOKE_DESTINATION_LABEL" \
  example.chromesmoke.test/androidx.test.runner.AndroidJUnitRunner
timeout 150s adb shell "$test_command" | tee "$output/test.log"
# am instrument can exit zero even when JUnit reports an assertion failure.
grep -Fx 'OK (1 test)' "$output/test.log"
