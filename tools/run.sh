#!/usr/bin/env bash
# Runs Godot headless and echoes the log, because the Windows build detaches
# from the console and print() never reaches stdout reliably.
#   tools/run.sh <log-name> [godot args…]
set -u
GODOT="C:/Users/User/Desktop/Jack/AI/Godot_v4.7.1-stable_win64.exe"
NAME="$1"; shift
LOG="art_export/${NAME}.log"
rm -f "$LOG"
"$GODOT" --headless --path . --log-file "$LOG" "$@" >/dev/null 2>&1
CODE=$?
sed -e 's/\r$//' "$LOG"
echo "--- exit=$CODE ---"
exit $CODE
