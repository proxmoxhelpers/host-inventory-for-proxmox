#!/bin/sh
# ============================================================
# extended_domains_test.sh
# Tests every v0.8.7 deep-observation collector/view pair with
# domain-specific JSON and human-view contracts.
#
# Version:
#   1.5.0
#
# Environment:
#   HFIP_TEST_RESULTS_PARENT  optional grouped-results parent
#   HFIP_TEST_FIXTURE_DIR     optional retained live run_all fixture
#
# Returns:
#   0 when every extended domain passes
#   1 when one or more validations fail
#   2 when test setup cannot be initialized
# ============================================================
app_rc=0
edt_test_version=1.5.0
app_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd -P) || exit 2
edt_timestamp=$(date '+%Y%m%d-%H%M%S')
if [ -n "${HFIP_TEST_RESULTS_PARENT-}" ]; then
    edt_results=$HFIP_TEST_RESULTS_PARENT/extended_domains_test
else
    edt_results=$app_dir/test/results/${edt_timestamp}-extended_domains_test-$$
fi
edt_log=$edt_results/test.log
edt_report=$edt_results/report.txt
edt_pass=0
edt_fail=0
edt_count=0
edt_expected=18
edt_fixture=${HFIP_TEST_FIXTURE_DIR-}
edt_fixture_mode=0
edt_source_collectors=$(find "$app_dir" -maxdepth 1 -type f -name 'collect_*.sh' 2>/dev/null | wc -l | tr -d ' ')
edt_domains="
cpu_firmware_ras
acpi_platform
firmware_settings
timers_watchdogs
virtualization_stack
pcie_advanced
memory_hardware
irq_activity
runtime_pressure
storage_health_power
network_advanced
usb_input_audio
kernel_events
guest_runtime_detail
kernel_housekeeping
pm_qos
desktop_io_path
latency_sample
"
mkdir -p "$edt_results" || exit 2
: > "$edt_log" || exit 2

# ============================================================
# edt_ColorInit
# Defines semantic test colors.
# Version: 1.0.0
# ============================================================
edt_ColorInit() {
    if [ -t 1 ] && [ -z "${NO_COLOR-}" ]; then
        edt_reset=$(printf '\033[0m')
        edt_title=$(printf '\033[1;96m')
        edt_info=$(printf '\033[96m')
        edt_ok=$(printf '\033[92m')
        edt_error=$(printf '\033[91m')
    else
        edt_reset=; edt_title=; edt_info=; edt_ok=; edt_error=
    fi
    return 0
}

# ============================================================
# edt_Log / edt_Pass / edt_Fail
# Persistent narrated test reporting.
# Version: 1.0.0
# ============================================================
edt_Log() {
    edtl_role=$1
    shift
    case "$edtl_role" in
        title) edtl_color=$edt_title ;;
        info) edtl_color=$edt_info ;;
        ok) edtl_color=$edt_ok ;;
        error) edtl_color=$edt_error ;;
        *) edtl_color= ;;
    esac
    printf '%s%s%s\n' "$edtl_color" "$*" "$edt_reset"
    printf '%s\n' "$*" >> "$edt_log"
    return 0
}
edt_Pass() { edt_pass=$((edt_pass + 1)); edt_Log ok "  PASS  $*"; return 0; }
edt_Fail() { edt_fail=$((edt_fail + 1)); app_rc=1; edt_Log error "  FAIL  $*"; return 0; }

