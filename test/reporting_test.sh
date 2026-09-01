#!/bin/sh
# ============================================================
# reporting_test.sh
# Tests descriptive terminal/HTML reporting and Layer 3 evaluation.
#
# Version:
#   1.1.0
# ============================================================
app_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd -P) || exit 2
rt_parent=${HFIP_TEST_RESULTS_PARENT-}
rt_stamp=$(date '+%Y%m%d-%H%M%S')
if [ -n "$rt_parent" ]; then rt_results=$rt_parent/reporting_test; else rt_results=$app_dir/test/results/${rt_stamp}-reporting_test-$$; fi
rt_fixture=${HFIP_TEST_FIXTURE_DIR-}
rt_pass=0
rt_fail=0
mkdir -p "$rt_results" || exit 2
rt_log=$rt_results/test.log
: >"$rt_log" || exit 2

if [ -t 1 ] && [ -z "${NO_COLOR-}" ]; then rt_reset=$(printf '\033[0m'); rt_ok=$(printf '\033[92m'); rt_bad=$(printf '\033[91m'); rt_info=$(printf '\033[96m'); else rt_reset=; rt_ok=; rt_bad=; rt_info=; fi
pass(){ rt_pass=$((rt_pass+1)); printf '%sPASS%s  %s\n' "$rt_ok" "$rt_reset" "$*" | tee -a "$rt_log"; }
fail(){ rt_fail=$((rt_fail+1)); printf '%sFAIL%s  %s\n' "$rt_bad" "$rt_reset" "$*" | tee -a "$rt_log"; }
printf '%sHost Inventory for Proxmox - reporting/evaluation tests%s\n' "$rt_info" "$rt_reset"

for f in build_report_model.sh report_host.sh report_desktop.sh evaluate_desktop.sh report_desktop_evaluation.sh report_html.sh; do
    if sh -n "$app_dir/$f"; then pass "$f syntax"; else fail "$f syntax"; fi
done

if grep -E -- 'as[[:space:]]+\$(module|end|label)([^[:alnum:]_]|$)|def[[:space:]][[:alnum:]_]+[[:space:]]*\([^)]*\$(module|end|label)([^[:alnum:]_]|$)|--arg(json)?[[:space:]]+(module|end)([[:space:]]|$)' \
    "$app_dir/build_report_model.sh" "$app_dir/report_host.sh" "$app_dir/report_desktop.sh" "$app_dir/evaluate_desktop.sh" "$app_dir/report_desktop_evaluation.sh" "$app_dir/report_html.sh" >/dev/null 2>&1; then
    fail "reporting jq 1.6 known reserved-binder compatibility"
else
    pass "reporting jq 1.6 known reserved-binder compatibility"
fi

for f in build_report_model.sh report_host.sh report_desktop.sh evaluate_desktop.sh report_desktop_evaluation.sh report_html.sh; do
    if [ "$("$app_dir/$f" --version 2>/dev/null)" = "${f%.sh} 0.9.2" ]; then pass "$f --version"; else fail "$f --version"; fi
done

if [ -z "$rt_fixture" ] || [ ! -r "$rt_fixture/inventory.json" ]; then
    rt_fixture=$rt_results/live-fixture
    if "$app_dir/run_all.sh" --output-dir "$rt_fixture" --no-install --skip-prepare >/dev/null 2>"$rt_results/run_all.stderr"; then
        pass "standalone live fixture"
    else
        fail "standalone live fixture"
    fi
else
    pass "reused supplied 38-collector fixture"
fi

rt_map=$rt_results/host-map.json
if "$app_dir/harmonize_host.sh" --from-run "$rt_fixture" --output "$rt_map" --no-color >/dev/null 2>"$rt_results/harmonize.stderr"; then pass "host-map for reports"; else fail "host-map for reports"; fi

rt_model=$rt_results/report-model.json
if "$app_dir/build_report_model.sh" --file "$rt_map" --output "$rt_model" >/dev/null 2>"$rt_results/model.stderr" &&
   jq -e '.model=="report-model" and .schema_version=="0.1.0" and (.reports.general.short|length)>0 and (.reports.general.dense|length)>0 and (.reports.desktop.short|length)>0 and (.reports.desktop.dense|length)>0' "$rt_model" >/dev/null 2>&1; then
    pass "descriptive report-model schema"
else fail "descriptive report-model schema"; fi

if ! grep -E '"status"[[:space:]]*:[[:space:]]*"(PASS|WARN|FAIL|UNKNOWN)"' "$rt_model" >/dev/null 2>&1; then
    pass "descriptive model contains no evaluator verdicts"
else fail "descriptive model leaked evaluator verdicts"; fi

if jq -e '([.reports.general.short[].rows[]]|length) < ([.reports.general.dense[].rows[]]|length) and ([.reports.desktop.short[].rows[]]|length) < ([.reports.desktop.dense[].rows[]]|length)' "$rt_model" >/dev/null 2>&1; then
    pass "short versus dense depth ordering"
else fail "short versus dense depth ordering"; fi

for spec in "report_host.sh --short host-short" "report_host.sh --dense-summary host-dense-summary" "report_host.sh --dense host-dense" "report_desktop.sh --short desktop-short" "report_desktop.sh --dense-summary desktop-dense-summary" "report_desktop.sh --dense desktop-dense"; do
    set -- $spec
    rt_script=$1; rt_style=$2; rt_name=$3
    if "$app_dir/$rt_script" --file "$rt_map" "$rt_style" --no-color >"$rt_results/$rt_name.txt" 2>"$rt_results/$rt_name.stderr" &&
       [ -s "$rt_results/$rt_name.txt" ] && ! grep "$(printf '\033')" "$rt_results/$rt_name.txt" >/dev/null 2>&1; then
        pass "$rt_name terminal rendering"
    else fail "$rt_name terminal rendering"; fi
