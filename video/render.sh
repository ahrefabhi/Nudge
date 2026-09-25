#!/usr/bin/env bash
# Renders the Peeku launch video into video/out/: peeku.mp4 (with audio), poster.jpg (also frame 0).
# Usage: video/render.sh [poster-time]   e.g. video/render.sh 6.6
# Needs node, python3 and ffmpeg. The first run installs Playwright and numpy locally.
set -euo pipefail
cd "$(dirname "$0")"
poster="${1:-6.6}"

[[ -d node_modules/playwright ]] || npm install --silent
npx --no-install playwright install chromium >/dev/null
[[ -x venv/bin/python ]] || { python3 -m venv venv && venv/bin/pip install -q -r requirements.txt; }

mkdir -p out
venv/bin/python audio.py
node capture.js video out/video-noaudio.mp4
ffmpeg -hide_banner -loglevel error -y -ss "$poster" -i out/video-noaudio.mp4 -frames:v 1 -q:v 2 out/poster.jpg
# The poster replaces frame 0, so every player's thumbnail shows it; length and sync don't change.
ffmpeg -hide_banner -loglevel error -y -i out/video-noaudio.mp4 -loop 1 -i out/poster.jpg -i out/audio.wav \
    -filter_complex "[0:v][1:v]overlay=enable='eq(n\,0)':shortest=1,format=yuv420p[v]" -map "[v]" -map 2:a \
    -c:v libx264 -preset slow -crf 16 -c:a aac -b:a 192k -movflags +faststart -shortest out/peeku.mp4
rm out/video-noaudio.mp4
echo "out/peeku.mp4 and out/poster.jpg"
