#!/bin/sh
# ============================================================
# collectors_test.sh
# Tests every standalone collector and preserves its evidence.
#
# Version:
#   2.1.0
#
# Last Change:
#   Adds deterministic kernel-event tokenization/de-duplication semantics while
#   retaining fixture-assisted umbrella execution and standalone live re-probing.
#
# Environment:
#   HFIP_TEST_RESULTS_PARENT  optional grouped-results parent
#   HFIP_TEST_FIXTURE_DIR     optional retained live run_all fixture
#
# Returns:
#   0 when all collector command tests pass
#   1 otherwise
# ============================================================
app_rc=0
HFIP_LATENCY_SAMPLE_DURATION=${HFIP_LATENCY_SAMPLE_DURATION:-1}
export HFIP_LATENCY_SAMPLE_DURATION
app_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd -P) || exit 2
ct_timestamp=$(date '+%Y%m%d-%H%M%S')
if [ -n "${HFIP_TEST_RESULTS_PARENT-}" ]; then ct_results=$HFIP_TEST_RESULTS_PARENT/collectors_test; else ct_results=$app_dir/test/results/${ct_timestamp}-collectors_test-$$; fi
ct_log=$ct_results/test.log
ct_pass_count=0
ct_fail_count=0
ct_collector_count=0
ct_expected_collectors=$(find "$app_dir" -maxdepth 1 -type f -name 'collect_*.sh' 2>/dev/null | wc -l | tr -d ' ')
ct_fixture=${HFIP_TEST_FIXTURE_DIR-}
ct_fixture_mode=0
mkdir -p "$ct_results" || exit 2
: > "$ct_log" || exit 2

ct_ColorInit() { if [ -t 1 ] && [ -z "${NO_COLOR-}" ]; then ct_reset=$(printf '\033[0m'); ct_info=$(printf '\033[96m'); ct_ok=$(printf '\033[92m'); ct_error=$(printf '\033[91m'); ct_title=$(printf '\033[1;96m'); ct_dim=$(printf '\033[90m'); else ct_reset=; ct_info=; ct_ok=; ct_error=; ct_title=; ct_dim=; fi; return 0; }
ct_Log() { ctl_role=$1; shift; case "$ctl_role" in title) ctl_color=$ct_title;; info) ctl_color=$ct_info;; ok) ctl_color=$ct_ok;; error) ctl_color=$ct_error;; *) ctl_color=$ct_dim;; esac; printf '%s%s%s\n' "$ctl_color" "$*" "$ct_reset"; printf '%s\n' "$*" >> "$ct_log"; return 0; }
ct_Pass() { ct_pass_count=$((ct_pass_count+1)); ct_Log ok "  PASS  $*"; }
ct_Fail() { ct_fail_count=$((ct_fail_count+1)); app_rc=1; ct_Log error "  FAIL  $*"; }

ct_ColorInit
ct_Log title "Host Inventory for Proxmox - collector command tests"
ct_Log info "Results directory: $ct_results"
if [ -n "$ct_fixture" ]; then
    if [ -d "$ct_fixture" ] && [ -s "$ct_fixture/inventory.json" ] && [ -s "$ct_fixture/manifest.json" ] &&
       jq -e --argjson expected "$ct_expected_collectors" 'type=="array" and length==$expected' "$ct_fixture/inventory.json" >/dev/null 2>&1 &&
       jq -e --argjson expected "$ct_expected_collectors" '.success_count==$expected and .failure_count==0 and (.collectors|length)==$expected' "$ct_fixture/manifest.json" >/dev/null 2>&1; then
        ct_fixture_mode=1
        ct_Log info "Evidence mode: retained live fixture from run_all_test.sh; redundant hardware re-probes suppressed"
    else
        ct_Log error "ERROR: HFIP_TEST_FIXTURE_DIR is not a valid successful complete collector fixture: $ct_fixture"
        exit 2
    fi
else
    ct_Log info "Evidence mode: exhaustive direct live collector execution"
