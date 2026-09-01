#!/bin/sh
# ============================================================
# run_complete_test.sh
# Tests the end-to-end wrapper in reports-only replay mode so the
# umbrella test does not trigger a second live hardware collection.
#
# Version:
#   1.0.0
# ============================================================
app_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd -P) || exit 2
rct_parent=${HFIP_TEST_RESULTS_PARENT-}
rct_fixture=${HFIP_TEST_FIXTURE_DIR-}
rct_stamp=$(date '+%Y%m%d-%H%M%S')
if [ -n "$rct_parent" ]; then rct_results=$rct_parent/run_complete_test; else rct_results=$app_dir/test/results/${rct_stamp}-run_complete_test-$$; fi
mkdir -p "$rct_results" || exit 2
rct_log=$rct_results/test.log
rct_pass=0
rct_fail=0
: > "$rct_log" || exit 2

if [ -t 1 ] && [ -z "${NO_COLOR-}" ]; then
    rct_0=$(printf '\033[0m'); rct_ok=$(printf '\033[92m'); rct_bad=$(printf '\033[91m'); rct_info=$(printf '\033[96m')
else
    rct_0=; rct_ok=; rct_bad=; rct_info=
fi

pass(){ rct_pass=$((rct_pass+1)); printf '%sPASS%s  %s\n' "$rct_ok" "$rct_0" "$*" | tee -a "$rct_log"; }
fail(){ rct_fail=$((rct_fail+1)); printf '%sFAIL%s  %s\n' "$rct_bad" "$rct_0" "$*" | tee -a "$rct_log"; }
printf '%sHost Inventory for Proxmox - complete workflow tests%s\n' "$rct_info" "$rct_0"

if sh -n "$app_dir/run_complete.sh"; then pass "run_complete.sh syntax"; else fail "run_complete.sh syntax"; fi
if sh -n "$app_dir/report_performance.sh"; then pass "report_performance.sh syntax"; else fail "report_performance.sh syntax"; fi
if [ "$("$app_dir/run_complete.sh" --version 2>/dev/null)" = "run_complete 0.9.2" ]; then pass "run_complete.sh --version"; else fail "run_complete.sh --version"; fi
if [ "$("$app_dir/report_performance.sh" --version 2>/dev/null)" = "report_performance 0.9.2" ]; then pass "report_performance.sh --version"; else fail "report_performance.sh --version"; fi
if "$app_dir/run_complete.sh" --help >"$rct_results/help.txt" 2>"$rct_results/help.stderr" &&
   grep 'Run test/test_all.sh' "$rct_results/help.txt" >/dev/null 2>&1 &&
   grep 'Run one fresh run_all.sh collection' "$rct_results/help.txt" >/dev/null 2>&1 &&
   grep 'passive' "$rct_results/help.txt" >/dev/null 2>&1; then
    pass "run_complete.sh help documents test, collection, reports and passive profiling"
else fail "run_complete.sh help contract"; fi

if grep -E '\$app_dir/measure_(osnoise|timerlat|kvm_exits|qemu_perf|irqsoff|hwlat)\.sh' "$app_dir/run_complete.sh" >/dev/null 2>&1; then
    fail "run_complete.sh must not execute intrusive/opt-in measurement tools"
else
    pass "run_complete.sh contains no automatic measurement-tool execution"
fi

if [ -z "$rct_fixture" ] || [ ! -r "$rct_fixture/inventory.json" ]; then
    fail "retained live fixture supplied by test_all.sh"
else
    pass "retained live fixture supplied by test_all.sh"
fi

# Older fixture sources used outside test_all may predate timing instrumentation.
# For this replay-safe test, synthesize only timing metadata when it is missing;
# collector evidence itself is never altered.
rct_work_fixture=$rct_results/fixture
mkdir -p "$rct_work_fixture" || exit 2
cp -a "$rct_fixture"/. "$rct_work_fixture"/ || exit 2
if [ ! -r "$rct_work_fixture/collector-timings.tsv" ]; then
    {
        printf 'collector\tcollection_ms\tsummary_ms\ttotal_ms\tcollector_rc\tsummary_rc\tsuccess\n'
        find "$app_dir" -maxdepth 1 -type f -name 'collect_*.sh' -printf '%f\n' 2>/dev/null | sort |
        while IFS= read -r rct_c; do printf '%s\t1\t0\t1\t0\t0\ttrue\n' "$rct_c"; done
    } > "$rct_work_fixture/collector-timings.tsv"
