#!/usr/bin/env bash
# Exports the Web build into docs/, which is what GitHub Pages serves.
#   bash tools/web_build.sh
#
# Non-threaded on purpose. Godot's threaded web export needs SharedArrayBuffer,
# which the browser only hands out to a cross-origin-isolated document — that
# means COOP/COEP response headers, and GitHub Pages does not let you set
# headers at all. The documented workaround (coi-serviceworker) fakes isolation
# from a service worker, but it costs a full extra page load on first visit,
# breaks in any context where the worker cannot register, and is a second thing
# to keep alive. `variant/thread_support=false` in export_presets.cfg avoids the
# requirement outright, which is the option that is actually stable on Pages.
#
# docs/ carries a .gdignore so the exporter's own icon PNGs do not get imported
# back into the project as resources (that is how the old root-level export
# left index.png.import lying in the repo).
set -eu
cd "$(dirname "$0")/.."
GODOT="C:/Users/User/Desktop/Jack/AI/Godot_v4.7.1-stable_win64.exe"
LOG="art_export/web_export.log"
mkdir -p art_export docs
[ -f docs/.gdignore ] || : > docs/.gdignore

# --import first: a cold .godot/ makes the exporter ship an empty pack.
"$GODOT" --headless --path . --import --log-file "$LOG" >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Web" docs/index.html \
  --log-file "$LOG" >/dev/null 2>&1 || true

sed -e 's/\r$//' "$LOG" | grep -iE "error|failed|missing" | head -20 || true
ls -l docs/index.html docs/index.pck docs/index.wasm docs/index.js 2>&1
