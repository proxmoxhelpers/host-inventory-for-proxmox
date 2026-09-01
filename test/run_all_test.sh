#!/bin/sh
# ============================================================
# run_all_test.sh
# Tests run_all.sh and preserves all generated evidence.
#
# Version:
#   2.5.0
#
# Last Change:
#   Adds passive run_all.sh phase/collector timing artifact validation without extra host workload.
#
# Usage:
#   test/run_all_test.sh
#
# Environment:
#   HFIP_TEST_RESULTS_PARENT  optional parent directory supplied by
#                             test_all.sh to group focused test results
#
# Output:
#   Colorized progress on an interactive terminal.
#   Persistent files under test/results/ or the supplied parent.
#
# Returns:
#   0 when orchestration tests pass
#   1 when one or more validations fail
#   2 when test setup cannot be initialized
# ============================================================
app_rc=0
rat_test_version=2.5.0
app_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd -P) || exit 2
rat_script=$app_dir/run_all.sh
rat_timestamp=$(date '+%Y%m%d-%H%M%S')
if [ -n "${HFIP_TEST_RESULTS_PARENT-}" ]; then
    rat_results=$HFIP_TEST_RESULTS_PARENT/run_all_test
else
    rat_results=$app_dir/test/results/${rat_timestamp}-run_all_test-$$
fi
rat_out=$rat_results/inventory
rat_log=$rat_results/test.log
rat_report=$rat_results/report.txt
rat_report_json=$rat_results/report.json
rat_pass_count=0
rat_fail_count=0
rat_total_stages=11
rat_expected_collectors=$(find "$app_dir" -maxdepth 1 -type f -name 'collect_*.sh' 2>/dev/null | wc -l | tr -d ' ')
mkdir -p "$rat_results" || exit 2
: > "$rat_log" || exit 2

# ============================================================
# rat_ColorInit
# Defines semantic ANSI colors for interactive test output.
#
# Version:
#   1.0.0
#
# Returns:
#   0
# ============================================================
rat_ColorInit() {
    if [ -t 1 ] && [ -z "${NO_COLOR-}" ]; then
        rat_c_reset=$(printf '\033[0m')
        rat_c_title=$(printf '\033[1;96m')
        rat_c_info=$(printf '\033[96m')
        rat_c_ok=$(printf '\033[92m')
        rat_c_warn=$(printf '\033[93m')
        rat_c_error=$(printf '\033[91m')
        rat_c_dim=$(printf '\033[90m')
    else
        rat_c_reset=; rat_c_title=; rat_c_info=; rat_c_ok=; rat_c_warn=; rat_c_error=; rat_c_dim=
    fi
    return 0
}

# ============================================================
# rat_Log
# Prints a test message and appends an ANSI-free copy to test.log.
#
# Version:
#   1.0.0
#
# Usage:
#   rat_Log role text
#
# Returns:
#   0
# ============================================================
rat_Log() {
    ratl_role=$1
    shift
    case "$ratl_role" in
        title) ratl_color=$rat_c_title ;;
        info) ratl_color=$rat_c_info ;;
        ok) ratl_color=$rat_c_ok ;;
        warn) ratl_color=$rat_c_warn ;;
        error) ratl_color=$rat_c_error ;;
        *) ratl_color=$rat_c_dim ;;
    esac
    printf '%s%s%s\n' "$ratl_color" "$*" "$rat_c_reset"
    printf '%s\n' "$*" >> "$rat_log"
    return 0
}

# ============================================================
# rat_Pass
# Records one successful validation.
#
# Version:
#   1.0.0
#
# Returns:
#   0
# ============================================================
rat_Pass() {
    rat_pass_count=$((rat_pass_count + 1))
    rat_Log ok "PASS  $*"
    return 0
}

# ============================================================
# rat_Fail
# Records one failed validation without aborting later checks.
#
# Version:
#   1.0.0
#
# Returns:
#   0
# ============================================================
rat_Fail() {
    rat_fail_count=$((rat_fail_count + 1))
    app_rc=1
    rat_Log error "FAIL  $*"
    return 0
}

# ============================================================
# rat_Stage
# Prints a numbered high-level validation stage.
#
# Version:
#   1.0.0
#
# Returns:
#   0
# ============================================================
rat_Stage() {
    rat_Log info "[$1/$rat_total_stages] $2"
    return 0
}