# ============================================================
# edt_ValidateData
# Applies one domain-specific JSON contract.
# Version: 1.0.0
# ============================================================
edt_ValidateData() {
    edv_domain=$1
    edv_file=$2
    [ -s "$edv_file" ] || return 1
    case "$edv_domain" in
        cpu_firmware_ras)
            jq -e '(.data.per_cpu|type)=="array" and (.data.vulnerabilities|type)=="object" and (.data.microcode_packages|type)=="object" and (.data.edac|type)=="array"' "$edv_file" >/dev/null 2>&1
            ;;
        acpi_platform)
            jq -e '(.data.acpi_tables|type)=="array" and (.data.decoded_tables|type)=="array" and (.data.dmidecode|type)=="object"' "$edv_file" >/dev/null 2>&1
            ;;
        firmware_settings)
            jq -e '(.data.bios|type)=="object" and (.data.firmware_attributes|type)=="array" and (.data.fwupd_bios_settings|type)=="object"' "$edv_file" >/dev/null 2>&1
            ;;
        timers_watchdogs)
            jq -e '(.data.clocksource|type)=="object" and (.data.clockevents|type)=="array" and (.data.watchdog|type)=="object" and (.data.hpet_device_present|type)=="boolean"' "$edv_file" >/dev/null 2>&1
            ;;
        virtualization_stack)
            jq -e '(.data.kvm_device|type)=="object" and (.data.module_parameters|type)=="array" and (.data.cpu_virtualization_flags|type)=="array" and (.data.io_uring|type)=="object" and (.data.debugfs_kvm|type)=="object" and (.data.raw|type)=="object"' "$edv_file" >/dev/null 2>&1
            ;;
        pcie_advanced)
            jq -e '(.data.devices|type)=="array" and all(.data.devices[]?; has("local_cpulist") and has("aer") and has("capability_evidence") and has("reset") and has("upstream_path_bdfs"))' "$edv_file" >/dev/null 2>&1
            ;;
        memory_hardware)
            jq -e '(.data.dmidecode_memory|type)=="object" and (.data.decode_dimms|type)=="object" and (.data.edac_controllers|type)=="array" and (.data.edac_controls|type)=="object"' "$edv_file" >/dev/null 2>&1
            ;;
        irq_activity)
            jq -e '.data.sample_seconds>=1 and (.data.irqs|type)=="array" and (.data.softirqs|type)=="array" and (.data.raw|type)=="object"' "$edv_file" >/dev/null 2>&1
            ;;
        runtime_pressure)
            jq -e '.data.sample_seconds>=1 and (.data.pressure|type)=="object" and (.data.deltas|type)=="object" and (.data.vmstat|type)=="object"' "$edv_file" >/dev/null 2>&1
            ;;
        storage_health_power)
            jq -e '(.data.disks|type)=="array" and (.data.nvme|type)=="array" and (.data.scsi_hosts|type)=="array"' "$edv_file" >/dev/null 2>&1
            ;;
        network_advanced)
            jq -e '(.data.interfaces|type)=="array" and (.data.net_core|type)=="object" and (.data.softnet_stat_raw|type)=="string"' "$edv_file" >/dev/null 2>&1
            ;;
        usb_input_audio)
            jq -e '(.data.usb_devices|type)=="array" and (.data.input_devices|type)=="array" and (.data.sound_cards|type)=="array" and ((.data.pcm_devices//[])|type)=="array" and (.data.snd_hda_intel_parameters|type)=="object"' "$edv_file" >/dev/null 2>&1
            ;;
        kernel_events)
            jq -e '(.data.events|type)=="array" and
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
)' "$edv_file" >/dev/null 2>&1
            ;;
        guest_runtime_detail)
            jq -e '(.data.qemu_vms|type)=="array" and (.data|has("task_delayacct"))' "$edv_file" >/dev/null 2>&1
            ;;
        kernel_housekeeping)
            jq -e '(.data.kernel_threads|type)=="array" and (.data.ipi_interrupt_lines|type)=="array" and (.data.workqueues|type)=="array"' "$edv_file" >/dev/null 2>&1
            ;;
        pm_qos)
            jq -e '(.data.cpu_resume_latency|type)=="array" and (.data.devices|type)=="array" and (.data.cpu_dma_latency_holders|type)=="array"' "$edv_file" >/dev/null 2>&1
            ;;
        desktop_io_path)
            jq -e '(.data.display|type)=="object" and (.data.usb|type)=="array" and (.data.audio|type)=="object" and (.data.network_policy|type)=="object" and (.data.qemu_configs|type)=="array"' "$edv_file" >/dev/null 2>&1
            ;;
        latency_sample)
            jq -e '(.data.sample.duration_seconds>=1) and (.data.per_cpu|type)=="array" and (.data.softirq_deltas|type)=="array" and (.data.ipi_deltas|type)=="array" and (.data.block_deltas|type)=="array" and (.data.network_deltas|type)=="array" and (.data.qemu_deltas|type)=="array"' "$edv_file" >/dev/null 2>&1
            ;;
        *) return 1 ;;
    esac
}