fi
if [ ! -r "$rct_work_fixture/run-timings.tsv" ]; then
    {
        printf 'phase\telapsed_ms\n'
        printf 'preparation\t0\ncollectors\t38\nfinalization\t1\ntotal\t39\n'
    } > "$rct_work_fixture/run-timings.tsv"
fi

rct_before=$(sha256sum "$rct_work_fixture/inventory.json" | awk '{print $1}')
rct_reports=$rct_results/reports
if "$app_dir/run_complete.sh" --from-run "$rct_work_fixture" --reports-dir "$rct_reports" --no-color >"$rct_results/run_complete.stdout" 2>"$rct_results/run_complete.stderr"; then
    pass "reports-only complete workflow"
else
    fail "reports-only complete workflow"
fi
rct_after=$(sha256sum "$rct_work_fixture/inventory.json" | awk '{print $1}')
if [ "$rct_before" = "$rct_after" ]; then pass "reports-only mode leaves collector inventory unchanged"; else fail "reports-only mode mutated inventory"; fi

rct_expected_files="
host-map.json
report-model.json
desktop-evaluation.json
view-all.txt
host-short.txt
host-dense-summary.txt
host-dense.txt
desktop-short.txt
desktop-dense-summary.txt
desktop-dense.txt
desktop-evaluation.txt
view-all.html
host-short.html
host-dense-summary.html
host-dense.html
desktop-short.html
desktop-dense-summary.html
desktop-dense.html
desktop-evaluation.html
workflow-timings.tsv
performance.txt
performance.json
performance.html
"
rct_missing=0
for rct_f in $rct_expected_files; do
    [ -s "$rct_reports/$rct_f" ] || { printf 'missing: %s\n' "$rct_f" >>"$rct_results/missing-files.log"; rct_missing=1; }
done
if [ "$rct_missing" -eq 0 ]; then pass "complete report artifact set"; else fail "complete report artifact set"; fi

if jq -e '.model=="performance-timing" and .schema_version=="0.1.0" and .measurement.kind=="passive-wall-clock" and .measurement.extra_workload==false and (.collectors|length)==38' "$rct_reports/performance.json" >/dev/null 2>&1; then
    pass "machine-readable passive performance model"
else fail "performance JSON contract"; fi

if grep -i '<!doctype html>' "$rct_reports/performance.html" >/dev/null 2>&1 &&
   grep 'id="search"' "$rct_reports/performance.html" >/dev/null 2>&1 &&
   ! grep -E '<(script|link)[^>]+https?://' "$rct_reports/performance.html" >/dev/null 2>&1; then
    pass "self-contained interactive performance HTML"
else fail "performance HTML contract"; fi

if awk -F '\t' '
  NR==1 {ok=($1=="phase" && $2=="elapsed_ms"); next}
  $1=="harmonization_once"{h=1}
  $1=="text_reports"{t=1}
  $1=="html_reports"{x=1}
  $1=="total"{z=1}
  END{exit !(ok&&h&&t&&x&&z)}
' "$rct_reports/workflow-timings.tsv"; then
    pass "complete workflow timing artifact"
else fail "workflow-timings.tsv contract"; fi

if jq -e '.model=="desktop-evaluation" and (.findings|length)>=20' "$rct_reports/desktop-evaluation.json" >/dev/null 2>&1; then
    pass "complete workflow includes Layer 3 evaluation"
else fail "complete workflow evaluation artifact"; fi

if grep 'Exact saved-data replay of view_all.sh' "$rct_reports/view-all.html" >/dev/null 2>&1 &&
   grep 'Unique normalized events' "$rct_reports/view-all.txt" >/dev/null 2>&1; then
    pass "complete workflow includes view_all text and HTML replay"
else fail "view_all replay artifacts"; fi

{
    printf 'Host Inventory for Proxmox - complete workflow test report\n'
    printf 'Test version: 1.0.0\n'
    printf 'Pass validations: %s\n' "$rct_pass"
    printf 'Failed validations: %s\n' "$rct_fail"
    if [ "$rct_fail" -eq 0 ]; then rct_rc=0; else rct_rc=1; fi
    printf 'Return code: %s\n' "$rct_rc"
} > "$rct_results/report.txt"

if [ "$rct_fail" -eq 0 ]; then
    printf 'RESULT: complete workflow layer passed (%s validations).\n' "$rct_pass"
else
    printf 'RESULT: complete workflow layer failed (%s pass / %s fail).\n' "$rct_pass" "$rct_fail"
fi
printf 'Test results kept at: %s\n' "$rct_results"
exit "$rct_rc"