# ============================================================
# rat_FinalizeReport
# Writes persistent text and JSON reports for the test run.
#
# Version:
#   1.0.0
#
# Returns:
#   0
# ============================================================
rat_FinalizeReport() {
    {
        printf 'Host Inventory for Proxmox - run_all.sh test report\n'
        printf '===================================================\n'
        printf 'Test version: %s\n' "$rat_test_version"
        printf 'Timestamp: %s\n' "$rat_timestamp"
        printf 'Command: %s\n' "$rat_script"
        printf 'Results directory: %s\n' "$rat_results"
        printf 'Pass validations: %s\n' "$rat_pass_count"
        printf 'Failed validations: %s\n' "$rat_fail_count"
        printf 'Return code: %s\n' "$app_rc"
        printf '\nPreserved evidence:\n'
        printf '  test.log\n'
        printf '  run_all.help.txt\n'
        printf '  run_all.version.txt\n'
        printf '  run_all.stdout.log\n'
        printf '  run_all.stderr.log\n'
        printf '  overwrite.stdout.log\n'
        printf '  overwrite.stderr.log\n'
        printf '  invalid-option.stdout.log\n'
        printf '  invalid-option.stderr.log\n'
        printf '  inventory/\n'
    } > "$rat_report"
    if command -v jq >/dev/null 2>&1; then
        jq -n --arg test "run_all_test.sh" --arg version "$rat_test_version" --arg timestamp "$rat_timestamp" --arg results_directory "$rat_results" --argjson pass_count "$rat_pass_count" --argjson fail_count "$rat_fail_count" --argjson rc "$app_rc" '{test:$test,version:$version,timestamp:$timestamp,results_directory:$results_directory,pass_count:$pass_count,fail_count:$fail_count,rc:$rc}' > "$rat_report_json" 2>/dev/null || :
    fi
    return 0
}

# ------------------------------ setup ------------------------------
rat_ColorInit
rat_Log title "Host Inventory for Proxmox - run_all.sh test"
rat_Log info "Results directory: $rat_results"

# ------------------------------- main -------------------------------
rat_Stage 1 "Checking run_all.sh shell syntax"
if sh -n "$rat_script" >"$rat_results/syntax.stdout.log" 2>"$rat_results/syntax.stderr.log"; then rat_Pass "shell syntax"; else rat_Fail "shell syntax"; fi

rat_Stage 2 "Checking --help interface"
if "$rat_script" --help --no-color >"$rat_results/run_all.help.txt" 2>"$rat_results/help.stderr.log"; then rat_Pass "--help"; else rat_Fail "--help"; fi

rat_Stage 3 "Checking --version interface"
if "$rat_script" --version --no-color >"$rat_results/run_all.version.txt" 2>"$rat_results/version.stderr.log"; then rat_Pass "--version"; else rat_Fail "--version"; fi

rat_Stage 4 "Running the complete collector orchestration"
HFIP_LATENCY_SAMPLE_DURATION=1 "$rat_script" --skip-prepare --no-install --no-color --output "$rat_out" >"$rat_results/run_all.stdout.log" 2>"$rat_results/run_all.stderr.log"
rat_run_rc=$?
if [ "$rat_run_rc" -eq 0 ]; then rat_Pass "run_all.sh completed with rc=0"; else rat_Fail "run_all.sh execution rc=$rat_run_rc"; fi

rat_Stage 5 "Validating inventory.json and manifest.json"
if [ "$rat_expected_collectors" = 38 ]; then rat_Pass "source tree contains the expected 38 collectors"; else rat_Fail "expected 38 collector scripts in source tree, found $rat_expected_collectors"; fi
if [ -f "$rat_out/inventory.json" ] && jq -e --argjson expected "$rat_expected_collectors" 'type=="array" and length==$expected and all(.[]; .schema_version=="0.5.0")' "$rat_out/inventory.json" >"$rat_results/inventory.validation.log" 2>&1; then
    rat_Pass "inventory.json contains $rat_expected_collectors schema-valid collector envelopes"
else
    rat_Fail "inventory.json validation"
