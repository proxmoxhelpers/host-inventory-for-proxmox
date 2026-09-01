#!/bin/sh
# ============================================================
# harmonize_host_test.sh
# Tests the v0.9.2 application with host-map schema 0.8.9, including topology/evidence depth, optional-join
# parent preservation, presence-aware cgroup evidence, configured
# versus running guest counts, runtime affinity and replay.
#
# Version:
#   2.1.0
#
# Environment:
#   HFIP_TEST_FIXTURE_DIR  optional existing 38-collector run_all output
#                          used as the base fixture
#
# Returns:
#   0 when all harmonization tests pass
#   1 otherwise
# ============================================================
app_rc=0
hht_test_version=2.1.0
app_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd -P) || exit 2
hht_timestamp=$(date '+%Y%m%d-%H%M%S')
if [ -n "${HFIP_TEST_RESULTS_PARENT-}" ]; then hht_results=$HFIP_TEST_RESULTS_PARENT/harmonize_host_test; else hht_results=$app_dir/test/results/${hht_timestamp}-harmonize_host_test-$$; fi
hht_fixture=$hht_results/fixture
hht_semantic=$hht_results/semantic-fixture
hht_partial=$hht_results/partial-fixture
hht_log=$hht_results/test.log
hht_pass=0
hht_fail=0
hht_expected_collectors=$(find "$app_dir" -maxdepth 1 -type f -name 'collect_*.sh' 2>/dev/null | wc -l | tr -d ' ')
mkdir -p "$hht_results" || exit 2
: > "$hht_log" || exit 2

# ============================================================
# hht_Log
# Writes one test message to console and persistent log.
#
# Version:
#   1.0.0
# ============================================================
hht_Log() {
    printf '%s\n' "$*"
    printf '%s\n' "$*" >> "$hht_log"
    return 0
}

# ============================================================
# hht_Pass
# Records one passing validation.
#
# Version:
#   1.0.0
# ============================================================
hht_Pass() {
    hht_pass=$((hht_pass+1))
    hht_Log "PASS  $*"
    return 0
}

# ============================================================
# hht_Fail
# Records one failing validation.
#
# Version:
#   1.0.0
# ============================================================
hht_Fail() {
    hht_fail=$((hht_fail+1))
    app_rc=1
    hht_Log "FAIL  $*"
    return 0
}

hht_Log "Host Inventory for Proxmox - harmonization tests"
hht_Log "Results directory: $hht_results"

hht_Log "[1/12] Checking shell syntax and public interfaces"
for hht_script in harmonize_host.sh view_harmonized_host.sh; do
    if sh -n "$app_dir/$hht_script" >"$hht_results/$hht_script.syntax.stdout.log" 2>"$hht_results/$hht_script.syntax.stderr.log"; then hht_Pass "$hht_script syntax"; else hht_Fail "$hht_script syntax"; fi
    if "$app_dir/$hht_script" --help --no-color >"$hht_results/$hht_script.help.txt" 2>"$hht_results/$hht_script.help.stderr.log"; then hht_Pass "$hht_script --help"; else hht_Fail "$hht_script --help"; fi
    if "$app_dir/$hht_script" --version --no-color >"$hht_results/$hht_script.version.txt" 2>"$hht_results/$hht_script.version.stderr.log"; then hht_Pass "$hht_script --version"; else hht_Fail "$hht_script --version"; fi
done
if grep -E -- '--arg(json)?[[:space:]]+(module|end)([[:space:]]|$)' "$app_dir"/collect_*.sh "$app_dir"/view_*.sh >/dev/null 2>&1; then hht_Fail "jq 1.6 known reserved external-variable source guard"; else hht_Pass "jq 1.6 known reserved external-variable source guard"; fi

hht_Log "[2/12] Preparing one 38-collector fixture"
if [ -n "${HFIP_TEST_FIXTURE_DIR-}" ]; then
    hht_fixture=$HFIP_TEST_FIXTURE_DIR
    if [ -d "$hht_fixture" ] && jq -e --argjson expected "$hht_expected_collectors" 'type=="array" and length==$expected' "$hht_fixture/inventory.json" >"$hht_results/fixture.validation.log" 2>&1; then hht_Pass "reused supplied fixture with $hht_expected_collectors collectors"; else hht_Fail "supplied fixture inventory contract"; fi
else
    if HFIP_LATENCY_SAMPLE_DURATION=1 "$app_dir/run_all.sh" --skip-prepare --no-install --no-color --output "$hht_fixture" >"$hht_results/run_all.stdout.log" 2>"$hht_results/run_all.stderr.log"; then
        if jq -e --argjson expected "$hht_expected_collectors" 'type=="array" and length==$expected' "$hht_fixture/inventory.json" >"$hht_results/fixture.validation.log" 2>&1; then hht_Pass "fixture contains $hht_expected_collectors collectors"; else hht_Fail "fixture inventory contract"; fi
    else
        hht_Fail "run_all.sh fixture creation"
    fi
fi

