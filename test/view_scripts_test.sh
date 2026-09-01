#!/bin/sh
# ============================================================
# view_scripts_test.sh
# Tests every collector-backed dedicated view_*.sh program plus view_all.sh.
# Derived view_desktop_vm.sh is covered by desktop_vm_view_test.sh.
#
# Version:
#   2.0.0
#
# Environment:
#   HFIP_TEST_FIXTURE_DIR  optional existing run_all output directory
#                          used instead of creating a new fixture
#
# Output:
#   Narrated console progress and persistent test evidence.
#
# Returns:
#   0 when all view command tests pass
#   1 when one or more validations fail
# ============================================================
app_rc=0
HFIP_LATENCY_SAMPLE_DURATION=${HFIP_LATENCY_SAMPLE_DURATION:-1}
export HFIP_LATENCY_SAMPLE_DURATION
app_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd -P) || exit 2
vst_timestamp=$(date '+%Y%m%d-%H%M%S')
if [ -n "${HFIP_TEST_RESULTS_PARENT-}" ]; then vst_results=$HFIP_TEST_RESULTS_PARENT/view_scripts_test; else vst_results=$app_dir/test/results/${vst_timestamp}-view_scripts_test-$$; fi
vst_log=$vst_results/test.log
vst_fixture=$vst_results/fixture
vst_pass_count=0
vst_fail_count=0
vst_view_count=0
vst_expected_collectors=$(find "$app_dir" -maxdepth 1 -type f -name 'collect_*.sh' 2>/dev/null | wc -l | tr -d ' ')
vst_expected_views=$(find "$app_dir" -maxdepth 1 -type f -name 'view_*.sh' ! -name 'view_all.sh' ! -name 'view_harmonized_host.sh' ! -name 'view_desktop_vm.sh' 2>/dev/null | wc -l | tr -d ' ')
mkdir -p "$vst_results" || exit 2
: > "$vst_log" || exit 2

# ============================================================
# vst_ColorInit
# Defines semantic test colors.
#
# Version:
#   1.0.0
#
# Returns:
#   0
# ============================================================
vst_ColorInit() {
    if [ -t 1 ] && [ -z "${NO_COLOR-}" ]; then
        vst_reset=$(printf '\033[0m'); vst_title=$(printf '\033[1;96m'); vst_info=$(printf '\033[96m'); vst_ok=$(printf '\033[92m'); vst_error=$(printf '\033[91m')
    else
        vst_reset=; vst_title=; vst_info=; vst_ok=; vst_error=
    fi
    return 0
}

# ============================================================
# vst_Log
# Writes one test message to console and persistent log.
#
# Version:
#   1.0.0
#
# Returns:
#   0
# ============================================================
vst_Log() {
    vstl_role=$1
    shift
    case "$vstl_role" in
        title) vstl_color=$vst_title ;;
        info) vstl_color=$vst_info ;;
        ok) vstl_color=$vst_ok ;;
        error) vstl_color=$vst_error ;;
        *) vstl_color= ;;
    esac
    printf '%s%s%s\n' "$vstl_color" "$*" "$vst_reset"
    printf '%s\n' "$*" >> "$vst_log"
    return 0
}

# ============================================================
# vst_Pass
# Records one successful validation.
#
# Version:
#   1.0.0
# ============================================================
vst_Pass() {
    vst_pass_count=$((vst_pass_count+1))
    vst_Log ok "  PASS  $*"
    return 0
}

# ============================================================
# vst_Fail
# Records one failed validation.
#
# Version:
#   1.0.0
# ============================================================
vst_Fail() {
    vst_fail_count=$((vst_fail_count+1))
    app_rc=1
    vst_Log error "  FAIL  $*"
    return 0
}

vst_ColorInit
vst_Log title "Host Inventory for Proxmox - dedicated view-script tests"
vst_Log info "Results directory: $vst_results"

vst_Log info "[1/4] Preparing one collector fixture set"
if [ -n "${HFIP_TEST_FIXTURE_DIR-}" ]; then
    vst_fixture=$HFIP_TEST_FIXTURE_DIR
    if [ -d "$vst_fixture" ] && jq -e --argjson expected "$vst_expected_collectors" 'type=="array" and length==$expected' "$vst_fixture/inventory.json" >"$vst_results/fixture.validation.log" 2>&1; then
        vst_Pass "reused supplied fixture with $vst_expected_collectors collector envelopes"
    else
        vst_Fail "supplied fixture validation"
    fi
