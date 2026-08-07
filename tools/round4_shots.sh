#!/usr/bin/env bash
# Shoots the round-4 surfaces into art_iterations/round4/.
# Needs a REAL window (frame_post_draw never fires headless), so no --headless.
#   bash tools/round4_shots.sh
set -u
cd "$(dirname "$0")/.."
GODOT="C:/Users/User/Desktop/Jack/AI/Godot_v4.7.1-stable_win64.exe"
LOG="art_export/round4_shots.log"
rm -f "$LOG"
"$GODOT" --path . --log-file "$LOG" tools/round4_shots.tscn >/dev/null 2>&1
sed -e 's/\r$//' "$LOG" | grep -Ei "SHOT|ROUND4|ERROR|SCRIPT" | tail -40
echo "--- files: $(find art_iterations/round4 -name '*.png' 2>/dev/null | wc -l) ---"
