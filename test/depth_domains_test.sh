#!/bin/sh
# ============================================================
# depth_domains_test.sh
# Tests v0.9.2 observation-depth collector/view pairs.
# Version: 1.2.0
# Environment:
#   HFIP_TEST_RESULTS_PARENT  optional grouped-results parent
#   HFIP_TEST_FIXTURE_DIR     optional retained live run_all fixture
# Returns: 0 pass, 1 validation failure, 2 setup failure
# ============================================================
app_rc=0
app_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd -P) || exit 2
ddt_timestamp=$(date '+%Y%m%d-%H%M%S')
if [ -n "${HFIP_TEST_RESULTS_PARENT-}" ]; then ddt_results=$HFIP_TEST_RESULTS_PARENT/depth_domains_test; else ddt_results=$app_dir/test/results/${ddt_timestamp}-depth_domains_test-$$; fi
mkdir -p "$ddt_results" || exit 2
ddt_log=$ddt_results/test.log; ddt_report=$ddt_results/report.txt; : > "$ddt_log" || exit 2
ddt_pass=0; ddt_fail=0; ddt_count=0; ddt_expected=6
ddt_fixture=${HFIP_TEST_FIXTURE_DIR-}
ddt_fixture_mode=0
ddt_source_collectors=$(find "$app_dir" -maxdepth 1 -type f -name 'collect_*.sh' 2>/dev/null | wc -l | tr -d ' ')
ddt_domains="cache_resource_qos cpu_limits_pmu irq_architecture memory_fragmentation display_timing security_mitigations"

ddt_log_msg() { printf '%s\n' "$*" | tee -a "$ddt_log"; }
ddt_pass_msg() { ddt_pass=$((ddt_pass+1)); ddt_log_msg "  PASS  $*"; }
ddt_fail_msg() { ddt_fail=$((ddt_fail+1)); app_rc=1; ddt_log_msg "  FAIL  $*"; }

ddt_contract() {
    ddc_domain=$1; ddc_file=$2
    case "$ddc_domain" in
        cache_resource_qos) jq -e '(.data.cache_entries|type)=="array" and (.data.numa_nodes|type)=="array" and (.data.resctrl|type)=="object" and ((.data.resctrl.groups//[])|type)=="array" and (.data.capabilities|type)=="object"' "$ddc_file" >/dev/null 2>&1 ;;
        cpu_limits_pmu) jq -e '(.data.cpus|type)=="array" and all(.data.cpus[]?; ((.time_in_state//[])|type)=="array" and (.time_in_state_total_ticks|type)=="number") and (.data.pmu_sources|type)=="array" and (.data|has("perf_event_paranoid"))' "$ddc_file" >/dev/null 2>&1 ;;
        irq_architecture) jq -e '(.data.irqs|type)=="array" and (.data|has("special_interrupts_raw")) and (.data|has("managed_irq_detection"))' "$ddc_file" >/dev/null 2>&1 ;;
        memory_fragmentation) jq -e '(.data.buddy_highest_order|type)=="array" and (.data.hugetlb|type)=="array" and (.data.transparent_hugepage|type)=="object" and (.data.vm_tunables|type)=="object"' "$ddc_file" >/dev/null 2>&1 ;;
        display_timing) jq -e '(.data.connectors|type)=="array" and (.data.connected_count|type)=="number" and all(.data.connectors[]?; (.edid|type)=="object")' "$ddc_file" >/dev/null 2>&1 ;;
        security_mitigations) jq -e '(.data.vulnerabilities|type)=="array" and (.data.cpu_capabilities|type)=="object" and (.data.smt|type)=="object"' "$ddc_file" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

ddt_marker() {
    case "$1" in
        cache_resource_qos) printf '%s' 'Cache / NUMA / Resource QoS View' ;;
        cpu_limits_pmu) printf '%s' 'CPU Performance Limits / PMU View' ;;
        irq_architecture) printf '%s' 'IRQ Architecture View' ;;
        memory_fragmentation) printf '%s' 'Memory Fragmentation / Hugepage Feasibility View' ;;
        display_timing) printf '%s' 'Display Timing / EDID View' ;;
        security_mitigations) printf '%s' 'Security Mitigations / Performance Dimension View' ;;
    esac
}

ddt_log_msg "Host Inventory for Proxmox - observation depth-domain tests"
ddt_log_msg "Results directory: $ddt_results"
if [ -n "$ddt_fixture" ]; then
    if [ -d "$ddt_fixture" ] && [ -s "$ddt_fixture/inventory.json" ] &&
       jq -e --argjson expected "$ddt_source_collectors" 'type=="array" and length==$expected' "$ddt_fixture/inventory.json" >/dev/null 2>&1; then
        ddt_fixture_mode=1
        ddt_log_msg "Evidence mode: retained live fixture from run_all_test.sh"
    else
        ddt_log_msg "ERROR: HFIP_TEST_FIXTURE_DIR is not a valid complete collector fixture: $ddt_fixture"
        exit 2
    fi