hht_Log "[3/12] Checking v0.9.2 collector evidence"
if jq -e 'all(.data.devices[]?; (.msi_irqs|type)=="array") and all(.data.iommu_groups[]?; has("type") and has("reserved_regions_raw"))' "$hht_fixture/collect_pcie_iommu.json" >"$hht_results/msi-collector.validation.log" 2>&1; then hht_Pass "PCI collector emits msi_irqs arrays"; else hht_Fail "PCI msi_irqs collector contract"; fi
if jq -e 'all(.data.block_queues[]?; has("device_path"))' "$hht_fixture/collect_storage.json" >"$hht_results/block-ancestry.validation.log" 2>&1; then hht_Pass "storage collector emits block device_path evidence"; else hht_Fail "storage device_path collector contract"; fi
if jq -e '(.data.lxc_configs|type)=="array" and (.data.qemu_runtime|type)=="array" and (.data.lxc_runtime|type)=="array" and (.data.runtime_capabilities|type)=="object" and all(.data.qemu_runtime[]?; (.tasks|type)=="array" and (.vhost_threads|type)=="array" and (.cgroup|type)=="object")' "$hht_fixture/collect_proxmox_host.json" >"$hht_results/proxmox-runtime.validation.log" 2>&1; then hht_Pass "Proxmox collector emits guest runtime/cgroup evidence"; else hht_Fail "Proxmox additive runtime/cgroup collector contract"; fi
if jq -e 'all(.data.qemu_runtime[]?; (.cgroup|has("cpuset_cpus_present")) and (.cgroup|has("cpuset_cpus_effective_present")) and (.cgroup|has("cpu_weight_present")) and (.cgroup|has("cpu_max_present"))) and all(.data.lxc_runtime[]?; (.cgroup|has("cpuset_cpus_present")) and (.cgroup|has("cpuset_cpus_effective_present")) and (.cgroup|has("cpu_weight_present")) and (.cgroup|has("cpu_max_present")))' "$hht_fixture/collect_proxmox_host.json" >"$hht_results/cgroup-presence.validation.log" 2>&1; then hht_Pass "collector preserves cgroup interface file-presence booleans"; else hht_Fail "cgroup file-presence collector contract"; fi
if jq -e '(.data.per_cpu|type)=="array" and (.data.vulnerabilities|type)=="object"' "$hht_fixture/collect_cpu_firmware_ras.json" >"$hht_results/cpu-firmware.validation.log" 2>&1; then hht_Pass "CPU microcode/RAS collector shape"; else hht_Fail "CPU microcode/RAS collector shape"; fi
if jq -e '(.data.acpi_tables|type)=="array" and (.data.decoded_tables|type)=="array"' "$hht_fixture/collect_acpi_platform.json" >"$hht_results/acpi.validation.log" 2>&1; then hht_Pass "ACPI platform collector shape"; else hht_Fail "ACPI platform collector shape"; fi
if jq -e '(.data.irqs|type)=="array" and (.data.softirqs|type)=="array"' "$hht_fixture/collect_irq_activity.json" >"$hht_results/irq-activity.validation.log" 2>&1; then hht_Pass "IRQ activity collector shape"; else hht_Fail "IRQ activity collector shape"; fi
if jq -e '(.data.interfaces|type)=="array"' "$hht_fixture/collect_network_advanced.json" >"$hht_results/network-advanced.validation.log" 2>&1; then hht_Pass "advanced network collector shape"; else hht_Fail "advanced network collector shape"; fi
if [ -s "$hht_fixture/collect_virtualization_stack.json" ] && jq -e '(.data.kvm_device|type)=="object" and (.data.module_parameters|type)=="array" and (.data.cpu_virtualization_flags|type)=="array" and (.data.io_uring|type)=="object"' "$hht_fixture/collect_virtualization_stack.json" >"$hht_results/virtualization-stack.validation.log" 2>&1; then hht_Pass "virtualization-stack collector shape"; else hht_Fail "virtualization-stack collector shape"; fi
if jq -e '(.data.events|type)=="array" and (.data.counts_by_severity|type)=="object"' "$hht_fixture/collect_kernel_events.json" >/dev/null 2>&1; then hht_Pass "kernel-event history collector shape"; else hht_Fail "kernel-event history collector shape"; fi
if jq -e '(.data.qemu_vms|type)=="array" and (.data|has("task_delayacct"))' "$hht_fixture/collect_guest_runtime_detail.json" >/dev/null 2>&1; then hht_Pass "guest runtime-detail collector shape"; else hht_Fail "guest runtime-detail collector shape"; fi
if jq -e '(.data.kernel_threads|type)=="array" and (.data.ipi_interrupt_lines|type)=="array"' "$hht_fixture/collect_kernel_housekeeping.json" >/dev/null 2>&1; then hht_Pass "kernel-housekeeping collector shape"; else hht_Fail "kernel-housekeeping collector shape"; fi
if jq -e '(.data.devices|type)=="array" and (.data.cpu_dma_latency_holders|type)=="array"' "$hht_fixture/collect_pm_qos.json" >/dev/null 2>&1; then hht_Pass "PM-QoS collector shape"; else hht_Fail "PM-QoS collector shape"; fi
if jq -e '(.data.display|type)=="object" and (.data.network_policy|type)=="object"' "$hht_fixture/collect_desktop_io_path.json" >/dev/null 2>&1; then hht_Pass "desktop I/O-path collector shape"; else hht_Fail "desktop I/O-path collector shape"; fi
if jq -e '(.data.sample.duration_seconds>=1) and (.data.softirq_deltas|type)=="array"' "$hht_fixture/collect_latency_sample.json" >/dev/null 2>&1; then hht_Pass "latency sample collector shape"; else hht_Fail "latency sample collector shape"; fi
if jq -e '(.data.cache_entries|type)=="array" and (.data.resctrl|type)=="object" and ((.data.resctrl.groups//[])|type)=="array"' "$hht_fixture/collect_cache_resource_qos.json" >/dev/null 2>&1; then hht_Pass "cache/resource-QoS collector shape"; else hht_Fail "cache/resource-QoS collector shape"; fi
if jq -e '(.data.cpus|type)=="array" and all(.data.cpus[]?; ((.time_in_state//[])|type)=="array" and (.time_in_state_total_ticks|type)=="number") and (.data.pmu_sources|type)=="array"' "$hht_fixture/collect_cpu_limits_pmu.json" >/dev/null 2>&1; then hht_Pass "CPU limits/PMU collector shape"; else hht_Fail "CPU limits/PMU collector shape"; fi
if jq -e '(.data.irqs|type)=="array"' "$hht_fixture/collect_irq_architecture.json" >/dev/null 2>&1; then hht_Pass "IRQ architecture collector shape"; else hht_Fail "IRQ architecture collector shape"; fi
if jq -e '(.data.buddy_highest_order|type)=="array" and (.data.hugetlb|type)=="array"' "$hht_fixture/collect_memory_fragmentation.json" >/dev/null 2>&1; then hht_Pass "memory fragmentation collector shape"; else hht_Fail "memory fragmentation collector shape"; fi
if jq -e '(.data.connectors|type)=="array"' "$hht_fixture/collect_display_timing.json" >/dev/null 2>&1; then hht_Pass "display timing collector shape"; else hht_Fail "display timing collector shape"; fi
if jq -e '(.data.vulnerabilities|type)=="array" and (.data.cpu_capabilities|type)=="object"' "$hht_fixture/collect_security_mitigations.json" >/dev/null 2>&1; then hht_Pass "security mitigation collector shape"; else hht_Fail "security mitigation collector shape"; fi