fi
if [ -f "$rat_out/manifest.json" ] && jq -e --argjson expected "$rat_expected_collectors" '.schema_version=="0.5.0" and .success_count==$expected and .failure_count==0 and all(.collectors[]; .success==true and (.summary_file|type=="string"))' "$rat_out/manifest.json" >"$rat_results/manifest.validation.log" 2>&1; then
    rat_Pass "manifest.json reports $rat_expected_collectors successful collectors"
else
    rat_Fail "manifest.json validation"
fi

rat_Stage 6 "Checking individual JSON and summary artifacts"
rat_json_count=$(find "$rat_out" -maxdepth 1 -type f -name 'collect_*.json' 2>/dev/null | wc -l | tr -d ' ')
rat_summary_count=$(find "$rat_out/summaries" -maxdepth 1 -type f -name 'collect_*.txt' 2>/dev/null | wc -l | tr -d ' ')
if [ "$rat_json_count" = "$rat_expected_collectors" ]; then rat_Pass "$rat_expected_collectors individual collector JSON files"; else rat_Fail "expected $rat_expected_collectors individual JSON files, got $rat_json_count"; fi
if [ "$rat_summary_count" = "$rat_expected_collectors" ]; then rat_Pass "$rat_expected_collectors individual human-readable summaries"; else rat_Fail "expected $rat_expected_collectors individual summaries, got $rat_summary_count"; fi
if [ -s "$rat_out/summary.txt" ]; then rat_Pass "combined summary.txt is present and non-empty"; else rat_Fail "summary.txt missing/empty"; fi
if [ -s "$rat_out/collector-timings.tsv" ] &&
   awk -F '\t' -v expected="$rat_expected_collectors" '
     NR==1 {ok=($1=="collector" && $2=="collection_ms" && $3=="summary_ms" && $4=="total_ms"); next}
     {
       n++
       if ($2 !~ /^[0-9]+$/ || $3 !~ /^[0-9]+$/ || $4 !~ /^[0-9]+$/ || $7!="true") bad=1
     }
     END {exit !(ok && !bad && n==expected)}
   ' "$rat_out/collector-timings.tsv"; then
    rat_Pass "passive per-collector timing artifact covers all $rat_expected_collectors collectors"
else
    rat_Fail "collector-timings.tsv contract"
fi
if [ -s "$rat_out/run-timings.tsv" ] &&
   awk -F '\t' '
     NR==1 {ok=($1=="phase" && $2=="elapsed_ms"); next}
     $1=="preparation" {p=$2}
     $1=="collectors" {c=$2}
     $1=="finalization" {f=$2}
     $1=="total" {t=$2}
     {if ($2 !~ /^[0-9]+$/) bad=1}
     END {exit !(ok && !bad && p!="" && c!="" && f!="" && t!="" && t>=c)}
   ' "$rat_out/run-timings.tsv"; then
    rat_Pass "passive run phase timing artifact"
else
    rat_Fail "run-timings.tsv contract"
fi

