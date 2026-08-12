#!/usr/bin/env bash
# 第十輪 mockup 截圖(地圖注釋 + 勝利畫面),出 art_iterations/round10/。
# Needs a REAL window (frame_post_draw never fires headless), so no --headless.
#   bash tools/round10_shots.sh
set -u
cd "$(dirname "$0")/.."
GODOT="C:/Users/User/Desktop/Jack/AI/Godot_v4.7.1-stable_win64.exe"
LOG="art_export/round10_shots.log"
rm -f "$LOG"
"$GODOT" --path . --log-file "$LOG" tools/round10_shots.tscn >/dev/null 2>&1
sed -e 's/\r$//' "$LOG" | grep -Ei "SHOT|ROUND10|ERROR|SCRIPT" | tail -40
echo "--- files: $(find art_iterations/round10 -name '*.png' 2>/dev/null | wc -l) ---"