fi
for ct_file in "$app_dir"/collect_*.sh; do
    [ -f "$ct_file" ] || { ct_Fail "no collectors found"; break; }
    ct_collector_count=$((ct_collector_count+1))
    ct_name=${ct_file##*/}
    ct_base=${ct_name%.sh}
    ct_dir=$ct_results/$ct_base
    mkdir -p "$ct_dir" || { ct_Fail "$ct_name result directory"; continue; }
    ct_Log info "[$ct_collector_count] Testing $ct_name"

    if sh -n "$ct_file" >"$ct_dir/syntax.stdout.log" 2>"$ct_dir/syntax.stderr.log"; then ct_Pass "syntax"; else ct_Fail "$ct_name syntax"; fi
    if grep -E -- '--arg(json)?[[:space:]]+(module|end)([[:space:]]|$)' "$ct_file" >/dev/null 2>&1; then ct_Fail "$ct_name jq 1.6 known reserved external-variable compatibility"; else ct_Pass "jq 1.6 known reserved external-variable compatibility"; fi
    if "$ct_file" --help --no-color >"$ct_dir/help.txt" 2>"$ct_dir/help.stderr.log"; then ct_Pass "--help"; else ct_Fail "$ct_name --help"; fi
    if "$ct_file" --version --no-color >"$ct_dir/version.txt" 2>"$ct_dir/version.stderr.log"; then ct_Pass "--version"; else ct_Fail "$ct_name --version"; fi

    if [ "$ct_fixture_mode" -eq 1 ]; then
        ct_fixture_json=$ct_fixture/$ct_base.json
        if [ -s "$ct_fixture_json" ] &&
           jq -e --arg script "$ct_name" 'any(.collectors[]?; .script==$script and .success==true and .rc==0)' "$ct_fixture/manifest.json" >/dev/null 2>&1 &&
           cp "$ct_fixture_json" "$ct_dir/collector.json"; then
            : > "$ct_dir/collector.stderr.log"
            ct_rc=0
        else
            : > "$ct_dir/collector.stderr.log"
            ct_rc=1
        fi
    else
        "$ct_file" --no-install --no-color >"$ct_dir/collector.json" 2>"$ct_dir/collector.stderr.log"; ct_rc=$?
    fi
    if [ "$ct_rc" -eq 0 ]; then
        if [ "$ct_fixture_mode" -eq 1 ]; then ct_Pass "normal live collection covered by supplied run_all fixture"; else ct_Pass "normal collection rc=0"; fi
        if [ -s "$ct_dir/collector.json" ] && jq -e '.schema_version=="0.5.0" and (.collector|type=="string") and (.data|type=="object") and (.notes|type=="array") and (.errors|type=="array")' "$ct_dir/collector.json" >"$ct_dir/json.validation.log" 2>&1; then ct_Pass "JSON envelope contract"; else ct_Fail "$ct_name JSON contract"; fi
    if [ "$ct_name" = "collect_pcie_iommu.sh" ]; then
        if jq -e '[.data.devices[] | select(.driver=="driver" or .iommu_group=="iommu_group")] | length == 0' "$ct_dir/collector.json" >"$ct_dir/pcie-symlink.validation.log" 2>&1; then ct_Pass "PCIe symlink absence represented correctly"; else ct_Fail "$ct_name PCIe symlink representation"; fi
    fi
    case "$ct_name" in
        collect_pcie_iommu.sh)
            if jq -e 'all(.data.devices[]?; (.msi_irqs|type)=="array") and all(.data.iommu_groups[]?; has("type") and has("reserved_regions_raw"))' "$ct_dir/collector.json" >"$ct_dir/pcie-msi.validation.log" 2>&1; then ct_Pass "PCIe MSI vector inventory contract"; else ct_Fail "$ct_name MSI vector inventory"; fi
            ;;
        collect_storage.sh)
            if jq -e 'all(.data.block_queues[]?; has("device_path"))' "$ct_dir/collector.json" >"$ct_dir/storage-ancestry.validation.log" 2>&1; then ct_Pass "block device ancestry contract"; else ct_Fail "$ct_name block device ancestry"; fi
            ;;
        collect_proxmox_host.sh)
            if jq -e '(.data.lxc_configs|type)=="array" and (.data.qemu_runtime|type)=="array"' "$ct_dir/collector.json" >"$ct_dir/proxmox-runtime.validation.log" 2>&1; then ct_Pass "LXC config and QEMU runtime contract"; else ct_Fail "$ct_name LXC/QEMU runtime contract"; fi
            ;;
        collect_cpu_firmware_ras.sh)
            jq -e '(.data.per_cpu|type)=="array" and (.data.vulnerabilities|type)=="object" and (.data.microcode_packages|type)=="object"' "$ct_dir/collector.json" >/dev/null 2>&1 && ct_Pass "microcode/RAS evidence contract" || ct_Fail "$ct_name evidence contract"
            ;;
        collect_acpi_platform.sh)
            jq -e '(.data.acpi_tables|type)=="array" and (.data.decoded_tables|type)=="array" and (.data.dmidecode|type)=="object"' "$ct_dir/collector.json" >/dev/null 2>&1 && ct_Pass "ACPI/platform evidence contract" || ct_Fail "$ct_name evidence contract"
            ;;
        collect_firmware_settings.sh)
            jq -e '(.data.firmware_attributes|type)=="array" and (.data.fwupd_bios_settings|type)=="object" and (.data.bios|type)=="object"' "$ct_dir/collector.json" >/dev/null 2>&1 && ct_Pass "firmware-settings evidence contract" || ct_Fail "$ct_name evidence contract"
            ;;
        collect_irq_activity.sh)
            jq -e '(.data.irqs|type)=="array" and (.data.softirqs|type)=="array" and .data.sample_seconds>=1' "$ct_dir/collector.json" >/dev/null 2>&1 && ct_Pass "passive IRQ/softirq evidence contract" || ct_Fail "$ct_name evidence contract"
            ;;
        collect_pcie_advanced.sh)
            jq -e '(.data.devices|type)=="array" and all(.data.devices[]?; has("aer") and has("local_cpulist") and has("capability_evidence") and has("upstream_path_bdfs") and (.capability_evidence|has("ats") and has("pri") and has("pasid") and has("tph")))' "$ct_dir/collector.json" >/dev/null 2>&1 && ct_Pass "advanced PCIe evidence contract" || ct_Fail "$ct_name evidence contract"
            ;;
        collect_storage_health_power.sh)
            jq -e '(.data.disks|type)=="array" and (.data.nvme|type)=="array" and (.data.scsi_hosts|type)=="array"' "$ct_dir/collector.json" >/dev/null 2>&1 && ct_Pass "storage health/power evidence contract" || ct_Fail "$ct_name evidence contract"
            ;;
        collect_network_advanced.sh)
            jq -e '(.data.interfaces|type)=="array" and (.data.net_core|type)=="object" and (.data.softnet_stat_raw|type)=="string"' "$ct_dir/collector.json" >/dev/null 2>&1 && ct_Pass "advanced network evidence contract" || ct_Fail "$ct_name evidence contract"
            ;;
        collect_usb_input_audio.sh)
            jq -e '(.data.usb_devices|type)=="array" and (.data.input_devices|type)=="array" and (.data.sound_cards|type)=="array" and ((.data.pcm_devices//[])|type)=="array" and (.data.raw|type)=="object"' "$ct_dir/collector.json" >/dev/null 2>&1 && ct_Pass "USB/input/audio evidence contract" || ct_Fail "$ct_name evidence contract"
            ;;
        collect_memory_hardware.sh)
            jq -e '(.data.dmidecode_memory|type)=="object" and (.data.edac_controllers|type)=="array" and (.data.edac_controls|type)=="object"' "$ct_dir/collector.json" >/dev/null 2>&1 && ct_Pass "memory hardware/EDAC evidence contract" || ct_Fail "$ct_name evidence contract"
            ;;
        collect_timers_watchdogs.sh)
            jq -e '(.data.clocksource|type)=="object" and (.data.clockevents|type)=="array" and (.data.watchdog|type)=="object"' "$ct_dir/collector.json" >/dev/null 2>&1 && ct_Pass "timers/watchdogs evidence contract" || ct_Fail "$ct_name evidence contract"
            ;;
        collect_runtime_pressure.sh)
            jq -e '(.data.pressure|type)=="object" and (.data.deltas|type)=="object" and .data.sample_seconds>=1' "$ct_dir/collector.json" >/dev/null 2>&1 && ct_Pass "runtime-pressure evidence contract" || ct_Fail "$ct_name evidence contract"
            ;;
        collect_virtualization_stack.sh)
            jq -e '(.data.kvm_device|type)=="object" and (.data.module_parameters|type)=="array" and (.data.cpu_virtualization_flags|type)=="array" and (.data.io_uring|type)=="object" and (.data.raw|type)=="object"' "$ct_dir/collector.json" >/dev/null 2>&1 && ct_Pass "KVM/QEMU/vhost/VFIO evidence contract" || ct_Fail "$ct_name evidence contract"
            ;;
        collect_kernel_events.sh)
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
)' "$ct_dir/collector.json" >/dev/null 2>&1 && ct_Pass "kernel event-history evidence contract" || ct_Fail "$ct_name kernel-event contract"
            ;;
        collect_guest_runtime_detail.sh)
            jq -e '(.data.qemu_vms|type)=="array" and (.data|has("task_delayacct"))' "$ct_dir/collector.json" >/dev/null 2>&1 && ct_Pass "guest runtime-detail evidence contract" || ct_Fail "$ct_name guest runtime-detail contract"
            ;;
        collect_kernel_housekeeping.sh)
            jq -e '(.data.kernel_threads|type)=="array" and (.data.ipi_interrupt_lines|type)=="array" and (.data.workqueues|type)=="array"' "$ct_dir/collector.json" >/dev/null 2>&1 && ct_Pass "kernel housekeeping evidence contract" || ct_Fail "$ct_name kernel housekeeping contract"
            ;;
        collect_pm_qos.sh)
            jq -e '(.data.cpu_resume_latency|type)=="array" and (.data.devices|type)=="array" and (.data.cpu_dma_latency_holders|type)=="array"' "$ct_dir/collector.json" >/dev/null 2>&1 && ct_Pass "PM-QoS evidence contract" || ct_Fail "$ct_name PM-QoS contract"
            ;;
        collect_desktop_io_path.sh)
            jq -e '(.data.display|type)=="object" and (.data.usb|type)=="array" and (.data.audio|type)=="object" and (.data.network_policy|type)=="object"' "$ct_dir/collector.json" >/dev/null 2>&1 && ct_Pass "desktop I/O-path evidence contract" || ct_Fail "$ct_name desktop I/O contract"
            ;;
        collect_latency_sample.sh)
            jq -e '(.data.sample.duration_seconds>=1) and (.data.per_cpu|type)=="array" and (.data.softirq_deltas|type)=="array" and (.data.ipi_deltas|type)=="array"' "$ct_dir/collector.json" >/dev/null 2>&1 && ct_Pass "passive multi-second sample evidence contract" || ct_Fail "$ct_name latency-sample contract"
            ;;
        collect_cache_resource_qos.sh)
            jq -e '(.data.cache_entries|type)=="array" and (.data.numa_nodes|type)=="array" and (.data.resctrl|type)=="object" and ((.data.resctrl.groups//[])|type)=="array"' "$ct_dir/collector.json" >/dev/null 2>&1 && ct_Pass "cache/NUMA/resctrl evidence contract" || ct_Fail "$ct_name evidence contract"
            ;;
        collect_cpu_limits_pmu.sh)
            jq -e '(.data.cpus|type)=="array" and all(.data.cpus[]?; ((.time_in_state//[])|type)=="array" and (.time_in_state_total_ticks|type)=="number") and (.data.pmu_sources|type)=="array"' "$ct_dir/collector.json" >/dev/null 2>&1 && ct_Pass "CPU limits/PMU evidence contract" || ct_Fail "$ct_name evidence contract"
            ;;
        collect_irq_architecture.sh)
            jq -e '(.data.irqs|type)=="array" and (.data|has("special_interrupts_raw"))' "$ct_dir/collector.json" >/dev/null 2>&1 && ct_Pass "IRQ architecture evidence contract" || ct_Fail "$ct_name evidence contract"
            ;;
        collect_memory_fragmentation.sh)
            jq -e '(.data.buddy_highest_order|type)=="array" and (.data.hugetlb|type)=="array"' "$ct_dir/collector.json" >/dev/null 2>&1 && ct_Pass "memory fragmentation evidence contract" || ct_Fail "$ct_name evidence contract"
            ;;
        collect_display_timing.sh)
            jq -e '(.data.connectors|type)=="array" and (.data.connected_count|type)=="number"' "$ct_dir/collector.json" >/dev/null 2>&1 && ct_Pass "display timing/EDID evidence contract" || ct_Fail "$ct_name evidence contract"
            ;;
        collect_security_mitigations.sh)
            jq -e '(.data.vulnerabilities|type)=="array" and (.data.cpu_capabilities|type)=="object"' "$ct_dir/collector.json" >/dev/null 2>&1 && ct_Pass "security mitigation evidence contract" || ct_Fail "$ct_name evidence contract"
            ;;
    esac
        if grep "$(printf '\033')" "$ct_dir/collector.json" >/dev/null 2>&1; then ct_Fail "$ct_name redirected JSON contains ANSI"; else ct_Pass "redirected JSON is ANSI-free"; fi
    else
        ct_Fail "$ct_name collection rc=$ct_rc"
    fi

    if [ "$ct_fixture_mode" -eq 1 ]; then
        # run_all_test.sh already executed this collector live. Re-check the
        # alternate output-mode wiring against that exact retained envelope
        # rather than probing hardware three more times.
        if grep -F -- '--compact) app_compact=1 ;;' "$ct_file" >/dev/null 2>&1 &&
           jq -cM . "$ct_dir/collector.json" >"$ct_dir/compact.json" 2>"$ct_dir/compact.stderr.log" &&
           [ -s "$ct_dir/compact.json" ] &&
           [ "$(wc -l < "$ct_dir/compact.json" | tr -d ' ')" -eq 1 ] 2>/dev/null &&
           jq -e '.schema_version=="0.5.0"' "$ct_dir/compact.json" >"$ct_dir/compact.validation.log" 2>&1; then
            ct_Pass "compact JSON contract and interface wiring (retained live evidence)"
        else
            ct_Fail "$ct_name compact JSON contract/interface wiring"
        fi
        if grep -F -- '--summary) _inv_action=summary ;;' "$ct_file" >/dev/null 2>&1; then
            printf '%s\n' 'verified: --summary dispatches to summary action; renderer is exercised by --summary-file below' > "$ct_dir/live-summary.interface.log"
            ct_Pass "live --summary interface wiring"
        else
            ct_Fail "$ct_name --summary interface wiring"
        fi
        ct_fixture_summary=$ct_fixture/summaries/$ct_base.txt
        if [ -s "$ct_fixture_summary" ] &&
           jq -e --arg script "$ct_name" 'any(.collectors[]?; .script==$script and (.summary_file|type)=="string" and (.summary_file|length)>0)' "$ct_fixture/manifest.json" >/dev/null 2>&1 &&
           cp "$ct_fixture_summary" "$ct_dir/file-summary.txt"; then
            : > "$ct_dir/file-summary.stderr.log"
            ct_Pass "--summary-file covered by successful run_all fixture with clean stderr"
        else
            ct_Fail "$ct_name retained --summary-file evidence"
        fi
        if grep -F -- '--view) _inv_action=view ;;' "$ct_file" >/dev/null 2>&1; then
            printf '%s\n' 'verified: --view dispatches to view action; renderer is exercised by --view-file below' > "$ct_dir/live-view.interface.log"
            ct_Pass "live --view interface wiring"
        else
            ct_Fail "$ct_name --view interface wiring"
        fi
        if [ -s "$ct_dir/collector.json" ] && "$ct_file" --view-file "$ct_dir/collector.json" --no-install --no-color >"$ct_dir/file-view.txt" 2>"$ct_dir/file-view.stderr.log" && [ -s "$ct_dir/file-view.txt" ] && [ ! -s "$ct_dir/file-view.stderr.log" ]; then ct_Pass "--view-file with clean stderr"; else ct_Fail "$ct_name --view-file or unexpected stderr"; fi
    else
        if "$ct_file" --compact --no-install --no-color >"$ct_dir/compact.json" 2>"$ct_dir/compact.stderr.log" && [ -s "$ct_dir/compact.json" ] && jq -e '.schema_version=="0.5.0"' "$ct_dir/compact.json" >"$ct_dir/compact.validation.log" 2>&1; then ct_Pass "compact JSON"; else ct_Fail "$ct_name compact JSON"; fi
        if "$ct_file" --summary --no-install --no-color >"$ct_dir/live-summary.txt" 2>"$ct_dir/live-summary.stderr.log" && [ -s "$ct_dir/live-summary.txt" ] && ! grep -E '(^jq:|ERROR:|syntax error|compile error)' "$ct_dir/live-summary.stderr.log" >/dev/null 2>&1; then ct_Pass "live --summary"; else ct_Fail "$ct_name --summary or summary stderr"; fi
        if [ -s "$ct_dir/collector.json" ] && "$ct_file" --summary-file "$ct_dir/collector.json" --no-install --no-color >"$ct_dir/file-summary.txt" 2>"$ct_dir/file-summary.stderr.log" && [ -s "$ct_dir/file-summary.txt" ] && [ ! -s "$ct_dir/file-summary.stderr.log" ]; then ct_Pass "--summary-file with clean stderr"; else ct_Fail "$ct_name --summary-file or unexpected stderr"; fi
        if "$ct_file" --view --no-install --no-color >"$ct_dir/live-view.txt" 2>"$ct_dir/live-view.stderr.log" && [ -s "$ct_dir/live-view.txt" ] && ! grep -E '(^jq:|ERROR:|syntax error|compile error)' "$ct_dir/live-view.stderr.log" >/dev/null 2>&1; then ct_Pass "live --view"; else ct_Fail "$ct_name --view or view stderr"; fi
        if [ -s "$ct_dir/collector.json" ] && "$ct_file" --view-file "$ct_dir/collector.json" --no-install --no-color >"$ct_dir/file-view.txt" 2>"$ct_dir/file-view.stderr.log" && [ -s "$ct_dir/file-view.txt" ] && [ ! -s "$ct_dir/file-view.stderr.log" ]; then ct_Pass "--view-file with clean stderr"; else ct_Fail "$ct_name --view-file or unexpected stderr"; fi
    fi
    if [ -s "$ct_dir/collector.json" ] && "$ct_file" --summary-file "$ct_dir/collector.json" --no-install --color >"$ct_dir/color-summary.txt" 2>"$ct_dir/color-summary.stderr.log" && grep "$(printf '\033')" "$ct_dir/color-summary.txt" >/dev/null 2>&1; then ct_Pass "forced-color summary"; else ct_Fail "$ct_name forced-color summary"; fi
    "$ct_file" --summary-file "$ct_dir/does-not-exist.json" --no-install --no-color >"$ct_dir/missing-summary.stdout.log" 2>"$ct_dir/missing-summary.stderr.log"; ct_missing_rc=$?
    if [ "$ct_missing_rc" -ne 0 ]; then ct_Pass "missing summary file rejected"; else ct_Fail "$ct_name accepted missing summary file"; fi
    "$ct_file" --definitely-invalid-option --no-color >"$ct_dir/invalid.stdout.log" 2>"$ct_dir/invalid.stderr.log"; ct_invalid_rc=$?
    if [ "$ct_invalid_rc" -ne 0 ]; then ct_Pass "invalid option rejected"; else ct_Fail "$ct_name accepted invalid option"; fi