done

if "$app_dir/report_host.sh" --file "$rt_map" --dense-summary --color >"$rt_results/host.color.txt" 2>/dev/null &&
   grep "$(printf '\033')" "$rt_results/host.color.txt" >/dev/null 2>&1; then pass "descriptive forced color"; else fail "descriptive forced color"; fi

rt_eval=$rt_results/desktop-evaluation.json
if "$app_dir/evaluate_desktop.sh" --file "$rt_map" --output "$rt_eval" >/dev/null 2>"$rt_results/eval.stderr" &&
   jq -e '.model=="desktop-evaluation" and .schema_version=="0.1.0" and (.findings|length)>=20 and (.summary.total==(.findings|length))' "$rt_eval" >/dev/null 2>&1; then
    pass "desktop evaluation schema"
else fail "desktop evaluation schema"; fi

if jq -e 'all(.findings[]; (.status=="PASS" or .status=="WARN" or .status=="FAIL" or .status=="UNKNOWN") and (.severity|type=="string") and (.confidence|type=="string") and (.evidence|type=="array") and (.recommendation|type=="string") and (.rationale|type=="string"))' "$rt_eval" >/dev/null 2>&1; then
    pass "finding evidence/severity/confidence/recommendation contract"
else fail "finding evidence/severity/confidence/recommendation contract"; fi

if jq -e '[.findings[]|select(.scope=="measurement-gap" and .status=="UNKNOWN")]|length>=2' "$rt_eval" >/dev/null 2>&1; then
    pass "measurement gaps remain UNKNOWN"
else fail "measurement gaps remain UNKNOWN"; fi

if grep -E 'collect_[[:alnum:]_]+\.sh|run_all\.sh' "$app_dir/evaluate_desktop.sh" >/dev/null 2>&1; then
    fail "evaluator source contains live collector orchestration"
else pass "evaluator consumes host-map only"; fi

rt_partial=$rt_results/partial-map.json
jq '.cpu.isolation=null | .cpu.timers_watchdogs.watchdog.nmi_watchdog=null' "$rt_map" >"$rt_partial"
if "$app_dir/evaluate_desktop.sh" --file "$rt_partial" >"$rt_results/partial-eval.json" 2>/dev/null &&
   jq -e '.findings[]|select(.id=="cpu-isolation" and .status=="UNKNOWN")' "$rt_results/partial-eval.json" >/dev/null 2>&1; then
    pass "missing evidence becomes UNKNOWN"
else fail "missing evidence becomes UNKNOWN"; fi

if "$app_dir/report_desktop_evaluation.sh" --file "$rt_map" --no-color >"$rt_results/eval.txt" 2>/dev/null &&
   grep -E '^Findings: .*FAIL=.*WARN=.*UNKNOWN=.*PASS=' "$rt_results/eval.txt" >/dev/null 2>&1 &&
   grep 'Recommendation\|Action:' "$rt_results/eval.txt" >/dev/null 2>&1; then
    pass "complete terminal evaluation layout"
else fail "complete terminal evaluation layout"; fi

if "$app_dir/report_desktop_evaluation.sh" --file "$rt_map" --color >"$rt_results/eval.color.txt" 2>/dev/null &&
   grep "$(printf '\033')" "$rt_results/eval.color.txt" >/dev/null 2>&1; then pass "evaluation forced color"; else fail "evaluation forced color"; fi

rt_html_modes="short dense-summary dense desktop-short desktop-dense-summary desktop-dense desktop-evaluation"
for rt_mode in $rt_html_modes; do
    rt_html=$rt_results/$rt_mode.html
    if "$app_dir/report_html.sh" --file "$rt_map" --mode "$rt_mode" --output "$rt_html" >/dev/null 2>"$rt_results/$rt_mode.html.stderr" &&
       grep -i '<!doctype html>' "$rt_html" >/dev/null 2>&1 &&
       grep 'id="search"' "$rt_html" >/dev/null 2>&1 &&
       ! grep -E '<(script|link)[^>]+https?://' "$rt_html" >/dev/null 2>&1; then
        pass "$rt_mode interactive self-contained HTML"
    else fail "$rt_mode interactive self-contained HTML"; fi
done

rt_all_html=$rt_results/all.html
if "$app_dir/report_html.sh" --from-run "$rt_fixture" --mode all --output "$rt_all_html" >/dev/null 2>"$rt_results/all.html.stderr" &&
   grep 'Exact saved-data replay of view_all.sh' "$rt_all_html" >/dev/null 2>&1 &&
   grep 'id="search"' "$rt_all_html" >/dev/null 2>&1; then
    pass "view_all-equivalent interactive HTML"
else fail "view_all-equivalent interactive HTML"; fi

{
    printf 'Host Inventory for Proxmox - reporting/evaluation test report\n'
    printf 'Test version: 1.1.0\n'
    printf 'Pass validations: %s\n' "$rt_pass"
    printf 'Failed validations: %s\n' "$rt_fail"
    if [ "$rt_fail" -eq 0 ]; then rt_rc=0; else rt_rc=1; fi
    printf 'Return code: %s\n' "$rt_rc"
} >"$rt_results/report.txt"
if [ "$rt_fail" -eq 0 ]; then printf 'RESULT: reporting/evaluation layer passed (%s validations).\n' "$rt_pass"; else printf 'RESULT: reporting/evaluation layer failed (%s pass / %s fail).\n' "$rt_pass" "$rt_fail"; fi
printf 'Test results kept at: %s\n' "$rt_results"
exit "$rt_rc"