hht_Log "[4/12] Building and validating strict host-map 0.8.9"
if "$app_dir/harmonize_host.sh" --from-run "$hht_fixture" --source-kind test-fixture --no-install --no-color --output "$hht_results/host-map.json" >"$hht_results/harmonize.stdout.log" 2>"$hht_results/harmonize.stderr.log"; then hht_Pass "strict harmonization completed"; else hht_Fail "strict harmonization execution"; fi
if jq -e --argjson expected "$hht_expected_collectors" '.schema_version=="0.8.9" and .model=="host-map" and .source.kind=="test-fixture" and (.source.collector_provenance|length)==$expected and .validation.strict==true and (.validation.present_collectors|length)==$expected and .validation.hostname_consistent==true' "$hht_results/host-map.json" >"$hht_results/host-map.validation.log" 2>&1; then hht_Pass "host-map 0.8.9 schema/provenance contract"; else hht_Fail "host-map schema/provenance contract"; fi
if [ "$hht_expected_collectors" = 38 ]; then hht_Pass "source tree exposes expected 38 collectors"; else hht_Fail "expected 38 source-tree collectors, found $hht_expected_collectors"; fi
if jq -e '(.platform_architecture|type)=="object" and (.firmware_settings|type)=="object" and (.virtualization_stack|type)=="object" and (.irq_activity|type)=="object" and (.runtime_pressure|type)=="object" and (.peripherals|type)=="object" and (.cpu.firmware_ras|type)=="object" and (.cpu.timers_watchdogs|type)=="object" and (.memory.hardware|type)=="object" and (.kernel_events|type)=="object" and (.guest_runtime_detail|type)=="object" and (.kernel_housekeeping|type)=="object" and (.pm_qos|type)=="object" and (.desktop_io_path|type)=="object" and (.latency_sample|type)=="object" and (.cache_resource_qos|type)=="object" and (.cpu_limits_pmu|type)=="object" and (.irq_architecture|type)=="object" and (.memory_fragmentation|type)=="object" and (.display_timing|type)=="object" and (.security_mitigations|type)=="object" and (.topology_graph|type)=="object" and (.capability_matrix|type)=="object" and (.evidence_catalog|type)=="array"' "$hht_results/host-map.json" >"$hht_results/extended-model.validation.log" 2>&1; then hht_Pass "all extended observation domains are preserved in host-map"; else hht_Fail "extended host-map domains"; fi
if jq -e '(.cpu.cores|length)==.cpu.physical_core_count and (.proxmox.virtual_machines|type=="array") and (.proxmox.containers|type=="array") and (.correlations.irq_sources|type=="array") and (.pci.irq_correlation_capability.msi_irqs_sysfs_collected|type)=="boolean"' "$hht_results/host-map.json" >"$hht_results/model-shape.validation.log" 2>&1; then hht_Pass "normalized CPU/guest/IRQ/MSI model shape"; else hht_Fail "normalized model shape"; fi
if jq -e '(.topology_graph.nodes|type)=="array" and (.topology_graph.edges|type)=="array" and all(.topology_graph.nodes[]?; has("id") and has("type")) and .topology_graph.integrity.all_edge_sources_have_nodes==true and .topology_graph.integrity.all_edge_targets_have_nodes==true and (.capability_matrix.resctrl|type)=="object" and (.capability_matrix.iommu.cmdline_arguments|type)=="array" and (.correlations.desktop_network_paths|type)=="array" and (.platform_architecture_summary.decoded_tables|type)=="array" and (.evidence_catalog|length)>=40 and all(.evidence_catalog[]?; (.path_prefixes|type)=="array" and (.source_collectors|type)=="array" and has("scope") and has("confidence") and has("stability")) and ((.capability_matrix.resctrl.groups//[])|type)=="array" and ((.capability_matrix.cpu_limits.frequency_residency//[])|type)=="array" and ((.capability_matrix.pcie.ats_devices//[])|type)=="array" and ((.capability_matrix.iommu.group_types//[])|type)=="array"' "$hht_results/host-map.json" >"$hht_results/depth-model.validation.log" 2>&1; then hht_Pass "topology graph/capability/evidence metadata model"; else hht_Fail "depth graph/capability/evidence model"; fi
if jq -e '.proxmox.guest_counts.configured_qemu==(.proxmox.virtual_machines|length) and .proxmox.guest_counts.configured_lxc==(.proxmox.containers|length) and .proxmox.guest_counts.running_qemu==([.proxmox.virtual_machines[]|select(.status=="running")]|length) and .proxmox.guest_counts.running_lxc==([.proxmox.containers[]|select(.status=="running")]|length)' "$hht_results/host-map.json" >"$hht_results/guest-counts.validation.log" 2>&1; then hht_Pass "configured/running guest counts are independently preserved"; else hht_Fail "configured/running guest count contract"; fi

hht_Log "[5/12] Checking normal cross-domain join shapes"
if jq -e 'all(.storage.nvme_controllers[]?; (.bdf==null or (.pci|type=="object")) and (.irq_correlation.configured_vectors|type)=="array" and (.irq_correlation.matches|type)=="array")' "$hht_results/host-map.json" >"$hht_results/storage-join.validation.log" 2>&1; then hht_Pass "NVMe -> PCI/configured-MSI/IRQ join shape"; else hht_Fail "NVMe join shape"; fi
if jq -e 'all(.network.physical_interfaces[]?; (.bdf==null or (.pci|type=="object")) and (.irq_correlation.configured_vectors|type)=="array")' "$hht_results/host-map.json" >"$hht_results/network-join.validation.log" 2>&1; then hht_Pass "NIC -> PCI/configured-MSI/IRQ join shape"; else hht_Fail "network join shape"; fi
if jq -e 'all(.gpu.devices[]?; (.slot_functions|type=="array") and (.irq_correlation.configured_vectors|type)=="array")' "$hht_results/host-map.json" >"$hht_results/gpu-join.validation.log" 2>&1; then hht_Pass "GPU -> PCI sibling/configured-MSI/IRQ join shape"; else hht_Fail "GPU join shape"; fi
if jq -e 'all(.network.bridges[]?; (.ports|type=="array") and (.configured_vm_guests|type=="array") and (.running_vm_guests|type=="array") and (.configured_lxc_guests|type=="array") and (.running_lxc_guests|type=="array"))' "$hht_results/host-map.json" >"$hht_results/bridge-join.validation.log" 2>&1; then hht_Pass "bridge configured/runtime guest join shape"; else hht_Fail "bridge guest join shape"; fi
if jq -e 'all(.proxmox.virtual_machines[]?; .config_scope.active_top_level_only==true and (.runtime|type=="object") and (.disks|type=="array") and all(.disks[]?; has("aio") and has("cache") and has("iothread") and has("queues")) and (.networks|type=="array") and all(.networks[]?; has("queues") and has("firewall") and has("mtu")))' "$hht_results/host-map.json" >"$hht_results/vm-normalization.validation.log" 2>&1; then hht_Pass "VM active-config/runtime/device-path normalization shape"; else hht_Fail "VM normalization"; fi

