#!/bin/sh
# ============================================================
# compare_hosts_test.sh
# Tests descriptive cross-host comparison over harmonized maps.
# Version: 1.1.0
# ============================================================
app_rc=0
app_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd -P) || exit 2
cht_timestamp=$(date '+%Y%m%d-%H%M%S')
if [ -n "${HFIP_TEST_RESULTS_PARENT-}" ]; then cht_results=$HFIP_TEST_RESULTS_PARENT/compare_hosts_test; else cht_results=$app_dir/test/results/${cht_timestamp}-compare_hosts_test-$$; fi
mkdir -p "$cht_results" || exit 2
cht_pass=0; cht_fail=0
cht_passf(){ cht_pass=$((cht_pass+1)); printf 'PASS  %s\n' "$*"; }
cht_failf(){ cht_fail=$((cht_fail+1)); app_rc=1; printf 'FAIL  %s\n' "$*"; }

printf 'Host Inventory for Proxmox - cross-host comparison tests\n'
if sh -n "$app_dir/compare_hosts.sh"; then cht_passf "shell syntax"; else cht_failf "shell syntax"; fi
"$app_dir/compare_hosts.sh" --help >"$cht_results/help.txt" 2>"$cht_results/help.err" && cht_passf "--help" || cht_failf "--help"
"$app_dir/compare_hosts.sh" --version >"$cht_results/version.txt" 2>"$cht_results/version.err" && cht_passf "--version" || cht_failf "--version"

if [ -n "${HFIP_TEST_FIXTURE_DIR-}" ] && [ -d "$HFIP_TEST_FIXTURE_DIR" ]; then cht_fixture=$HFIP_TEST_FIXTURE_DIR; else
  cht_fixture=$cht_results/inventory
  HFIP_LATENCY_SAMPLE_DURATION=1 "$app_dir/run_all.sh" --skip-prepare --no-install --no-color --output "$cht_fixture" >"$cht_results/run_all.out" 2>"$cht_results/run_all.err" || cht_failf "fixture creation"
fi
"$app_dir/harmonize_host.sh" --from-run "$cht_fixture" --source-kind test-fixture --no-install --no-color --output "$cht_results/left.json" >"$cht_results/harmonize.out" 2>"$cht_results/harmonize.err" && cht_passf "left host-map" || cht_failf "left host-map"
if [ -s "$cht_results/left.json" ]; then
  jq '.source.hostname="comparison-right" | .cpu.logical_cpu_count=(.cpu.logical_cpu_count+2) | .capability_matrix.display.connected=(.capability_matrix.display.connected+1)' "$cht_results/left.json" > "$cht_results/right.json"
fi
"$app_dir/compare_hosts.sh" --left "$cht_results/left.json" --right "$cht_results/right.json" --json >"$cht_results/compare.json" 2>"$cht_results/compare.err" && cht_passf "JSON comparison execution" || cht_failf "JSON comparison execution"
if jq -e '.left.host!=.right.host and ([.differences[]|select(.field=="cpu.logical" and .different==true)]|length)==1 and ([.differences[]|select(.field=="display.connected" and .different==true)]|length)==1' "$cht_results/compare.json" >/dev/null 2>&1; then cht_passf "difference contract"; else cht_failf "difference contract"; fi
"$app_dir/compare_hosts.sh" --left "$cht_results/left.json" --right "$cht_results/right.json" --no-color >"$cht_results/compare.txt" 2>"$cht_results/compare-text.err" && cht_passf "human comparison execution" || cht_failf "human comparison execution"
if grep 'cpu.logical' "$cht_results/compare.txt" >/dev/null 2>&1 && grep 'different=true' "$cht_results/compare.txt" >/dev/null 2>&1; then cht_passf "human comparison layout"; else cht_failf "human comparison layout"; fi
"$app_dir/compare_hosts.sh" --left "$cht_results/left.json" --right "$cht_results/left.json" --json >"$cht_results/same.json" 2>/dev/null
if jq -e 'all(.differences[]; .different==false)' "$cht_results/same.json" >/dev/null 2>&1; then cht_passf "identical-map comparison"; else cht_failf "identical-map comparison"; fi
"$app_dir/compare_hosts.sh" --left "$cht_results/missing.json" --right "$cht_results/right.json" >/dev/null 2>&1; cht_bad=$?; if [ "$cht_bad" -ne 0 ]; then cht_passf "missing input rejected"; else cht_failf "missing input rejected"; fi
"$app_dir/compare_hosts.sh" --definitely-invalid >/dev/null 2>&1; cht_bad=$?; if [ "$cht_bad" -ne 0 ]; then cht_passf "invalid option rejected"; else cht_failf "invalid option rejected"; fi
{
  printf 'Host Inventory for Proxmox - compare-hosts test report\nTest version: 1.0.0\nPass validations: %s\nFailed validations: %s\nReturn code: %s\nResults directory: %s\n' "$cht_pass" "$cht_fail" "$app_rc" "$cht_results"
} > "$cht_results/report.txt"
if [ "$app_rc" -eq 0 ]; then printf 'RESULT: compare-hosts tests passed (%s validations).\n' "$cht_pass"; else printf 'RESULT: compare-hosts tests failed (%s failed).\n' "$cht_fail"; fi
exit "$app_rc"
