#!/bin/sh
# ============================================================
# measurement_tools_test.sh
# Tests opt-in measurement-tool interfaces and safety gates
# without running any real tracing or performance measurement.
#
# Version:
#   1.0.0
# ============================================================
app_rc=0
mt_test_version=1.0.0
app_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd -P) || exit 2
mt_timestamp=$(date '+%Y%m%d-%H%M%S')
if [ -n "${HFIP_TEST_RESULTS_PARENT-}" ]; then mt_results=$HFIP_TEST_RESULTS_PARENT/measurement_tools_test; else mt_results=$app_dir/test/results/${mt_timestamp}-measurement_tools_test-$$; fi
mt_log=$mt_results/test.log
mt_pass=0
mt_fail=0
mkdir -p "$mt_results" || exit 2
: > "$mt_log" || exit 2
mt_Log(){ printf '%s\n' "$*"; printf '%s\n' "$*" >>"$mt_log"; }
mt_Pass(){ mt_pass=$((mt_pass+1)); mt_Log "PASS  $*"; }
mt_Fail(){ mt_fail=$((mt_fail+1)); app_rc=1; mt_Log "FAIL  $*"; }

mt_Log "Host Inventory for Proxmox - measurement tool safety/interface tests"
mt_Log "Results directory: $mt_results"
for mt_name in measure_osnoise measure_timerlat measure_kvm_exits measure_qemu_perf measure_irqsoff measure_hwlat; do
    mt_script=$app_dir/$mt_name.sh
    mt_dir=$mt_results/$mt_name
    mkdir -p "$mt_dir"
    mt_Log "Testing $mt_name"
    sh -n "$mt_script" && mt_Pass "$mt_name syntax" || mt_Fail "$mt_name syntax"
    "$mt_script" --help >"$mt_dir/help.txt" 2>"$mt_dir/help.stderr" && mt_Pass "$mt_name --help" || mt_Fail "$mt_name --help"
    "$mt_script" --version >"$mt_dir/version.txt" 2>"$mt_dir/version.stderr" && mt_Pass "$mt_name --version" || mt_Fail "$mt_name --version"
    case "$mt_name" in
        measure_osnoise|measure_timerlat)
            "$mt_script" --dry-run --duration 1 --cpus 0 >"$mt_dir/dry-run.txt" 2>"$mt_dir/dry-run.stderr"
            ;;
        measure_kvm_exits|measure_qemu_perf)
            "$mt_script" --dry-run --duration 1 --vmid 999 >"$mt_dir/dry-run.txt" 2>"$mt_dir/dry-run.stderr"
            ;;
        measure_irqsoff)
            "$mt_script" --dry-run --duration 1 >"$mt_dir/unacked.txt" 2>"$mt_dir/unacked.stderr"; mt_unacked=$?
            [ "$mt_unacked" -ne 0 ] && mt_Pass "$mt_name refuses unacknowledged tracing" || mt_Fail "$mt_name missing acknowledgement gate"
            "$mt_script" --dry-run --ack-tracing --duration 1 >"$mt_dir/dry-run.txt" 2>"$mt_dir/dry-run.stderr"
            ;;
        measure_hwlat)
            "$mt_script" --dry-run --duration 1 >"$mt_dir/unacked.txt" 2>"$mt_dir/unacked.stderr"; mt_unacked=$?
            [ "$mt_unacked" -ne 0 ] && mt_Pass "$mt_name refuses unacknowledged intrusive tracing" || mt_Fail "$mt_name missing intrusive acknowledgement gate"
            "$mt_script" --dry-run --ack-intrusive --duration 1 >"$mt_dir/dry-run.txt" 2>"$mt_dir/dry-run.stderr"
            ;;
    esac
    mt_dry_rc=$?
    if [ "$mt_dry_rc" -eq 0 ] && grep '^DRY-RUN:' "$mt_dir/dry-run.txt" >/dev/null 2>&1; then mt_Pass "$mt_name dry-run"; else mt_Fail "$mt_name dry-run rc=$mt_dry_rc"; fi
    "$mt_script" --definitely-invalid >"$mt_dir/invalid.txt" 2>"$mt_dir/invalid.stderr"; mt_invalid=$?
    [ "$mt_invalid" -ne 0 ] && mt_Pass "$mt_name invalid option rejected" || mt_Fail "$mt_name invalid option accepted"
done
if ! grep -R 'measure_.*\.sh' "$app_dir/run_all.sh" "$app_dir/view_all.sh" >/dev/null 2>&1; then mt_Pass "measurement programs are absent from normal orchestration"; else mt_Fail "measurement program leaked into normal orchestration"; fi
{
  printf 'Host Inventory for Proxmox - measurement tool test report\n'
  printf 'Test version: %s\nPass validations: %s\nFailed validations: %s\nReturn code: %s\nResults directory: %s\n' "$mt_test_version" "$mt_pass" "$mt_fail" "$app_rc" "$mt_results"
} >"$mt_results/report.txt"
[ "$app_rc" -eq 0 ] && mt_Log "RESULT: measurement tools passed ($mt_pass validations)." || mt_Log "RESULT: measurement tools failed ($mt_fail validation(s))."
mt_Log "Test results kept at: $mt_results"
exit "$app_rc"