hht_Log "[6/12] Creating semantic fixture for snapshots, runtime affinity and LXC config"
cp -a "$hht_fixture" "$hht_semantic" || hht_Fail "semantic fixture copy"
hht_test_bdf=$(jq -r '.data.devices[0].bdf // empty' "$hht_semantic/collect_pcie_iommu.json")
if [ -z "$hht_test_bdf" ]; then hht_Fail "semantic fixture requires at least one PCI device"; hht_test_bdf=0000:00:00.0; fi
hht_pcie_tmp=$hht_results/pcie.semantic.json
jq '.data.devices[0].msi_irqs += [{irq:65000,type:"msi"}]' "$hht_semantic/collect_pcie_iommu.json" > "$hht_pcie_tmp" && mv "$hht_pcie_tmp" "$hht_semantic/collect_pcie_iommu.json"
hht_cpu_tmp=$hht_results/cpu.semantic.json
jq '.data.online="0-7" | .data.present="0-7" | .data.cpus |= map(select((.cpu|tonumber)<8))' "$hht_semantic/collect_cpu_topology.json" > "$hht_cpu_tmp" && mv "$hht_cpu_tmp" "$hht_semantic/collect_cpu_topology.json"
hht_cache_tmp=$hht_results/cache.semantic.json
jq '.data.cache_entries |= map(select((.cpu|tonumber)<8)) | .data.numa_nodes |= map(.cpulist="0-7")' "$hht_semantic/collect_cache_resource_qos.json" > "$hht_cache_tmp" && mv "$hht_cache_tmp" "$hht_semantic/collect_cache_resource_qos.json"
hht_pve_tmp=$hht_results/proxmox.semantic.json
jq '.data.vm_configs=[
 {vmid:"900",config_raw:"name: active-vm\ncores: 4\nmemory: 4096\ncpu: host\nscsi0: local-lvm:vm-900-disk-0,size=32G,aio=io_uring,cache=none,iothread=1,discard=on,ssd=1,queues=4\nnet0: virtio=AA:BB:CC:DD:EE:FF,bridge=vmbr0,queues=4,firewall=1,mtu=1500\nhostpci0: 0000:01:00.0\n[snap-old]\ncores: 99\nmemory: 99999\nscsi1: local-lvm:vm-900-old,size=999G\nnet1: e1000=00:00:00:00:00:01,bridge=oldbr\n"},
 {vmid:"902",config_raw:"name: stopped-vm\ncores: 2\nmemory: 1024\ncpu: host\nscsi0: local-lvm:vm-902-disk-0,size=8G\nnet0: virtio=AA:BB:CC:DD:EE:02,bridge=vmbr0\n"}
] | .data.qm_list={rc:0,stdout:" VMID NAME STATUS MEM(MB) BOOTDISK(GB) PID\n 900 active-vm running 4096 32.00 1234\n 902 stopped-vm stopped 1024 0.00 0\n",stderr:""} | .data.qemu_runtime=[{vmid:"900",pid:1234,cpus_allowed_list:"0-15",cgroup_raw:"0::/qemu.slice/900.scope",cgroup:{path:"/qemu.slice/900.scope",available:true,controllers_present:true,controllers:"cpu cpuset io memory pids",subtree_control_present:true,subtree_control:"",type_present:true,type:"domain",cpuset_cpus_present:true,cpuset_cpus:"",cpuset_cpus_effective_present:true,cpuset_cpus_effective:"2-7",cpuset_mems_present:true,cpuset_mems:"",cpuset_mems_effective_present:true,cpuset_mems_effective:"0",cpu_weight_present:true,cpu_weight:"100",cpu_max_present:true,cpu_max:"max 100000"},tasks:[{tid:1234,comm:"kvm",cpus_allowed_list:"0-15",is_main:true},{tid:1235,comm:"CPU 0/KVM",cpus_allowed_list:"4",is_main:false},{tid:1236,comm:"CPU 1/KVM",cpus_allowed_list:"5",is_main:false},{tid:1237,comm:"IO mon_iothread",cpus_allowed_list:"6",is_main:false},{tid:1238,comm:"vhost-1234",cpus_allowed_list:"0-15",is_main:false},{tid:1239,comm:"iou-wrk-1234",cpus_allowed_list:"0-15",is_main:false}],vhost_threads:[]}] | .data.lxc_configs=[
 {vmid:"901",config_raw:"hostname: active-ct\ncores: 2\ncpulimit: 1.5\ncpuset: 0-1\nmemory: 512\nswap: 0\nrootfs: local-lvm:subvol-901-disk-0,size=8G\nnet0: name=eth0,bridge=vmbr0,type=veth\n"},
 {vmid:"903",config_raw:"hostname: stopped-ct\ncores: 1\nmemory: 256\nswap: 0\nnet0: name=eth0,bridge=vmbr0,type=veth\n"}
] | .data.lxc_runtime=[{vmid:"901",pid:2222,cpus_allowed_list:"0-15",cgroup_raw:"0::/lxc/901",cgroup:{path:"/lxc/901",available:true,controllers_present:true,controllers:"cpu io memory pids",subtree_control_present:true,subtree_control:"",type_present:true,type:"domain",cpuset_cpus_present:false,cpuset_cpus:null,cpuset_cpus_effective_present:false,cpuset_cpus_effective:null,cpuset_mems_present:false,cpuset_mems:null,cpuset_mems_effective_present:false,cpuset_mems_effective:null,cpu_weight_present:false,cpu_weight:null,cpu_max_present:false,cpu_max:null}}] | .data.runtime_capabilities={lxc_info_available:true,cgroup_v2_present:true} | .data.pct_list={rc:0,stdout:"VMID Status Lock Name\n901 running - active-ct\n903 stopped - stopped-ct\n",stderr:""}' "$hht_semantic/collect_proxmox_host.json" > "$hht_pve_tmp" && mv "$hht_pve_tmp" "$hht_semantic/collect_proxmox_host.json"
hht_net_tmp=$hht_results/network.semantic.json
jq --arg bdf "$hht_test_bdf" '.data.bridge_config_raw="auto vmbr0\niface vmbr0 inet manual\n    bridge-ports hfipeth0\n" | .data.interfaces += [{name:"hfipeth0",operstate:"up",mtu:"1500",address:"00:00:00:00:08:00",numa_node:null,driver:"/sys/bus/pci/drivers/hfip-test",device_path:("/sys/devices/pci0000:00/"+$bdf),queues:[],channels:{rc:1},coalesce:{rc:1}},{name:"tap900i0",operstate:"up",mtu:"1500",address:"00:00:00:00:09:00",numa_node:null,driver:null,queues:[],channels:{rc:1},coalesce:{rc:1}},{name:"veth901i0",operstate:"up",mtu:"1500",address:"00:00:00:00:09:01",numa_node:null,driver:null,queues:[],channels:{rc:1},coalesce:{rc:1}}]' "$hht_semantic/collect_network.json" > "$hht_net_tmp" && mv "$hht_net_tmp" "$hht_semantic/collect_network.json"
if "$app_dir/harmonize_host.sh" --from-run "$hht_semantic" --source-kind test-fixture --no-install --no-color --output "$hht_results/semantic-host-map.json" >"$hht_results/semantic.stdout.log" 2>"$hht_results/semantic.stderr.log"; then hht_Pass "semantic fixture harmonized"; else hht_Fail "semantic fixture harmonization"; fi
if jq -e --arg bdf "$hht_test_bdf" '([.topology_graph.nodes[]|select(.id=="irq:65000")]|length)==1 and ([.topology_graph.edges[]|select(.from==("pci:"+$bdf) and .to=="irq:65000" and .relation=="msi-vector")]|length)==1 and .topology_graph.integrity.all_edge_sources_have_nodes==true and .topology_graph.integrity.all_edge_targets_have_nodes==true' "$hht_results/semantic-host-map.json" >"$hht_results/configured-msi-graph.validation.log" 2>&1; then hht_Pass "configured MSI vector absent from IRQ snapshot still has referentially valid graph node"; else hht_Fail "configured-MSI topology graph parent preservation"; fi

