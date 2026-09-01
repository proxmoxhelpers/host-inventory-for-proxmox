#!/bin/sh
# ============================================================
# compare_hosts.sh
# Compares two Host Inventory for Proxmox host-map files without
# assigning tuning policy verdicts.
#
# Version: 0.8.14
# Usage: ./compare_hosts.sh --left HOST1.json --right HOST2.json [--json]
# Returns: 0 success, 2 invalid input/options
# Dependencies: /bin/sh, jq
# Side Effects: read-only
# ============================================================
app_name=compare_hosts
app_version=0.9.2
app_left=
app_right=
app_json=0
app_color=auto

usage() {
    cat <<'EOF'
compare_hosts.sh - compare two harmonized Host Inventory for Proxmox host maps

Usage:
  ./compare_hosts.sh --left HOST1.json --right HOST2.json
  ./compare_hosts.sh --left HOST1.json --right HOST2.json --json
  ./compare_hosts.sh --help
  ./compare_hosts.sh --version

The comparison is descriptive. It does not assign PASS/WARN/FAIL verdicts.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --left) shift; [ "$#" -gt 0 ] || { echo 'ERROR: --left requires a file.' >&2; exit 2; }; app_left=$1 ;;
        --right) shift; [ "$#" -gt 0 ] || { echo 'ERROR: --right requires a file.' >&2; exit 2; }; app_right=$1 ;;
        --json) app_json=1 ;;
        --color) app_color=always ;;
        --no-color) app_color=never ;;
        --help|-h|-\?|/h|/\?) usage; exit 0 ;;
        --version) printf '%s %s\n' "$app_name" "$app_version"; exit 0 ;;
        *) echo "ERROR: Unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

command -v jq >/dev/null 2>&1 || { echo 'ERROR: jq is required.' >&2; exit 2; }
[ -r "$app_left" ] || { echo "ERROR: Left host-map is not readable: $app_left" >&2; exit 2; }
[ -r "$app_right" ] || { echo "ERROR: Right host-map is not readable: $app_right" >&2; exit 2; }
jq -e '.model=="host-map"' "$app_left" >/dev/null 2>&1 || { echo 'ERROR: Left input is not a host-map.' >&2; exit 2; }
jq -e '.model=="host-map"' "$app_right" >/dev/null 2>&1 || { echo 'ERROR: Right input is not a host-map.' >&2; exit 2; }

app_tmp=$(mktemp "${TMPDIR:-/tmp}/hfip-compare.XXXXXX") || exit 2
trap 'rm -f "$app_tmp"' EXIT HUP INT TERM

