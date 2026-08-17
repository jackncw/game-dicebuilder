#!/usr/bin/env bash
# Shoots the round-11 death-dissolve sequence into art_iterations/round11/.
# Needs a REAL window (frame_post_draw never fires headless), so no --headless.
#   bash tools/dissolve_shots.sh
set -u
cd "$(dirname "$0")/.."
GODOT="C:/Users/User/Desktop/Jack/AI/Godot_v4.7.1-stable_win64.exe"
LOG="art_export/dissolve_shots.log"
rm -f "$LOG"
"$GODOT" --path . --log-file "$LOG" tools/dissolve_shots.tscn >/dev/null 2>&1
sed -e 's/\r$//' "$LOG" | grep -Ei "SHOT|DONE|ERROR|SCRIPT" | tail -20