rat_Stage 7 "Checking collector/summary diagnostic logs"
rat_bad_diag=0
if [ -d "$rat_out/logs" ]; then
    for rat_diag_file in "$rat_out"/logs/*.summary.stderr.log; do
        [ -e "$rat_diag_file" ] || continue
        if [ -s "$rat_diag_file" ]; then
            rat_bad_diag=1
            break
        fi
    done
fi
if [ "$rat_bad_diag" -eq 0 ]; then rat_Pass "no summary renderer produced unexpected stderr"; else rat_Fail "summary renderer diagnostic stderr detected"; fi
if [ -d "$rat_out/logs" ] && grep -R -E '^(Host Inventory for Proxmox - collect_|Collecting host state\.\.\.)' "$rat_out/logs" >"$rat_results/routine-chatter.validation.log" 2>&1; then
    rat_Fail "routine collector chatter found in diagnostic logs"
else
    rat_Pass "diagnostic logs contain no routine collector chatter"
fi
if find "$rat_out/logs" -maxdepth 1 -type f \( -name '*\**' -o -name '*%2A*' \) | grep . >"$rat_results/wildcard-log.validation.log" 2>&1; then
    rat_Fail "literal wildcard diagnostic filename detected"
else
    rat_Pass "no literal wildcard diagnostic filenames"
fi
if [ -f "$rat_out/manifest.json" ] && jq -e 'all(.collectors[]; .success==true and (.summary_file|type=="string"))' "$rat_out/manifest.json" >"$rat_results/summary-manifest.validation.log" 2>&1; then rat_Pass "every successful collector has a summary file"; else rat_Fail "missing summary_file in manifest"; fi

rat_Stage 8 "Checking collected-data sanity"
rat_data_ok=1
if [ -f "$rat_out/collect_pcie_iommu.json" ]; then
    if ! jq -e '[.data.devices[] | select(.driver=="driver" or .iommu_group=="iommu_group")] | length == 0' "$rat_out/collect_pcie_iommu.json" >"$rat_results/pcie-symlink.validation.log" 2>&1; then rat_data_ok=0; fi
else
    rat_data_ok=0
fi
if [ "$rat_data_ok" -eq 1 ]; then rat_Pass "PCIe absent symlinks are not reported as literal driver/iommu_group values"; else rat_Fail "PCIe symlink sentinel-value sanity check"; fi
if [ -f "$rat_out/collect_pcie_iommu.json" ] && jq -e 'all(.data.devices[]?; (.msi_irqs|type)=="array") and all(.data.iommu_groups[]?; has("type") and has("reserved_regions_raw"))' "$rat_out/collect_pcie_iommu.json" >"$rat_results/pcie-msi.validation.log" 2>&1; then rat_Pass "PCIe devices include MSI/MSI-X sysfs vector arrays"; else rat_Fail "PCIe MSI vector inventory contract"; fi
if [ -f "$rat_out/collect_storage.json" ] && jq -e 'all(.data.block_queues[]?; has("device_path"))' "$rat_out/collect_storage.json" >"$rat_results/storage-ancestry.validation.log" 2>&1; then rat_Pass "storage block devices include sysfs ancestry fields"; else rat_Fail "storage block ancestry contract"; fi
if [ -f "$rat_out/collect_proxmox_host.json" ] && jq -e '(.data.lxc_configs|type)=="array" and (.data.qemu_runtime|type)=="array" and (.data.lxc_runtime|type)=="array" and (.data.runtime_capabilities|type)=="object" and all(.data.qemu_runtime[]?; (.tasks|type)=="array" and (.vhost_threads|type)=="array" and (.cgroup|type)=="object")' "$rat_out/collect_proxmox_host.json" >"$rat_results/proxmox-runtime.validation.log" 2>&1; then rat_Pass "Proxmox data includes guest runtime/cgroup arrays"; else rat_Fail "Proxmox guest runtime/cgroup contract"; fi
if [ -f "$rat_out/collect_proxmox_host.json" ] && jq -e 'all(.data.qemu_runtime[]?; (.cgroup|has("cpuset_cpus_present")) and (.cgroup|has("cpuset_cpus_effective_present")) and (.cgroup|has("cpu_weight_present")) and (.cgroup|has("cpu_max_present"))) and all(.data.lxc_runtime[]?; (.cgroup|has("cpuset_cpus_present")) and (.cgroup|has("cpuset_cpus_effective_present")) and (.cgroup|has("cpu_weight_present")) and (.cgroup|has("cpu_max_present")))' "$rat_out/collect_proxmox_host.json" >"$rat_results/proxmox-cgroup-presence.validation.log" 2>&1; then rat_Pass "guest cgroup records preserve interface file-presence evidence"; else rat_Fail "guest cgroup file-presence contract"; fi
if [ -f "$rat_out/collect_cpu_firmware_ras.json" ] && jq -e '(.data.per_cpu|type)=="array" and (.data.vulnerabilities|type)=="object" and (.data.microcode_packages|type)=="object"' "$rat_out/collect_cpu_firmware_ras.json" >"$rat_results/cpu-firmware.validation.log" 2>&1; then rat_Pass "CPU firmware/RAS collector contract"; else rat_Fail "CPU firmware/RAS collector contract"; fi
if [ -f "$rat_out/collect_acpi_platform.json" ] && jq -e '(.data.acpi_tables|type)=="array" and (.data.decoded_tables|type)=="array"' "$rat_out/collect_acpi_platform.json" >"$rat_results/acpi-platform.validation.log" 2>&1; then rat_Pass "ACPI platform collector contract"; else rat_Fail "ACPI platform collector contract"; fi
if [ -f "$rat_out/collect_firmware_settings.json" ] && jq -e '(.data.firmware_attributes|type)=="array" and (.data.fwupd_bios_settings|type)=="object"' "$rat_out/collect_firmware_settings.json" >"$rat_results/firmware-settings.validation.log" 2>&1; then rat_Pass "firmware-settings collector contract"; else rat_Fail "firmware-settings collector contract"; fi
if [ -f "$rat_out/collect_irq_activity.json" ] && jq -e '(.data.irqs|type)=="array" and (.data.softirqs|type)=="array" and .data.sample_seconds>=1' "$rat_out/collect_irq_activity.json" >"$rat_results/irq-activity.validation.log" 2>&1; then rat_Pass "passive IRQ activity collector contract"; else rat_Fail "IRQ activity collector contract"; fi
if [ -f "$rat_out/collect_pcie_advanced.json" ] && jq -e 'all(.data.devices[]?; has("local_cpulist") and has("aer") and has("capability_evidence") and has("upstream_path_bdfs"))' "$rat_out/collect_pcie_advanced.json" >"$rat_results/pcie-advanced.validation.log" 2>&1; then rat_Pass "advanced PCIe collector contract"; else rat_Fail "advanced PCIe collector contract"; fi
if [ -f "$rat_out/collect_storage_health_power.json" ] && jq -e '(.data.disks|type)=="array" and (.data.nvme|type)=="array" and (.data.scsi_hosts|type)=="array"' "$rat_out/collect_storage_health_power.json" >"$rat_results/storage-health.validation.log" 2>&1; then rat_Pass "storage health/power collector contract"; else rat_Fail "storage health/power collector contract"; fi
if [ -f "$rat_out/collect_network_advanced.json" ] && jq -e '(.data.interfaces|type)=="array" and (.data.net_core|type)=="object"' "$rat_out/collect_network_advanced.json" >"$rat_results/network-advanced.validation.log" 2>&1; then rat_Pass "advanced network collector contract"; else rat_Fail "advanced network collector contract"; fi
if [ -f "$rat_out/collect_usb_input_audio.json" ] && jq -e '(.data.usb_devices|type)=="array" and (.data.input_devices|type)=="array" and (.data.sound_cards|type)=="array" and ((.data.pcm_devices//[])|type)=="array"' "$rat_out/collect_usb_input_audio.json" >"$rat_results/usb-input-audio.validation.log" 2>&1; then rat_Pass "USB/input/audio collector contract"; else rat_Fail "USB/input/audio collector contract"; fi
if [ -f "$rat_out/collect_memory_hardware.json" ] && jq -e '(.data.edac_controllers|type)=="array" and (.data.dmidecode_memory|type)=="object"' "$rat_out/collect_memory_hardware.json" >"$rat_results/memory-hardware.validation.log" 2>&1; then rat_Pass "memory hardware/EDAC collector contract"; else rat_Fail "memory hardware/EDAC collector contract"; fi
if [ -f "$rat_out/collect_timers_watchdogs.json" ] && jq -e '(.data.clocksource|type)=="object" and (.data.clockevents|type)=="array" and (.data.watchdog|type)=="object"' "$rat_out/collect_timers_watchdogs.json" >"$rat_results/timers-watchdogs.validation.log" 2>&1; then rat_Pass "timers/watchdogs collector contract"; else rat_Fail "timers/watchdogs collector contract"; fi
if [ -f "$rat_out/collect_runtime_pressure.json" ] && jq -e '(.data.pressure|type)=="object" and (.data.deltas|type)=="object" and .data.sample_seconds>=1' "$rat_out/collect_runtime_pressure.json" >"$rat_results/runtime-pressure.validation.log" 2>&1; then rat_Pass "runtime pressure collector contract"; else rat_Fail "runtime pressure collector contract"; fi
if grep -E -- '--arg(json)?[[:space:]]+(module|end)([[:space:]]|$)' "$app_dir"/collect_*.sh "$app_dir"/view_*.sh >/dev/null 2>&1; then rat_Fail "suite-wide jq 1.6 known reserved external-variable compatibility"; else rat_Pass "suite-wide jq 1.6 known reserved external-variable compatibility"; fi
if [ -s "$rat_out/collect_virtualization_stack.json" ] && jq -e '(.data.kvm_device|type)=="object" and (.data.module_parameters|type)=="array" and (.data.cpu_virtualization_flags|type)=="array" and (.data.io_uring|type)=="object" and (.data.raw|type)=="object"' "$rat_out/collect_virtualization_stack.json" >"$rat_results/virtualization-stack.validation.log" 2>&1; then rat_Pass "virtualization-stack collector contract"; else rat_Fail "virtualization-stack collector contract"; fi
if [ -s "$rat_out/collect_kernel_events.json" ] && jq -e '(.data.events|type)=="array" and
(.data.counts_by_severity|type)=="object" and
(.data.counts_by_category|type)=="object" and
(.data.occurrences_by_severity|type)=="object" and
(.data.occurrences_by_category|type)=="object" and
(.data.source_status|type)=="object" and
all(.data.events[]?;
  (.sources|type)=="array" and
  (.occurrences|type)=="number" and .occurrences>=1 and
  (.message|type)=="string" and ((.message|contains("\n"))|not) and
  (.normalized_message|type)=="string" and
  (.evidence|type)=="array" and (.evidence|length)<=5 and
  ((.first_occurrence==null) or (.first_occurrence.scope=="current-boot-monotonic" and (.first_occurrence.boot_seconds|type)=="number")) and
  ((.last_occurrence==null) or (.last_occurrence.scope=="current-boot-monotonic" and (.last_occurrence.boot_seconds|type)=="number"))
)' "$rat_out/collect_kernel_events.json" >"$rat_results/kernel-events.validation.log" 2>&1; then rat_Pass "kernel-event history collector contract"; else rat_Fail "kernel-event history collector contract"; fi
if [ -s "$rat_out/collect_guest_runtime_detail.json" ] && jq -e '(.data.qemu_vms|type)=="array" and (.data|has("task_delayacct"))' "$rat_out/collect_guest_runtime_detail.json" >"$rat_results/guest-runtime-detail.validation.log" 2>&1; then rat_Pass "guest runtime detail collector contract"; else rat_Fail "guest runtime detail collector contract"; fi
if [ -s "$rat_out/collect_kernel_housekeeping.json" ] && jq -e '(.data.kernel_threads|type)=="array" and (.data.ipi_interrupt_lines|type)=="array" and (.data.workqueues|type)=="array"' "$rat_out/collect_kernel_housekeeping.json" >"$rat_results/kernel-housekeeping.validation.log" 2>&1; then rat_Pass "kernel housekeeping collector contract"; else rat_Fail "kernel housekeeping collector contract"; fi
if [ -s "$rat_out/collect_pm_qos.json" ] && jq -e '(.data.cpu_resume_latency|type)=="array" and (.data.devices|type)=="array" and (.data.cpu_dma_latency_holders|type)=="array"' "$rat_out/collect_pm_qos.json" >"$rat_results/pm-qos.validation.log" 2>&1; then rat_Pass "PM-QoS collector contract"; else rat_Fail "PM-QoS collector contract"; fi
if [ -s "$rat_out/collect_desktop_io_path.json" ] && jq -e '(.data.display|type)=="object" and (.data.usb|type)=="array" and (.data.audio|type)=="object" and (.data.network_policy|type)=="object" and (.data.qemu_configs|type)=="array"' "$rat_out/collect_desktop_io_path.json" >"$rat_results/desktop-io-path.validation.log" 2>&1; then rat_Pass "desktop I/O path collector contract"; else rat_Fail "desktop I/O path collector contract"; fi
if [ -s "$rat_out/collect_latency_sample.json" ] && jq -e '(.data.sample.duration_seconds>=1) and (.data.per_cpu|type)=="array" and (.data.softirq_deltas|type)=="array" and (.data.ipi_deltas|type)=="array" and (.data.block_deltas|type)=="array" and (.data.network_deltas|type)=="array" and (.data.qemu_deltas|type)=="array"' "$rat_out/collect_latency_sample.json" >"$rat_results/latency-sample.validation.log" 2>&1; then rat_Pass "multi-second latency sample collector contract"; else rat_Fail "multi-second latency sample collector contract"; fi
if [ -s "$rat_out/collect_cache_resource_qos.json" ] && jq -e '(.data.cache_entries|type)=="array" and (.data.numa_nodes|type)=="array" and (.data.resctrl|type)=="object" and ((.data.resctrl.groups//[])|type)=="array"' "$rat_out/collect_cache_resource_qos.json" >/dev/null 2>&1; then rat_Pass "cache/resource-QoS collector contract"; else rat_Fail "cache/resource-QoS collector contract"; fi
if [ -s "$rat_out/collect_cpu_limits_pmu.json" ] && jq -e '(.data.cpus|type)=="array" and all(.data.cpus[]?; ((.time_in_state//[])|type)=="array" and (.time_in_state_total_ticks|type)=="number") and (.data.pmu_sources|type)=="array"' "$rat_out/collect_cpu_limits_pmu.json" >/dev/null 2>&1; then rat_Pass "CPU limits/PMU collector contract"; else rat_Fail "CPU limits/PMU collector contract"; fi
if [ -s "$rat_out/collect_irq_architecture.json" ] && jq -e '(.data.irqs|type)=="array" and (.data|has("special_interrupts_raw"))' "$rat_out/collect_irq_architecture.json" >/dev/null 2>&1; then rat_Pass "IRQ architecture collector contract"; else rat_Fail "IRQ architecture collector contract"; fi
if [ -s "$rat_out/collect_memory_fragmentation.json" ] && jq -e '(.data.buddy_highest_order|type)=="array" and (.data.hugetlb|type)=="array" and (.data.transparent_hugepage|type)=="object"' "$rat_out/collect_memory_fragmentation.json" >/dev/null 2>&1; then rat_Pass "memory fragmentation collector contract"; else rat_Fail "memory fragmentation collector contract"; fi
if [ -s "$rat_out/collect_display_timing.json" ] && jq -e '(.data.connectors|type)=="array" and (.data.connected_count|type)=="number"' "$rat_out/collect_display_timing.json" >/dev/null 2>&1; then rat_Pass "display timing collector contract"; else rat_Fail "display timing collector contract"; fi
if [ -s "$rat_out/collect_security_mitigations.json" ] && jq -e '(.data.vulnerabilities|type)=="array" and (.data.cpu_capabilities|type)=="object"' "$rat_out/collect_security_mitigations.json" >/dev/null 2>&1; then rat_Pass "security mitigation collector contract"; else rat_Fail "security mitigation collector contract"; fi
if [ -f "$rat_out/summaries/collect_irqs.txt" ] && ! grep -E 'effective=-?[0-9]+ node=$' "$rat_out/summaries/collect_irqs.txt" >"$rat_results/irq-summary.validation.log" 2>&1; then
    rat_Pass "IRQ summary preserves empty affinity fields without column shifting"
else
    rat_Fail "IRQ summary field alignment"
fi

rat_Stage 9 "Checking output-directory overwrite protection"
"$rat_script" --skip-prepare --no-install --no-color --output "$rat_out" >"$rat_results/overwrite.stdout.log" 2>"$rat_results/overwrite.stderr.log"
rat_overwrite_rc=$?
if [ "$rat_overwrite_rc" -ne 0 ]; then rat_Pass "existing output directory is refused (rc=$rat_overwrite_rc)"; else rat_Fail "run_all.sh overwrote/accepted an existing output directory"; fi

rat_Stage 10 "Checking invalid-option handling"
"$rat_script" --definitely-invalid-option --no-color >"$rat_results/invalid-option.stdout.log" 2>"$rat_results/invalid-option.stderr.log"
rat_invalid_rc=$?
if [ "$rat_invalid_rc" -ne 0 ]; then rat_Pass "invalid option is rejected (rc=$rat_invalid_rc)"; else rat_Fail "run_all.sh accepted an invalid option"; fi

rat_Stage 11 "Writing persistent test report"
rat_FinalizeReport
if [ -s "$rat_report" ]; then rat_Pass "report.txt written"; else rat_Fail "report.txt was not written"; fi
if grep -F "Test version: $rat_test_version" "$rat_report" >/dev/null 2>&1 && jq -e --arg version "$rat_test_version" '.version==$version' "$rat_report_json" >/dev/null 2>&1; then
    rat_Pass "persistent report version metadata matches $rat_test_version"
else
    rat_Fail "persistent report version metadata"
fi
rat_FinalizeReport

# -------------------------------- end -------------------------------
if [ "$app_rc" -eq 0 ]; then
    rat_Log ok "RESULT: run_all.sh test passed ($rat_pass_count validations)."
else
    rat_Log error "RESULT: run_all.sh test failed ($rat_fail_count failed validation(s))."
fi
rat_Log info "Test results kept at: $rat_results"
exit "$app_rc"