hht_Log "[7/12] Verifying snapshot-safe VM and actual QEMU thread affinity model"
if jq -e '.proxmox.virtual_machines[] | select(.vmid=="900") | .cpu.cores==4 and .memory.memory_mib==4096 and (.disks|length)==1 and (.networks|length)==1 and .config_scope.snapshot_count==1 and .config_scope.snapshot_names==["snap-old"]' "$hht_results/semantic-host-map.json" >"$hht_results/snapshot-safe.validation.log" 2>&1; then hht_Pass "snapshot sections cannot override active VM configuration"; else hht_Fail "snapshot-safe VM parsing"; fi
if jq -e '.proxmox.virtual_machines[] | select(.vmid=="900") | .runtime.observed==true and .runtime.process_cpus_allowed_list=="0-15" and .runtime.process_online_cpus_allowed_list=="0-7" and ([.runtime.threads[]|select(.role=="vcpu")]|length)==2 and ([.runtime.threads[]|select(.role=="iothread")]|length)==1 and ([.runtime.threads[]|select(.role=="vhost")]|length)==1 and ([.runtime.threads[]|select(.role=="io-uring-worker")]|length)==1 and (.runtime.vhost_threads|length)==1' "$hht_results/semantic-host-map.json" >"$hht_results/qemu-runtime.validation.log" 2>&1; then hht_Pass "QEMU vCPU/IOThread/vhost/io_uring role normalization"; else hht_Fail "QEMU runtime role normalization"; fi
if jq -e '.proxmox.virtual_machines[] | select(.vmid=="900") | .disks[0].aio=="io_uring" and .disks[0].cache=="none" and .disks[0].iothread=="1" and .disks[0].queues=="4" and .networks[0].queues=="4" and .networks[0].firewall=="1" and .networks[0].mtu=="1500"' "$hht_results/semantic-host-map.json" >"$hht_results/qemu-device-path.validation.log" 2>&1; then hht_Pass "QEMU storage/network performance options normalized"; else hht_Fail "QEMU device-path option normalization"; fi
if jq -e '.proxmox.virtual_machines[] | select(.vmid=="900") | (.disks|length)==1 and .disks[0].backup==null' "$hht_results/semantic-host-map.json" >"$hht_results/qemu-missing-backup.validation.log" 2>&1; then hht_Pass "disk without backup option preserves disk and emits backup=null"; else hht_Fail "disk missing-backup parent preservation"; fi
if jq -e '.proxmox.virtual_machines[] | select(.vmid=="902") | (.disks|length)==1 and .disks[0].cache==null' "$hht_results/semantic-host-map.json" >"$hht_results/qemu-missing-cache.validation.log" 2>&1; then hht_Pass "disk without cache option preserves disk and emits cache=null"; else hht_Fail "disk missing-cache parent preservation"; fi
if jq -e '.proxmox.virtual_machines[] | select(.vmid=="900") | (.networks|length)==1 and .networks[0].rate==null' "$hht_results/semantic-host-map.json" >"$hht_results/qemu-missing-rate.validation.log" 2>&1; then hht_Pass "network without rate option preserves network and emits rate=null"; else hht_Fail "network missing-rate parent preservation"; fi
if jq -e '.proxmox.virtual_machines[] | select(.vmid=="900") | (.networks|length)==1 and .networks[0].tag==null' "$hht_results/semantic-host-map.json" >"$hht_results/qemu-missing-tag.validation.log" 2>&1; then hht_Pass "network without tag option preserves network and emits tag=null"; else hht_Fail "network missing-tag parent preservation"; fi
if jq -e '.proxmox.virtual_machines[] | select(.vmid=="900") | (.hostpci|length)==1 and .hostpci[0].bdf=="0000:01:00.0" and .hostpci[0].pcie==null and .hostpci[0].rombar==null and .hostpci[0].x_vga==null and .hostpci[0].multifunction==null' "$hht_results/semantic-host-map.json" >"$hht_results/qemu-missing-hostpci-flags.validation.log" 2>&1; then hht_Pass "hostpci without optional flags preserves object and emits null flags"; else hht_Fail "hostpci missing-flag parent preservation"; fi
if jq -e '([.correlations.desktop_network_paths[]|select(.vmid=="900")]|length)==1 and ([.correlations.desktop_network_paths[]|select(.vmid=="900")][0].vhost_threads|length)==1 and ([.correlations.desktop_network_paths[]|select(.vmid=="900")][0].physical_paths|length)>=1 and ([.correlations.desktop_network_paths[]|select(.vmid=="900")][0].physical_paths[0].bdf//null)!=null' "$hht_results/semantic-host-map.json" >"$hht_results/network-vhost.validation.log" 2>&1; then hht_Pass "VM TAP/vhost/bridge/physical-NIC path correlation"; else hht_Fail "VM network-to-vhost correlation"; fi
if jq -e '.proxmox.virtual_machines[] | select(.vmid=="900") | .runtime.cgroup.path=="/qemu.slice/900.scope" and .runtime.cgroup.cpuset_interface_state=="exposed" and .runtime.cgroup.cpuset_cpus_state=="empty/inherited" and .runtime.cgroup.cpuset_cpus_effective=="2-7" and .runtime.cgroup.cpuset_cpus_effective_online=="2-7" and .runtime.cgroup.cpu_weight_state=="value" and .runtime.cgroup.cpu_weight=="100" and .runtime.cgroup.cpu_max=="max 100000"' "$hht_results/semantic-host-map.json" >"$hht_results/qemu-cgroup.validation.log" 2>&1; then hht_Pass "QEMU cgroup presence distinguishes inheritance from exposed values"; else hht_Fail "QEMU cgroup presence-aware normalization"; fi
if jq -e '(.proxmox.virtual_machines|length)==2 and (.proxmox.virtual_machines[]|select(.vmid=="902")|.status)=="stopped" and (.proxmox.virtual_machines[]|select(.vmid=="902")|.runtime.observed)==false and (.proxmox.containers|length)==2 and (.proxmox.containers[]|select(.vmid=="903")|.status)=="stopped" and (.proxmox.containers[]|select(.vmid=="903")|.runtime.observed)==false and .proxmox.guest_counts.configured_qemu==2 and .proxmox.guest_counts.running_qemu==1 and .proxmox.guest_counts.configured_lxc==2 and .proxmox.guest_counts.running_lxc==1' "$hht_results/semantic-host-map.json" >"$hht_results/stopped-guests.validation.log" 2>&1; then hht_Pass "optional runtime absence never deletes stopped configured guests"; else hht_Fail "stopped guest parent preservation"; fi

