#!/bin/bash
# Records docs/demo.gif + docs/demo.mp4: runs the app in --autoplay mode, which plays the whole
# demo inside its own stage window (wallpaper, menu bar, notch, a drawn cursor and stand-in
# terminals) and quits when done. Your real pointer and sessions are never involved.
# Needs screen-recording permission for the terminal, and ffmpeg.
set -euo pipefail
cd "$(dirname "$0")/.."
./build.sh >/dev/null
swiftc -O tools/drive.swift -o build/drive
read -r SW SH < <(osascript -l JavaScript -e 'ObjC.import("AppKit"); const f = $.NSScreen.mainScreen.frame; `${f.size.width} ${f.size.height}`')
X0=$(( (${SW%.*} - 1000) / 2 )); Y0=$(( (${SH%.*} - 440) / 2 ))

pkill -x Topnotchers || true; sleep 0.4
build/drive move $(( ${SW%.*} / 2 )) $(( Y0 + 440 + 60 ))   # real pointer out of frame
rm -f build/raw.mov
# screencapture only saves when it runs its full length, so record long and trim to the demo.
T0=$(python3 -c 'import time; print(time.time())')
screencapture -v -V 60 -R "$X0,$Y0,1000,440" build/raw.mov >/dev/null 2>&1 &
CAP=$!
sleep 1
"build/Topnotchers.app/Contents/MacOS/Topnotchers" --autoplay >/dev/null 2>&1   # returns when the demo ends
END=$(python3 -c "import time; print(round(time.time() - $T0 - 0.2, 2))")
open "$HOME/Applications/Topnotchers.app"
wait $CAP
[ -s build/raw.mov ] || { echo "screencapture wrote nothing (screen-recording permission?)"; exit 1; }

ffmpeg -loglevel error -y -ss 1.2 -to "$END" -i build/raw.mov -vf "fps=30,scale=1200:-2:flags=lanczos" -c:v libx264 -pix_fmt yuv420p -crf 20 -movflags +faststart -an docs/demo.mp4
ffmpeg -loglevel error -y -ss 1.2 -to "$END" -i build/raw.mov -vf "fps=15,scale=800:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=160:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" docs/demo.gif
ls -la docs