# ============================================================
# edt_ValidateView
# Checks one domain-specific human-view marker.
# Version: 1.0.0
# ============================================================
edt_ValidateView() {
    edw_domain=$1
    edw_file=$2
    [ -s "$edw_file" ] || return 1
    case "$edw_domain" in
        cpu_firmware_ras) edw_marker='CPU Firmware / Microcode / RAS View' ;;
        acpi_platform) edw_marker='ACPI / Motherboard Architecture View' ;;
        firmware_settings) edw_marker='Firmware / BIOS Settings View' ;;
        timers_watchdogs) edw_marker='Timers / Watchdogs View' ;;
        virtualization_stack) edw_marker='KVM / Virtualization Stack View' ;;
        pcie_advanced) edw_marker='Advanced PCIe View' ;;
        memory_hardware) edw_marker='Memory Hardware / EDAC View' ;;
        irq_activity) edw_marker='IRQ / SoftIRQ Activity View' ;;
        runtime_pressure) edw_marker='Runtime Pressure / Scheduler View' ;;
        storage_health_power) edw_marker='Storage Health / Power View' ;;
        network_advanced) edw_marker='Advanced Network View' ;;
        usb_input_audio) edw_marker='USB / Input / Audio Topology View' ;;
        kernel_events) edw_marker='Kernel Event / Reliability History View' ;;
        guest_runtime_detail) edw_marker='Guest Runtime Scheduler / Memory Detail View' ;;
        kernel_housekeeping) edw_marker='Kernel Housekeeping / IPI Noise View' ;;
        pm_qos) edw_marker='PM-QoS / Runtime Power Latency View' ;;
        desktop_io_path) edw_marker='Desktop I/O Path / Interactive Device View' ;;
        latency_sample) edw_marker='Passive Multi-second Latency / Pressure Sample View' ;;
        *) return 1 ;;
    esac
    grep -F "$edw_marker" "$edw_file" >/dev/null 2>&1
}

# ------------------------------ setup ------------------------------
edt_ColorInit
edt_Log title "Host Inventory for Proxmox - extended observation domain tests"
edt_Log info "Results directory: $edt_results"
if [ -n "$edt_fixture" ]; then
    if [ -d "$edt_fixture" ] && [ -s "$edt_fixture/inventory.json" ] &&
       jq -e --argjson expected "$edt_source_collectors" 'type=="array" and length==$expected' "$edt_fixture/inventory.json" >/dev/null 2>&1; then
        edt_fixture_mode=1
        edt_Log info "Evidence mode: retained live fixture from run_all_test.sh"
    else
        edt_Log error "ERROR: HFIP_TEST_FIXTURE_DIR is not a valid complete collector fixture: $edt_fixture"
        exit 2
    fi
else
    edt_Log info "Evidence mode: direct live collector execution"
fi

