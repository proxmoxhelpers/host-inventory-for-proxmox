#!/bin/sh
# ============================================================
# harmonize_host.sh
# Builds a coherent cross-collector host model from one
# Host Inventory for Proxmox run_all.sh output directory.
#
# Version:
#   0.9.2
#
# Usage:
#   ./harmonize_host.sh --from-run host-inventory-YYYYMMDD-HHMMSS
#   ./harmonize_host.sh --from-run DIR --output host-map.json
#
# Output:
#   host-map JSON on stdout unless --output is supplied.
#   Human status/errors on stderr.
#
# Returns:
#   0 on successful harmonization
#   1 on model-generation failure
#   2 on invalid input, validation failure, or missing dependency
#
# Dependencies:
#   jq (required; may be installed through apt after approval)
#
# Side Effects:
#   Read-only except for optional approved jq package installation
#   and writing the explicitly requested --output file.
# ============================================================
app_name=harmonize_host
app_version=0.9.2
app_rc=0
app_from_run=
app_output=
app_compact=0
app_allow_partial=0
app_source_kind=saved-run
app_color_mode=auto
app_install_mode=ask
app_temp_dir=
app_core_specs="platform:collect_platform.json boot-kernel:collect_boot_kernel.json cpu-topology:collect_cpu_topology.json cpu-power-idle:collect_cpu_power_idle.json pcie-iommu:collect_pcie_iommu.json gpu-vfio:collect_gpu_vfio.json isolation-scheduler:collect_isolation_scheduler.json memory:collect_memory.json irqs:collect_irqs.json storage:collect_storage.json network:collect_network.json services-background:collect_services_background.json thermal-power:collect_thermal_power.json proxmox-host:collect_proxmox_host.json"
app_extended_specs="firmware-settings:collect_firmware_settings.json acpi-platform:collect_acpi_platform.json cpu-firmware-ras:collect_cpu_firmware_ras.json timers-watchdogs:collect_timers_watchdogs.json virtualization-stack:collect_virtualization_stack.json pcie-advanced:collect_pcie_advanced.json memory-hardware:collect_memory_hardware.json irq-activity:collect_irq_activity.json runtime-pressure:collect_runtime_pressure.json storage-health-power:collect_storage_health_power.json network-advanced:collect_network_advanced.json usb-input-audio:collect_usb_input_audio.json"
app_final_specs="kernel-events:collect_kernel_events.json guest-runtime-detail:collect_guest_runtime_detail.json kernel-housekeeping:collect_kernel_housekeeping.json pm-qos:collect_pm_qos.json desktop-io-path:collect_desktop_io_path.json latency-sample:collect_latency_sample.json"
app_depth_specs="cache-resource-qos:collect_cache_resource_qos.json cpu-limits-pmu:collect_cpu_limits_pmu.json irq-architecture:collect_irq_architecture.json memory-fragmentation:collect_memory_fragmentation.json display-timing:collect_display_timing.json security-mitigations:collect_security_mitigations.json"
app_expected_specs="$app_core_specs $app_extended_specs $app_final_specs $app_depth_specs"

# ============================================================
# color_init
# Defines semantic ANSI colors for human status messages.
#
# Version:
#   1.0.0
# ============================================================
color_init() {
    hci_enable=0
    [ -n "${NO_COLOR-}" ] && app_color_mode=never
    case "$app_color_mode" in
        always) hci_enable=1 ;;
        never) hci_enable=0 ;;
        auto) [ -t 2 ] && hci_enable=1 ;;
        *) app_color_mode=auto; [ -t 2 ] && hci_enable=1 ;;
    esac
    if [ "$hci_enable" -eq 1 ]; then
        app_color_reset=$(printf '[0m')
        app_color_title=$(printf '[1;96m')
        app_color_info=$(printf '[96m')
        app_color_ok=$(printf '[92m')
        app_color_warn=$(printf '[93m')
        app_color_error=$(printf '[91m')
        app_color_dim=$(printf '[90m')
    else
        app_color_reset=; app_color_title=; app_color_info=; app_color_ok=; app_color_warn=; app_color_error=; app_color_dim=
    fi
    return 0
}

# ============================================================
# message
# Prints one semantic human-status line to stderr.
#
# Version:
#   1.0.0
# ============================================================
message() {
    hm_role=$1
    shift
    case "$hm_role" in
        title) hm_color=$app_color_title ;;
        info) hm_color=$app_color_info ;;
        ok) hm_color=$app_color_ok ;;
        warn) hm_color=$app_color_warn ;;
        error) hm_color=$app_color_error ;;
        *) hm_color=$app_color_dim ;;
    esac
    printf '%s%s%s
' "$hm_color" "$*" "$app_color_reset" >&2
    return 0
}

# ============================================================
# cleanup
# Removes private temporary state.
#
# Version:
#   1.0.0
# ============================================================
cleanup() {
    [ -n "$app_temp_dir" ] && [ -d "$app_temp_dir" ] && rm -rf -- "$app_temp_dir"
    return 0
}

# ============================================================
# usage
# Prints harmonizer usage.
#
# Version:
#   1.0.0
# ============================================================
usage() {
    cat <<'EOF'
harmonize_host.sh - build one coherent Host Inventory for Proxmox host map

Usage:
  ./harmonize_host.sh --from-run host-inventory-YYYYMMDD-HHMMSS
  ./harmonize_host.sh --from-run DIR --output host-map.json

Options:
  --from-run DIR      run_all.sh output directory to harmonize (required).
                      Common test wrappers containing inventory/ or fixture/
                      are resolved automatically.
  --output FILE       Write host-map JSON to FILE instead of stdout.
  --compact           Emit compact JSON.
  --allow-partial     Build a degraded map when collector files are missing.
  --source-kind KIND  Provenance kind: saved-run, live-ephemeral, or test-fixture.
  --install-missing  Install jq automatically if it is missing.
  --no-install       Never offer dependency installation.
  --color            Force ANSI color for human status on stderr.
  --no-color         Disable ANSI color for human status.
  --help             Show help without installing/probing anything.
  --version          Show version.

Strict mode requires all 38 collectors for a current v0.8.9/v0.8.10/v0.8.11/v0.8.12/v0.8.13/v0.8.14/v0.9.0/v0.9.1/v0.9.2 capture. Saved v0.8.7/v0.8.8 captures retain their 32-collector contract; saved
v0.8.5/v0.8.6 captures remain replayable with their 26-collector contract, while
captures containing none of the extended collectors retain the original 14-collector
contract. A manifest, consistent hostname and zero manifest failures are still required.

Harmonization is descriptive only. It does not emit PASS/WARN/FAIL tuning policy.
EOF
    return 0
}

# ============================================================
# parse_options
# Parses harmonizer options.
#
# Version:
#   1.0.0
# ============================================================
parse_options() {
    hpo_action=run
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --from-run)
                shift
                [ "$#" -gt 0 ] || { message error "ERROR: --from-run requires a directory."; return 2; }
                app_from_run=$1
                ;;
            --output)
                shift
                [ "$#" -gt 0 ] || { message error "ERROR: --output requires a file."; return 2; }
                app_output=$1
                ;;
            --compact) app_compact=1 ;;
            --allow-partial) app_allow_partial=1 ;;
            --source-kind)
                shift
                [ "$#" -gt 0 ] || { message error "ERROR: --source-kind requires a value."; return 2; }
                case "$1" in
                    saved-run|live-ephemeral|test-fixture) app_source_kind=$1 ;;
                    *) message error "ERROR: Invalid --source-kind: $1"; return 2 ;;
                esac
                ;;
            --install-missing) app_install_mode=always ;;
            --no-install) app_install_mode=never ;;
            --color) app_color_mode=always ;;
            --no-color) app_color_mode=never ;;
            --help|-h|-\?|/h|/\?) hpo_action=help ;;
            --version) hpo_action=version ;;
            *) message error "ERROR: Unknown argument: $1"; return 2 ;;
        esac
        shift
    done
    return 0
}

# ============================================================
# install_jq
# Installs jq through apt after explicit approval/policy.
#
# Version:
#   1.0.0
# ============================================================
install_jq() {
    command -v apt-get >/dev/null 2>&1 || { message error "ERROR: jq is required and apt-get is unavailable."; return 2; }
    hij_install=0
    case "$app_install_mode" in
        always) hij_install=1 ;;
        never) hij_install=0 ;;
        ask)
            if [ -r /dev/tty ]; then
                printf 'jq is required. Install package jq now? [y/N] ' >/dev/tty
                IFS= read -r hij_answer </dev/tty || hij_answer=
                case "$hij_answer" in y|Y|yes|YES|Yes) hij_install=1 ;; esac
            fi
            ;;
    esac
    [ "$hij_install" -eq 1 ] || { message error "ERROR: jq is required."; return 2; }
    if [ "$(id -u 2>/dev/null)" = 0 ]; then
        apt-get install -y jq
    elif command -v sudo >/dev/null 2>&1; then
        sudo apt-get install -y jq
    else
        message error "ERROR: Installing jq requires root or sudo."
        return 2
    fi
}

# ============================================================
# ensure_dependencies
# Ensures jq is available before collector-envelope validation.
#
# Version:
#   1.0.0
# ============================================================
ensure_dependencies() {
    command -v jq >/dev/null 2>&1 && return 0
    install_jq || return $?
    command -v jq >/dev/null 2>&1 || return 2
    return 0
}


# ============================================================
# resolve_run_directory
# Resolves a direct run_all directory or a common test wrapper.
#
# Version:
#   1.0.0
#
# Usage:
#   resolve_run_directory DIR
#
# Output:
#   hrd_resolved_dir
#
# Returns:
#   0 when a collection directory is found
#   2 otherwise
# ============================================================
resolve_run_directory() {
    hrd_input=$1
    [ -d "$hrd_input" ] || { message error "ERROR: Run directory does not exist: $hrd_input"; return 2; }
    hrd_input=$(CDPATH= cd -- "$hrd_input" 2>/dev/null && pwd -P) || return 2

    if [ -r "$hrd_input/collect_platform.json" ]; then
        hrd_resolved_dir=$hrd_input
        return 0
    fi
    if [ -r "$hrd_input/inventory/collect_platform.json" ]; then
        hrd_resolved_dir=$hrd_input/inventory
        message info "Resolved collection directory: $hrd_resolved_dir"
        return 0
    fi
    if [ -r "$hrd_input/fixture/collect_platform.json" ]; then
        hrd_resolved_dir=$hrd_input/fixture
        message info "Resolved collection directory: $hrd_resolved_dir"
        return 0
    fi

    message error "ERROR: No collector set found directly in: $hrd_input"
    message error "       Expected collect_platform.json, inventory/collect_platform.json,"
    message error "       or fixture/collect_platform.json."
    return 2
}

