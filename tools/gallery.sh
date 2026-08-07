#!/usr/bin/env bash
# Shoots the full art-review gallery into art_iterations/iter_<N>/.
# Needs a REAL window (frame_post_draw never fires headless), so no --headless.
#   bash tools/gallery.sh 1                 # everything, both resolutions
#   bash tools/gallery.sh 1 --only battle   # just the battle shots
#   bash tools/gallery.sh 1 --res 720
set -u
cd "$(dirname "$0")/.."
GODOT="C:/Users/User/Desktop/Jack/AI/Godot_v4.7.1-stable_win64.exe"
ITER="$1"; shift
LOG="art_export/gallery_${ITER}.log"
rm -f "$LOG"
"$GODOT" --path . --log-file "$LOG" tools/gallery_export.tscn -- --iter "$ITER" "$@" >/dev/null 2>&1
sed -e 's/\r$//' "$LOG" | grep -Ei "SHOT|GALLERY|ERROR|error|SCRIPT" | tail -120
echo "--- files: $(find "art_iterations/iter_${ITER}" -name '*.png' 2>/dev/null | wc -l) ---"
