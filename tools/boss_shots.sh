#!/usr/bin/env bash
# Shoots the boss / crowded-arena layout cases into art_iterations/boss_layout/.
# Needs a REAL window (frame_post_draw never fires headless), so no --headless.
#   bash tools/boss_shots.sh
set -u
cd "$(dirname "$0")/.."
GODOT="C:/Users/User/Desktop/Jack/AI/Godot_v4.7.1-stable_win64.exe"
LOG="art_export/boss_shots.log"
rm -f "$LOG"
"$GODOT" --path . --log-file "$LOG" tools/boss_shots.tscn >/dev/null 2>&1
sed -e 's/\r$//' "$LOG" | grep -Ei "SHOT|BOSS SHOTS|ERROR|SCRIPT" | tail -40
echo "--- files: $(find art_iterations/boss_layout -name '*.png' 2>/dev/null | wc -l) ---"