# ============================================================
# prepare_input
# Validates collector files/manifest and builds collectors.json.
#
# Version:
#   1.0.0
#
# Output globals:
#   hpi_collectors_file hpi_manifest_file hpi_hostname
#   hpi_missing_csv hpi_expected_csv hpi_start hpi_end
# ============================================================
prepare_input() {
    [ -n "$app_from_run" ] || { message error "ERROR: --from-run is required."; return 2; }
    resolve_run_directory "$app_from_run" || return $?
    app_from_run=$hrd_resolved_dir

    app_temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/hfip-harmonize.XXXXXX") || return 2
    hpi_valid_list=$app_temp_dir/valid-files.txt
    : > "$hpi_valid_list" || return 2
    hpi_missing_csv=
    hpi_expected_csv=
    hpi_hostnames=$app_temp_dir/hostnames.txt
    hpi_times=$app_temp_dir/times.txt
    : > "$hpi_hostnames"; : > "$hpi_times"

    hpi_depth_mode=false
    for hpi_depth_spec in $app_depth_specs; do
        hpi_depth_file=${hpi_depth_spec#*:}
        if [ -r "$app_from_run/$hpi_depth_file" ]; then hpi_depth_mode=true; break; fi
    done
    hpi_final_mode=false
    for hpi_final_spec in $app_final_specs; do
        hpi_final_file=${hpi_final_spec#*:}
        if [ -r "$app_from_run/$hpi_final_file" ]; then hpi_final_mode=true; break; fi
    done
    hpi_extended_mode=false
    for hpi_ext_spec in $app_extended_specs; do
        hpi_ext_file=${hpi_ext_spec#*:}
        if [ -r "$app_from_run/$hpi_ext_file" ]; then hpi_extended_mode=true; break; fi
    done
    if [ "$hpi_depth_mode" = true ]; then
        hpi_active_specs=$app_expected_specs
    elif [ "$hpi_final_mode" = true ]; then
        hpi_active_specs="$app_core_specs $app_extended_specs $app_final_specs"
    elif [ "$hpi_extended_mode" = true ]; then
        hpi_active_specs="$app_core_specs $app_extended_specs"
    else
        hpi_active_specs=$app_core_specs
    fi

    for hpi_spec in $hpi_active_specs; do
        hpi_collector=${hpi_spec%%:*}
        hpi_file=${hpi_spec#*:}
        hpi_path=$app_from_run/$hpi_file
        hpi_expected_csv="${hpi_expected_csv}${hpi_expected_csv:+,}$hpi_collector"
        if [ ! -r "$hpi_path" ]; then
            hpi_missing_csv="${hpi_missing_csv}${hpi_missing_csv:+,}$hpi_collector"
            message warn "Missing collector: $hpi_file"
            continue
        fi
        if ! jq -e --arg collector "$hpi_collector" 'type=="object" and .collector==$collector and (.data|type=="object") and (.notes|type=="array") and (.errors|type=="array")' "$hpi_path" >/dev/null 2>&1; then
            hpi_missing_csv="${hpi_missing_csv}${hpi_missing_csv:+,}$hpi_collector"
            message warn "Invalid collector envelope: $hpi_file"
            continue
        fi
        printf '%s
' "$hpi_path" >> "$hpi_valid_list"
        jq -r '.hostname // empty' "$hpi_path" >> "$hpi_hostnames"
        jq -r '.collected_at // empty' "$hpi_path" >> "$hpi_times"
    done

    if [ -n "$hpi_missing_csv" ] && [ "$app_allow_partial" -eq 0 ]; then
        message error "ERROR: Strict harmonization requires all collectors. Missing/invalid: $hpi_missing_csv"
        return 2
    fi
    [ -s "$hpi_valid_list" ] || { message error "ERROR: No valid collector envelopes were found."; return 2; }

    hpi_unique_hosts=$(sed '/^$/d' "$hpi_hostnames" | sort -u)
    hpi_host_count=$(printf '%s
' "$hpi_unique_hosts" | sed '/^$/d' | wc -l | tr -d ' ')
    if [ "$hpi_host_count" -gt 1 ] && [ "$app_allow_partial" -eq 0 ]; then
        message error "ERROR: Collector hostnames are inconsistent: $(printf '%s' "$hpi_unique_hosts" | tr '
' ' ')"
        return 2
    fi
    hpi_hostname=$(printf '%s
' "$hpi_unique_hosts" | sed -n '1p')
    [ -n "$hpi_hostname" ] || hpi_hostname=unknown
    hpi_start=$(sed '/^$/d' "$hpi_times" | sort | sed -n '1p')
    hpi_end=$(sed '/^$/d' "$hpi_times" | sort | tail -n 1)

    hpi_manifest_file=$app_from_run/manifest.json
    hpi_manifest_present=false
    if [ -r "$hpi_manifest_file" ] && jq -e 'type=="object" and (.collectors|type=="array")' "$hpi_manifest_file" >/dev/null 2>&1; then
        hpi_manifest_present=true
        hpi_manifest_failures=$(jq -r '.failure_count // 0' "$hpi_manifest_file")
        if [ "$hpi_manifest_failures" -ne 0 ] 2>/dev/null && [ "$app_allow_partial" -eq 0 ]; then
            message error "ERROR: Manifest reports $hpi_manifest_failures collector failure(s)."
            return 2
        fi
    else
        printf '{}
' > "$app_temp_dir/manifest.json"
        hpi_manifest_file=$app_temp_dir/manifest.json
        [ "$app_allow_partial" -eq 1 ] || { message error "ERROR: Strict harmonization requires manifest.json."; return 2; }
    fi

    # shellcheck disable=SC2046
    jq -s 'map({key:.collector,value:.})|from_entries' $(cat "$hpi_valid_list") > "$app_temp_dir/collectors.json" || return 1
    hpi_collectors_file=$app_temp_dir/collectors.json
    return 0
}

# ============================================================
# write_harmonizer_program
# Writes the embedded jq harmonization program to private temp state.
#
# Version:
#   1.0.0
# ============================================================
write_harmonizer_program() {
    cat > "$app_temp_dir/harmonize.jq" <<'HFIP_JQ'
def env($c;$name): $c[$name] // {collector:$name,hostname:null,schema_version:null,data:{},notes:[],errors:["collector missing"]};
def d($c;$name): (env($c;$name).data // {});
def clean_text:
  if . == null then null
  elif type != "string" then .
  elif test("^\\s*$|^\\s*\\(null\\)\\s*$") then null
  else gsub("^\\s+|\\s+$";"") end;
def cpu_list_array:
  (clean_text) as $s |
  if $s == null then []
  else [$s | split(",")[] |
    if test("^[0-9]+-[0-9]+$") then
      (split("-") | map(tonumber)) as $r | range($r[0]; $r[1]+1)
    elif test("^[0-9]+$") then tonumber
    else empty end]
  end;
def kv_lines($s):
  reduce (($s // "") | split("\n")[]) as $line ({};
    if ($line|test("^[A-Za-z][A-Za-z0-9_]*=")) then
      ($line|capture("^(?<k>[^=]+)=(?<v>.*)$")) as $m | .[$m.k]=$m.v
    else . end);
def cfg_active_lines($raw):
  reduce (($raw // "") | split("\n")[]) as $line ({lines:[],done:false};
    if .done then .
    elif ($line|test("^\\s*\\[[^]]+\\]\\s*$")) then .done=true
    else .lines += [$line] end) | .lines;
def cfg_snapshot_names($raw):
  [($raw // "") | split("\n")[] | select(test("^\\s*\\[[^]]+\\]\\s*$")) | capture("^\\s*\\[(?<name>[^]]+)\\]\\s*$").name];
def cfg_obj($raw):
  reduce (cfg_active_lines($raw)[]) as $line ({};
    if ($line|test("^[^#][^:]*:\\s*")) then
      ($line|capture("^(?<k>[^:]+):\\s*(?<v>.*)$")) as $m | .[$m.k]=$m.v
    else . end);
def cfg_entries($raw):
  [cfg_active_lines($raw)[] | select(test("^[^#][^:]*:\\s*")) |
    capture("^(?<key>[^:]+):\\s*(?<value>.*)$")];
def bdf_from_path($p):
  (([($p // "") | scan("[0-9A-Fa-f]{4}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}\\.[0-7]")] | last) // null);
def base_block($dev):
  (($dev // "") | split("(") | (.[0] // "") | sub("^/dev/";"")) as $x |
  if $x=="" then null
  elif ($x|test("^nvme[0-9]+n[0-9]+p[0-9]+$")) then $x|sub("p[0-9]+$";"")
  elif ($x|test("^[a-z]+[0-9]+$")) then $x|sub("[0-9]+$";"")
  else $x end;
def parse_irq_sources($raw):
  [($raw // "") | split("\n")[] | select(test("^\\s*[0-9]+:")) |
    . as $line |
    capture("^\\s*(?<irq>[0-9]+):(?<body>.*)$") |
    {irq:(.irq|tonumber),
     bdf:([try ($line|capture("(?<bdf>[0-9A-Fa-f]{4}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}\\.[0-7])").bdf) catch empty][0] // null),
     source:(.body | sub("^.*\\s[0-9]+-(edge|fasteoi)\\s+";"") | gsub("^\\s+|\\s+$";"")),
     raw_line:$line}];
def irq_matches_bdf($irqsrc;$bdf):
  if ($bdf//"")=="" then [] else [$irqsrc[] | select(.bdf==$bdf)] end;
def source_matches($irqsrc;$needle):
  if ($needle//"")=="" then [] else
    [$irqsrc[] | select((.source|ascii_downcase) | contains($needle|ascii_downcase))]
  end;
def parse_qm_status($raw):
  reduce (($raw//"")|split("\n")[1:][]) as $line ({};
    ([ $line | scan("\\S+") ]) as $f |
    if ($f|length)>=6 then .[$f[0]]={vmid:$f[0],name:$f[1],status:$f[2],memory_mib:($f[3]|tonumber?),bootdisk_gib:($f[4]|tonumber?),pid:($f[5]|tonumber?)} else . end);
def parse_pct($raw):
  [($raw//"")|split("\n")[1:][] |
    ([ . | scan("\\S+") ]) as $f |
    select(($f|length)>=3) |
    if ($f|length)==3 then {vmid:$f[0],status:$f[1],lock:null,name:$f[2]}
    else {vmid:$f[0],status:$f[1],lock:$f[2],name:$f[3]} end];
def parse_storage_cfg($raw):
  reduce (($raw//"")|split("\n")[]) as $line ({out:[],current:null};
    if ($line|test("^[A-Za-z0-9_-]+:\\s+\\S+")) then
      ($line|capture("^(?<type>[^:]+):\\s+(?<name>\\S+)")) as $m |
      .out += [{name:$m.name,type:$m.type,options:{}}] | .current=$m.name
    elif (.current != null and ($line|test("^\\s+\\S+\\s+"))) then
      ($line|capture("^\\s+(?<k>\\S+)\\s+(?<v>.*)$")) as $m | .current as $cur |
      .out |= map(if .name==$cur then .options[$m.k]=$m.v else . end)
    else . end) | .out;
def parse_pvesm_status($raw):
  reduce (($raw//"")|split("\n")[1:][]) as $line ({};
    ([ $line | scan("\\S+") ]) as $f |
    if ($f|length)>=7 then .[$f[0]]={name:$f[0],type:$f[1],status:$f[2],total_kib:($f[3]|tonumber?),used_kib:($f[4]|tonumber?),available_kib:($f[5]|tonumber?),percent:$f[6]} else . end);
def parse_bridges($raw):
  reduce (($raw//"")|split("\n")[]) as $line ({out:[],current:null};
    if ($line|test("^iface\\s+\\S+")) then
      ($line|capture("^iface\\s+(?<name>\\S+)\\s+(?<family>\\S+)\\s+(?<method>\\S+)")) as $m |
      .current=$m.name |
      if ($m.name|startswith("vmbr")) then .out += [{name:$m.name,family:$m.family,method:$m.method,ports:[]}]
      else . end
    elif (.current != null and ($line|test("^\\s*bridge-ports\\s+"))) then
      ($line|capture("^\\s*bridge-ports\\s+(?<ports>.+)$").ports | split(" ") | map(select(length>0))) as $ports |
      .current as $cur | .out |= map(if .name==$cur then .ports=$ports else . end)
    else . end) | .out;
def cmdline_relevant_args($raw):
  [($raw//"") | split(" ")[] | select(test("^(iommu=|amd_iommu=|intel_iommu=|pcie_acs_override=|vfio_iommu_type1\\.|kvm\\.)"))];
def kernel_lines_matching($raw;$re):
  [($raw//"") | split("\n")[] | select(test($re;"i"))];
def pci_from_bdf($devices;$bdf): ([ $devices[]? | select(.bdf==$bdf) ][0] // null);
def net_from_name($interfaces;$name): ([ $interfaces[]? | select(.name==$name) ][0] // null);
def advanced_net_from_name($interfaces;$name): ([ $interfaces[]? | select(.name==$name) ][0] // null);
def vm_runtime_for($runtime;$vmid): ([ $runtime[]? | select(.vmid==$vmid) ][0] // null);
def vm_vhost_threads($runtime;$vmid):
  (vm_runtime_for($runtime;$vmid)) as $r |
  if $r==null then [] else
    (([ $r.tasks[]? | select((.comm//"")|startswith("vhost-")) | {tid:(.tid//.pid),comm:.comm,cpus_allowed_list:(.cpus_allowed_list//null)} ] +
      [ $r.vhost_threads[]? | {tid:(.tid//.pid),comm:.comm,cpus_allowed_list:(.cpus_allowed_list//null)} ]) | unique_by(.tid))
  end;
def unique_cache_nodes($entries):
  [$entries[]? | {level:.level,type:.type,cache_id:.cache_id,shared_cpu_list:.shared_cpu_list,size:.size}] | unique_by([.level,.type,.cache_id,.shared_cpu_list]);
def lvs_json($raw): try (($raw//"")|fromjson) catch {report:[]};
def lvs_flat($raw): [lvs_json($raw).report[]?.lv[]?];
def findmnt_flat($raw):
  try (($raw//"")|fromjson).filesystems catch []
  | [ .[] | recurse(.children[]?) ];
def mount_for_path($raw;$path):
  if ($path//"")=="" then null else
    ([findmnt_flat($raw)[] | .target as $t | select($t=="/" or $path==$t or ($path|startswith($t+"/")))] | sort_by(.target|length) | last // null)
  end;
def mapper_name($vg;$lv): (($vg|gsub("-";"--"))+"-"+($lv|gsub("-";"--")));
def vm_disk_entries($raw): [cfg_entries($raw)[] | select(.key|test("^(scsi|sata|virtio|ide|efidisk)[0-9]+$"))];
def vm_net_entries($raw): [cfg_entries($raw)[] | select(.key|test("^net[0-9]+$"))];
def vm_hostpci_entries($raw): [cfg_entries($raw)[] | select(.key|test("^hostpci[0-9]+$"))];
def storage_name_from_value($v): ([try (($v|split(",")[0])|capture("^(?<s>[^:]+):").s) catch empty][0] // null);
def bridge_from_net($v): ([try ($v|capture("(?:^|,)bridge=(?<b>[^,]+)").b) catch empty][0] // null);
def model_from_net($v): ([try ($v|capture("^(?<m>[^=]+)=").m) catch empty][0] // null);
def hostpci_bdf($v): ([try (($v|split(",")[0])|capture("(?<bdf>[0-9A-Fa-f]{4}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}\\.[0-7])").bdf) catch empty][0] // null);
def entry_index($key): ([try ($key|capture("(?<n>[0-9]+)$").n|tonumber) catch empty][0] // null);
def cpulist_values($s):
  if ($s//"")=="" then []
  else
    [($s|split(",")[]) as $part |
      if ($part|test("^[0-9]+-[0-9]+$")) then
        ($part|split("-")) as $r | range(($r[0]|tonumber); (($r[1]|tonumber)+1))
      elif ($part|test("^[0-9]+$")) then ($part|tonumber)
      else empty end]
    | unique | sort
  end;
def values_to_cpulist($a):
  ($a|unique|sort) as $v |
  if ($v|length)==0 then null
  else
    (reduce $v[] as $n ({ranges:[],start:null,last:null};
       if .start==null then .start=$n | .last=$n
       elif $n == (.last+1) then .last=$n
       else .ranges += [{start:.start,last:.last}] | .start=$n | .last=$n end)
     | .ranges += [{start:.start,last:.last}]
     | [.ranges[] |
         if .start==.last then (.start|tostring)
         else ((.start|tostring)+"-"+(.last|tostring)) end]
     | join(","))
  end;
def cpulist_intersection($a;$b):
  (cpulist_values($a)) as $aa |
  (cpulist_values($b)) as $bb |
  values_to_cpulist([$aa[] as $n | select(($bb|index($n)) != null) | $n]);
def cgroup_path_from_raw($raw):
  ([($raw//"") | split("\n")[] | select(startswith("0::")) | sub("^0::";"")][0] // null);
def object_field_or_null($o;$k): if (($o|type)=="object" and ($o|has($k))) then $o[$k] else null end;
def whitespace_values($s): if $s==null then [] else (($s|gsub("^\\s+|\\s+$";"")) as $v | if $v=="" then [] else ($v|split(" ")|map(select(length>0))) end) end;
def interface_state($present;$value):
  if $present==true then (if ($value//"")=="" then "empty/inherited" else "value" end)
  elif $present==false then "not-exposed"
  else "unknown" end;
def normalize_cgroup($cg;$raw;$online):
  ($cg // {}) as $c |
  (object_field_or_null($c;"controllers_present")) as $controllers_present |
  (object_field_or_null($c;"subtree_control_present")) as $subtree_present |
  (object_field_or_null($c;"type_present")) as $type_present |
  (object_field_or_null($c;"cpuset_cpus_present")) as $cpuset_present |
  (object_field_or_null($c;"cpuset_cpus_effective_present")) as $cpuset_effective_present |
  (object_field_or_null($c;"cpuset_mems_present")) as $mems_present |
  (object_field_or_null($c;"cpuset_mems_effective_present")) as $mems_effective_present |
  (object_field_or_null($c;"cpu_weight_present")) as $weight_present |
  (object_field_or_null($c;"cpu_max_present")) as $max_present |
  {
    path:(object_field_or_null($c;"path") // cgroup_path_from_raw($raw)),
    available:(object_field_or_null($c;"available") // false),
    controllers_present:$controllers_present,
    controllers:object_field_or_null($c;"controllers"),
    controller_values:whitespace_values(object_field_or_null($c;"controllers")),
    subtree_control_present:$subtree_present,
    subtree_control:object_field_or_null($c;"subtree_control"),
    subtree_control_values:whitespace_values(object_field_or_null($c;"subtree_control")),
    type_present:$type_present,
    type:object_field_or_null($c;"type"),
    cpuset_cpus_present:$cpuset_present,
    cpuset_cpus:object_field_or_null($c;"cpuset_cpus"),
    cpuset_cpus_state:interface_state($cpuset_present;object_field_or_null($c;"cpuset_cpus")),
    cpuset_cpus_effective_present:$cpuset_effective_present,
    cpuset_cpus_effective:object_field_or_null($c;"cpuset_cpus_effective"),
    cpuset_cpus_effective_state:interface_state($cpuset_effective_present;object_field_or_null($c;"cpuset_cpus_effective")),
    cpuset_cpus_effective_online:cpulist_intersection(object_field_or_null($c;"cpuset_cpus_effective");$online),
    cpuset_interface_state:(if $cpuset_present==true or $cpuset_effective_present==true then "exposed" elif $cpuset_present==false and $cpuset_effective_present==false then "not-exposed" else "unknown" end),
    cpuset_mems_present:$mems_present,
    cpuset_mems:object_field_or_null($c;"cpuset_mems"),
    cpuset_mems_state:interface_state($mems_present;object_field_or_null($c;"cpuset_mems")),
    cpuset_mems_effective_present:$mems_effective_present,
    cpuset_mems_effective:object_field_or_null($c;"cpuset_mems_effective"),
    cpuset_mems_effective_state:interface_state($mems_effective_present;object_field_or_null($c;"cpuset_mems_effective")),
    cpu_weight_present:$weight_present,
    cpu_weight:object_field_or_null($c;"cpu_weight"),
    cpu_weight_state:interface_state($weight_present;object_field_or_null($c;"cpu_weight")),
    cpu_max_present:$max_present,
    cpu_max:object_field_or_null($c;"cpu_max"),
    cpu_max_state:interface_state($max_present;object_field_or_null($c;"cpu_max"))
  };
def qemu_thread_role($t):
  if ($t.is_main//false) then "emulator-main"
  elif (($t.comm//"")|test("^CPU [0-9]+/KVM$")) then "vcpu"
  elif (($t.comm//"")|test("^vhost-[0-9]+$")) then "vhost"
  elif (($t.comm//"")|test("^iou-wrk-")) then "io-uring-worker"
  elif (($t.comm//"")|test("iothread|^IO ";"i")) then "iothread"
  else "helper" end;
def qemu_vcpu_index($t): if (($t.comm//"")|test("^CPU [0-9]+/KVM$")) then (($t.comm//"")|capture("^CPU (?<n>[0-9]+)/KVM$").n|tonumber) else null end;
def lxc_net_entries($raw): [cfg_entries($raw)[] | select(.key|test("^net[0-9]+$"))];
def lxc_mount_entries($raw): [cfg_entries($raw)[] | select(.key|test("^(rootfs|mp[0-9]+)$"))];
def option_from_csv($v;$key): ([try ($v|capture("(?:^|,)"+$key+"=(?<x>[^,]+)").x) catch empty][0] // null);
def selected_bracket($s): ([try ($s|capture("\\[(?<v>[^]]+)\\]").v) catch empty][0] // null);

($collectors[0]) as $c |
($manifest[0] // {}) as $manifestObj |
(d($c;"boot-kernel")) as $boot |
(d($c;"cpu-topology")) as $cpu |
(d($c;"isolation-scheduler")) as $iso |
(d($c;"irqs")) as $irqd |
(parse_irq_sources($irqd.interrupts_raw)
 | map(. as $src |
     ([ $irqd.irqs[]? | select(.irq==$src.irq) ][0] // {}) as $aff |
     . + {configured_affinity_list:($aff.smp_affinity_list//null),effective_affinity_list:($aff.effective_affinity_list//null),node:($aff.node//null)})) as $irqsrc |
(d($c;"pcie-iommu")) as $pcie |
(d($c;"storage")) as $storage |
(d($c;"network")) as $net |
(d($c;"gpu-vfio")) as $gpu |
(d($c;"proxmox-host")) as $pve |
(d($c;"memory")) as $mem |
(d($c;"cpu-power-idle")) as $power |
(d($c;"services-background")) as $services |
(d($c;"thermal-power")) as $thermal |
(d($c;"cpu-firmware-ras")) as $cpuFw |
(d($c;"acpi-platform")) as $acpiPlatform |
(d($c;"firmware-settings")) as $firmwareSettings |
(d($c;"irq-activity")) as $irqActivity |
(d($c;"pcie-advanced")) as $pcieAdvanced |
(d($c;"storage-health-power")) as $storageHealth |
(d($c;"network-advanced")) as $networkAdvanced |
(d($c;"usb-input-audio")) as $usbAudio |
(d($c;"memory-hardware")) as $memoryHardware |
(d($c;"timers-watchdogs")) as $timersWatchdogs |
(d($c;"virtualization-stack")) as $virtualizationStack |
(d($c;"runtime-pressure")) as $runtimePressure |
(d($c;"kernel-events")) as $kernelEvents |
(d($c;"guest-runtime-detail")) as $guestRuntimeDetail |
(d($c;"kernel-housekeeping")) as $kernelHousekeeping |
(d($c;"pm-qos")) as $pmQos |
(d($c;"desktop-io-path")) as $desktopIoPath |
(d($c;"latency-sample")) as $latencySample |
(d($c;"cache-resource-qos")) as $cacheResourceQos |
(d($c;"cpu-limits-pmu")) as $cpuLimitsPmu |
(d($c;"irq-architecture")) as $irqArchitecture |
(d($c;"memory-fragmentation")) as $memoryFragmentation |
(d($c;"display-timing")) as $displayTiming |
(d($c;"security-mitigations")) as $securityMitigations |
(parse_qm_status($pve.qm_list.stdout)) as $qmStatus |
(parse_pct($pve.pct_list.stdout)) as $pctStatus |
(parse_storage_cfg($storage.proxmox_storage.storage_cfg_raw)) as $storageCfg |
(parse_pvesm_status($storage.proxmox_storage.pvesm_status.stdout)) as $storageStatus |
(lvs_flat($storage.raw.lvs.stdout)) as $lvs |
(parse_bridges($net.bridge_config_raw)) as $bridges |
(cmdline_relevant_args($boot.cmdline_raw)) as $iommuCmdlineArgs |
(kernel_lines_matching($pcie.raw.dmesg.stdout;"IOMMU|AMD-Vi|DMAR|interrupt remapp|default domain")) as $iommuDmesgEvidence |
(unique_cache_nodes($cacheResourceQos.cache_entries//[])) as $cacheNodes |

{
  schema_version:"0.8.9",
  model:"host-map",
  generated_at:$generated_at,
  source:{
    kind:$source_kind,
    directory:(if $source_kind=="live-ephemeral" then null else $source_dir end),
    hostname:$hostname,
    collection_window:{start:$collection_start,end:$collection_end},
    manifest_schema:($manifestObj.schema_version//null),
    collector_schema_versions:([$c[]?.schema_version]|unique),
    collector_provenance:([$c|to_entries[] | {collector:.key,collected_at:(.value.collected_at//null),schema_version:(.value.schema_version//null),error_count:((.value.errors//[])|length)}] | sort_by(.collector)),
    collection_manifest:$manifestObj
  },
  validation:{
    strict:($strict=="true"),
    manifest_present:($manifest_present=="true"),
    expected_collectors:($expected_collectors|split(",")),
    present_collectors:($c|keys|sort),
    missing_collectors:($missing_collectors|if .=="" then [] else split(",") end),
    hostnames:([$c[]?.hostname|select(.!=null)]|unique),
    hostname_consistent:(([$c[]?.hostname|select(.!=null)]|unique|length)<=1),
    manifest_failure_count:($manifestObj.failure_count//null)
  },
  cpu:{
    logical_cpu_count:($cpu.cpus|length),
    physical_core_count:([$cpu.cpus[]?|(.physical_package_id+":"+.core_id)]|unique|length),
    package_count:([$cpu.cpus[]?.physical_package_id]|unique|length),
    numa_nodes:$cpu.numa_nodes,
    present:{raw:($cpu.present//null),cpus:(($cpu.present//null)|cpu_list_array)},
    possible:{raw:($cpu.possible//null),cpus:(($cpu.possible//null)|cpu_list_array)},
    online:{raw:($cpu.online//null),cpus:(($cpu.online//null)|cpu_list_array)},
    offline_raw:{raw:($cpu.offline//null),cpus:(($cpu.offline//null)|cpu_list_array)},
    smt:{active:($cpu.smt_active//null),control:($cpu.smt_control//null)},
    cores:([
      $cpu.cpus | group_by([.physical_package_id,.core_id])[] |
      . as $threads |
      {
        package_id:$threads[0].physical_package_id,
        core_id:$threads[0].core_id,
        die_id:$threads[0].die_id,
        node:$threads[0].node,
        core_type:(($threads[0].core_type//"")|clean_text),
        cpus:($threads|map(.cpu)|sort),
        thread_siblings_raw:$threads[0].thread_siblings_list,
        caches:$threads[0].cache,
        online_cpus:($threads|map(.cpu)|map(select(. as $id | (($cpu.online//"")|cpu_list_array|index($id))!=null)))
      }
    ] | sort_by((.package_id|tonumber?),(.core_id|tonumber?))),
    isolation:{
      isolated:{raw:(($iso.kernel_runtime.isolated_cpus//null)|clean_text),cpus:(($iso.kernel_runtime.isolated_cpus//null)|cpu_list_array)},
      nohz_full:{raw:(($iso.kernel_runtime.nohz_full_cpus//null)|clean_text),cpus:(($iso.kernel_runtime.nohz_full_cpus//null)|cpu_list_array)},
      rcu_nocb:{raw:(($iso.kernel_runtime.rcu_nocb_mask//null)|clean_text),cpus:(($iso.kernel_runtime.rcu_nocb_mask//null)|cpu_list_array)},
      cgroup_root:{cpus:($iso.cgroup_v2_root.cpuset_cpus//null),effective_cpus:($iso.cgroup_v2_root.cpuset_cpus_effective//null),mems:($iso.cgroup_v2_root.cpuset_mems//null),effective_mems:($iso.cgroup_v2_root.cpuset_mems_effective//null),partition:($iso.cgroup_v2_root.cpuset_cpus_partition//null)},
      systemd:{system_slice:kv_lines($iso.systemd_cpu_affinity.system_slice.stdout),user_slice:kv_lines($iso.systemd_cpu_affinity.user_slice.stdout),machine_slice:kv_lines($iso.systemd_cpu_affinity.machine_slice.stdout)},
      workqueues:[$iso.global_workqueues[]? | {name:.workqueue,mask:(.values.cpumask//.values.cpumask_requested//null),affinity_scope:(.values.affinity_scope//null),nice:(.values.nice//null)}],
      scheduler_sysctls:$iso.scheduler_sysctls
    },
    firmware_ras:$cpuFw,
    timers_watchdogs:$timersWatchdogs,
    power:{
      boost:($power.cpufreq.boost//null),
      scaling_drivers:([$power.cpufreq.policies[]?.values.scaling_driver|select(.!=null)]|unique),
      governors:([$power.cpufreq.policies[]?.values.scaling_governor|select(.!=null)]|unique),
      policies:$power.cpufreq.policies,
      idle_driver:($power.cpuidle.driver//null),
      idle_governor:($power.cpuidle.governor//null),
      idle_states_cpu0:((first($power.cpuidle.per_cpu[]?|select(.cpu==0))//{}).states//[])
    },
    irq_distribution:([
      $irqd.irqs[]? | {effective:(if (.effective_affinity_list//"")=="" then "none" else .effective_affinity_list end)}
      ] | group_by(.effective) | map({effective_cpus:.[0].effective,count:length}) | sort_by(if .effective_cpus=="none" then 999999 elif (.effective_cpus|test("^[0-9]+$")) then (.effective_cpus|tonumber) else 999998 end))
  },
  pci:{
    devices:[$pcie.devices[]? | . as $pd | . + {
      advanced:([ $pcieAdvanced.devices[]? | select(.bdf==$pd.bdf) ][0] // null),
      role:(if (.class|startswith("0x03")) then "display"
            elif (.class|startswith("0x04")) then "audio/media"
            elif (.class|startswith("0x0108")) then "nvme"
            elif (.class|startswith("0x01")) then "storage"
            elif (.class|startswith("0x02")) then "network"
            elif (.class|startswith("0x0c03")) then "usb"
            elif .class=="0x060400" then "bridge"
            else "other" end),
      proc_interrupt_irqs:irq_matches_bdf($irqsrc;$pd.bdf),
      msi_irqs:($pd.msi_irqs//[]),
      msi_irq_inventory_available:($pd|has("msi_irqs"))
    }],
    iommu_groups:$pcie.iommu_groups,
    irq_correlation_capability:{method:"sysfs msi_irqs plus /proc/interrupts MSI/MSI-X descriptor BDF",confidence:"configured-vector-and-point-in-time-observation",msi_irqs_sysfs_collected:(any($pcie.devices[]?; has("msi_irqs")))}
  },
  storage:{
    physical_block_devices:((try ($storage.raw.lsblk.stdout|fromjson).blockdevices catch []) | map(select(.type=="disk") as $disk | ([ $storage.block_queues[]? | select(.block==$disk.name) ][0] // null) as $q | {name:$disk.name,model:$disk.model,serial:$disk.serial,size:$disk.size,rota:$disk.rota,tran:$disk.tran,type:$disk.type,children:$disk.children,device_path:($q.device_path//null),pci_bdf:bdf_from_path($q.device_path),health_power:([ $storageHealth.disks[]? | select(.name==$disk.name) ][0] // null)})),
    nvme_controllers:[
      $storage.nvme_sysfs[]? as $n |
      (bdf_from_path($n.device_path)) as $bdf |
      ([ $pcie.devices[]? | select(.bdf==$bdf) ][0] // {}) as $pd |
      {
        controller:$n.controller,model:($n.model|clean_text),serial:$n.serial,firmware_rev:($n.firmware_rev|clean_text),state:$n.state,transport:$n.transport,health_power:([ $storageHealth.nvme[]? | select(.controller==$n.controller) ][0] // null),
        bdf:$bdf,block_devices:([$storage.block_queues[]?.block|select(startswith($n.controller))]),
        pci:{iommu_group:$pd.iommu_group,driver:$pd.driver,numa_node:$pd.numa_node,current_link_speed:$pd.current_link_speed,current_link_width:$pd.current_link_width,max_link_speed:$pd.max_link_speed,max_link_width:$pd.max_link_width,power_runtime_status:$pd.power_runtime_status,power_control:$pd.power_control,msi_irqs:($pd.msi_irqs//[])},
        irq_correlation:{method:(if (irq_matches_bdf($irqsrc;$bdf)|length)>0 then "proc-interrupts-msi-bdf" else "interrupt-source-name" end),confidence:(if (irq_matches_bdf($irqsrc;$bdf)|length)>0 then "exact-bdf" else "high" end),configured_vectors:($pd.msi_irqs//[]),matches:(if (irq_matches_bdf($irqsrc;$bdf)|length)>0 then irq_matches_bdf($irqsrc;$bdf) else source_matches($irqsrc;$n.controller) end)}
      }
    ],
    pve_storages:[
      $storageCfg[]? as $s |
      ($storageStatus[$s.name]//null) as $st |
      ($s.options.vgname//null) as $vg |
      ($s.options.thinpool//null) as $pool |
      (if ($vg!=null and $pool!=null) then
         (([ $lvs[]? | select(.vg_name==$vg and .lv_name==("["+$pool+"_tdata]")) ][0] //
          [ $lvs[]? | select(.vg_name==$vg and .lv_name==$pool) ][0]) // null)
       else null end) as $poollv |
      (if $s.type=="dir" then mount_for_path($storage.raw.findmnt.stdout;$s.options.path) else null end) as $mount |
      (if ($mount.source//"")|startswith("/dev/mapper/") then
          (($mount.source|sub("^/dev/mapper/";""))) as $mapper |
          ([ $lvs[]? | select(mapper_name(.vg_name;.lv_name)==$mapper) ][0] // null)
       else null end) as $dirlv |
      (($poollv.devices // $dirlv.devices // null)) as $devref |
      (base_block($devref)) as $base |
      ([ $storage.block_queues[]? | select(.block==$base) ][0] // null) as $blockq |
      (bdf_from_path($blockq.device_path)) as $block_bdf |
      (if $block_bdf!=null then $block_bdf
       elif ($base!=null and ($base|test("^nvme[0-9]+n[0-9]+$"))) then
         ($base|sub("n[0-9]+$";"")) as $ctrl |
         ([ $storage.nvme_sysfs[]? | select(.controller==$ctrl) | bdf_from_path(.device_path) ][0] // null)
       else null end) as $backing_bdf |
      {
        name:$s.name,type:$s.type,options:$s.options,status:$st,
        backing:{
          vg:($vg // $dirlv.vg_name // null),thinpool:$pool,mount_target:($mount.target//null),mount_source:($mount.source//null),filesystem:($mount.fstype//null),mount_options:($mount.options//null),lvm_devices:$devref,
          base_block:$base,sysfs_device_path:($blockq.device_path//null),pci_bdf:$backing_bdf,
          pci_correlation_method:(if $block_bdf!=null then "sysfs-block-device-ancestry" elif $backing_bdf!=null then "nvme-controller-sysfs" else null end)
        }
      }
    ],
    queue_objects:$storage.block_queues
  },
  network:{
    physical_interfaces:[
      $net.interfaces[]? | select((.driver//"")!="") as $n |
      (bdf_from_path($n.device_path)) as $bdf |
      ([ $pcie.devices[]? | select(.bdf==$bdf) ][0] // {}) as $pd |
      {
        name:$n.name,operstate:$n.operstate,mtu:$n.mtu,address:$n.address,numa_node:$n.numa_node,driver:($n.driver|split("/")[-1]),bdf:$bdf,advanced:([ $networkAdvanced.interfaces[]? | select(.name==$n.name) ][0] // null),
        pci:{iommu_group:$pd.iommu_group,current_link_speed:$pd.current_link_speed,current_link_width:$pd.current_link_width,max_link_speed:$pd.max_link_speed,max_link_width:$pd.max_link_width,msi_irqs:($pd.msi_irqs//[])},
        queues:$n.queues,ethtool:{settings:$n.ethtool,channels:$n.channels,coalesce:$n.coalesce,ring:$n.ring,features:$n.features},
        irq_correlation:{method:(if (irq_matches_bdf($irqsrc;$bdf)|length)>0 then "proc-interrupts-msi-bdf" else "interrupt-source-name" end),confidence:(if (irq_matches_bdf($irqsrc;$bdf)|length)>0 then "exact-bdf" else "high" end),configured_vectors:($pd.msi_irqs//[]),matches:(if (irq_matches_bdf($irqsrc;$bdf)|length)>0 then irq_matches_bdf($irqsrc;$bdf) else source_matches($irqsrc;$n.name) end)}
      }
    ],
    bridges:[
      $bridges[] as $b |
      ([ $pve.vm_configs[]? as $vm | vm_net_entries($vm.config_raw)[]? as $ne | select(bridge_from_net($ne.value)==$b.name) |
         ($qmStatus[$vm.vmid]//{}) as $vms | (entry_index($ne.key)) as $idx | ("tap"+$vm.vmid+"i"+($idx|tostring)) as $runtime_if |
         {vmid:$vm.vmid,name:(cfg_obj($vm.config_raw).name//$vms.name//null),net:$ne.key,model:model_from_net($ne.value),status:($vms.status//"unknown"),runtime_interface:$runtime_if,runtime_present:any($net.interfaces[]?; .name==$runtime_if)} ]) as $vms |
      ([ $pve.lxc_configs[]? as $ct | lxc_net_entries($ct.config_raw)[]? as $ne | select(option_from_csv($ne.value;"bridge")==$b.name) |
         ([ $pctStatus[]? | select(.vmid==$ct.vmid) ][0] // {}) as $cts | (entry_index($ne.key)) as $idx | ("veth"+$ct.vmid+"i"+($idx|tostring)) as $runtime_if |
         {vmid:$ct.vmid,name:(cfg_obj($ct.config_raw).hostname//$cts.name//null),net:$ne.key,type:option_from_csv($ne.value;"type"),status:($cts.status//"unknown"),runtime_interface:$runtime_if,runtime_present:any($net.interfaces[]?; .name==$runtime_if)} ]) as $cts |
      $b + {configured_vm_guests:$vms,running_vm_guests:[$vms[]|select(.status=="running")],configured_lxc_guests:$cts,running_lxc_guests:[$cts[]|select(.status=="running")]}
    ],
    virtual_interface_counts:{tap:([$net.interfaces[]?|select(.name|startswith("tap"))]|length),veth:([$net.interfaces[]?|select(.name|startswith("veth"))]|length),firewall_links:([$net.interfaces[]?|select(.name|test("^(fwln|fwpr)"))]|length)}
  },
  gpu:{
    devices:[
      $gpu.gpus[]? as $g |
      ([ $pcie.devices[]? | select(.bdf==$g.bdf) ][0] // {}) as $pd |
      {
        bdf:$g.bdf,vendor:$g.vendor,device:$g.device,driver:$g.driver,iommu_group:$g.iommu_group,boot_vga:$g.boot_vga,rom_present:$g.rom_present,power_runtime_status:$g.power_runtime_status,power_control:$g.power_control,
        pci:{current_link_speed:$pd.current_link_speed,current_link_width:$pd.current_link_width,max_link_speed:$pd.max_link_speed,max_link_width:$pd.max_link_width,numa_node:$pd.numa_node,msi_irqs:($pd.msi_irqs//[]),advanced:([ $pcieAdvanced.devices[]? | select(.bdf==$g.bdf) ][0] // null)},
        slot_functions:$g.slot_functions,
        irq_correlation:{method:(if (irq_matches_bdf($irqsrc;$g.bdf)|length)>0 then "proc-interrupts-msi-bdf" else "driver/source-name" end),confidence:(if (irq_matches_bdf($irqsrc;$g.bdf)|length)>0 then "exact-bdf" else "medium" end),configured_vectors:($pd.msi_irqs//[]),matches:(if (irq_matches_bdf($irqsrc;$g.bdf)|length)>0 then irq_matches_bdf($irqsrc;$g.bdf) else source_matches($irqsrc;$g.driver) end)}
      }
    ],
    vfio:{module_loaded:$gpu.vfio_module_loaded,parameters:$gpu.vfio_pci_parameters,configuration_probe:$gpu.vfio_related_configuration}
  },
  memory:{
    hardware:$memoryHardware,
    meminfo_raw:$mem.meminfo_raw,
    transparent_hugepages:{enabled_raw:$mem.transparent_hugepages.enabled,enabled_selected:selected_bracket($mem.transparent_hugepages.enabled),defrag_raw:$mem.transparent_hugepages.defrag,defrag_selected:selected_bracket($mem.transparent_hugepages.defrag),hpage_pmd_size:$mem.transparent_hugepages.hpage_pmd_size},
    ksm:$mem.ksm,
    swap:{raw:$mem.swap.proc_swaps_raw,swappiness:$mem.swap.swappiness,active:((($mem.swap.proc_swaps_raw//"")|split("\n")|map(select(length>0))|length)>1)},
    zswap:$mem.zswap,
    hugetlb:$mem.hugetlb
  },
  proxmox:{
    node:$pve.node,version:(($pve.version.stdout//"")|split("\n")[0]),cluster:{rc:$pve.cluster_status.rc,stdout:$pve.cluster_status.stdout,stderr:$pve.cluster_status.stderr},runtime_capabilities:($pve.runtime_capabilities//{lxc_info_available:false,cgroup_v2_present:false}),
    guest_counts:{configured_qemu:($pve.vm_configs|length),running_qemu:([$qmStatus|to_entries[]?|select(.value.status=="running")]|length),configured_lxc:($pve.lxc_configs|length),running_lxc:([$pctStatus[]?|select(.status=="running")]|length),qemu_status_records:($qmStatus|length),lxc_status_records:($pctStatus|length)},
    virtual_machines:[
      $pve.vm_configs[]? as $vm | (cfg_obj($vm.config_raw)) as $cfg | ($qmStatus[$vm.vmid]//{}) as $status | ([ $pve.qemu_runtime[]? | select(.vmid==$vm.vmid) ][0] // null) as $runtime |
      {vmid:$vm.vmid,name:($cfg.name//$status.name//null),status:($status.status//"unknown"),pid:(if (($status.pid//0)|tonumber?)>0 then $status.pid else null end),config_scope:{active_top_level_only:true,snapshot_count:(cfg_snapshot_names($vm.config_raw)|length),snapshot_names:cfg_snapshot_names($vm.config_raw)},
       cpu:{cores:(try ($cfg.cores|tonumber) catch null),sockets:(try ($cfg.sockets|tonumber) catch null),vcpus:(try ($cfg.vcpus|tonumber) catch null),type:($cfg.cpu//null),affinity:($cfg.affinity//null),numa:($cfg.numa//null)},
       memory:{memory_mib:(try ($cfg.memory|tonumber) catch null),balloon_mib:(try ($cfg.balloon|tonumber) catch null),hugepages:($cfg.hugepages//null)},firmware:{bios:($cfg.bios//null),machine:($cfg.machine//null)},
       hostpci:[vm_hostpci_entries($vm.config_raw)[]? | {key:.key,value:.value,bdf:hostpci_bdf(.value),pcie:option_from_csv(.value;"pcie"),rombar:option_from_csv(.value;"rombar"),x_vga:option_from_csv(.value;"x-vga"),multifunction:option_from_csv(.value;"multifunction")}],
       disks:[vm_disk_entries($vm.config_raw)[]? | {key:.key,bus:(.key|capture("^(?<bus>[A-Za-z]+)").bus),value:.value,storage:storage_name_from_value(.value),aio:option_from_csv(.value;"aio"),cache:option_from_csv(.value;"cache"),iothread:option_from_csv(.value;"iothread"),discard:option_from_csv(.value;"discard"),ssd:option_from_csv(.value;"ssd"),queues:option_from_csv(.value;"queues"),backup:option_from_csv(.value;"backup")}],
       networks:[vm_net_entries($vm.config_raw)[]? | . as $ne | (entry_index($ne.key)) as $idx | {key:.key,value:.value,model:model_from_net(.value),bridge:bridge_from_net(.value),queues:option_from_csv(.value;"queues"),firewall:option_from_csv(.value;"firewall"),mtu:option_from_csv(.value;"mtu"),rate:option_from_csv(.value;"rate"),tag:option_from_csv(.value;"tag"),runtime_interface:("tap"+$vm.vmid+"i"+($idx|tostring)),runtime_present:any($net.interfaces[]?; .name==("tap"+$vm.vmid+"i"+($idx|tostring)))}],
       qemu_args:($cfg.args//null),
       runtime:(if $runtime==null then {observed:false,pid:(if (($status.pid//0)|tonumber?)>0 then $status.pid else null end),process_cpus_allowed_list:null,process_online_cpus_allowed_list:null,cgroup:normalize_cgroup(null;null;($cpu.online//null)),threads:[],vhost_threads:[],affinity_groups:[]} else
         ([ $runtime.tasks[]? | . as $thr | . + {role:qemu_thread_role($thr),vcpu_index:qemu_vcpu_index($thr),online_cpus_allowed_list:cpulist_intersection(($thr.cpus_allowed_list//null);($cpu.online//null))} ]) as $threads |
         (([ $threads[]? | select(.role=="vhost") ] +
           [ $runtime.vhost_threads[]? | . as $vh |
             {tid:($vh.tid//$vh.pid),comm:$vh.comm,cpus_allowed_list:($vh.cpus_allowed_list//null),online_cpus_allowed_list:cpulist_intersection(($vh.cpus_allowed_list//null);($cpu.online//null)),scheduler_policy:($vh.scheduler_policy//null),scheduler_prio:($vh.scheduler_prio//null),is_main:false,role:"vhost",vcpu_index:null} ])
          | unique_by(.tid)) as $vhost |
         {observed:true,pid:$runtime.pid,process_cpus_allowed_list:$runtime.cpus_allowed_list,process_online_cpus_allowed_list:cpulist_intersection(($runtime.cpus_allowed_list//null);($cpu.online//null)),cgroup_raw:$runtime.cgroup_raw,cgroup:normalize_cgroup(($runtime.cgroup//null);($runtime.cgroup_raw//null);($cpu.online//null)),threads:$threads,vhost_threads:$vhost,affinity_groups:([ $threads[]? | {role:.role,cpus_allowed_list:(.cpus_allowed_list//"unknown"),online_cpus_allowed_list:(.online_cpus_allowed_list//"none")} ] | group_by([.role,.cpus_allowed_list,.online_cpus_allowed_list]) | map({role:.[0].role,cpus_allowed_list:.[0].cpus_allowed_list,online_cpus_allowed_list:.[0].online_cpus_allowed_list,count:length}))} end)}
    ],
    containers:[
      $pve.lxc_configs[]? as $ct | (cfg_obj($ct.config_raw)) as $cfg | ([ $pctStatus[]? | select(.vmid==$ct.vmid) ][0] // {}) as $status | ([ $pve.lxc_runtime[]? | select(.vmid==$ct.vmid) ][0] // null) as $runtime |
      {vmid:$ct.vmid,name:($cfg.hostname//$status.name//null),status:($status.status//"unknown"),lock:($status.lock//null),cpu:{cores:(try ($cfg.cores|tonumber) catch null),cpulimit:(try ($cfg.cpulimit|tonumber) catch null),cpuset:($cfg.cpuset//null)},memory:{memory_mib:(try ($cfg.memory|tonumber) catch null),swap_mib:(try ($cfg.swap|tonumber) catch null)},rootfs:($cfg.rootfs//null),features:($cfg.features//null),unprivileged:(try ($cfg.unprivileged|tonumber) catch null),mounts:[lxc_mount_entries($ct.config_raw)[]? | {key:.key,value:.value,storage:storage_name_from_value(.value)}],networks:[lxc_net_entries($ct.config_raw)[]? | . as $ne | (entry_index($ne.key)) as $idx | {key:.key,value:.value,type:option_from_csv(.value;"type"),name:option_from_csv(.value;"name"),bridge:option_from_csv(.value;"bridge"),runtime_interface:("veth"+$ct.vmid+"i"+($idx|tostring)),runtime_present:any($net.interfaces[]?; .name==("veth"+$ct.vmid+"i"+($idx|tostring)))}],
       runtime:(if $runtime==null then {observed:false,pid:null,process_cpus_allowed_list:null,process_online_cpus_allowed_list:null,cgroup:normalize_cgroup(null;null;($cpu.online//null))} else {observed:true,pid:$runtime.pid,process_cpus_allowed_list:$runtime.cpus_allowed_list,process_online_cpus_allowed_list:cpulist_intersection(($runtime.cpus_allowed_list//null);($cpu.online//null)),cgroup_raw:$runtime.cgroup_raw,cgroup:normalize_cgroup(($runtime.cgroup//null);($runtime.cgroup_raw//null);($cpu.online//null))} end)}
    ],
    status_only_virtual_machines:[ $qmStatus|to_entries[]? | .value as $qs | select(([ $pve.vm_configs[]?.vmid ] | index($qs.vmid))==null) | $qs ],
    status_only_containers:[ $pctStatus[]? as $ps | select(([ $pve.lxc_configs[]?.vmid ] | index($ps.vmid))==null) | $ps ],pve_storages:[]
  },
  platform_architecture:$acpiPlatform,
  platform_architecture_summary:{
    decoded_tables:[ $acpiPlatform.decoded_tables[]? | {name:.name,decoded:((.decoded_text//null)!=null),relevant_line_count:((.normalized_relevant_lines//[])|length),relevant_lines:(.normalized_relevant_lines//[])} ],
    apic_lines:([ $acpiPlatform.decoded_tables[]? | select(.name=="APIC") | .normalized_relevant_lines[]? ]),
    ivrs_lines:([ $acpiPlatform.decoded_tables[]? | select(.name=="IVRS") | .normalized_relevant_lines[]? ]),
    mcfg_lines:([ $acpiPlatform.decoded_tables[]? | select(.name=="MCFG") | .normalized_relevant_lines[]? ]),
    numa_locality_lines:([ $acpiPlatform.decoded_tables[]? | select(.name=="SRAT" or .name=="SLIT" or .name=="CRAT") | .normalized_relevant_lines[]? ])
  },
  firmware_settings:$firmwareSettings,
  virtualization_stack:$virtualizationStack,
  irq_activity:$irqActivity,
  runtime_pressure:$runtimePressure,
  kernel_events:$kernelEvents,
  guest_runtime_detail:$guestRuntimeDetail,
  kernel_housekeeping:$kernelHousekeeping,
  pm_qos:$pmQos,
  desktop_io_path:$desktopIoPath,
  latency_sample:$latencySample,
  cache_resource_qos:$cacheResourceQos,
  cpu_limits_pmu:$cpuLimitsPmu,
  irq_architecture:$irqArchitecture,
  memory_fragmentation:$memoryFragmentation,
  display_timing:$displayTiming,
  security_mitigations:$securityMitigations,
  peripherals:$usbAudio,
  background:{
    important_units:[ $services.important_units[]? | {unit:.unit,state:kv_lines(.state.stdout)} ],
    pve_jobs_configured:(($services.proxmox_jobs_cfg_raw//"")!=""),
    replication_configured:(($services.replication_cfg_raw//"")!="")
  },
  thermal_power:{
    thermal_zones:$thermal.thermal_zones,
    hwmon:$thermal.hwmon,
    powercap:$thermal.powercap,
    turbostat_snapshot:$thermal.raw.turbostat_snapshot
  },
  capability_matrix:{
    resctrl:{supported:(if ($cacheResourceQos.resctrl|has("filesystem_supported")) then $cacheResourceQos.resctrl.filesystem_supported else null end),mounted:(if ($cacheResourceQos.resctrl|has("mounted")) then $cacheResourceQos.resctrl.mounted else null end),available_but_inactive:((if ($cacheResourceQos.resctrl|has("filesystem_supported")) then $cacheResourceQos.resctrl.filesystem_supported else false end) and ((if ($cacheResourceQos.resctrl|has("mounted")) then $cacheResourceQos.resctrl.mounted else false end)|not)),group_count:(($cacheResourceQos.resctrl.groups//[])|length),groups:($cacheResourceQos.resctrl.groups//[])},
    cache_qos:($cacheResourceQos.capabilities//{}),
    pmu:{source_count:(($cpuLimitsPmu.pmu_sources//[])|length),perf_event_paranoid:($cpuLimitsPmu.perf_event_paranoid//null)},
    iommu:{
      group_count:(($pcie.iommu_groups//[])|length),
      interrupt_remapping_observed:(any($irqArchitecture.irqs[]?; .interrupt_remapped_msi==true) or any($iommuDmesgEvidence[]?; test("interrupt remapp";"i"))),
      cmdline_arguments:$iommuCmdlineArgs,
      default_domain_evidence:[$iommuDmesgEvidence[]? | select(test("default domain|domain type";"i"))],
      interrupt_remapping_evidence:[$iommuDmesgEvidence[]? | select(test("interrupt remapp";"i"))],
      initialization_evidence:$iommuDmesgEvidence,
      group_types:[$pcie.iommu_groups[]? | select((.type//null)!=null) | {group:.group,type:.type}],
      reserved_region_groups:[$pcie.iommu_groups[]? | select((.reserved_regions_raw//"")!="") | {group:.group,reserved_regions_raw:.reserved_regions_raw}],
      acs_override_argument:([$iommuCmdlineArgs[]? | select(startswith("pcie_acs_override="))][0] // null)
    },
    pcie:{
      rebar_devices:([$pcieAdvanced.devices[]?|select((.capability_evidence.resizable_bar//"")!="")]|map(.bdf)),
      acs_devices:([$pcieAdvanced.devices[]?|select((.capability_evidence.acs//"")!="")]|map(.bdf)),
      dpc_devices:([$pcieAdvanced.devices[]?|select((.capability_evidence.dpc//"")!="")]|map(.bdf)),
      ats_devices:([$pcieAdvanced.devices[]?|select((.capability_evidence.ats//"")!="")]|map(.bdf)),
      pri_devices:([$pcieAdvanced.devices[]?|select((.capability_evidence.pri//"")!="")]|map(.bdf)),
      pasid_devices:([$pcieAdvanced.devices[]?|select((.capability_evidence.pasid//"")!="")]|map(.bdf)),
      tph_devices:([$pcieAdvanced.devices[]?|select((.capability_evidence.tph//"")!="")]|map(.bdf)),
      sriov_capable_devices:([$pcieAdvanced.devices[]?|select((.sriov.totalvfs//0)>0)]|map(.bdf)),
      sriov_enabled_devices:([$pcieAdvanced.devices[]?|select((.sriov.numvfs//0)>0)]|map(.bdf)),
      acs_override_configured:any($iommuCmdlineArgs[]?; startswith("pcie_acs_override="))
    },
    display:{connected:($displayTiming.connected_count//0),vrr_capable_connectors:([$displayTiming.connectors[]?|select(.vrr_capable==true)]|map(.connector)),edid_connectors:([$displayTiming.connectors[]?|select(.edid.present==true)]|map(.connector)),active_modes:[$displayTiming.connectors[]?|select((.active_mode//null)!=null)|{connector:.connector,active_mode:.active_mode,max_bpc:(.max_bpc//null),link_status:(.link_status//null)}]},
    delay_accounting:{enabled:($guestRuntimeDetail.task_delayacct//null),task_count:([$guestRuntimeDetail.qemu_vms[]?.tasks[]?]|length)},
    virtualization:{
      kvm_available:($virtualizationStack.kvm_device.exists//null),
      avic_supported:any(($virtualizationStack.cpu_virtualization_flags//[])?; .=="avic"),
      avic_parameter:([ $virtualizationStack.module_parameters[]? | select(.module=="kvm_amd") | .parameters.avic? ][0] // null),
      nested_parameter:([ $virtualizationStack.module_parameters[]? | select(.module=="kvm_amd" or .module=="kvm_intel") | .parameters.nested? ][0] // null),
      vfio_allow_unsafe_interrupts:([ $virtualizationStack.module_parameters[]? | select(.module=="vfio_iommu_type1") | .parameters.allow_unsafe_interrupts? ][0] // null)
    },
    cpu_limits:{
      thermal_pressure_cpus:[$cpuLimitsPmu.cpus[]? | select((.thermal_pressure//0)!=0) | {cpu:.cpu,thermal_pressure:.thermal_pressure}],
      throttle_counters:[$cpuLimitsPmu.cpus[]? | select((.thermal_throttle.core_count//0)>0 or (.thermal_throttle.package_count//0)>0) | {cpu:.cpu,thermal_throttle:.thermal_throttle}],
      time_in_state_cpus:[$cpuLimitsPmu.cpus[]? | select((.time_in_state_raw//"")!="") | .cpu],
      frequency_residency:[$cpuLimitsPmu.cpus[]? | select((.time_in_state//[])|length>0) | {cpu:.cpu,total_ticks:(.time_in_state_total_ticks//0),states:.time_in_state}],
      nmi_watchdog:($cpuLimitsPmu.nmi_watchdog//null)
    },
    security:{
      vulnerability_count:(($securityMitigations.vulnerabilities//[])|length),
      vulnerable_or_unknown:[$securityMitigations.vulnerabilities[]? | select((.state//"")|test("Vulnerable|Unknown|Not affected";"i")|not) | {name:.name,state:.state}],
      explicit_arguments:($securityMitigations.explicit_mitigation_arguments//[]),
      cpu_capabilities:($securityMitigations.cpu_capabilities//{})
    },
    audio:{pcm_device_count:(($usbAudio.pcm_devices//[])|length),open_substreams:([ $usbAudio.pcm_devices[]?.substreams[]? | select(.stream_open==true)]|length),hda_parameters:($usbAudio.snd_hda_intel_parameters//[])},
    network:{interfaces:[ $networkAdvanced.interfaces[]? | {name:.name,configured_rx_queues:([.queues[]?|select(.queue|startswith("rx-"))]|length),configured_tx_queues:([.queues[]?|select(.queue|startswith("tx-"))]|length),channels_raw:(.channels.stdout//null),rss_available:(.rss.available//false)}]},
    hugepages:{pools:($memoryFragmentation.hugetlb//[]),thp:($memoryFragmentation.transparent_hugepage//{}),fragmentation_zones:($memoryFragmentation.fragmentation_summary//[])}
  },
  topology_graph:{
    nodes:(([ $cpu.cpus[]? | {id:("cpu:"+(.cpu|tostring)),type:"logical-cpu",label:("CPU "+(.cpu|tostring))}] +
           [ $cpu.cpus[]? | {id:("core:"+(.physical_package_id//"?")+":"+(.core_id//"?")),type:"physical-core",label:("package "+(.physical_package_id//"?")+" core "+(.core_id//"?"))}] +
           [ $cacheNodes[]? | {id:("cache:L"+(.level|tostring)+":"+(.type//"?")+":"+((.cache_id//.shared_cpu_list//"?")|tostring)),type:"cache",label:("L"+(.level|tostring)+" "+(.type//"cache")+" "+(.size//"?")),shared_cpu_list:.shared_cpu_list}] +
           [ $cacheResourceQos.numa_nodes[]? | {id:("numa:"+(.node|tostring)),type:"numa-node",label:("NUMA "+(.node|tostring)),cpulist:(.cpulist//null)}] +
           [ $pcie.iommu_groups[]? | {id:("iommu-group:"+(.group|tostring)),type:"iommu-group",label:("IOMMU group "+(.group|tostring))}] +
           [ $pcie.devices[]? | {id:("pci:"+.bdf),type:"pci-device",label:.bdf}] +
           [ $irqd.irqs[]? | {id:("irq:"+(.irq|tostring)),type:"irq",label:("IRQ "+(.irq|tostring))}] +
           [ $pcie.devices[]? as $pd | ($pd.msi_irqs//[])[]? as $m | (($m.irq//$m)|tostring) as $irq | {id:("irq:"+$irq),type:"irq",label:("IRQ "+$irq)}] +
           [ $pve.vm_configs[]? | {id:("vm:"+.vmid),type:"qemu-vm",label:(.vmid+":"+((cfg_obj(.config_raw).name)//"unnamed"))}] +
           [ $storage.block_queues[]? | {id:("block:"+.block),type:"block-device",label:.block}] +
           [ $net.interfaces[]? | {id:("net:"+.name),type:"net-interface",label:.name}] +
           [ $desktopIoPath.usb[]? | {id:("usb:"+.device),type:"usb-device",label:.device}] +
           [ $displayTiming.connectors[]? | {id:("display:"+.connector),type:"display-connector",label:.connector}] +
           [ $usbAudio.sound_cards[]? | {id:("sound:"+.card),type:"sound-card",label:(.card+":"+(.id//"unknown"))}] ) | unique_by(.id)),
    edges:(([ $cpu.cpus[]? | {from:("cpu:"+(.cpu|tostring)),to:("core:"+(.physical_package_id//"?")+":"+(.core_id//"?")),relation:"thread-of-core"}] +
           [ $cacheResourceQos.cache_entries[]? | {from:("cpu:"+(.cpu|tostring)),to:("cache:L"+(.level|tostring)+":"+(.type//"?")+":"+((.cache_id//.shared_cpu_list//"?")|tostring)),relation:"shares-cache"}] +
           [ $cacheResourceQos.numa_nodes[]? as $n | (($n.cpulist//"")|cpu_list_array)[]? | {from:("cpu:"+(tostring)),to:("numa:"+($n.node|tostring)),relation:"numa-member"}] +
           [ $pcie.devices[]? | select((.iommu_group//null)!=null) | {from:("pci:"+.bdf),to:("iommu-group:"+(.iommu_group|tostring)),relation:"iommu-member"}] +
           [ $pcieAdvanced.devices[]? | select((.upstream_path_bdfs//[])|length>1) | {from:("pci:"+.bdf),to:("pci:"+(.upstream_path_bdfs[-2])),relation:"upstream-parent"}] +
           [ $pcie.devices[]? as $pd | ($pd.msi_irqs//[])[]? as $m | {from:("pci:"+$pd.bdf),to:("irq:"+(($m.irq//$m)|tostring)),relation:"msi-vector"}] +
           [ $storage.block_queues[]? | (bdf_from_path(.device_path)) as $b | select($b!=null) | {from:("block:"+.block),to:("pci:"+$b),relation:"controller-path"}] +
           [ $net.interfaces[]? | (bdf_from_path(.device_path)) as $b | select($b!=null) | {from:("net:"+.name),to:("pci:"+$b),relation:"controller-path"}] +
           [ $desktopIoPath.usb[]? | select((.controller_bdf//null)!=null) | {from:("usb:"+.device),to:("pci:"+.controller_bdf),relation:"usb-controller"}] +
           [ $displayTiming.connectors[]? | select((.pci_bdf//null)!=null) | {from:("display:"+.connector),to:("pci:"+.pci_bdf),relation:"display-controller"}] +
           [ $usbAudio.sound_cards[]? | select((.pci_ancestor//null)!=null) | {from:("sound:"+.card),to:("pci:"+.pci_ancestor),relation:"audio-controller"}] ) | unique_by([.from,.to,.relation])),
    integrity:{
      all_edge_sources_have_nodes:null,
      all_edge_targets_have_nodes:null,
      note:"Graph edges are evidence correlations; absence of an edge is not proof of physical separation."
    }
  },
  evidence_catalog:([
    {domain:"platform",source_collectors:["platform"],path_prefixes:["source","platform_architecture_summary"],scope:"runtime-snapshot",confidence:"direct",stability:"boot-stable",collector_present:($c|has("platform")),error_count:((env($c;"platform").errors//[])|length),captured_at:(env($c;"platform").collected_at//null)},
    {domain:"firmware-settings",source_collectors:["firmware-settings"],path_prefixes:["firmware_settings"],scope:"firmware-reported",confidence:"direct-where-exposed",stability:"firmware-stable",collector_present:($c|has("firmware-settings")),error_count:((env($c;"firmware-settings").errors//[])|length),captured_at:(env($c;"firmware-settings").collected_at//null)},
    {domain:"acpi-platform",source_collectors:["acpi-platform"],path_prefixes:["platform_architecture","platform_architecture_summary"],scope:"firmware-reported",confidence:"direct-plus-decoded-firmware",stability:"boot-stable",collector_present:($c|has("acpi-platform")),error_count:((env($c;"acpi-platform").errors//[])|length),captured_at:(env($c;"acpi-platform").collected_at//null)},
    {domain:"security-mitigations",source_collectors:["security-mitigations"],path_prefixes:["security_mitigations","capability_matrix.security"],scope:"boot-plus-runtime-state",confidence:"kernel-reported",stability:"boot-stable",collector_present:($c|has("security-mitigations")),error_count:((env($c;"security-mitigations").errors//[])|length),captured_at:(env($c;"security-mitigations").collected_at//null)},
    {domain:"boot-kernel",source_collectors:["boot-kernel"],path_prefixes:["cpu.isolation","capability_matrix.iommu"],scope:"boot-configuration",confidence:"direct",stability:"boot-stable",collector_present:($c|has("boot-kernel")),error_count:((env($c;"boot-kernel").errors//[])|length),captured_at:(env($c;"boot-kernel").collected_at//null)},
    {domain:"cpu-topology",source_collectors:["cpu-topology"],path_prefixes:["cpu","topology_graph"],scope:"static-hardware",confidence:"direct",stability:"hardware-stable",collector_present:($c|has("cpu-topology")),error_count:((env($c;"cpu-topology").errors//[])|length),captured_at:(env($c;"cpu-topology").collected_at//null)},
    {domain:"cpu-firmware-ras",source_collectors:["cpu-firmware-ras"],path_prefixes:["cpu.firmware_ras"],scope:"boot-plus-runtime-state",confidence:"direct-plus-kernel-reported",stability:"boot-stable",collector_present:($c|has("cpu-firmware-ras")),error_count:((env($c;"cpu-firmware-ras").errors//[])|length),captured_at:(env($c;"cpu-firmware-ras").collected_at//null)},
    {domain:"cpu-power-idle",source_collectors:["cpu-power-idle"],path_prefixes:["cpu.power"],scope:"runtime-snapshot",confidence:"direct",stability:"runtime-dynamic",collector_present:($c|has("cpu-power-idle")),error_count:((env($c;"cpu-power-idle").errors//[])|length),captured_at:(env($c;"cpu-power-idle").collected_at//null)},
    {domain:"cpu-limits-pmu",source_collectors:["cpu-limits-pmu"],path_prefixes:["cpu_limits_pmu","capability_matrix.pmu","capability_matrix.cpu_limits"],scope:"runtime-snapshot-plus-cumulative-counters",confidence:"direct",stability:"runtime-dynamic",collector_present:($c|has("cpu-limits-pmu")),error_count:((env($c;"cpu-limits-pmu").errors//[])|length),captured_at:(env($c;"cpu-limits-pmu").collected_at//null)},
    {domain:"cache-resource-qos",source_collectors:["cache-resource-qos"],path_prefixes:["cache_resource_qos","capability_matrix.resctrl","capability_matrix.cache_qos","topology_graph"],scope:"static-plus-runtime-interface",confidence:"direct",stability:"mixed-static-runtime",collector_present:($c|has("cache-resource-qos")),error_count:((env($c;"cache-resource-qos").errors//[])|length),captured_at:(env($c;"cache-resource-qos").collected_at//null)},
    {domain:"timers-watchdogs",source_collectors:["timers-watchdogs"],path_prefixes:["cpu.timers_watchdogs"],scope:"boot-plus-runtime-state",confidence:"direct",stability:"boot-stable",collector_present:($c|has("timers-watchdogs")),error_count:((env($c;"timers-watchdogs").errors//[])|length),captured_at:(env($c;"timers-watchdogs").collected_at//null)},
    {domain:"kernel-events",source_collectors:["kernel-events"],path_prefixes:["kernel_events"],scope:"historical-current-boot",confidence:"normalized-from-kernel-log",stability:"current-boot-history",collector_present:($c|has("kernel-events")),error_count:((env($c;"kernel-events").errors//[])|length),captured_at:(env($c;"kernel-events").collected_at//null)},
    {domain:"virtualization-stack",source_collectors:["virtualization-stack"],path_prefixes:["virtualization_stack","capability_matrix.virtualization"],scope:"boot-plus-runtime-state",confidence:"direct",stability:"boot-stable",collector_present:($c|has("virtualization-stack")),error_count:((env($c;"virtualization-stack").errors//[])|length),captured_at:(env($c;"virtualization-stack").collected_at//null)},
    {domain:"kernel-housekeeping",source_collectors:["kernel-housekeeping"],path_prefixes:["kernel_housekeeping"],scope:"runtime-snapshot",confidence:"direct",stability:"runtime-dynamic",collector_present:($c|has("kernel-housekeeping")),error_count:((env($c;"kernel-housekeeping").errors//[])|length),captured_at:(env($c;"kernel-housekeeping").collected_at//null)},
    {domain:"pm-qos",source_collectors:["pm-qos"],path_prefixes:["pm_qos"],scope:"runtime-snapshot",confidence:"direct-where-exposed",stability:"runtime-dynamic",collector_present:($c|has("pm-qos")),error_count:((env($c;"pm-qos").errors//[])|length),captured_at:(env($c;"pm-qos").collected_at//null)},
    {domain:"pcie-iommu",source_collectors:["pcie-iommu"],path_prefixes:["pci","capability_matrix.iommu","topology_graph"],scope:"static-plus-runtime-state",confidence:"direct",stability:"mixed-static-runtime",collector_present:($c|has("pcie-iommu")),error_count:((env($c;"pcie-iommu").errors//[])|length),captured_at:(env($c;"pcie-iommu").collected_at//null)},
    {domain:"pcie-advanced",source_collectors:["pcie-advanced"],path_prefixes:["pci.devices[].advanced","capability_matrix.pcie","topology_graph"],scope:"runtime-snapshot-plus-capability",confidence:"direct",stability:"mixed-static-runtime",collector_present:($c|has("pcie-advanced")),error_count:((env($c;"pcie-advanced").errors//[])|length),captured_at:(env($c;"pcie-advanced").collected_at//null)},
    {domain:"irq-architecture",source_collectors:["irq-architecture"],path_prefixes:["irq_architecture","capability_matrix.iommu"],scope:"runtime-snapshot",confidence:"direct-where-exposed",stability:"runtime-dynamic",collector_present:($c|has("irq-architecture")),error_count:((env($c;"irq-architecture").errors//[])|length),captured_at:(env($c;"irq-architecture").collected_at//null)},
    {domain:"gpu-vfio",source_collectors:["gpu-vfio"],path_prefixes:["gpu"],scope:"runtime-snapshot",confidence:"direct",stability:"runtime-dynamic",collector_present:($c|has("gpu-vfio")),error_count:((env($c;"gpu-vfio").errors//[])|length),captured_at:(env($c;"gpu-vfio").collected_at//null)},
    {domain:"isolation-scheduler",source_collectors:["isolation-scheduler"],path_prefixes:["cpu.isolation"],scope:"boot-plus-runtime-state",confidence:"direct",stability:"runtime-dynamic",collector_present:($c|has("isolation-scheduler")),error_count:((env($c;"isolation-scheduler").errors//[])|length),captured_at:(env($c;"isolation-scheduler").collected_at//null)},
    {domain:"memory",source_collectors:["memory"],path_prefixes:["memory"],scope:"runtime-snapshot",confidence:"direct",stability:"runtime-dynamic",collector_present:($c|has("memory")),error_count:((env($c;"memory").errors//[])|length),captured_at:(env($c;"memory").collected_at//null)},
    {domain:"memory-hardware",source_collectors:["memory-hardware"],path_prefixes:["memory.hardware"],scope:"static-hardware",confidence:"firmware-kernel-reported",stability:"hardware-stable",collector_present:($c|has("memory-hardware")),error_count:((env($c;"memory-hardware").errors//[])|length),captured_at:(env($c;"memory-hardware").collected_at//null)},
    {domain:"memory-fragmentation",source_collectors:["memory-fragmentation"],path_prefixes:["memory_fragmentation","capability_matrix.hugepages"],scope:"runtime-snapshot-plus-cumulative-counters",confidence:"direct",stability:"runtime-dynamic",collector_present:($c|has("memory-fragmentation")),error_count:((env($c;"memory-fragmentation").errors//[])|length),captured_at:(env($c;"memory-fragmentation").collected_at//null)},
    {domain:"irqs",source_collectors:["irqs"],path_prefixes:["cpu.irq_distribution","correlations.irq_sources"],scope:"runtime-snapshot",confidence:"direct",stability:"runtime-dynamic",collector_present:($c|has("irqs")),error_count:((env($c;"irqs").errors//[])|length),captured_at:(env($c;"irqs").collected_at//null)},
    {domain:"irq-activity",source_collectors:["irq-activity"],path_prefixes:["irq_activity"],scope:"runtime-window",confidence:"passive-sample",stability:"runtime-window",collector_present:($c|has("irq-activity")),error_count:((env($c;"irq-activity").errors//[])|length),captured_at:(env($c;"irq-activity").collected_at//null)},
    {domain:"runtime-pressure",source_collectors:["runtime-pressure"],path_prefixes:["runtime_pressure"],scope:"runtime-window",confidence:"passive-sample",stability:"runtime-window",collector_present:($c|has("runtime-pressure")),error_count:((env($c;"runtime-pressure").errors//[])|length),captured_at:(env($c;"runtime-pressure").collected_at//null)},
    {domain:"latency-sample",source_collectors:["latency-sample"],path_prefixes:["latency_sample"],scope:"runtime-window",confidence:"passive-sample",stability:"runtime-window",collector_present:($c|has("latency-sample")),error_count:((env($c;"latency-sample").errors//[])|length),captured_at:(env($c;"latency-sample").collected_at//null)},
    {domain:"storage",source_collectors:["storage"],path_prefixes:["storage"],scope:"runtime-snapshot",confidence:"direct-plus-sysfs-correlation",stability:"runtime-dynamic",collector_present:($c|has("storage")),error_count:((env($c;"storage").errors//[])|length),captured_at:(env($c;"storage").collected_at//null)},
    {domain:"storage-health-power",source_collectors:["storage-health-power"],path_prefixes:["storage.physical_block_devices[].health_power","storage.nvme_controllers[].health_power"],scope:"runtime-snapshot-plus-device-counters",confidence:"direct-device-reported",stability:"runtime-dynamic",collector_present:($c|has("storage-health-power")),error_count:((env($c;"storage-health-power").errors//[])|length),captured_at:(env($c;"storage-health-power").collected_at//null)},
    {domain:"network",source_collectors:["network"],path_prefixes:["network","correlations.desktop_network_paths"],scope:"runtime-snapshot",confidence:"direct-plus-correlation",stability:"runtime-dynamic",collector_present:($c|has("network")),error_count:((env($c;"network").errors//[])|length),captured_at:(env($c;"network").collected_at//null)},
    {domain:"network-advanced",source_collectors:["network-advanced"],path_prefixes:["network.physical_interfaces[].advanced","capability_matrix.network"],scope:"runtime-snapshot-plus-capability",confidence:"direct",stability:"runtime-dynamic",collector_present:($c|has("network-advanced")),error_count:((env($c;"network-advanced").errors//[])|length),captured_at:(env($c;"network-advanced").collected_at//null)},
    {domain:"usb-input-audio",source_collectors:["usb-input-audio"],path_prefixes:["peripherals","capability_matrix.audio","topology_graph"],scope:"runtime-snapshot-plus-capability",confidence:"direct-plus-sysfs-correlation",stability:"runtime-dynamic",collector_present:($c|has("usb-input-audio")),error_count:((env($c;"usb-input-audio").errors//[])|length),captured_at:(env($c;"usb-input-audio").collected_at//null)},
    {domain:"desktop-io-path",source_collectors:["desktop-io-path"],path_prefixes:["desktop_io_path","correlations.desktop_network_paths"],scope:"runtime-snapshot",confidence:"direct-plus-sysfs-correlation",stability:"runtime-dynamic",collector_present:($c|has("desktop-io-path")),error_count:((env($c;"desktop-io-path").errors//[])|length),captured_at:(env($c;"desktop-io-path").collected_at//null)},
    {domain:"display-timing",source_collectors:["display-timing"],path_prefixes:["display_timing","capability_matrix.display","topology_graph"],scope:"runtime-snapshot",confidence:"direct-host-visible",stability:"runtime-dynamic",collector_present:($c|has("display-timing")),error_count:((env($c;"display-timing").errors//[])|length),captured_at:(env($c;"display-timing").collected_at//null)},
    {domain:"services-background",source_collectors:["services-background"],path_prefixes:["background"],scope:"runtime-snapshot",confidence:"direct",stability:"runtime-dynamic",collector_present:($c|has("services-background")),error_count:((env($c;"services-background").errors//[])|length),captured_at:(env($c;"services-background").collected_at//null)},
    {domain:"thermal-power",source_collectors:["thermal-power"],path_prefixes:["thermal_power"],scope:"runtime-snapshot",confidence:"direct-sensor-reported",stability:"runtime-dynamic",collector_present:($c|has("thermal-power")),error_count:((env($c;"thermal-power").errors//[])|length),captured_at:(env($c;"thermal-power").collected_at//null)},
    {domain:"proxmox-host",source_collectors:["proxmox-host"],path_prefixes:["proxmox","correlations.desktop_network_paths"],scope:"configuration-plus-runtime-snapshot",confidence:"direct-plus-normalized-config",stability:"runtime-dynamic",collector_present:($c|has("proxmox-host")),error_count:((env($c;"proxmox-host").errors//[])|length),captured_at:(env($c;"proxmox-host").collected_at//null)},
    {domain:"guest-runtime-detail",source_collectors:["guest-runtime-detail"],path_prefixes:["guest_runtime_detail","capability_matrix.delay_accounting"],scope:"runtime-snapshot",confidence:"direct",stability:"runtime-dynamic",collector_present:($c|has("guest-runtime-detail")),error_count:((env($c;"guest-runtime-detail").errors//[])|length),captured_at:(env($c;"guest-runtime-detail").collected_at//null)}
  ] + [
    {domain:"topology-graph",source_collectors:["multiple"],path_prefixes:["topology_graph"],scope:"derived-correlation",confidence:"evidence-linked",stability:"depends-on-source-domains",collector_present:true,error_count:0,captured_at:$generated_at},
    {domain:"capability-matrix",source_collectors:["multiple"],path_prefixes:["capability_matrix"],scope:"derived-capability-summary",confidence:"evidence-linked",stability:"depends-on-source-domains",collector_present:true,error_count:0,captured_at:$generated_at}
  ]),
  correlations:{
    irq_sources:$irqsrc,
    exact_pci_msi_irq_mapping_from_proc_interrupts:true,
    msi_irqs_sysfs_collected:any($pcie.devices[]?; has("msi_irqs")),
    desktop_network_paths:[
      $pve.vm_configs[]? as $vm |
      vm_net_entries($vm.config_raw)[]? as $ne |
      (bridge_from_net($ne.value)) as $bridge |
      (entry_index($ne.key)) as $idx |
      ("tap"+$vm.vmid+"i"+($idx|tostring)) as $tap |
      ([ $bridges[]? | select(.name==$bridge) ][0] // {ports:[]}) as $br |
      (vm_vhost_threads($pve.qemu_runtime;$vm.vmid)) as $vhost |
      {
        vmid:$vm.vmid,
        vm_name:(cfg_obj($vm.config_raw).name//null),
        net:$ne.key,
        model:model_from_net($ne.value),
        bridge:$bridge,
        tap_interface:$tap,
        tap_present:any($net.interfaces[]?; .name==$tap),
        vhost_threads:$vhost,
        physical_paths:[
          $br.ports[]? as $port |
          (net_from_name($net.interfaces;$port)) as $ni |
          select($ni!=null) |
          (bdf_from_path($ni.device_path)) as $bdf |
          (pci_from_bdf($pcie.devices;$bdf)) as $pd |
          (advanced_net_from_name($networkAdvanced.interfaces;$port)) as $na |
          {
            interface:$port,
            bdf:$bdf,
            driver:(($ni.driver//"")|split("/")[-1]),
            queues:($na.queues//$ni.queues//[]),
            rss:($na.rss//null),
            rps_xps:($na.queues//[]),
            configured_msi_vectors:($pd.msi_irqs//[]),
            observed_irqs:(if $bdf!=null and (irq_matches_bdf($irqsrc;$bdf)|length)>0 then irq_matches_bdf($irqsrc;$bdf) else source_matches($irqsrc;$port) end)
          }
        ]
      }
    ],
    notes:["PCI msi_irqs is the configured sysfs MSI/MSI-X vector inventory when captured; /proc/interrupts is the point-in-time interrupt observation.","When /proc/interrupts exposes an MSI/MSI-X descriptor containing a PCI BDF, the harmonizer maps that IRQ to the BDF directly.","Source-name matching is used only as a fallback when a BDF is absent from the interrupt descriptor.","QEMU/LXC task affinity and cgroup CPU controls are point-in-time observations and are not inferred from guest configuration affinity.","Raw task Cpus_allowed_list is preserved separately from its intersection with the host online CPU set.","cgroup file-presence evidence distinguishes an absent cpuset interface from a present-but-empty inherited value when captured."]
  },
  limitations:(["Physical CPU-lane versus chipset attachment is not inferred from generic Linux PCI topology.","Literal firmware Above 4G Decoding state is not inferred.","Older 32-domain v0.8.7/v0.8.8, 26-domain v0.8.5/v0.8.6 and 14-domain core captures remain replayable under explicit compatibility contracts; unavailable newer evidence stays empty rather than being inferred.","QEMU/LXC runtime task and cgroup affinity is point-in-time evidence only; threads and effective controls can change after collection.","Older captures that lack cgroup file-presence booleans retain cgroup interface state as unknown rather than assuming inheritance or absence."] + (if ($missing_collectors=="") then [] else ["This host map was generated from a partial collector set: "+$missing_collectors] end))
}
| .proxmox.pve_storages = .storage.pve_storages
| (.topology_graph.nodes | map(.id)) as $graph_ids
| .topology_graph.integrity.all_edge_sources_have_nodes = (all(.topology_graph.edges[]?; (.from as $id | ($graph_ids | index($id)) != null)))
| .topology_graph.integrity.all_edge_targets_have_nodes = (all(.topology_graph.edges[]?; (.to as $id | ($graph_ids | index($id)) != null)))

HFIP_JQ
}

# ============================================================
# harmonize
# Generates the host-map JSON model.
#
# Version:
#   1.0.0
# ============================================================
harmonize() {
    hh_generated=$(date '+%Y-%m-%dT%H:%M:%S%z')
    if [ "$app_allow_partial" -eq 1 ]; then hh_strict=false; else hh_strict=true; fi
    write_harmonizer_program || return 1
    hh_result=$app_temp_dir/host-map.json
    jq -n       --slurpfile collectors "$hpi_collectors_file"       --slurpfile manifest "$hpi_manifest_file"       --arg generated_at "$hh_generated"       --arg source_dir "$app_from_run"       --arg source_kind "$app_source_kind"       --arg hostname "$hpi_hostname"       --arg collection_start "$hpi_start"       --arg collection_end "$hpi_end"       --arg manifest_present "$hpi_manifest_present"       --arg strict "$hh_strict"       --arg expected_collectors "$hpi_expected_csv"       --arg missing_collectors "$hpi_missing_csv"       -f "$app_temp_dir/harmonize.jq" > "$hh_result" || return 1

    jq -e '.schema_version=="0.8.9" and .model=="host-map" and (.cpu|type=="object") and (.pci|type=="object") and (.proxmox|type=="object")' "$hh_result" >/dev/null 2>&1 || return 1

    if [ -n "$app_output" ]; then
        if [ -e "$app_output" ]; then
            message error "ERROR: Output file already exists: $app_output"
            return 2
        fi
        hh_parent=$(dirname -- "$app_output")
        [ -d "$hh_parent" ] || { message error "ERROR: Output directory does not exist: $hh_parent"; return 2; }
        if [ "$app_compact" -eq 1 ]; then jq -c . "$hh_result" > "$app_output"; else jq . "$hh_result" > "$app_output"; fi || return 1
        message ok "Host map written: $app_output"
    else
        if [ "$app_compact" -eq 1 ]; then jq -c . "$hh_result"; else jq . "$hh_result"; fi
    fi
    return 0
}

# ============================================================
# main
# Coordinates validation and harmonization.
#
# Version:
#   1.0.0
# ============================================================
main() {
    case "$hpo_action" in
        help) usage; return 0 ;;
        version) printf '%s %s
' "$app_name" "$app_version"; return 0 ;;
    esac
    message title "Host Inventory for Proxmox - Harmonizer $app_version"
    ensure_dependencies || return $?
    prepare_input || return $?
    message info "Source: $app_from_run"
    message info "Host: $hpi_hostname"
    if [ -n "$hpi_missing_csv" ]; then
        message warn "Partial collectors: $hpi_missing_csv"
    else
        hmain_present_count=$(printf '%s' "$hpi_expected_csv" | awk -F, '{print NF}')
        message ok "Validated all $hmain_present_count collector envelopes."
    fi
    harmonize
}

# ------------------------------ setup ------------------------------
trap cleanup EXIT HUP INT TERM
color_init
parse_options "$@"
app_rc=$?
color_init

# ------------------------------- main -------------------------------
if [ "$app_rc" -eq 0 ]; then main; app_rc=$?; fi

# -------------------------------- end -------------------------------
exit "$app_rc"