else
    ddt_log_msg "Evidence mode: direct live collector execution"
fi
for ddt_domain in $ddt_domains; do
    ddt_count=$((ddt_count+1)); ddt_c=$app_dir/collect_$ddt_domain.sh; ddt_v=$app_dir/view_$ddt_domain.sh; ddt_d=$ddt_results/$ddt_domain
    mkdir -p "$ddt_d" || exit 2
    ddt_log_msg "[$ddt_count/$ddt_expected] Testing $ddt_domain"
    if [ -x "$ddt_c" ] && [ -x "$ddt_v" ]; then ddt_pass_msg "collector/view pair present"; else ddt_fail_msg "collector/view pair missing"; continue; fi
    if sh -n "$ddt_c" && sh -n "$ddt_v"; then ddt_pass_msg "shell syntax"; else ddt_fail_msg "shell syntax"; fi
    if grep -E -- '--arg(json)?[[:space:]]+(module|end)([[:space:]]|$)' "$ddt_c" "$ddt_v" >/dev/null 2>&1; then ddt_fail_msg "jq 1.6 reserved-variable guard"; else ddt_pass_msg "jq 1.6 reserved-variable guard"; fi
    if [ "$ddt_fixture_mode" -eq 1 ]; then
        ddt_fixture_json=$ddt_fixture/collect_$ddt_domain.json
        if [ -s "$ddt_fixture_json" ] && cp "$ddt_fixture_json" "$ddt_d/collector.json"; then
            : > "$ddt_d/collector.stderr.log"
            ddt_rc=0
            ddt_pass_msg "collector evidence reused from supplied live fixture"
        else
            ddt_rc=1
            ddt_fail_msg "collector evidence missing from supplied live fixture"
        fi
    else
        "$ddt_c" --no-install --no-color >"$ddt_d/collector.json" 2>"$ddt_d/collector.stderr.log"; ddt_rc=$?
        if [ "$ddt_rc" -eq 0 ]; then ddt_pass_msg "collector rc=0"; else ddt_fail_msg "collector rc=$ddt_rc"; fi
    fi
    ddt_expected_name=$(printf '%s' "$ddt_domain" | tr '_' '-')
    if [ -s "$ddt_d/collector.json" ] && jq -e --arg c "$ddt_expected_name" '.schema_version=="0.5.0" and .collector==$c and (.data|type)=="object" and (.errors|type)=="array"' "$ddt_d/collector.json" >/dev/null 2>&1; then ddt_pass_msg "envelope contract"; else ddt_fail_msg "envelope contract"; fi
    if ddt_contract "$ddt_domain" "$ddt_d/collector.json"; then ddt_pass_msg "domain evidence contract"; else ddt_fail_msg "domain evidence contract"; fi
    "$ddt_v" --file "$ddt_d/collector.json" --no-install --no-color >"$ddt_d/view.txt" 2>"$ddt_d/view.stderr.log"; ddt_vrc=$?
    if [ "$ddt_vrc" -eq 0 ] && [ -s "$ddt_d/view.txt" ] && [ ! -s "$ddt_d/view.stderr.log" ]; then ddt_pass_msg "saved-data view"; else ddt_fail_msg "saved-data view"; fi
    ddt_m=$(ddt_marker "$ddt_domain"); if grep -F "$ddt_m" "$ddt_d/view.txt" >/dev/null 2>&1; then ddt_pass_msg "view layout"; else ddt_fail_msg "view layout"; fi
    if grep "$(printf '\033')" "$ddt_d/collector.json" "$ddt_d/view.txt" >/dev/null 2>&1; then ddt_fail_msg "no-color artifacts ANSI-free"; else ddt_pass_msg "no-color artifacts ANSI-free"; fi
done
if [ "$ddt_count" -eq "$ddt_expected" ]; then ddt_pass_msg "all $ddt_expected depth domains exercised"; else ddt_fail_msg "depth-domain coverage"; fi
{
  printf 'Host Inventory for Proxmox - depth-domain test report\n'
  printf 'Test version: 1.2.0\nDomains tested: %s\n' "$ddt_count"
  if [ "$ddt_fixture_mode" -eq 1 ]; then printf 'Evidence mode: retained-live-fixture\n'; else printf 'Evidence mode: direct-live\n'; fi
  printf 'Pass validations: %s\nFailed validations: %s\nReturn code: %s\nResults directory: %s\n' "$ddt_pass" "$ddt_fail" "$app_rc" "$ddt_results"
} > "$ddt_report"
if [ "$app_rc" -eq 0 ]; then ddt_log_msg "RESULT: all depth domains passed ($ddt_pass validations)."; else ddt_log_msg "RESULT: depth-domain tests failed ($ddt_fail failed validations)."; fi
ddt_log_msg "Test results kept at: $ddt_results"
exit "$app_rc"