hht_Log "[8/12] Verifying LXC configuration and configured-vs-runtime bridge attachment"
if jq -e '.proxmox.containers[] | select(.vmid=="901") | .status=="running" and .cpu.cores==2 and .cpu.cpulimit==1.5 and .cpu.cpuset=="0-1" and .memory.memory_mib==512 and .memory.swap_mib==0 and .networks[0].bridge=="vmbr0" and .networks[0].runtime_present==true and .runtime.observed==true and .runtime.process_cpus_allowed_list=="0-15" and .runtime.process_online_cpus_allowed_list=="0-7" and .runtime.cgroup.cpuset_interface_state=="not-exposed" and .runtime.cgroup.cpu_weight_state=="not-exposed"' "$hht_results/semantic-host-map.json" >"$hht_results/lxc-config.validation.log" 2>&1; then hht_Pass "LXC cgroup absence is reported as not-exposed rather than inherited"; else hht_Fail "LXC presence-aware cgroup normalization"; fi
if jq -e '.network.bridges[] | select(.name=="vmbr0") | (.configured_vm_guests|length)==2 and (.running_vm_guests|length)==1 and ([.configured_vm_guests[]|select(.vmid=="900")][0].runtime_present)==true and ([.configured_vm_guests[]|select(.vmid=="902")][0].runtime_present)==false and (.configured_lxc_guests|length)==2 and (.running_lxc_guests|length)==1 and ([.configured_lxc_guests[]|select(.vmid=="901")][0].runtime_present)==true and ([.configured_lxc_guests[]|select(.vmid=="903")][0].runtime_present)==false' "$hht_results/semantic-host-map.json" >"$hht_results/runtime-bridge.validation.log" 2>&1; then hht_Pass "bridge distinguishes configured/running VM and LXC attachment"; else hht_Fail "configured/runtime bridge normalization"; fi

# Optional joins must never erase a parent entity. Add a physical NIC whose
# PCI device is intentionally absent, plus an interrupt source with no affinity
# record, then re-harmonize.
hht_optional_net=$hht_results/network.optional.json
jq '.data.interfaces += [{name:"orphan0",operstate:"down",mtu:"1500",address:"00:11:22:33:44:55",numa_node:"-1",driver:"/sys/bus/pci/drivers/example",device_path:"/sys/devices/pci0000:00/0000:ff:00.0",queues:[],ethtool:{},channels:{},coalesce:{},ring:{},features:{}}]' "$hht_semantic/collect_network.json" > "$hht_optional_net" && mv "$hht_optional_net" "$hht_semantic/collect_network.json"
hht_optional_irq=$hht_results/irq.optional.json
jq '.data.interrupts_raw += "\n998:          1          0          0          0  local-no-bdf\n999:          0          0          0          0  PCI-MSI 0000:ff:00.0 orphan0"' "$hht_semantic/collect_irqs.json" > "$hht_optional_irq" && mv "$hht_optional_irq" "$hht_semantic/collect_irqs.json"
rm -f "$hht_results/optional-host-map.json"
if "$app_dir/harmonize_host.sh" --from-run "$hht_semantic" --source-kind test-fixture --no-install --no-color --output "$hht_results/optional-host-map.json" >"$hht_results/optional.stdout.log" 2>"$hht_results/optional.stderr.log" && jq -e '([.network.physical_interfaces[]|select(.name=="orphan0")]|length)==1 and ([.network.physical_interfaces[]|select(.name=="orphan0")][0].pci.iommu_group)==null and ([.correlations.irq_sources[]|select(.irq==998)]|length)==1 and ([.correlations.irq_sources[]|select(.irq==998)][0].bdf)==null and ([.correlations.irq_sources[]|select(.irq==999)]|length)==1 and ([.correlations.irq_sources[]|select(.irq==999)][0].effective_affinity_list)==null' "$hht_results/optional-host-map.json" >"$hht_results/optional-parent.validation.log" 2>&1; then hht_Pass "missing optional PCI/IRQ joins preserve their parent entities"; else hht_Fail "optional join parent preservation"; fi