else
    if HFIP_LATENCY_SAMPLE_DURATION=1 "$app_dir/run_all.sh" --skip-prepare --no-install --no-color --output "$vst_fixture" >"$vst_results/run_all.stdout.log" 2>"$vst_results/run_all.stderr.log"; then
        if jq -e --argjson expected "$vst_expected_collectors" 'type=="array" and length==$expected' "$vst_fixture/inventory.json" >"$vst_results/fixture.validation.log" 2>&1; then vst_Pass "fixture contains $vst_expected_collectors collector envelopes"; else vst_Fail "fixture inventory validation"; fi
    else
        vst_Fail "run_all.sh fixture creation"
    fi
fi

vst_Log info "[2/4] Checking collector/view embedded implementation parity"
vst_parity_failures=
for vst_file in "$app_dir"/view_*.sh; do
    [ -f "$vst_file" ] || continue
    vst_name=${vst_file##*/}
    case "$vst_name" in view_all.sh|view_harmonized_host.sh|view_desktop_vm.sh) continue ;; esac
    vst_base=${vst_name%.sh}
    vst_aspect=${vst_base#view_}
    vst_collector=$app_dir/collect_$vst_aspect.sh
    vst_collect_chunk=$vst_results/parity-collect-$vst_aspect.txt
    vst_view_chunk=$vst_results/parity-view-$vst_aspect.txt
    if [ ! -f "$vst_collector" ]; then
        vst_parity_failures="${vst_parity_failures}${vst_parity_failures:+ }$vst_aspect:missing-collector"
        continue
    fi
    sed -n "/^collect_${vst_aspect}() {$/,/^# main$/p" "$vst_collector" > "$vst_collect_chunk"
    sed -n "/^collect_${vst_aspect}() {$/,/^# main$/p" "$vst_file" > "$vst_view_chunk"
    if [ ! -s "$vst_collect_chunk" ] || [ ! -s "$vst_view_chunk" ] || ! cmp -s "$vst_collect_chunk" "$vst_view_chunk"; then
        vst_parity_failures="${vst_parity_failures}${vst_parity_failures:+ }$vst_aspect"
    fi
done
if [ -z "$vst_parity_failures" ]; then
    vst_Pass "all 38 collector-backed views embed the same domain collection/rendering implementation as their companion collectors"
else
    vst_Fail "collector/view embedded implementation drift: $vst_parity_failures"
fi

vst_Log info "[3/4] Testing every standalone view_*.sh"
for vst_file in "$app_dir"/view_*.sh; do
    [ -f "$vst_file" ] || { vst_Fail "no view scripts found"; break; }
    vst_name=${vst_file##*/}
    case "$vst_name" in view_all.sh|view_harmonized_host.sh|view_desktop_vm.sh) continue ;; esac
    vst_view_count=$((vst_view_count+1))
    vst_base=${vst_name%.sh}
    vst_aspect=${vst_base#view_}
    vst_dir=$vst_results/$vst_base
    vst_json=$vst_fixture/collect_$vst_aspect.json
    mkdir -p "$vst_dir/isolated" || { vst_Fail "$vst_name result directory"; continue; }

    vst_Log info "[$vst_view_count/$vst_expected_views] Testing $vst_name"

    if sh -n "$vst_file" >"$vst_dir/syntax.stdout.log" 2>"$vst_dir/syntax.stderr.log"; then vst_Pass "$vst_name syntax"; else vst_Fail "$vst_name syntax"; fi
    if grep -E -- '--arg(json)?[[:space:]]+(module|end)([[:space:]]|$)' "$vst_file" >/dev/null 2>&1; then vst_Fail "$vst_name jq 1.6 known reserved external-variable compatibility"; else vst_Pass "$vst_name jq 1.6 known reserved external-variable compatibility"; fi
    if "$vst_file" --help --no-color >"$vst_dir/help.txt" 2>"$vst_dir/help.stderr.log"; then vst_Pass "$vst_name --help"; else vst_Fail "$vst_name --help"; fi
    if "$vst_file" --version --no-color >"$vst_dir/version.txt" 2>"$vst_dir/version.stderr.log"; then vst_Pass "$vst_name --version"; else vst_Fail "$vst_name --version"; fi

    if [ -s "$vst_json" ] && "$vst_file" --file "$vst_json" --no-install --no-color --quiet >"$vst_dir/quiet-view.txt" 2>"$vst_dir/quiet-view.stderr.log" && [ -s "$vst_dir/quiet-view.txt" ] && [ ! -s "$vst_dir/quiet-view.stderr.log" ]; then
        vst_Pass "$vst_name --quiet suppresses routine status"
    else
        vst_Fail "$vst_name --quiet"
    fi

    if [ -s "$vst_json" ] && "$vst_file" --file "$vst_json" --no-install --no-color >"$vst_dir/view.txt" 2>"$vst_dir/view.stderr.log" && [ -s "$vst_dir/view.txt" ] && [ ! -s "$vst_dir/view.stderr.log" ]; then
        vst_Pass "$vst_name --file clean view"
    else
        vst_Fail "$vst_name --file"
    fi
    if grep "$(printf '\033')" "$vst_dir/view.txt" >/dev/null 2>&1; then vst_Fail "$vst_name no-color view contains ANSI"; else vst_Pass "$vst_name no-color view is ANSI-free"; fi

    if [ -s "$vst_json" ] && "$vst_file" --file "$vst_json" --no-install --color >"$vst_dir/color-view.txt" 2>"$vst_dir/color-view.stderr.log" && grep "$(printf '\033')" "$vst_dir/color-view.txt" >/dev/null 2>&1; then
        vst_Pass "$vst_name forced-color view"
    else
        vst_Fail "$vst_name forced-color view"
    fi

    # Prove file-rendering mode is standalone: copy only the one script.
    cp "$vst_file" "$vst_dir/isolated/$vst_name" || { vst_Fail "$vst_name isolated copy"; continue; }
    chmod +x "$vst_dir/isolated/$vst_name"
    if "$vst_dir/isolated/$vst_name" --file "$vst_json" --no-install --no-color >"$vst_dir/isolated-view.txt" 2>"$vst_dir/isolated-view.stderr.log" && [ -s "$vst_dir/isolated-view.txt" ] && [ ! -s "$vst_dir/isolated-view.stderr.log" ]; then
        vst_Pass "$vst_name works as a single copied file"
    else
        vst_Fail "$vst_name standalone isolated execution"
    fi

    "$vst_file" --file "$vst_dir/does-not-exist.json" --no-install --no-color >"$vst_dir/missing.stdout.log" 2>"$vst_dir/missing.stderr.log"
    vst_missing_rc=$?
    if [ "$vst_missing_rc" -ne 0 ]; then vst_Pass "$vst_name rejects missing file"; else vst_Fail "$vst_name accepted missing file"; fi

    "$vst_file" --definitely-invalid-option --no-color >"$vst_dir/invalid.stdout.log" 2>"$vst_dir/invalid.stderr.log"
    vst_invalid_rc=$?
    if [ "$vst_invalid_rc" -ne 0 ]; then vst_Pass "$vst_name rejects invalid option"; else vst_Fail "$vst_name accepted invalid option"; fi

    case "$vst_name" in
        view_cpu_topology.sh)
            if grep 'Present CPUs:' "$vst_dir/view.txt" >/dev/null 2>&1 && grep 'online (fixed)' "$vst_dir/view.txt" >/dev/null 2>&1; then vst_Pass "$vst_name clarifies present/online topology"; else vst_Fail "$vst_name topology layout"; fi
            ;;
        view_storage.sh)
            vst_storage_lines=$(wc -l < "$vst_dir/view.txt" | tr -d ' ')
            if grep 'Device-mapper queue profiles' "$vst_dir/view.txt" >/dev/null 2>&1 && [ "$vst_storage_lines" -lt 100 ]; then vst_Pass "$vst_name groups repetitive device-mapper rows"; else vst_Fail "$vst_name storage ergonomics"; fi
            ;;
        view_network.sh)
            if grep 'Physical interfaces' "$vst_dir/view.txt" >/dev/null 2>&1 && grep 'Guest / container virtual interfaces' "$vst_dir/view.txt" >/dev/null 2>&1; then vst_Pass "$vst_name separates physical and virtual networking"; else vst_Fail "$vst_name network layout"; fi
            ;;
        view_thermal_power.sh)
            vst_temp_count=$(jq -r '[.data.hwmon[].values | to_entries[] | select(.key|test("^temp[0-9]+_input$"))] | length' "$vst_json" 2>/dev/null || printf '0')
            if ! grep 'Temperature sensors' "$vst_dir/view.txt" >/dev/null 2>&1; then
                vst_Fail "$vst_name thermal section missing"
            elif [ "$vst_temp_count" -gt 0 ] 2>/dev/null; then
                if grep ' = .* C' "$vst_dir/view.txt" >/dev/null 2>&1; then vst_Pass "$vst_name exposes captured sensor values"; else vst_Fail "$vst_name omitted available thermal values"; fi
            else
                if ! grep ' = .* C' "$vst_dir/view.txt" >/dev/null 2>&1; then vst_Pass "$vst_name preserves absent thermal capability without inventing values"; else vst_Fail "$vst_name invented thermal values"; fi
            fi
            ;;
        view_cpu_firmware_ras.sh)
            grep 'CPU Firmware / Microcode / RAS View' "$vst_dir/view.txt" >/dev/null 2>&1 && vst_Pass "$vst_name microcode/RAS layout" || vst_Fail "$vst_name microcode/RAS layout"
            ;;
        view_acpi_platform.sh)
            grep 'ACPI / Motherboard Architecture View' "$vst_dir/view.txt" >/dev/null 2>&1 && vst_Pass "$vst_name ACPI architecture layout" || vst_Fail "$vst_name ACPI architecture layout"
            ;;
        view_firmware_settings.sh)
            grep 'Firmware / BIOS Settings View' "$vst_dir/view.txt" >/dev/null 2>&1 && vst_Pass "$vst_name firmware-settings layout" || vst_Fail "$vst_name firmware-settings layout"
            ;;
        view_irq_activity.sh)
            grep 'IRQ / SoftIRQ Activity View' "$vst_dir/view.txt" >/dev/null 2>&1 && vst_Pass "$vst_name IRQ activity layout" || vst_Fail "$vst_name IRQ activity layout"
            ;;
        view_pcie_advanced.sh)
            grep 'Advanced PCIe View' "$vst_dir/view.txt" >/dev/null 2>&1 && vst_Pass "$vst_name advanced PCIe layout" || vst_Fail "$vst_name advanced PCIe layout"
            ;;
        view_storage_health_power.sh)
            grep 'Storage Health / Power View' "$vst_dir/view.txt" >/dev/null 2>&1 && vst_Pass "$vst_name storage health/power layout" || vst_Fail "$vst_name storage health/power layout"
            ;;
        view_network_advanced.sh)
            grep 'Advanced Network View' "$vst_dir/view.txt" >/dev/null 2>&1 && vst_Pass "$vst_name advanced network layout" || vst_Fail "$vst_name advanced network layout"
            ;;
        view_usb_input_audio.sh)
            grep 'USB / Input / Audio Topology View' "$vst_dir/view.txt" >/dev/null 2>&1 && vst_Pass "$vst_name USB/input/audio layout" || vst_Fail "$vst_name USB/input/audio layout"
            ;;
        view_memory_hardware.sh)
            grep 'Memory Hardware / EDAC View' "$vst_dir/view.txt" >/dev/null 2>&1 && vst_Pass "$vst_name memory hardware layout" || vst_Fail "$vst_name memory hardware layout"
            ;;
        view_timers_watchdogs.sh)
            grep 'Timers / Watchdogs View' "$vst_dir/view.txt" >/dev/null 2>&1 && vst_Pass "$vst_name timers/watchdogs layout" || vst_Fail "$vst_name timers/watchdogs layout"
            ;;
        view_runtime_pressure.sh)
            grep 'Runtime Pressure / Scheduler View' "$vst_dir/view.txt" >/dev/null 2>&1 && vst_Pass "$vst_name runtime-pressure layout" || vst_Fail "$vst_name runtime-pressure layout"
            ;;
        view_virtualization_stack.sh)
            if grep 'KVM / Virtualization Stack View' "$vst_dir/view.txt" >/dev/null 2>&1 && grep 'KVM device / CPU capability' "$vst_dir/view.txt" >/dev/null 2>&1; then vst_Pass "$vst_name virtualization-stack layout"; else vst_Fail "$vst_name virtualization-stack layout"; fi
            ;;
        view_kernel_events.sh)
            if grep 'Kernel Event / Reliability History View' "$vst_dir/view.txt" >/dev/null 2>&1 &&
               grep 'Unique normalized events' "$vst_dir/view.txt" >/dev/null 2>&1 &&
               grep 'Deduplicated observations' "$vst_dir/view.txt" >/dev/null 2>&1 &&
               grep 'Cross-source duplicates' "$vst_dir/view.txt" >/dev/null 2>&1; then
                vst_Pass "$vst_name normalized kernel-events layout"
            else
                vst_Fail "$vst_name normalized kernel-events layout"
            fi
            ;;
        view_guest_runtime_detail.sh)
            grep 'Guest Runtime Scheduler / Memory Detail View' "$vst_dir/view.txt" >/dev/null 2>&1 && vst_Pass "$vst_name guest-runtime-detail layout" || vst_Fail "$vst_name guest-runtime-detail layout"
            ;;
        view_kernel_housekeeping.sh)
            grep 'Kernel Housekeeping / IPI Noise View' "$vst_dir/view.txt" >/dev/null 2>&1 && vst_Pass "$vst_name kernel-housekeeping layout" || vst_Fail "$vst_name kernel-housekeeping layout"
            ;;
        view_pm_qos.sh)
            grep 'PM-QoS / Runtime Power Latency View' "$vst_dir/view.txt" >/dev/null 2>&1 && vst_Pass "$vst_name PM-QoS layout" || vst_Fail "$vst_name PM-QoS layout"
            ;;
        view_desktop_io_path.sh)
            grep 'Desktop I/O Path / Interactive Device View' "$vst_dir/view.txt" >/dev/null 2>&1 && vst_Pass "$vst_name desktop-I/O layout" || vst_Fail "$vst_name desktop-I/O layout"
            ;;
        view_latency_sample.sh)
            grep 'Passive Multi-second Latency / Pressure Sample View' "$vst_dir/view.txt" >/dev/null 2>&1 && vst_Pass "$vst_name latency-sample layout" || vst_Fail "$vst_name latency-sample layout"
            ;;
        view_cache_resource_qos.sh)
            grep 'Cache / NUMA / Resource QoS View' "$vst_dir/view.txt" >/dev/null 2>&1 && vst_Pass "$vst_name cache-resource-QoS layout" || vst_Fail "$vst_name cache-resource-QoS layout"
            ;;
        view_cpu_limits_pmu.sh)
            grep 'CPU Performance Limits / PMU View' "$vst_dir/view.txt" >/dev/null 2>&1 && vst_Pass "$vst_name CPU-limits layout" || vst_Fail "$vst_name CPU-limits layout"
            ;;
        view_irq_architecture.sh)
            grep 'IRQ Architecture View' "$vst_dir/view.txt" >/dev/null 2>&1 && vst_Pass "$vst_name IRQ-architecture layout" || vst_Fail "$vst_name IRQ-architecture layout"
            ;;
        view_memory_fragmentation.sh)
            grep 'Memory Fragmentation / Hugepage Feasibility View' "$vst_dir/view.txt" >/dev/null 2>&1 && vst_Pass "$vst_name memory-fragmentation layout" || vst_Fail "$vst_name memory-fragmentation layout"
            ;;
        view_display_timing.sh)
            grep 'Display Timing / EDID View' "$vst_dir/view.txt" >/dev/null 2>&1 && vst_Pass "$vst_name display-timing layout" || vst_Fail "$vst_name display-timing layout"
            ;;
        view_security_mitigations.sh)
            grep 'Security Mitigations / Performance Dimension View' "$vst_dir/view.txt" >/dev/null 2>&1 && vst_Pass "$vst_name security-mitigation layout" || vst_Fail "$vst_name security-mitigation layout"
            ;;
    esac
