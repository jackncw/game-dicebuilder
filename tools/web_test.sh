#!/usr/bin/env bash
# The browser-side regression: builds the web export and runs the Playwright
# viewport suite against it.
#
#   bash tools/web_test.sh            # build, then test
#   bash tools/web_test.sh --no-build # test whatever is already in docs/
#
# Kept out of `tools/test_all.sh` on purpose. That suite is thirteen headless
# Godot runs and finishes in a couple of minutes with nothing installed but
# Godot; this one needs a web export template, node, and a Chromium download,
# and a cold wasm boot under SwiftShader is tens of seconds per case. It is the
# check you run before publishing, not the one you run on every edit.
set -eu
cd "$(dirname "$0")/.."

if [ "${1:-}" != "--no-build" ]; then
  bash tools/web_build.sh
fi

cd web
[ -d node_modules ] || npm install
npx playwright install chromium
npx playwright test "$@"