hht_Log "[9/12] Verifying non-NVMe block-to-PCI ancestry"
hht_storage_tmp=$hht_results/storage.semantic.json
jq '.data.block_queues += [{block:"sdz",device_path:"/sys/devices/pci0000:00/0000:00:08.1/ata1/host0/target0:0:0/0:0:0:0",queue:{}}] | .data.proxmox_storage.storage_cfg_raw += "\nlvmthin: sata-test\n    vgname satavg\n    thinpool data\n" | .data.proxmox_storage.pvesm_status.stdout += "\nsata-test lvmthin active 1000000 100000 900000 10.00%" | .data.raw.lvs.stdout="{\"report\":[{\"lv\":[{\"lv_name\":\"[data_tdata]\",\"vg_name\":\"satavg\",\"devices\":\"/dev/sdz1(0)\"}]}]}"' "$hht_semantic/collect_storage.json" > "$hht_storage_tmp" && mv "$hht_storage_tmp" "$hht_semantic/collect_storage.json"
rm -f "$hht_results/ancestry-host-map.json"
if "$app_dir/harmonize_host.sh" --from-run "$hht_semantic" --source-kind test-fixture --no-install --no-color --output "$hht_results/ancestry-host-map.json" >"$hht_results/ancestry.stdout.log" 2>"$hht_results/ancestry.stderr.log" && jq -e '.storage.pve_storages[] | select(.name=="sata-test") | .backing.base_block=="sdz" and .backing.pci_bdf=="0000:00:08.1" and .backing.pci_correlation_method=="sysfs-block-device-ancestry"' "$hht_results/ancestry-host-map.json" >"$hht_results/sata-ancestry.validation.log" 2>&1; then hht_Pass "SATA/SCSI block device resolves to PCI controller ancestry"; else hht_Fail "block-to-PCI ancestry correlation"; fi

hht_Log "[10/12] Rendering harmonized view and checking new evidence sections"
if "$app_dir/view_harmonized_host.sh" --file "$hht_results/semantic-host-map.json" --no-install --no-color >"$hht_results/harmonized-view.txt" 2>"$hht_results/harmonized-view.stderr.log" && [ -s "$hht_results/harmonized-view.txt" ] && [ ! -s "$hht_results/harmonized-view.stderr.log" ]; then hht_Pass "view_harmonized_host.sh --file clean rendering"; else hht_Fail "harmonized --file rendering"; fi
if grep 'Collector timestamps' "$hht_results/harmonized-view.txt" >/dev/null 2>&1 && grep 'KVM / virtualization stack' "$hht_results/harmonized-view.txt" >/dev/null 2>&1 && grep 'QEMU configured / running:.*2 / 1' "$hht_results/harmonized-view.txt" >/dev/null 2>&1 && grep 'LXC configured / running:.*2 / 1' "$hht_results/harmonized-view.txt" >/dev/null 2>&1 && grep 'QEMU runtime observed=true.*online-effective=' "$hht_results/harmonized-view.txt" >/dev/null 2>&1 && grep 'cpuset-interface=exposed requested-state=empty/inherited requested=inherited' "$hht_results/harmonized-view.txt" >/dev/null 2>&1 && grep 'runtime vhost raw=' "$hht_results/harmonized-view.txt" >/dev/null 2>&1 && grep 'runtime io-uring-worker raw=' "$hht_results/harmonized-view.txt" >/dev/null 2>&1 && grep 'LXC configuration / runtime attachment' "$hht_results/harmonized-view.txt" >/dev/null 2>&1 && grep 'cpuset-interface=not-exposed' "$hht_results/harmonized-view.txt" >/dev/null 2>&1 && grep 'Final host-side latency audit domains' "$hht_results/harmonized-view.txt" >/dev/null 2>&1; then hht_Pass "harmonized view exposes guest counts, cgroup states and final audit domains"; else hht_Fail "harmonized v0.8.7 view layout"; fi
if grep "$(printf '\033')" "$hht_results/harmonized-view.txt" >/dev/null 2>&1; then hht_Fail "--no-color harmonized view contains ANSI"; else hht_Pass "--no-color harmonized view is ANSI-free"; fi
if "$app_dir/view_harmonized_host.sh" --file "$hht_results/semantic-host-map.json" --no-install --color >"$hht_results/harmonized-view.color.txt" 2>"$hht_results/harmonized-view.color.stderr.log" && grep "$(printf '\033')" "$hht_results/harmonized-view.color.txt" >/dev/null 2>&1; then hht_Pass "forced-color harmonized view"; else hht_Fail "forced-color harmonized view"; fi