done

if [ "$vst_view_count" = "$vst_expected_views" ] && [ "$vst_expected_views" = 38 ]; then vst_Pass "all 38 dedicated source-tree views were exercised"; else vst_Fail "view coverage expected=38 source=$vst_expected_views tested=$vst_view_count"; fi

vst_Log info "[4/4] Testing view_all.sh replay orchestration"
if sh -n "$app_dir/view_all.sh" >"$vst_results/view_all.syntax.stdout.log" 2>"$vst_results/view_all.syntax.stderr.log"; then vst_Pass "view_all.sh syntax"; else vst_Fail "view_all.sh syntax"; fi
if "$app_dir/view_all.sh" --help --no-color >"$vst_results/view_all.help.txt" 2>"$vst_results/view_all.help.stderr.log"; then vst_Pass "view_all.sh --help"; else vst_Fail "view_all.sh --help"; fi
if "$app_dir/view_all.sh" --version --no-color >"$vst_results/view_all.version.txt" 2>"$vst_results/view_all.version.stderr.log"; then vst_Pass "view_all.sh --version"; else vst_Fail "view_all.sh --version"; fi

vst_discovery_parent=$vst_results/run-discovery
mkdir -p "$vst_discovery_parent/host-inventory-20260101-010101" "$vst_discovery_parent/host-inventory-20260102-020202" || exit 2
vst_discovery_i=0
while [ "$vst_discovery_i" -lt "$vst_expected_views" ]; do
    vst_discovery_i=$((vst_discovery_i+1))
    : >"$vst_discovery_parent/host-inventory-20260102-020202/collect_dummy_$vst_discovery_i.json"