jq -n --slurpfile l "$app_left" --slurpfile r "$app_right" '
  def one($h): {
    host:($h.source.hostname//null), schema:$h.schema_version,
    cpu:{logical:$h.cpu.logical_cpu_count,physical:$h.cpu.physical_core_count,smt:$h.cpu.smt.active,governors:$h.cpu.power.governors},
    memory:{swap_active:$h.memory.swap.active,hugetlb:$h.memory.hugetlb,fragmentation:($h.memory_fragmentation.buddy_highest_order//[])},
    virtualization:{stack:$h.virtualization_stack,delayacct:$h.capability_matrix.delay_accounting.enabled,capabilities:$h.capability_matrix.virtualization},
    pci:{iommu_groups:($h.pci.iommu_groups|length),iommu:$h.capability_matrix.iommu,rebar_devices:$h.capability_matrix.pcie.rebar_devices,acs_devices:$h.capability_matrix.pcie.acs_devices,dpc_devices:$h.capability_matrix.pcie.dpc_devices,ats_devices:($h.capability_matrix.pcie.ats_devices//[]),pri_devices:($h.capability_matrix.pcie.pri_devices//[]),pasid_devices:($h.capability_matrix.pcie.pasid_devices//[]),tph_devices:($h.capability_matrix.pcie.tph_devices//[]),sriov_capable:$h.capability_matrix.pcie.sriov_capable_devices},
    display:{connected:$h.capability_matrix.display.connected,vrr:$h.capability_matrix.display.vrr_capable_connectors},
    qos:{resctrl:$h.capability_matrix.resctrl,cache_qos:$h.capability_matrix.cache_qos,pmu:$h.capability_matrix.pmu,cpu_limits:$h.capability_matrix.cpu_limits},
    memory_depth:{hugepages:$h.capability_matrix.hugepages},
    security:$h.capability_matrix.security,
    audio:$h.capability_matrix.audio,
    guests:{qemu:$h.proxmox.guest_counts.configured_qemu,lxc:$h.proxmox.guest_counts.configured_lxc},
    network_paths:(($h.correlations.desktop_network_paths//[])|length),
    kernel_events:{severity:$h.kernel_events.counts_by_severity,categories:$h.kernel_events.counts_by_category},
    topology:{nodes:($h.topology_graph.nodes|length),edges:($h.topology_graph.edges|length),integrity:$h.topology_graph.integrity}
  };
  one($l[0]) as $left | one($r[0]) as $right |
  {left:$left,right:$right,
   differences:[
     {field:"cpu.logical",left:$left.cpu.logical,right:$right.cpu.logical},
     {field:"cpu.physical",left:$left.cpu.physical,right:$right.cpu.physical},
     {field:"cpu.smt",left:$left.cpu.smt,right:$right.cpu.smt},
     {field:"memory.swap_active",left:$left.memory.swap_active,right:$right.memory.swap_active},
     {field:"pci.iommu_groups",left:$left.pci.iommu_groups,right:$right.pci.iommu_groups},
     {field:"pci.iommu.cmdline_arguments",left:$left.pci.iommu.cmdline_arguments,right:$right.pci.iommu.cmdline_arguments},
     {field:"pci.iommu.acs_override_argument",left:$left.pci.iommu.acs_override_argument,right:$right.pci.iommu.acs_override_argument},
     {field:"pci.rebar_devices",left:$left.pci.rebar_devices,right:$right.pci.rebar_devices},
     {field:"pci.ats_devices",left:$left.pci.ats_devices,right:$right.pci.ats_devices},
     {field:"pci.pri_devices",left:$left.pci.pri_devices,right:$right.pci.pri_devices},
     {field:"pci.pasid_devices",left:$left.pci.pasid_devices,right:$right.pci.pasid_devices},
     {field:"qos.resctrl",left:$left.qos.resctrl,right:$right.qos.resctrl},
     {field:"qos.pmu.source_count",left:$left.qos.pmu.source_count,right:$right.qos.pmu.source_count},
     {field:"qos.cpu_limits.frequency_residency",left:$left.qos.cpu_limits.frequency_residency,right:$right.qos.cpu_limits.frequency_residency},
     {field:"display.connected",left:$left.display.connected,right:$right.display.connected},
     {field:"display.vrr",left:$left.display.vrr,right:$right.display.vrr},
     {field:"security.explicit_arguments",left:$left.security.explicit_arguments,right:$right.security.explicit_arguments},
     {field:"audio.pcm_device_count",left:$left.audio.pcm_device_count,right:$right.audio.pcm_device_count},
     {field:"network_paths",left:$left.network_paths,right:$right.network_paths},
     {field:"guests.qemu",left:$left.guests.qemu,right:$right.guests.qemu},
     {field:"guests.lxc",left:$left.guests.lxc,right:$right.guests.lxc},
     {field:"topology.nodes",left:$left.topology.nodes,right:$right.topology.nodes},
     {field:"topology.edges",left:$left.topology.edges,right:$right.topology.edges}
   ] | map(. + {different:(.left != .right)})}
' > "$app_tmp" || exit 2

if [ "$app_json" -eq 1 ]; then
    cat "$app_tmp"
    exit 0
fi

printf 'Host Inventory for Proxmox - Cross-host Comparison\n'
printf 'Left:  %s\n' "$(jq -r '.left.host // "unknown"' "$app_tmp")"
printf 'Right: %s\n' "$(jq -r '.right.host // "unknown"' "$app_tmp")"
printf '\nObserved differences\n'
jq -r '.differences[] | [.field,(.left|tojson),(.right|tojson),(.different|tostring)] | @tsv' "$app_tmp" |
while IFS="$(printf '\t')" read -r field left right different; do
    printf '  %-28s left=%s right=%s different=%s\n' "$field" "$left" "$right" "$different"
done
exit 0