hht_Log "[11/12] Testing replay wrappers, live provenance and partial mode"
hht_wrapper=$hht_results/wrapper-result
mkdir -p "$hht_wrapper" && cp -a "$hht_fixture" "$hht_wrapper/inventory"
if "$app_dir/view_harmonized_host.sh" --from-run "$hht_wrapper" --no-install --no-color >"$hht_results/wrapper-view.txt" 2>"$hht_results/wrapper-view.stderr.log" && grep 'Source kind:.*saved-run' "$hht_results/wrapper-view.txt" >/dev/null 2>&1; then hht_Pass "test-wrapper replay resolves inventory and saved-run provenance"; else hht_Fail "wrapper replay/provenance"; fi
hht_legacy32=$hht_results/legacy-32-fixture
cp -a "$hht_fixture" "$hht_legacy32"
for hht_depth in collect_cache_resource_qos.json collect_cpu_limits_pmu.json collect_irq_architecture.json collect_memory_fragmentation.json collect_display_timing.json collect_security_mitigations.json; do rm -f -- "$hht_legacy32/$hht_depth"; done
if "$app_dir/harmonize_host.sh" --from-run "$hht_legacy32" --no-install --no-color --output "$hht_results/legacy-32-host-map.json" >"$hht_results/legacy-32.stdout.log" 2>"$hht_results/legacy-32.stderr.log" && jq -e '(.validation.expected_collectors|length)==32 and (.validation.present_collectors|length)==32 and (.schema_version=="0.8.9")' "$hht_results/legacy-32-host-map.json" >/dev/null 2>&1; then hht_Pass "v0.8.7/v0.8.8 32-collector captures remain replayable"; else hht_Fail "32-domain replay compatibility"; fi
hht_legacy26=$hht_results/legacy-26-fixture
cp -a "$hht_legacy32" "$hht_legacy26"
for hht_new in collect_kernel_events.json collect_guest_runtime_detail.json collect_kernel_housekeeping.json collect_pm_qos.json collect_desktop_io_path.json collect_latency_sample.json; do rm -f -- "$hht_legacy26/$hht_new"; done
if "$app_dir/harmonize_host.sh" --from-run "$hht_legacy26" --no-install --no-color --output "$hht_results/legacy-26-host-map.json" >"$hht_results/legacy-26.stdout.log" 2>"$hht_results/legacy-26.stderr.log" && jq -e '(.validation.expected_collectors|length)==26 and (.validation.present_collectors|length)==26 and (.schema_version=="0.8.9")' "$hht_results/legacy-26-host-map.json" >/dev/null 2>&1; then hht_Pass "v0.8.5/v0.8.6 26-collector captures remain replayable"; else hht_Fail "26-domain replay compatibility"; fi
hht_legacy=$hht_results/legacy-core-fixture
cp -a "$hht_legacy26" "$hht_legacy"
for hht_ext in collect_firmware_settings.json collect_acpi_platform.json collect_cpu_firmware_ras.json collect_timers_watchdogs.json collect_virtualization_stack.json collect_pcie_advanced.json collect_memory_hardware.json collect_irq_activity.json collect_runtime_pressure.json collect_storage_health_power.json collect_network_advanced.json collect_usb_input_audio.json; do rm -f -- "$hht_legacy/$hht_ext"; done
if "$app_dir/harmonize_host.sh" --from-run "$hht_legacy" --no-install --no-color --output "$hht_results/legacy-host-map.json" >"$hht_results/legacy.stdout.log" 2>"$hht_results/legacy.stderr.log" && jq -e '(.validation.expected_collectors|length)==14 and (.validation.present_collectors|length)==14' "$hht_results/legacy-host-map.json" >/dev/null 2>&1; then hht_Pass "legacy 14-collector captures remain replayable"; else hht_Fail "legacy core replay compatibility"; fi
hht_live_dir=$hht_results/live-orchestration
mkdir -p "$hht_live_dir"
cp "$app_dir/view_harmonized_host.sh" "$hht_live_dir/view_harmonized_host.sh"
cp "$app_dir/harmonize_host.sh" "$hht_live_dir/harmonize_host.sh"
chmod +x "$hht_live_dir/view_harmonized_host.sh" "$hht_live_dir/harmonize_host.sh"
cat > "$hht_live_dir/run_all.sh" <<EOF
#!/bin/sh
hls_output=
while [ "\$#" -gt 0 ]; do
    case "\$1" in --output) shift; hls_output=\$1 ;; esac
    shift
done
[ -n "\$hls_output" ] || exit 2
mkdir -p "\$hls_output" || exit 2
cp -a "$hht_fixture/." "\$hls_output/" || exit 2
printf 'stub live collector\n'
exit 0
EOF
chmod +x "$hht_live_dir/run_all.sh"
if "$hht_live_dir/view_harmonized_host.sh" --no-install --no-color >"$hht_results/live-view.txt" 2>"$hht_results/live-view.stderr.log" && grep 'Source kind:.*live-ephemeral' "$hht_results/live-view.txt" >/dev/null 2>&1 && grep 'Source directory:.*ephemeral / cleaned after rendering' "$hht_results/live-view.txt" >/dev/null 2>&1 && ! grep 'stub live collector' "$hht_results/live-view.txt" >/dev/null 2>&1; then hht_Pass "no-argument live view marks ephemeral provenance and keeps stdout clean"; else hht_Fail "live orchestration/provenance"; fi
cp -a "$hht_fixture" "$hht_partial" && rm -f -- "$hht_partial/collect_gpu_vfio.json"
"$app_dir/harmonize_host.sh" --from-run "$hht_partial" --no-install --no-color --output "$hht_results/strict-missing.json" >"$hht_results/strict-missing.stdout.log" 2>"$hht_results/strict-missing.stderr.log"
[ "$?" -ne 0 ] && hht_Pass "strict mode rejects missing collector" || hht_Fail "strict mode accepted missing collector"
if "$app_dir/harmonize_host.sh" --from-run "$hht_partial" --allow-partial --no-install --no-color --output "$hht_results/partial-host-map.json" >"$hht_results/partial.stdout.log" 2>"$hht_results/partial.stderr.log" && jq -e '.validation.strict==false and (.validation.missing_collectors|index("gpu-vfio"))!=null' "$hht_results/partial-host-map.json" >/dev/null 2>&1; then hht_Pass "--allow-partial preserves missing collector explicitly"; else hht_Fail "--allow-partial behavior"; fi

hht_Log "[12/12] Checking failure paths and persistent report"
"$app_dir/harmonize_host.sh" --source-kind nonsense --from-run "$hht_fixture" --no-color >"$hht_results/source-kind.stdout.log" 2>"$hht_results/source-kind.stderr.log"
[ "$?" -ne 0 ] && hht_Pass "harmonizer rejects invalid source kind" || hht_Fail "harmonizer accepted invalid source kind"
"$app_dir/harmonize_host.sh" --definitely-invalid-option --no-color >"$hht_results/invalid.stdout.log" 2>"$hht_results/invalid.stderr.log"
[ "$?" -ne 0 ] && hht_Pass "harmonizer rejects invalid option" || hht_Fail "harmonizer accepted invalid option"
"$app_dir/view_harmonized_host.sh" --file "$hht_results/does-not-exist.json" --no-install --no-color >"$hht_results/missing-view.stdout.log" 2>"$hht_results/missing-view.stderr.log"
[ "$?" -ne 0 ] && hht_Pass "harmonized view rejects missing file" || hht_Fail "harmonized view accepted missing file"

{
    printf 'Host Inventory for Proxmox - harmonization test report\n'
    printf '=======================================================\n'
    printf 'Test version: %s\n' "$hht_test_version"
    printf 'Pass validations: %s\n' "$hht_pass"
    printf 'Failed validations: %s\n' "$hht_fail"
    printf 'Return code: %s\n' "$app_rc"
    printf 'Results directory: %s\n' "$hht_results"
} > "$hht_results/report.txt"

if [ "$app_rc" -eq 0 ]; then hht_Log "RESULT: harmonization layer passed ($hht_pass validations)."; else hht_Log "RESULT: harmonization layer failed ($hht_fail failed validation(s))."; fi
hht_Log "Test results kept at: $hht_results"
exit "$app_rc"
