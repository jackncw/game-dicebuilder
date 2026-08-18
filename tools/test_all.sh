#!/usr/bin/env bash
# Runs every headless test suite and reports a single pass/fail summary.
#   bash tools/test_all.sh
cd "$(dirname "$0")/.."
SUITES="engine_smoke font_coverage_test data_policy_test value_band_test api_parity_test keywords_test save_migrate_test boss_test phase4_test meta_test run_flow_test ui_smoke layout_test screens_crawl charselect_input_test drag_input_test codex_scroll_test"
FAILED=0
for t in $SUITES; do
  printf '%-24s ' "$t"
  bash tools/run.sh "t_$t" "res://tests/$t.tscn" >/dev/null 2>&1
  LINE=$(sed -e 's/\r$//' "art_export/t_$t.log" | grep -Ei "OK$|OK —|failures|FAILED" | tail -1)
  echo "$LINE"
  # "PHASE4: 218 tests, 1 failures" is a FAILING run — matching only on the
  # word FAIL let a suite that printed its own tally slip through green.
  case "$LINE" in
    *FAIL*|"") FAILED=$((FAILED+1));;
    *" 0 failures"*) ;;
    *failures*) FAILED=$((FAILED+1));;
  esac
done
printf '%-24s ' "enemy_cutout"
LINE=$(python tools/enemy_cutout_test.py 2>&1 | grep -E "tests, .* failures" | tail -1)
echo "$LINE"
case "$LINE" in
  "") FAILED=$((FAILED+1));;
  *" 0 failures"*) ;;
  *failures*) FAILED=$((FAILED+1));;
esac
echo "-----"
if [ "$FAILED" -eq 0 ]; then echo "ALL SUITES PASSED"; else echo "$FAILED SUITE(S) FAILED"; fi
exit $FAILED
