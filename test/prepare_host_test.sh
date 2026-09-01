#!/bin/sh
# ============================================================
# prepare_host_test.sh
# Tests preparation interfaces while preserving test evidence.
#
# Version:
#   1.3.0
#
# Last Change:
#   Added narrated stages and persistent timestamped results.
#
# Returns:
#   0 when preparation command tests pass
#   1 otherwise
# ============================================================
app_rc=0
app_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd -P) || exit 2
pt_script=$app_dir/prepare_host.sh
pt_timestamp=$(date '+%Y%m%d-%H%M%S')
if [ -n "${HFIP_TEST_RESULTS_PARENT-}" ]; then pt_results=$HFIP_TEST_RESULTS_PARENT/prepare_host_test; else pt_results=$app_dir/test/results/${pt_timestamp}-prepare_host_test-$$; fi
pt_log=$pt_results/test.log
pt_pass_count=0
pt_fail_count=0
mkdir -p "$pt_results" || exit 2
: > "$pt_log" || exit 2

pt_ColorInit() { if [ -t 1 ] && [ -z "${NO_COLOR-}" ]; then pt_reset=$(printf '\033[0m'); pt_info=$(printf '\033[96m'); pt_ok=$(printf '\033[92m'); pt_error=$(printf '\033[91m'); pt_title=$(printf '\033[1;96m'); else pt_reset=; pt_info=; pt_ok=; pt_error=; pt_title=; fi; return 0; }
pt_Log() { ptl_role=$1; shift; case "$ptl_role" in title) ptl_color=$pt_title;; info) ptl_color=$pt_info;; ok) ptl_color=$pt_ok;; error) ptl_color=$pt_error;; *) ptl_color=;; esac; printf '%s%s%s\n' "$ptl_color" "$*" "$pt_reset"; printf '%s\n' "$*" >> "$pt_log"; return 0; }
pt_Pass() { pt_pass_count=$((pt_pass_count+1)); pt_Log ok "PASS  $*"; }
pt_Fail() { pt_fail_count=$((pt_fail_count+1)); app_rc=1; pt_Log error "FAIL  $*"; }

pt_ColorInit
pt_Log title "Host Inventory for Proxmox - prepare_host.sh test"
pt_Log info "Results directory: $pt_results"
pt_Log info "[1/8] Checking shell syntax"
if sh -n "$pt_script" >"$pt_results/syntax.stdout.log" 2>"$pt_results/syntax.stderr.log"; then pt_Pass "shell syntax"; else pt_Fail "shell syntax"; fi
pt_Log info "[2/8] Checking --help"
if "$pt_script" --help --no-color >"$pt_results/help.txt" 2>"$pt_results/help.stderr.log"; then pt_Pass "--help"; else pt_Fail "--help"; fi
pt_Log info "[3/8] Checking --version"
if "$pt_script" --version --no-color >"$pt_results/version.txt" 2>"$pt_results/version.stderr.log"; then pt_Pass "--version"; else pt_Fail "--version"; fi
pt_Log info "[4/8] Checking expanded diagnostic dependency policy"
if grep 'dmidecode:dmidecode:optional' "$pt_script" >/dev/null 2>&1 && grep 'acpidump:acpica-tools:optional' "$pt_script" >/dev/null 2>&1 && grep 'lsusb:usbutils:optional' "$pt_script" >/dev/null 2>&1 && grep 'aplay:alsa-utils:optional' "$pt_script" >/dev/null 2>&1 && grep 'decode-dimms:i2c-tools:optional' "$pt_script" >/dev/null 2>&1 && ! grep -E 'fwupdmgr:|smartctl:|iasl:' "$pt_script" >/dev/null 2>&1; then
    pt_Pass "expanded safe dependency set present; service-bearing capability-only tools excluded"
else
    pt_Fail "expanded dependency policy"
fi
pt_Log info "[5/8] Checking opt-in measurement dependency policy"
if grep 'rtla:rtla:optional' "$pt_script" >/dev/null 2>&1 && grep 'perf:linux-perf:optional' "$pt_script" >/dev/null 2>&1 && ! grep -E 'rtla:rtla:required|perf:linux-perf:required' "$pt_script" >/dev/null 2>&1; then
    pt_Pass "rtla/linux-perf are safe optional measurement dependencies"
else
    pt_Fail "measurement dependency policy"
fi
pt_Log info "[6/8] Checking no-install preparation path"
"$pt_script" --no-install --no-color >"$pt_results/no-install.stdout.log" 2>"$pt_results/no-install.stderr.log"; pt_rc=$?
if [ "$pt_rc" -eq 0 ] || [ "$pt_rc" -eq 2 ]; then pt_Pass "--no-install returned documented rc=$pt_rc"; else pt_Fail "--no-install unexpected rc=$pt_rc"; fi
pt_Log info "[7/8] Checking forced-color output"
"$pt_script" --no-install --color >"$pt_results/color.stdout.log" 2>"$pt_results/color.stderr.log"; pt_color_rc=$?
if { [ "$pt_color_rc" -eq 0 ] || [ "$pt_color_rc" -eq 2 ]; } && grep "$(printf '\033')" "$pt_results/color.stdout.log" "$pt_results/color.stderr.log" >/dev/null 2>&1; then pt_Pass "forced color emits ANSI"; else pt_Fail "forced-color behavior rc=$pt_color_rc"; fi
pt_Log info "[8/8] Checking invalid-option handling"
"$pt_script" --definitely-invalid-option --no-color >"$pt_results/invalid.stdout.log" 2>"$pt_results/invalid.stderr.log"; pt_invalid_rc=$?
if [ "$pt_invalid_rc" -ne 0 ]; then pt_Pass "invalid option rejected (rc=$pt_invalid_rc)"; else pt_Fail "invalid option accepted"; fi
{
    printf 'Host Inventory for Proxmox - prepare_host.sh test report\n'
    printf 'Pass validations: %s\nFailed validations: %s\nReturn code: %s\nResults directory: %s\n' "$pt_pass_count" "$pt_fail_count" "$app_rc" "$pt_results"
} > "$pt_results/report.txt"
if [ "$app_rc" -eq 0 ]; then pt_Log ok "RESULT: prepare_host.sh test passed ($pt_pass_count validations)."; else pt_Log error "RESULT: prepare_host.sh test failed ($pt_fail_count failed validation(s))."; fi
pt_Log info "Test results kept at: $pt_results"
exit "$app_rc"
