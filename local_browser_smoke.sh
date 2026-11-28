#!/usr/bin/env bash
set -euo pipefail

# Set these on the machine running the app and the browser.
: "${SMOKE_PORT:?Set SMOKE_PORT to the local app port}"
: "${SMOKE_HEALTH_PATH:?Set SMOKE_HEALTH_PATH to the local health path}"
: "${SMOKE_PAGE_MARKER:?Set SMOKE_PAGE_MARKER to an expected literal in the rendered home page}"

if [[ ! "$SMOKE_PORT" =~ ^[0-9]{1,5}$ ]] || (( 10#$SMOKE_PORT < 1 || 10#$SMOKE_PORT > 65535 )); then
  echo 'SMOKE_PORT must be an integer from 1 to 65535.' >&2
  exit 2
fi
if [[ "$SMOKE_HEALTH_PATH" != /* || "$SMOKE_HEALTH_PATH" == //* ]]; then
  echo 'SMOKE_HEALTH_PATH must be a path on the local app.' >&2
  exit 2
fi

base_url="http://127.0.0.1:$SMOKE_PORT"
chrome=${SMOKE_CHROME:-'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'}
if [[ ! -x "$chrome" ]]; then
  echo 'Chrome is unavailable. Set SMOKE_CHROME to its executable path.' >&2
  exit 2
fi

if ! status=$(curl --noproxy '*' --globoff --silent --max-time 30 \
  --output /dev/null --write-out '%{http_code}' "$base_url$SMOKE_HEALTH_PATH"); then
  echo 'Could not reach the local health endpoint.' >&2
  exit 1
fi
if [[ "$status" != 200 ]]; then
  printf 'Health check returned HTTP %s.\n' "$status" >&2
  exit 1
fi
echo 'Health check returned HTTP 200.'

scratch=$(mktemp -d "${TMPDIR:-/tmp}/local-browser-smoke.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
chrome_options=(
  --headless
  --disable-background-networking
  --no-proxy-server
  '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1'
  "--user-data-dir=$scratch/profile"
  --timeout=90000
  --dump-dom
)
if [[ -n "${SMOKE_USER_AGENT:-}" ]]; then
  chrome_options+=("--user-agent=$SMOKE_USER_AGENT")
fi

if ! "$chrome" "${chrome_options[@]}" "$base_url/" >"$scratch/page.html" 2>"$scratch/chrome.log"; then
  echo 'Chrome could not render the local page.' >&2
  exit 1
fi
if ! grep -Fq -- "$SMOKE_PAGE_MARKER" "$scratch/page.html"; then
  echo 'The expected page marker was not found.' >&2
  exit 1
fi
echo 'Chrome rendered the expected local page.'
