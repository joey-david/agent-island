#!/bin/bash
# Records docs/demo.gif + docs/demo.mp4: runs the app in --stage mode (its own wallpaper,
# menu bar and notch, centred on screen) and drives demo.sh with a synthetic pointer.
# Needs screen-recording permission for the terminal, and ffmpeg.
set -euo pipefail
cd "$(dirname "$0")/.."
./build.sh >/dev/null
swiftc -O tools/drive.swift -o build/drive
D=build/drive
read -r SW SH < <(osascript -l JavaScript -e 'ObjC.import("AppKit"); const f = $.NSScreen.mainScreen.frame; `${f.size.width} ${f.size.height}`')
X0=$(( (${SW%.*} - 1000) / 2 )); Y0=$(( (${SH%.*} - 440) / 2 ))
at() { echo "$((X0 + $1)) $((Y0 + $2))"; }   # stage coordinates → screen

pkill -x AgentIsland || true; sleep 0.4
"build/Agent Island.app/Contents/MacOS/AgentIsland" --stage >/dev/null 2>&1 &
sleep 1.5
$D move $(at 500 400)
screencapture -v -V 45 -R "$X0,$Y0,1000,440" build/raw.mov >/dev/null 2>&1 &
sleep 0.5
./demo.sh &
sleep 7.5;  $D move $(at 470 16); sleep 3.2; $D move $(at 500 400)       # tray with live action
sleep 3.6;  $D move $(at 470 16); sleep 1.0                                 # stacked sessions
$D key 124; sleep 0.9; $D key 124; sleep 0.9; $D key 53; sleep 0.3; $D move $(at 500 400)
sleep 2.3;  $D move $(at 360 122); sleep 0.9; $D click $(at 360 122)        # answer "Hoots"
sleep 3.0;  $D move $(at 826 113); sleep 0.9; $D click $(at 826 113)        # Allow
sleep 5.5;  $D move $(at 530 16); sleep 2.6; $D move $(at 500 400)          # hover marks read
wait %2 2>/dev/null || true; sleep 2
pkill -x AgentIsland || true
open "$HOME/Applications/Agent Island.app"

ffmpeg -loglevel error -y -i build/raw.mov -vf "fps=30,scale=1200:-2:flags=lanczos" -c:v libx264 -pix_fmt yuv420p -crf 20 -movflags +faststart -an docs/demo.mp4
ffmpeg -loglevel error -y -i build/raw.mov -vf "fps=15,scale=800:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=160:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" docs/demo.gif
ls -la docs