# ------------------------------- main -------------------------------
for edt_domain in $edt_domains; do
    edt_count=$((edt_count + 1))
    edt_collector=$app_dir/collect_$edt_domain.sh
    edt_view=$app_dir/view_$edt_domain.sh
    edt_expected_name=$(printf '%s' "$edt_domain" | tr '_' '-')
    edt_dir=$edt_results/$edt_domain
    mkdir -p "$edt_dir" || { edt_Fail "$edt_domain result directory"; continue; }
    edt_Log info "[$edt_count/$edt_expected] Testing $edt_domain"

    if [ -x "$edt_collector" ] && [ -x "$edt_view" ]; then edt_Pass "collector/view pair present and executable"; else edt_Fail "collector/view pair missing or not executable"; continue; fi
    if sh -n "$edt_collector" && sh -n "$edt_view"; then edt_Pass "collector/view shell syntax"; else edt_Fail "collector/view shell syntax"; fi
    if grep -E -- '--arg(json)?[[:space:]]+(module|end)([[:space:]]|$)' "$edt_collector" "$edt_view" >/dev/null 2>&1; then
        edt_Fail "jq 1.6 known reserved external-variable compatibility"
    else
        edt_Pass "jq 1.6 known reserved external-variable compatibility"
    fi

    if [ "$edt_fixture_mode" -eq 1 ]; then
        edt_fixture_json=$edt_fixture/collect_$edt_domain.json
        if [ -s "$edt_fixture_json" ] && cp "$edt_fixture_json" "$edt_dir/collector.json"; then
            : > "$edt_dir/collector.stderr.log"
            edt_collect_rc=0
            edt_Pass "collector evidence reused from supplied live fixture"
        else
            edt_collect_rc=1
            edt_Fail "collector evidence missing from supplied live fixture"
        fi
    else
        if [ "$edt_domain" = "latency_sample" ]; then
            HFIP_LATENCY_SAMPLE_DURATION=1 "$edt_collector" --no-install --no-color >"$edt_dir/collector.json" 2>"$edt_dir/collector.stderr.log"
        else
            "$edt_collector" --no-install --no-color >"$edt_dir/collector.json" 2>"$edt_dir/collector.stderr.log"
        fi
        edt_collect_rc=$?
        if [ "$edt_collect_rc" -eq 0 ]; then edt_Pass "collector rc=0"; else edt_Fail "collector rc=$edt_collect_rc"; fi
    fi

    if [ -s "$edt_dir/collector.json" ] && jq -e --arg collector "$edt_expected_name" '.schema_version=="0.5.0" and .collector==$collector and (.data|type)=="object" and (.notes|type)=="array" and (.errors|type)=="array"' "$edt_dir/collector.json" >"$edt_dir/envelope.validation.log" 2>&1; then
        edt_Pass "collector envelope contract"
    else
        edt_Fail "collector envelope contract"
    fi

    if edt_ValidateData "$edt_domain" "$edt_dir/collector.json"; then edt_Pass "domain-specific evidence contract"; else edt_Fail "domain-specific evidence contract"; fi

    "$edt_view" --file "$edt_dir/collector.json" --no-install --no-color >"$edt_dir/view.txt" 2>"$edt_dir/view.stderr.log"
    edt_view_rc=$?
    if [ "$edt_view_rc" -eq 0 ] && [ -s "$edt_dir/view.txt" ] && [ ! -s "$edt_dir/view.stderr.log" ]; then edt_Pass "standalone saved-data view"; else edt_Fail "standalone saved-data view rc=$edt_view_rc"; fi
    if edt_ValidateView "$edt_domain" "$edt_dir/view.txt"; then edt_Pass "domain-specific view layout"; else edt_Fail "domain-specific view layout"; fi
    if grep "$(printf '\033')" "$edt_dir/collector.json" "$edt_dir/view.txt" >/dev/null 2>&1; then edt_Fail "--no-color artifacts contain ANSI"; else edt_Pass "--no-color artifacts are ANSI-free"; fi
done

if [ "$edt_count" = "$edt_expected" ]; then edt_Pass "all $edt_expected extended observation domains exercised"; else edt_Fail "expected $edt_expected extended domains, tested $edt_count"; fi

{
    printf 'Host Inventory for Proxmox - extended observation domain test report\n'
    printf '====================================================================\n'
    printf 'Test version: %s\n' "$edt_test_version"
    printf 'Domains tested: %s\n' "$edt_count"
    if [ "$edt_fixture_mode" -eq 1 ]; then printf 'Evidence mode: retained-live-fixture\n'; else printf 'Evidence mode: direct-live\n'; fi
    printf 'Pass validations: %s\n' "$edt_pass"
    printf 'Failed validations: %s\n' "$edt_fail"
    printf 'Return code: %s\n' "$app_rc"
    printf 'Results directory: %s\n' "$edt_results"
} > "$edt_report"

# -------------------------------- end -------------------------------
if [ "$app_rc" -eq 0 ]; then edt_Log ok "RESULT: all $edt_count extended domains passed ($edt_pass validations)."; else edt_Log error "RESULT: extended domain tests failed ($edt_fail failed validation(s))."; fi
edt_Log info "Test results kept at: $edt_results"
exit "$app_rc"
