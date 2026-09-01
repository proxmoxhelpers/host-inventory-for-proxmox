#!/bin/sh
# ============================================================
# view_desktop_vm.sh
# Renders a derived host-side latency/performance path for one
# Proxmox QEMU desktop VM from host-map.json.
#
# Version:
#   0.9.2
#
# Usage:
#   ./view_desktop_vm.sh --file host-map.json --vmid 111
#   ./view_desktop_vm.sh --from-run DIR --vmid 111
#   ./view_desktop_vm.sh --file host-map.json --list
#
# Output:
#   Human-readable host-side evidence only.
#
# Returns:
#   0 success
#   2 invalid arguments/input/dependency
#
# Dependencies:
#   jq; harmonize_host.sh/run_all.sh for --from-run or live mode.
#
# Side Effects:
#   Read-only except private temporary collection in live mode.
# ============================================================

app_name=view_desktop_vm
app_version=0.9.2
app_file=
app_from_run=
app_vmid=
app_list=0
app_color_mode=auto
app_temp=
app_script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || exit 2

color_init() {
    vdm_enable=0
    [ -n "${NO_COLOR-}" ] && app_color_mode=never
    case "$app_color_mode" in
        always) vdm_enable=1 ;;
        never) vdm_enable=0 ;;
        auto) [ -t 1 ] && vdm_enable=1 ;;
    esac
    if [ "$vdm_enable" -eq 1 ]; then
        c_reset=$(printf '\033[0m'); c_title=$(printf '\033[1;96m')
        c_section=$(printf '\033[96m'); c_key=$(printf '\033[95m'); c_dim=$(printf '\033[90m')
    else
        c_reset=; c_title=; c_section=; c_key=; c_dim=
    fi
}
cleanup() { [ -n "$app_temp" ] && [ -d "$app_temp" ] && rm -rf -- "$app_temp"; }
usage() {
    cat <<'EOF'
view_desktop_vm.sh - derived host-side desktop VM latency/performance path

Usage:
  ./view_desktop_vm.sh --file host-map.json --vmid VMID
  ./view_desktop_vm.sh --from-run RUN_DIR --vmid VMID
  ./view_desktop_vm.sh --file host-map.json --list
  sudo ./view_desktop_vm.sh --vmid VMID

Options:
  --file FILE       Existing host-map v0.8.7 or v0.8.9 JSON.
  --from-run DIR    Harmonize a saved Host Inventory run.
  --vmid VMID       Target QEMU VM.
  --list            List configured QEMU VMs in the map.
  --color           Force ANSI.
  --no-color        Disable ANSI.
  --help            Show help.
  --version         Show version.

With neither --file nor --from-run, a private live run is collected and removed.
This view does not claim guest-side DPC/ISR, Present timing, game scheduling or
frame pacing.
EOF
}
parse_options() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --file) shift; [ "$#" -gt 0 ] || return 2; app_file=$1 ;;
            --from-run) shift; [ "$#" -gt 0 ] || return 2; app_from_run=$1 ;;
            --vmid) shift; [ "$#" -gt 0 ] || return 2; app_vmid=$1 ;;
            --list) app_list=1 ;;
            --color) app_color_mode=always ;;
            --no-color) app_color_mode=never ;;
            --help|-h) usage; exit 0 ;;
            --version) printf '%s %s\n' "$app_name" "$app_version"; exit 0 ;;
            *) printf 'ERROR: Unknown argument: %s\n' "$1" >&2; return 2 ;;
        esac
        shift
    done
}
kv() { printf '%s%-28s%s %s\n' "$c_key" "$1:" "$c_reset" "${2:-unknown}"; }
section() { printf '\n%s%s%s\n' "$c_section" "$1" "$c_reset"; }
item() { printf '  %s-%s %s\n' "$c_dim" "$c_reset" "$1"; }