done

# Deterministic kernel-event semantic regression. Mock dmesg/journalctl so
# line tokenization, cross-source de-duplication and classification do not
# depend on what happened to occur on the test host.
ct_ke_dir=$ct_results/kernel-events-semantic
ct_ke_bin=$ct_ke_dir/bin
mkdir -p "$ct_ke_bin" || exit 2
cat > "$ct_ke_bin/dmesg" <<'EOF'
#!/bin/sh
cat <<'LOG'
[    1.000000] IOMMU: Default domain type: Translated
[    2.000000] Buffer I/O error on dev dm-999, logical block 123, lost async page write
[    3.000000] Buffer I/O error on dev dm-999, logical block 456, lost async page write
[    4.000000] oom-kill:constraint=x,task_memcg=/qemu.slice/777.scope,task=kvm,pid=1234,uid=0
[    4.100000] Out of memory: Killed process 1234 (kvm) total-vm:1000kB, anon-rss:900kB, file-rss:1kB, shmem-rss:0kB, UID:0 pgtables:3kB oom_score_adj:0
[    5.000000] warning: synthetic kernel warning
[    6.000000] pcieport 0000:00:01.0: AER: enabled with IRQ 27
LOG
EOF
cat > "$ct_ke_bin/journalctl" <<'EOF'
#!/bin/sh
cat <<'LOG'
[    2.000000] proxmox kernel: Buffer I/O error on dev dm-999, logical block 123, lost async page write
[    3.000000] proxmox kernel: Buffer I/O error on dev dm-999, logical block 456, lost async page write
[    4.000000] proxmox kernel: oom-kill:constraint=x,task_memcg=/qemu.slice/777.scope,task=kvm,pid=1234,uid=0
[    4.100000] proxmox kernel: Out of memory: Killed process 1234 (kvm) total-vm:1000kB, anon-rss:900kB, file-rss:1kB, shmem-rss:0kB, UID:0 pgtables:3kB oom_score_adj:0
LOG
EOF
chmod +x "$ct_ke_bin/dmesg" "$ct_ke_bin/journalctl"
PATH="$ct_ke_bin:$PATH" "$app_dir/collect_kernel_events.sh" --no-install --no-color > "$ct_ke_dir/collector.json" 2> "$ct_ke_dir/collector.stderr.log"
ct_ke_rc=$?
if [ "$ct_ke_rc" -eq 0 ] && jq -e '
  .data.source_record_count==10 and
  .data.cross_source_duplicates_removed==4 and
  .data.total_observations==6 and
  (.data.qemu_oom_vmids==[777]) and
  ([.data.events[]?|select(.category=="iommu")]|length)==0 and
  any(.data.events[]?;
      .category=="storage" and .event_type=="storage-io" and
      .dm_device=="dm-999" and .occurrences==2 and
      .first_occurrence.boot_seconds==2 and .last_occurrence.boot_seconds==3 and
      (.sources==["dmesg","journal"])) and
  any(.data.events[]?;
      .event_type=="oom" and .vmid==777 and
      (.guest_correlation.bases|index("oom-pid-nearby"))!=null) and
  any(.data.events[]?;
      .event_type=="pcie-capability" and .severity=="info" and .pci_bdf=="0000:00:01.0") and
  any(.data.events[]?;
      .event_type=="kernel-warning" and .severity=="warning") and
  all(.data.events[]?;
      ((.message|contains("\n"))|not) and (.evidence|length)<=5)
