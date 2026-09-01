#!/bin/sh
# ============================================================
# desktop_vm_view_test.sh
# Tests the derived per-desktop-VM host-path view.
#
# Version:
#   1.1.0
# ============================================================
app_rc=0
dvt_test_version=1.1.0
app_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd -P) || exit 2
dvt_timestamp=$(date '+%Y%m%d-%H%M%S')
if [ -n "${HFIP_TEST_RESULTS_PARENT-}" ]; then dvt_results=$HFIP_TEST_RESULTS_PARENT/desktop_vm_view_test; else dvt_results=$app_dir/test/results/${dvt_timestamp}-desktop_vm_view_test-$$; fi
mkdir -p "$dvt_results" || exit 2
dvt_log=$dvt_results/test.log; : >"$dvt_log"
dvt_pass=0; dvt_fail=0
dvt_Log(){ printf '%s\n' "$*"; printf '%s\n' "$*" >>"$dvt_log"; }
dvt_Pass(){ dvt_pass=$((dvt_pass+1)); dvt_Log "PASS  $*"; }
dvt_Fail(){ dvt_fail=$((dvt_fail+1)); app_rc=1; dvt_Log "FAIL  $*"; }

dvt_script=$app_dir/view_desktop_vm.sh
dvt_Log "Host Inventory for Proxmox - desktop VM derived-view tests"
dvt_Log "Results directory: $dvt_results"
sh -n "$dvt_script" && dvt_Pass "shell syntax" || dvt_Fail "shell syntax"
"$dvt_script" --help --no-color >"$dvt_results/help.txt" 2>"$dvt_results/help.stderr" && dvt_Pass "--help" || dvt_Fail "--help"
"$dvt_script" --version --no-color >"$dvt_results/version.txt" 2>"$dvt_results/version.stderr" && dvt_Pass "--version" || dvt_Fail "--version"

cat >"$dvt_results/synthetic-host-map.json" <<'EOF'
{
  "schema_version":"0.8.7","model":"host-map",
  "cpu":{"isolation":{"isolated":{"raw":"4-15"}}},
  "memory":{"swap":{"active":true},"transparent_hugepages":{"enabled_selected":"madvise"}},
  "kernel_events":{"total_events":1,"counts":{"oom":1}},
  "kernel_housekeeping":{"thread_count":7},
  "guest_runtime_detail":{"qemu_vms":[{"vmid":"999","process":{"migrations":2},"memory":{"rss_kb":1048576,"anon_huge_pages_kb":0}}]},
  "latency_sample":{"sample":{"duration_seconds":5},"qemu_deltas":[{"vmid":"999","sched_runtime_ns_delta":1000,"sched_wait_ns_delta":50,"migrations_delta":1}]},
  "pm_qos":{"cpu_dma_latency_present":true,"cpu_dma_latency_holders":[]},
  "desktop_io_path":{"network_policy":{"busy_poll":0,"busy_read":0},"usb":[{"endpoints":[{"bInterval":"1"}]}],"audio":{"snd_hda_intel_parameters":[]},"display":{"vtconsoles":[{"bound":true}]}},
  "storage":{"pve_storages":[{"name":"local","backing":{"base_block":"nvme0n1","pci_bdf":"0000:01:00.0"}}]},
  "proxmox":{"virtual_machines":[{"vmid":"999","name":"desktop-test","status":"running","cpu":{"cores":8,"affinity":"4-15"},"runtime":{"process_cpus_allowed_list":"4-15","process_online_cpus_allowed_list":"4-15"},"hostpci":[{"key":"hostpci0","bdf":"0000:0f:00.0"}],"disks":[{"key":"scsi0","storage":"local"}],"networks":[{"key":"net0","model":"virtio","bridge":"vmbr0","runtime_interface":"tap999i0"}]}]}
}
EOF

if "$dvt_script" --file "$dvt_results/synthetic-host-map.json" --list --no-color >"$dvt_results/list.txt" 2>"$dvt_results/list.stderr" && grep '999' "$dvt_results/list.txt" >/dev/null; then dvt_Pass "--list"; else dvt_Fail "--list"; fi
if "$dvt_script" --file "$dvt_results/synthetic-host-map.json" --vmid 999 --no-color >"$dvt_results/view.txt" 2>"$dvt_results/view.stderr" && grep 'Desktop VM Host Path - VM 999' "$dvt_results/view.txt" >/dev/null && grep 'Storage path' "$dvt_results/view.txt" >/dev/null && grep 'USB / input / audio' "$dvt_results/view.txt" >/dev/null; then dvt_Pass "derived VM path layout"; else dvt_Fail "derived VM path layout"; fi
if grep "$(printf '\033')" "$dvt_results/view.txt" >/dev/null 2>&1; then dvt_Fail "no-color view contains ANSI"; else dvt_Pass "no-color view is ANSI-free"; fi
if "$dvt_script" --file "$dvt_results/synthetic-host-map.json" --vmid 999 --color >"$dvt_results/color.txt" 2>"$dvt_results/color.stderr" && grep "$(printf '\033')" "$dvt_results/color.txt" >/dev/null 2>&1; then dvt_Pass "forced-color view"; else dvt_Fail "forced-color view"; fi
"$dvt_script" --file "$dvt_results/synthetic-host-map.json" --vmid 12345 --no-color >"$dvt_results/missing.txt" 2>"$dvt_results/missing.stderr"; dvt_missing=$?
[ "$dvt_missing" -ne 0 ] && dvt_Pass "missing VM rejected" || dvt_Fail "missing VM accepted"
cp "$dvt_script" "$dvt_results/isolated.sh"; chmod +x "$dvt_results/isolated.sh"
if "$dvt_results/isolated.sh" --file "$dvt_results/synthetic-host-map.json" --vmid 999 --no-color >"$dvt_results/isolated.txt" 2>"$dvt_results/isolated.stderr"; then dvt_Pass "standalone file-mode execution"; else dvt_Fail "standalone file-mode execution"; fi

if [ -n "${HFIP_TEST_FIXTURE_DIR-}" ] && [ -d "$HFIP_TEST_FIXTURE_DIR" ]; then
    if "$dvt_script" --from-run "$HFIP_TEST_FIXTURE_DIR" --list --no-color >"$dvt_results/from-run.txt" 2>"$dvt_results/from-run.stderr"; then dvt_Pass "saved-run wrapper mode"; else dvt_Fail "saved-run wrapper mode"; fi
else
    dvt_Pass "saved-run wrapper mode skipped (no supplied fixture)"
fi

{
  printf 'Host Inventory for Proxmox - desktop VM view test report\n'
  printf 'Test version: %s\nPass validations: %s\nFailed validations: %s\nReturn code: %s\nResults directory: %s\n' "$dvt_test_version" "$dvt_pass" "$dvt_fail" "$app_rc" "$dvt_results"
} >"$dvt_results/report.txt"
[ "$app_rc" -eq 0 ] && dvt_Log "RESULT: desktop VM view passed ($dvt_pass validations)." || dvt_Log "RESULT: desktop VM view failed ($dvt_fail validation(s))."
dvt_Log "Test results kept at: $dvt_results"
exit "$app_rc"
