#!/usr/bin/env bash
set -euo pipefail

case "$APPIUM_MODE" in
  xcuitest-managed)
    ;;
  xcuitest-attach)
    wda_project_file=$(find "$APPIUM_HOME/node_modules" -path '*/WebDriverAgent.xcodeproj/project.pbxproj' -print -quit)
    : "${wda_project_file:?WebDriverAgent Xcode project missing}"
    wda_project=$(dirname "$wda_project_file")
    wda_build="$RUNNER_TEMP/wda"
    xcodebuild build-for-testing -project "$wda_project" -scheme WebDriverAgentRunner \
      -destination 'generic/platform=iOS Simulator' -derivedDataPath "$wda_build" \
      CODE_SIGNING_ALLOWED=NO -quiet
    echo "WDA build completed"
    TEST_RUNNER_USE_PORT=8100 xcodebuild test-without-building \
      -project "$wda_project" -scheme WebDriverAgentRunner \
      -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
      -derivedDataPath "$wda_build" -parallel-testing-enabled NO > wda.log 2>&1 &
    wda_pid=$!
    trap 'kill "$wda_pid" 2>/dev/null || true' EXIT
    wda_deadline=$((SECONDS + 600))
    until curl --silent --fail --max-time 3 http://127.0.0.1:8100/status > /dev/null; do
      if ! kill -0 "$wda_pid" 2>/dev/null || (( SECONDS >= wda_deadline )); then
        echo "WDA did not become reachable on port 8100"
        exit 1
      fi
      sleep 3
    done
    echo "WDA HTTP endpoint is ready"
    ;;
  safari-driver)
    sudo -n /usr/bin/safaridriver --enable
    xcrun simctl bootstatus "$SIMULATOR_UDID" -b
    open -a "$(xcode-select -p)/Applications/Simulator.app" --args -CurrentDeviceUDID "$SIMULATOR_UDID"
    xcrun simctl launch "$SIMULATOR_UDID" com.apple.mobilesafari
    ;;
  *)
    echo "Unknown Appium mode: $APPIUM_MODE"
    exit 1
    ;;
esac

time python3 appium_smoke.py