resolve_map() {
    command -v jq >/dev/null 2>&1 || { printf 'ERROR: jq is required.\n' >&2; return 2; }
    if [ -n "$app_file" ]; then
        [ -r "$app_file" ] || { printf 'ERROR: host-map not readable: %s\n' "$app_file" >&2; return 2; }
        return 0
    fi
    app_temp=$(mktemp -d "${TMPDIR:-/tmp}/hfip-desktop-vm.XXXXXX") || return 2
    if [ -n "$app_from_run" ]; then
        "$app_script_dir/harmonize_host.sh" --from-run "$app_from_run" --output "$app_temp/host-map.json" --no-install --no-color >/dev/null || return $?
    else
        "$app_script_dir/run_all.sh" --output "$app_temp/inventory" --no-install --no-color >/dev/null || return $?
        "$app_script_dir/harmonize_host.sh" --from-run "$app_temp/inventory" --source-kind live-ephemeral --output "$app_temp/host-map.json" --no-install --no-color >/dev/null || return $?
    fi
    app_file=$app_temp/host-map.json
}
validate_map() {
    jq -e '.model=="host-map" and ((.schema_version=="0.8.7") or (.schema_version=="0.8.9")) and (.proxmox.virtual_machines|type=="array")' "$app_file" >/dev/null 2>&1 ||
      { printf 'ERROR: Expected Host Inventory host-map schema 0.8.7 or 0.8.9.\n' >&2; return 2; }
}
render_list() {
    printf '%sConfigured QEMU VMs%s\n' "$c_title" "$c_reset"
    jq -r '.proxmox.virtual_machines|sort_by((.vmid|tonumber))[]|
      "\(.vmid)\t\(.status)\t\(.name//"unnamed")"' "$app_file"
}
render_vm() {
    jq -e --arg id "$app_vmid" '.proxmox.virtual_machines[]?|select(.vmid==$id)' "$app_file" >/dev/null ||
      { printf 'ERROR: VMID %s is not present in host-map.\n' "$app_vmid" >&2; return 2; }

    printf '%sDesktop VM Host Path - VM %s%s\n' "$c_title" "$app_vmid" "$c_reset"
    kv "Name / status" "$(jq -r --arg id "$app_vmid" '.proxmox.virtual_machines[]|select(.vmid==$id)|(.name//"unnamed")+" / "+(.status//"unknown")' "$app_file")"

    section "CPU / scheduler"
    kv "Configured vCPU cores" "$(jq -r --arg id "$app_vmid" '.proxmox.virtual_machines[]|select(.vmid==$id)|.cpu.cores//"unknown"' "$app_file")"
    kv "Configured affinity" "$(jq -r --arg id "$app_vmid" '.proxmox.virtual_machines[]|select(.vmid==$id)|.cpu.affinity//"none"' "$app_file")"
    kv "Runtime raw affinity" "$(jq -r --arg id "$app_vmid" '.proxmox.virtual_machines[]|select(.vmid==$id)|.runtime.process_cpus_allowed_list//"unknown"' "$app_file")"
    kv "Runtime online affinity" "$(jq -r --arg id "$app_vmid" '.proxmox.virtual_machines[]|select(.vmid==$id)|.runtime.process_online_cpus_allowed_list//"none"' "$app_file")"
    jq -r --arg id "$app_vmid" '.guest_runtime_detail.qemu_vms[]?|select(.vmid==$id)|
      "RSS=\(.memory.rss_kb//"unknown")kB AnonHugePages=\(.memory.anon_huge_pages_kb//"unknown")kB migrations=\(.process.migrations//"unknown")"' "$app_file" |
      while IFS= read -r line; do item "$line"; done

    section "Host noise overlap"
    kv "Isolated CPUs" "$(jq -r '.cpu.isolation.isolated.raw//"none"' "$app_file")"
    kv "Housekeeping threads" "$(jq -r '.kernel_housekeeping.thread_count//0' "$app_file")"
    kv "Kernel event matches" "$(jq -r '.kernel_events.total_events//0' "$app_file")"
    jq -r '.kernel_events.counts//{}|to_entries[]?|"kernel-event \(.key)=\(.value)"' "$app_file" |
      while IFS= read -r line; do item "$line"; done

    section "Memory / pressure"
    kv "Host swap active" "$(jq -r '.memory.swap.active|tostring' "$app_file")"
    kv "THP" "$(jq -r '.memory.transparent_hugepages.enabled_selected//"unknown"' "$app_file")"
    kv "Passive sample" "$(jq -r '(.latency_sample.sample.duration_seconds//0|tostring)+"s"' "$app_file")"
    jq -r --arg id "$app_vmid" '.latency_sample.qemu_deltas[]?|select(.vmid==$id)|
      "sample runtime-ns=\(.sched_runtime_ns_delta) wait-ns=\(.sched_wait_ns_delta) migrations=\(.migrations_delta)"' "$app_file" |
      while IFS= read -r line; do item "$line"; done

    section "GPU / PCI"
    jq -r --arg id "$app_vmid" '.proxmox.virtual_machines[]|select(.vmid==$id)|.hostpci[]?|
      "\(.key) \(.bdf//.value)"' "$app_file" | while IFS= read -r line; do item "$line"; done
    [ "$(jq -r --arg id "$app_vmid" '.proxmox.virtual_machines[]|select(.vmid==$id)|.hostpci|length' "$app_file")" -gt 0 ] 2>/dev/null ||
      item "No hostpci device configured"

    section "Storage path"
    jq -r --arg id "$app_vmid" '
      .proxmox.virtual_machines[]|select(.vmid==$id)|.disks[]? as $d |
      ($d.storage//"unknown") as $s |
      (.storage.pve_storages[]?|select(.name==$s)) as $p |
      "\($d.key) storage=\($s) block=\($p.backing.base_block//"unknown") BDF=\($p.backing.pci_bdf//"none")"' "$app_file" |
      while IFS= read -r line; do item "$line"; done

    section "Network path"
    jq -r --arg id "$app_vmid" '
      .proxmox.virtual_machines[]|select(.vmid==$id)|.networks[]? |
      "\(.key) model=\(.model//"unknown") bridge=\(.bridge//"none") runtime=\(.runtime_interface//"none")"' "$app_file" |
      while IFS= read -r line; do item "$line"; done
    jq -r --arg id "$app_vmid" '(.correlations.desktop_network_paths//[])[]?|select(.vmid==$id) |
      "\(.net) vhost=\(.vhost_threads|length) tap=\(.tap_interface) physical=" + (([.physical_paths[]?|((.interface//"?")+"/"+(.bdf//"no-bdf")+"/irqs="+((.observed_irqs|length)|tostring))]|join(",")) // "none")' "$app_file" |
      while IFS= read -r line; do item "$line"; done
    kv "Host busy_poll" "$(jq -r '.desktop_io_path.network_policy.busy_poll//"unknown"' "$app_file")"
    kv "Host busy_read" "$(jq -r '.desktop_io_path.network_policy.busy_read//"unknown"' "$app_file")"

    section "USB / input / audio"
    kv "USB devices observed" "$(jq -r '.desktop_io_path.usb|length//0' "$app_file")"
    kv "Periodic USB endpoints" "$(jq -r '[.desktop_io_path.usb[]?.endpoints[]?|select(.bInterval!=null)]|length' "$app_file")"
    kv "snd_hda parameters" "$(jq -r '.desktop_io_path.audio.snd_hda_intel_parameters|length//0' "$app_file")"
    kv "Bound host VT consoles" "$(jq -r '[.desktop_io_path.display.vtconsoles[]?|select(.bound==true)]|length' "$app_file")"

    section "Host topology / capability context"
    kv "IOMMU interrupt remapping" "$(jq -r '(.capability_matrix.iommu.interrupt_remapping_observed//false)|tostring' "$app_file")"
    kv "IOMMU cmdline" "$(jq -r '(.capability_matrix.iommu.cmdline_arguments//[])|if length==0 then "none" else join(" ") end' "$app_file")"
    kv "PCIe ACS override" "$(jq -r '.capability_matrix.iommu.acs_override_argument//"none"' "$app_file")"
    kv "resctrl supported/mounted" "$(jq -r '((.capability_matrix.resctrl.supported//false)|tostring)+"/"+((.capability_matrix.resctrl.mounted//false)|tostring)' "$app_file")"
    kv "Graph edge integrity" "$(jq -r '((.topology_graph.integrity.all_edge_sources_have_nodes//false)|tostring)+"/"+((.topology_graph.integrity.all_edge_targets_have_nodes//false)|tostring)' "$app_file")"

    section "PM-QoS"
    kv "/dev/cpu_dma_latency" "$(jq -r 'if .pm_qos.cpu_dma_latency_present then "present" else "absent" end' "$app_file")"
    kv "cpu_dma_latency holders" "$(jq -r '.pm_qos.cpu_dma_latency_holders|length//0' "$app_file")"

    section "Evidence boundary"
    item "Host-side evidence only; guest DPC/ISR, display Present timing, game-thread scheduling and actual frame pacing are not inferred."
}

# ------------------------------ setup ------------------------------
parse_options "$@" || exit $?
color_init
trap cleanup EXIT HUP INT TERM

# ------------------------------- main -------------------------------
resolve_map || exit $?
validate_map || exit $?
if [ "$app_list" -eq 1 ]; then
    render_list
    exit $?
fi
case "$app_vmid" in *[!0-9]*|"") printf 'ERROR: --vmid is required unless --list is used.\n' >&2; exit 2 ;; esac
render_vm
