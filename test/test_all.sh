#!/bin/sh
# ============================================================
# test_all.sh
# Runs every Host Inventory for Proxmox focused test and groups
# all persistent evidence under one timestamped result directory.
#
# Version:
#   2.2.0
#
# Last Change:
#   Adds complete-workflow/passive-performance coverage while retaining one authoritative live collector fixture.
#
# Returns:
#   0 when every focused test script succeeds
#   1 otherwise
# ============================================================
app_rc=0
app_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || exit 2
ta_root=$(CDPATH= cd -- "$app_dir/.." 2>/dev/null && pwd -P) || exit 2
ta_timestamp=$(date '+%Y%m%d-%H%M%S')
ta_results=$ta_root/test/results/${ta_timestamp}-test_all-$$
ta_log=$ta_results/test_all.log
ta_timings=$ta_results/timings.tsv
ta_started_epoch=$(date '+%s' 2>/dev/null || printf '0')
mkdir -p "$ta_results" || exit 2
: > "$ta_log" || exit 2
printf 'test\tseconds\n' > "$ta_timings" || exit 2

if [ -t 1 ] && [ -z "${NO_COLOR-}" ]; then ta_reset=$(printf '\033[0m'); ta_title=$(printf '\033[1;96m'); ta_info=$(printf '\033[96m'); ta_ok=$(printf '\033[92m'); ta_error=$(printf '\033[91m'); else ta_reset=; ta_title=; ta_info=; ta_ok=; ta_error=; fi
printf '%sHost Inventory for Proxmox - complete test suite%s\n' "$ta_title" "$ta_reset"
printf '%sResults directory: %s%s\n' "$ta_info" "$ta_results" "$ta_reset"
printf 'Results directory: %s\n' "$ta_results" >> "$ta_log"

for ta_test in prepare_host_test.sh run_all_test.sh extended_domains_test.sh depth_domains_test.sh collectors_test.sh view_scripts_test.sh harmonize_host_test.sh desktop_vm_view_test.sh compare_hosts_test.sh reporting_test.sh run_complete_test.sh measurement_tools_test.sh; do
    ta_test_started=$(date '+%s' 2>/dev/null || printf '0')
    printf '\n%s=== Running %s ===%s\n' "$ta_info" "$ta_test" "$ta_reset"
    printf '\n=== Running %s ===\n' "$ta_test" >> "$ta_log"
    case "$ta_test" in
        extended_domains_test.sh|depth_domains_test.sh|collectors_test.sh|view_scripts_test.sh|harmonize_host_test.sh|desktop_vm_view_test.sh|compare_hosts_test.sh|reporting_test.sh|run_complete_test.sh)
            if [ -d "$ta_results/run_all_test/inventory" ]; then
                HFIP_TEST_RESULTS_PARENT="$ta_results" HFIP_TEST_FIXTURE_DIR="$ta_results/run_all_test/inventory" "$app_dir/$ta_test" 2>&1 | tee "$ta_results/${ta_test%.sh}.console.log"
            else
                HFIP_TEST_RESULTS_PARENT="$ta_results" "$app_dir/$ta_test" 2>&1 | tee "$ta_results/${ta_test%.sh}.console.log"
            fi
            ;;
        *)
            HFIP_TEST_RESULTS_PARENT="$ta_results" "$app_dir/$ta_test" 2>&1 | tee "$ta_results/${ta_test%.sh}.console.log"
            ;;
    esac
    # POSIX sh has no PIPESTATUS; read the child result from its report when possible.
    case "$ta_test" in
        collectors_test.sh) ta_child_dir=$ta_results/collectors_test ;;
        extended_domains_test.sh) ta_child_dir=$ta_results/extended_domains_test ;;
        depth_domains_test.sh) ta_child_dir=$ta_results/depth_domains_test ;;
        view_scripts_test.sh) ta_child_dir=$ta_results/view_scripts_test ;;
        harmonize_host_test.sh) ta_child_dir=$ta_results/harmonize_host_test ;;
        prepare_host_test.sh) ta_child_dir=$ta_results/prepare_host_test ;;
        run_all_test.sh) ta_child_dir=$ta_results/run_all_test ;;
        desktop_vm_view_test.sh) ta_child_dir=$ta_results/desktop_vm_view_test ;;
        compare_hosts_test.sh) ta_child_dir=$ta_results/compare_hosts_test ;;
        reporting_test.sh) ta_child_dir=$ta_results/reporting_test ;;
        run_complete_test.sh) ta_child_dir=$ta_results/run_complete_test ;;
        measurement_tools_test.sh) ta_child_dir=$ta_results/measurement_tools_test ;;
    esac
    if [ -f "$ta_child_dir/report.txt" ]; then
        ta_child_rc=$(sed -n 's/^Return code: //p' "$ta_child_dir/report.txt" | tail -1)
    else
        ta_child_rc=1
    fi
    [ -n "$ta_child_rc" ] || ta_child_rc=1
    ta_test_finished=$(date '+%s' 2>/dev/null || printf '0')
    if [ "$ta_test_started" -gt 0 ] 2>/dev/null && [ "$ta_test_finished" -ge "$ta_test_started" ] 2>/dev/null; then
        ta_test_seconds=$((ta_test_finished - ta_test_started))
    else
        ta_test_seconds=0
    fi
    printf '%s\t%s\n' "$ta_test" "$ta_test_seconds" >> "$ta_timings"
    printf '%sDuration: %ss%s\n' "$ta_info" "$ta_test_seconds" "$ta_reset"
    printf 'Duration: %s %ss\n' "$ta_test" "$ta_test_seconds" >> "$ta_log"
    if [ "$ta_child_rc" -eq 0 ] 2>/dev/null; then
        printf '%sPASS: %s%s\n' "$ta_ok" "$ta_test" "$ta_reset"
        printf 'PASS: %s\n' "$ta_test" >> "$ta_log"
    else
        printf '%sFAIL: %s%s\n' "$ta_error" "$ta_test" "$ta_reset"
        printf 'FAIL: %s\n' "$ta_test" >> "$ta_log"
        app_rc=1
    fi
done

ta_finished_epoch=$(date '+%s' 2>/dev/null || printf '0')
if [ "$ta_started_epoch" -gt 0 ] 2>/dev/null && [ "$ta_finished_epoch" -ge "$ta_started_epoch" ] 2>/dev/null; then
    ta_total_seconds=$((ta_finished_epoch - ta_started_epoch))
else
    ta_total_seconds=0
fi
{
    printf 'Host Inventory for Proxmox - complete test suite report\n'
    printf '=======================================================\n'
    printf 'Results directory: %s\n' "$ta_results"
    printf 'Elapsed seconds: %s\n' "$ta_total_seconds"
    printf 'Return code: %s\n' "$app_rc"
    printf '\nPer-suite timings:\n'
    sed '1d' "$ta_timings" 2>/dev/null || :
} > "$ta_results/report.txt"

if [ "$app_rc" -eq 0 ]; then printf '\n%sRESULT: complete test suite passed.%s\n' "$ta_ok" "$ta_reset"; else printf '\n%sRESULT: complete test suite failed.%s\n' "$ta_error" "$ta_reset"; fi
printf '%sTest results kept at: %s%s\n' "$ta_info" "$ta_results" "$ta_reset"
exit "$app_rc"