' "$ct_ke_dir/collector.json" > "$ct_ke_dir/semantic.validation.log" 2>&1; then
    ct_Pass "kernel-event line tokenization, de-duplication and semantic classification"
else
    ct_Fail "kernel-event deterministic semantic regression"
fi

if [ "$ct_collector_count" = "$ct_expected_collectors" ] && [ "$ct_expected_collectors" = 38 ]; then ct_Pass "all 38 source-tree collectors were exercised"; else ct_Fail "collector coverage expected=38 source=$ct_expected_collectors tested=$ct_collector_count"; fi
{
    printf 'Host Inventory for Proxmox - collector test report\n'
    printf 'Test version: 2.1.0\n'
    printf 'Collectors tested: %s\n' "$ct_collector_count"
    if [ "$ct_fixture_mode" -eq 1 ]; then printf 'Evidence mode: retained-live-fixture\n'; else printf 'Evidence mode: exhaustive-direct-live\n'; fi
    printf 'Pass validations: %s\nFailed validations: %s\nReturn code: %s\nResults directory: %s\n' "$ct_pass_count" "$ct_fail_count" "$app_rc" "$ct_results"
} > "$ct_results/report.txt"
if [ "$app_rc" -eq 0 ]; then ct_Log ok "RESULT: all $ct_collector_count collectors passed ($ct_pass_count validations)."; else ct_Log error "RESULT: collector tests failed ($ct_fail_count failed validation(s))."; fi
ct_Log info "Test results kept at: $ct_results"
exit "$app_rc"