done
(
    cd "$vst_discovery_parent" || exit 2
    "$app_dir/view_all.sh" --from-run --no-color
) >"$vst_results/view_all.discovery.txt" 2>"$vst_results/view_all.discovery.stderr.log"
vst_discovery_rc=$?
if [ "$vst_discovery_rc" -eq 0 ] && grep 'host-inventory-20260102-020202' "$vst_results/view_all.discovery.txt" >/dev/null 2>&1 && grep '38/38' "$vst_results/view_all.discovery.txt" >/dev/null 2>&1 && grep 'ready' "$vst_results/view_all.discovery.txt" >/dev/null 2>&1; then
    vst_Pass "view_all.sh bare --from-run lists replay-ready saved runs"
else
    vst_Fail "view_all.sh bare --from-run saved-run discovery"
fi
if grep 'host-inventory-20260101-010101' "$vst_results/view_all.discovery.txt" >/dev/null 2>&1 && grep 'incomplete' "$vst_results/view_all.discovery.txt" >/dev/null 2>&1; then
    vst_Pass "view_all.sh saved-run discovery labels incomplete captures"
else
    vst_Fail "view_all.sh saved-run discovery incomplete-capture labeling"
fi

if "$app_dir/view_all.sh" --from-run "$vst_fixture" --skip-prepare --no-install --no-color >"$vst_results/view_all.txt" 2>"$vst_results/view_all.stderr.log"; then
    vst_header_count=$(grep -c ' View$' "$vst_results/view_all.txt" 2>/dev/null || true)
    if [ "$vst_header_count" -ge "$vst_expected_views" ]; then vst_Pass "view_all.sh renders all $vst_expected_views replay views"; else vst_Fail "view_all.sh rendered only $vst_header_count of $vst_expected_views view headings"; fi
