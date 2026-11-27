#!/usr/bin/env bash
set -euo pipefail

input="${1:?Recording file required}"
output="${2:?Output MP4 file required}"
ffmpeg_bin="${FFMPEG_BIN:-ffmpeg}"

"$ffmpeg_bin" -nostdin -hide_banner -loglevel error -y -i "$input" \
  -map 0:v:0 -vf 'fps=12,scale=w=min(540\,iw):h=-2' \
  -an -c:v libx264 -preset veryfast -crf 29 -pix_fmt yuv420p \
  -movflags +faststart "$output"

printf 'Video bytes before and after: %s -> %s\n' \
  "$(wc -c < "$input" | tr -d ' ')" "$(wc -c < "$output" | tr -d ' ')"