else
    vst_Fail "view_all.sh replay execution"
fi
if grep -E '^Host Inventory for Proxmox - view_|^Collecting host state\.\.\.$' "$vst_results/view_all.stderr.log" >/dev/null 2>&1; then
    vst_Fail "view_all.sh contains repeated child-view status chatter"
else
    vst_Pass "view_all.sh suppresses repeated child-view status chatter"
fi

if "$app_dir/view_all.sh" --from-run "$vst_fixture" --skip-prepare --no-install --color >"$vst_results/view_all.color.txt" 2>"$vst_results/view_all.color.stderr.log" && grep "$(printf '\033')" "$vst_results/view_all.color.txt" >/dev/null 2>&1; then
    vst_Pass "view_all.sh forced-color replay"
else
    vst_Fail "view_all.sh forced-color replay"
fi

"$app_dir/view_all.sh" --from-run "$vst_results/does-not-exist" --no-install --no-color >"$vst_results/view_all-missing.stdout.log" 2>"$vst_results/view_all-missing.stderr.log"
vst_missing_all_rc=$?
if [ "$vst_missing_all_rc" -ne 0 ]; then vst_Pass "view_all.sh rejects missing replay directory"; else vst_Fail "view_all.sh accepted missing replay directory"; fi

{
    printf 'Host Inventory for Proxmox - view-script test report\n'
    printf '=====================================================\n'
    printf 'View scripts tested: %s\n' "$vst_view_count"
    printf 'Pass validations: %s\n' "$vst_pass_count"
    printf 'Failed validations: %s\n' "$vst_fail_count"
    printf 'Return code: %s\n' "$app_rc"
    printf 'Results directory: %s\n' "$vst_results"
} > "$vst_results/report.txt"

if [ "$app_rc" -eq 0 ]; then
    vst_Log ok "RESULT: all $vst_view_count dedicated view scripts and view_all.sh passed ($vst_pass_count validations)."
else
    vst_Log error "RESULT: dedicated view-script tests failed ($vst_fail_count failed validation(s))."
fi
vst_Log info "Test results kept at: $vst_results"
exit "$app_rc"
