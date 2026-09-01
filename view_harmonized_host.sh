#!/bin/sh
# ============================================================
# view_harmonized_host.sh
# Presents the harmonized Host Inventory for Proxmox host map in a
# colorized, cross-domain, evidence-oriented terminal layout.
#
# Version:
#   0.9.2
#
# Usage:
#   sudo ./view_harmonized_host.sh
#   ./view_harmonized_host.sh --file host-map.json
#   ./view_harmonized_host.sh --from-run host-inventory-YYYYMMDD-HHMMSS
#
# Output:
#   Human-readable harmonized host view on stdout.
#
# Returns:
#   0 on success
#   1 on rendering/harmonization failure
#   2 on invalid input or missing dependency
#
# Dependencies:
#   jq; sibling run_all.sh and harmonize_host.sh for live mode;
#   harmonize_host.sh for --from-run replay mode.
#
# Side Effects:
#   Live mode invokes run_all.sh and may install explicitly approved
#   diagnostic packages. Its temporary collection directory is removed
#   after rendering. Replay/file modes are read-only except for optional
#   approved jq installation.
# ============================================================
app_name=view_harmonized_host
app_version=0.9.2
app_rc=0
app_file=
app_from_run=
app_allow_partial=0
app_skip_prepare=0
app_color_mode=auto
app_install_mode=ask
app_temp_dir=
app_script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || exit 2

# ============================================================
# color_init
# Defines semantic ANSI colors.
#
# Version:
#   1.0.0
# ============================================================
color_init() {
    vhc_enable=0
    [ -n "${NO_COLOR-}" ] && app_color_mode=never
    case "$app_color_mode" in
        always) vhc_enable=1 ;;
        never) vhc_enable=0 ;;
        auto) [ -t 1 ] && vhc_enable=1 ;;
        *) app_color_mode=auto; [ -t 1 ] && vhc_enable=1 ;;
    esac
    if [ "$vhc_enable" -eq 1 ]; then
        app_color_reset=$(printf '\033[0m')
        app_color_title=$(printf '\033[1;96m')
        app_color_section=$(printf '\033[96m')
        app_color_accent=$(printf '\033[95m')
        app_color_detail=$(printf '\033[37m')
        app_color_dim=$(printf '\033[90m')
        app_color_note=$(printf '\033[93m')
        app_color_error=$(printf '\033[91m')
    else
        app_color_reset=; app_color_title=; app_color_section=; app_color_accent=; app_color_detail=; app_color_dim=; app_color_note=; app_color_error=
    fi
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
# message
# Prints one human status/error line to stderr.
#
# Version:
#   1.0.0
# ============================================================
message() {
    vhm_role=$1
    shift
    case "$vhm_role" in
        error) vhm_color=$app_color_error ;;
        note) vhm_color=$app_color_note ;;
        *) vhm_color=$app_color_dim ;;
    esac
    printf '%s%s%s\n' "$vhm_color" "$*" "$app_color_reset" >&2
    return 0
}

# ============================================================
# view_divider
# Prints a wide view divider.
#
# Version:
#   1.0.0
# ============================================================
view_divider() {
    printf '%s%s%s\n' "$app_color_dim" '==============================================================================' "$app_color_reset"
    return 0
}

# ============================================================
# view_section
# Prints one major section heading.
#
# Version:
#   1.0.0
# ============================================================
view_section() {
    printf '\n%s%s%s\n' "$app_color_section" "$1" "$app_color_reset"
    return 0
}

# ============================================================
# view_kv
# Prints one aligned key/value field.
#
# Version:
#   1.0.0
# ============================================================
view_kv() {
    vhkv_label=$1
    vhkv_value=$2
    [ -n "$vhkv_value" ] || vhkv_value=unknown
    printf '  %s%-27s%s %s\n' "$app_color_accent" "$vhkv_label:" "$app_color_reset" "$vhkv_value"
    return 0
}

# ============================================================
# view_item
# Prints one indented detail item.
#
# Version:
#   1.0.0
# ============================================================
view_item() {
    printf '    %s-%s %s\n' "$app_color_dim" "$app_color_reset" "$1"
    return 0
}

# ============================================================
# usage
# Prints command usage.
#
# Version:
#   1.0.0
# ============================================================
usage() {
    cat <<'EOF'
view_harmonized_host.sh - render a cross-domain Host Inventory for Proxmox map

Usage:
  sudo ./view_harmonized_host.sh
  ./view_harmonized_host.sh --file host-map.json
  ./view_harmonized_host.sh --from-run host-inventory-YYYYMMDD-HHMMSS

Modes:
  Live (default)
    With no --file or --from-run, run the complete collector suite into
    private temporary state, harmonize it, render the host view, then clean up.

  Replay
    --from-run DIR
    Harmonize a saved run_all.sh directory. Common test result wrappers
    containing inventory/ or fixture/ are resolved automatically.

  Existing host-map
    --file FILE
    Render a previously generated host-map JSON file.

Options:
  --file FILE        Render an existing harmonized host-map JSON file.
  --from-run DIR     Harmonize saved collector JSON, then render it.
  --allow-partial    Permit missing collectors in live/replay harmonization.
  --install-missing Let live preparation install missing diagnostic packages.
  --no-install      Never offer dependency installation.
  --skip-prepare    Skip prepare_host.sh during default live collection.
  --color           Force ANSI color.
  --no-color        Disable ANSI color.
  --help            Show help.
  --version         Show version.

Live collection progress is written to stderr. The final harmonized view is
written to stdout, so redirection keeps the report clean.

This view is descriptive only. It intentionally does not emit tuning
PASS/WARN/FAIL judgments.
EOF
    return 0
}

# ============================================================
# parse_options
# Parses view options.
#
# Version:
#   1.0.0
# ============================================================
parse_options() {
    vhp_action=run
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --file)
                shift
                [ "$#" -gt 0 ] || { message error "ERROR: --file requires a host-map JSON file."; return 2; }
                app_file=$1
                ;;
            --from-run)
                shift
                [ "$#" -gt 0 ] || { message error "ERROR: --from-run requires a directory."; return 2; }
                app_from_run=$1
                ;;
            --allow-partial) app_allow_partial=1 ;;
            --install-missing) app_install_mode=always ;;
            --no-install) app_install_mode=never ;;
            --skip-prepare) app_skip_prepare=1 ;;
            --color) app_color_mode=always ;;
            --no-color) app_color_mode=never ;;
            --help|-h|-\?|/h|/\?) vhp_action=help ;;
            --version) vhp_action=version ;;
            *) message error "ERROR: Unknown argument: $1"; return 2 ;;
        esac
        shift
    done
    return 0
}

# ============================================================
# ensure_jq
# Ensures jq is available, optionally installing it through apt.
#
# Version:
#   1.0.0
# ============================================================
ensure_jq() {
    command -v jq >/dev/null 2>&1 && return 0
    vhj_install=0
    case "$app_install_mode" in
        always) vhj_install=1 ;;
        never) vhj_install=0 ;;
        ask)
            if [ -r /dev/tty ]; then
                printf 'jq is required. Install package jq now? [y/N] ' >/dev/tty
                IFS= read -r vhj_answer </dev/tty || vhj_answer=
                case "$vhj_answer" in y|Y|yes|YES|Yes) vhj_install=1 ;; esac
            fi
            ;;
    esac
    [ "$vhj_install" -eq 1 ] || { message error "ERROR: jq is required."; return 2; }
    command -v apt-get >/dev/null 2>&1 || { message error "ERROR: apt-get is unavailable."; return 2; }
    if [ "$(id -u 2>/dev/null)" = 0 ]; then apt-get install -y jq
    elif command -v sudo >/dev/null 2>&1; then sudo apt-get install -y jq
    else message error "ERROR: Installing jq requires root or sudo."; return 2
    fi
    command -v jq >/dev/null 2>&1 || return 2
}


# ============================================================
# resolve_run_directory
# Resolves a direct collection directory or common test wrapper.
#
# Version:
#   1.0.0
#
# Output:
#   vhr_resolved_dir
#
# Returns:
#   0 on success
#   2 when no collector set is found
# ============================================================
resolve_run_directory() {
    vhr_input=$1
    [ -d "$vhr_input" ] || { message error "ERROR: Run directory does not exist: $vhr_input"; return 2; }
    vhr_input=$(CDPATH= cd -- "$vhr_input" 2>/dev/null && pwd -P) || return 2

    if [ -r "$vhr_input/collect_platform.json" ]; then
        vhr_resolved_dir=$vhr_input
        return 0
    fi
    if [ -r "$vhr_input/inventory/collect_platform.json" ]; then
        vhr_resolved_dir=$vhr_input/inventory
        message note "Resolved collection directory: $vhr_resolved_dir"
        return 0
    fi
    if [ -r "$vhr_input/fixture/collect_platform.json" ]; then
        vhr_resolved_dir=$vhr_input/fixture
        message note "Resolved collection directory: $vhr_resolved_dir"
        return 0
    fi

    message error "ERROR: No collector set found in: $vhr_input"
    message error "       Expected collect_platform.json, inventory/collect_platform.json,"
    message error "       or fixture/collect_platform.json."
    return 2
}

# ============================================================
# run_harmonizer
# Invokes sibling harmonize_host.sh with current policy.
#
# Version:
#   1.0.0
#
# Usage:
#   run_harmonizer runDir outputFile
#
# Returns:
#   harmonize_host.sh return code
# ============================================================
run_harmonizer() {
    vrh_run_dir=$1
    vrh_output=$2
    vrh_harmonizer=$app_script_dir/harmonize_host.sh
    [ -x "$vrh_harmonizer" ] || { message error "ERROR: Missing sibling harmonize_host.sh."; return 2; }

    [ -n "${vhi_source_kind-}" ] || vhi_source_kind=saved-run
    case "$app_install_mode:$app_allow_partial" in
        always:1) "$vrh_harmonizer" --from-run "$vrh_run_dir" --output "$vrh_output" --source-kind "$vhi_source_kind" --allow-partial --install-missing --no-color ;;
        always:0) "$vrh_harmonizer" --from-run "$vrh_run_dir" --output "$vrh_output" --source-kind "$vhi_source_kind" --install-missing --no-color ;;
        never:1) "$vrh_harmonizer" --from-run "$vrh_run_dir" --output "$vrh_output" --source-kind "$vhi_source_kind" --allow-partial --no-install --no-color ;;
        never:0) "$vrh_harmonizer" --from-run "$vrh_run_dir" --output "$vrh_output" --source-kind "$vhi_source_kind" --no-install --no-color ;;
        ask:1) "$vrh_harmonizer" --from-run "$vrh_run_dir" --output "$vrh_output" --source-kind "$vhi_source_kind" --allow-partial --no-color ;;
        *) "$vrh_harmonizer" --from-run "$vrh_run_dir" --output "$vrh_output" --source-kind "$vhi_source_kind" --no-color ;;
    esac
}

# ============================================================
# collect_live_run
# Runs the complete collector suite into private temporary state.
#
# Version:
#   1.0.0
#
# Output:
#   vlr_run_dir
#
# Returns:
#   run_all.sh return code, except rc=1 is accepted with --allow-partial
# ============================================================
collect_live_run() {
    vlr_runner=$app_script_dir/run_all.sh
    [ -x "$vlr_runner" ] || { message error "ERROR: Live mode requires sibling run_all.sh."; return 2; }

    [ -n "$app_temp_dir" ] || {
        app_temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/hfip-harmonized-view.XXXXXX") || return 2
    }
    vlr_run_dir=$app_temp_dir/inventory

    message note "No saved run supplied; collecting a fresh host inventory..."

    vlr_install=
    case "$app_install_mode" in
        always) vlr_install=--install-missing ;;
        never) vlr_install=--no-install ;;
    esac
    vlr_prepare=
    [ "$app_skip_prepare" -eq 1 ] && vlr_prepare=--skip-prepare
    vlr_color=
    case "$app_color_mode" in
        always) vlr_color=--color ;;
        never) vlr_color=--no-color ;;
    esac

    # run_all.sh writes normal orchestration messages to stdout; send those
    # messages to stderr so this command's stdout remains the final view only.
    if [ -n "$vlr_install" ] && [ -n "$vlr_prepare" ] && [ -n "$vlr_color" ]; then
        "$vlr_runner" --output "$vlr_run_dir" "$vlr_install" "$vlr_prepare" "$vlr_color" 1>&2
    elif [ -n "$vlr_install" ] && [ -n "$vlr_prepare" ]; then
        "$vlr_runner" --output "$vlr_run_dir" "$vlr_install" "$vlr_prepare" 1>&2
    elif [ -n "$vlr_install" ] && [ -n "$vlr_color" ]; then
        "$vlr_runner" --output "$vlr_run_dir" "$vlr_install" "$vlr_color" 1>&2
    elif [ -n "$vlr_prepare" ] && [ -n "$vlr_color" ]; then
        "$vlr_runner" --output "$vlr_run_dir" "$vlr_prepare" "$vlr_color" 1>&2
    elif [ -n "$vlr_install" ]; then
        "$vlr_runner" --output "$vlr_run_dir" "$vlr_install" 1>&2
    elif [ -n "$vlr_prepare" ]; then
        "$vlr_runner" --output "$vlr_run_dir" "$vlr_prepare" 1>&2
    elif [ -n "$vlr_color" ]; then
        "$vlr_runner" --output "$vlr_run_dir" "$vlr_color" 1>&2
    else
        "$vlr_runner" --output "$vlr_run_dir" 1>&2
    fi
    vlr_rc=$?

    if [ "$vlr_rc" -eq 0 ]; then
        return 0
    fi
    if [ "$vlr_rc" -eq 1 ] && [ "$app_allow_partial" -eq 1 ]; then
        message note "Collector suite reported partial failures; continuing because --allow-partial was requested."
        return 0
    fi
    return "$vlr_rc"
}

# ============================================================
# resolve_input
# Resolves --file or invokes harmonize_host.sh for --from-run.
#
# Version:
#   1.0.0
# ============================================================
resolve_input() {
    if [ -n "$app_file" ] && [ -n "$app_from_run" ]; then
        message error "ERROR: Use either --file or --from-run, not both."
        return 2
    fi

    if [ -n "$app_file" ]; then
        ensure_jq || return $?
        [ -r "$app_file" ] || { message error "ERROR: Host-map file is not readable: $app_file"; return 2; }
        vhi_file=$app_file
    else
        [ -n "$app_temp_dir" ] || {
            app_temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/hfip-harmonized-view.XXXXXX") || return 2
        }
        vhi_file=$app_temp_dir/host-map.json

        if [ -n "$app_from_run" ]; then
            resolve_run_directory "$app_from_run" || return $?
            vhi_run_dir=$vhr_resolved_dir
            vhi_source_kind=saved-run
        else
            collect_live_run || return $?
            vhi_run_dir=$vlr_run_dir
            vhi_source_kind=live-ephemeral
        fi

        run_harmonizer "$vhi_run_dir" "$vhi_file" || return $?
        ensure_jq || return $?
    fi

    jq -e '.schema_version=="0.8.9" and .model=="host-map"' "$vhi_file" >/dev/null 2>&1 ||
        { message error "ERROR: Not a Host Inventory for Proxmox host-map v0.8.9 file."; return 2; }
    return 0
}

# ============================================================
# render_view
# Renders the harmonized host map.
#
# Version:
#   1.0.0
# ============================================================
render_view() {
    rv_file=$1
    rv_host=$(jq -r '.source.hostname // "unknown"' "$rv_file")
    rv_source=$(jq -r '.source.directory // "ephemeral / cleaned after rendering"' "$rv_file")
    rv_source_kind=$(jq -r '.source.kind // "unknown"' "$rv_file")
    rv_generated=$(jq -r '.generated_at // "unknown"' "$rv_file")
    rv_window=$(jq -r '[.source.collection_window.start,.source.collection_window.end] | map(select(.!=null and .!="")) | join(" -> ")' "$rv_file")

    view_divider
    printf '%sHarmonized Host View%s\n' "$app_color_title" "$app_color_reset"
    view_divider
    view_kv "Host" "$rv_host"
    view_kv "Generated" "$rv_generated"
    view_kv "Collection window" "$rv_window"
    view_kv "Source kind" "$rv_source_kind"
    view_kv "Source directory" "$rv_source"
    view_kv "Collector model" "$(jq -r '.source.collector_schema_versions|join(", ")' "$rv_file")"
    view_kv "Policy evaluation" "not performed"

    view_section "Input validation"
    view_kv "Strict model" "$(jq -r '.validation.strict|tostring' "$rv_file")"
    view_kv "Hostname consistent" "$(jq -r '.validation.hostname_consistent|tostring' "$rv_file")"
    view_kv "Collectors present" "$(jq -r '.validation.present_collectors|length' "$rv_file") / $(jq -r '.validation.expected_collectors|length' "$rv_file")"
    rv_missing=$(jq -r '.validation.missing_collectors|join(", ")' "$rv_file")
    view_kv "Missing collectors" "${rv_missing:-none}"
    view_kv "Manifest failures" "$(jq -r '.validation.manifest_failure_count // "unknown"' "$rv_file")"
    printf '%s  Collector timestamps%s\n' "$app_color_detail" "$app_color_reset"
    for rv_collector in cpu-topology cpu-firmware-ras virtualization-stack irqs irq-activity pcie-iommu pcie-advanced storage storage-health-power network network-advanced proxmox-host thermal-power runtime-pressure; do
        rv_collected=$(jq -r --arg c "$rv_collector" '.source.collector_provenance[]? | select(.collector==$c) | .collected_at // "unknown"' "$rv_file" | sed -n '1p')
        [ -n "$rv_collected" ] && view_item "$rv_collector = $rv_collected"
    done

    view_section "CPU topology / isolation / IRQ placement"
    view_kv "Logical CPUs" "$(jq -r '.cpu.logical_cpu_count' "$rv_file")"
    view_kv "Physical cores" "$(jq -r '.cpu.physical_core_count' "$rv_file")"
    view_kv "Packages / NUMA" "$(jq -r '(.cpu.package_count|tostring)+" / "+(.cpu.numa_nodes|length|tostring)' "$rv_file")"
    view_kv "Online CPUs" "$(jq -r '.cpu.online.raw // "unknown"' "$rv_file")"
    view_kv "SMT" "$(jq -r '(.cpu.smt.active // "unknown")+" / control="+(.cpu.smt.control // "unknown")' "$rv_file")"
    view_kv "Isolated CPUs" "$(jq -r '.cpu.isolation.isolated.raw // "none"' "$rv_file")"
    view_kv "nohz_full" "$(jq -r '.cpu.isolation.nohz_full.raw // "none"' "$rv_file")"
    view_kv "RCU nocb" "$(jq -r '.cpu.isolation.rcu_nocb.raw // "none"' "$rv_file")"
    view_kv "cgroup effective CPUs" "$(jq -r '.cpu.isolation.cgroup_root.effective_cpus // "unknown"' "$rv_file")"
    view_kv "Scaling driver" "$(jq -r '.cpu.power.scaling_drivers|join(", ")' "$rv_file")"
    view_kv "Governor" "$(jq -r '.cpu.power.governors|join(", ")' "$rv_file")"
    view_kv "Idle driver/governor" "$(jq -r '(.cpu.power.idle_driver//"unknown")+" / "+(.cpu.power.idle_governor//"unknown")' "$rv_file")"

    printf '%s  Physical core map%s\n' "$app_color_detail" "$app_color_reset"
    jq -r '.cpu.cores[] | [(.package_id//"?"),(.core_id//"?"),(.node//"?"),(.cpus|map(tostring)|join(",")),(.core_type//"unknown")] | @tsv' "$rv_file" |
    while IFS="$(printf '\t')" read -r rv_pkg rv_core rv_node rv_cpus rv_type; do
        view_item "package=$rv_pkg core=$rv_core CPUs=$rv_cpus node=$rv_node core_type=$rv_type"
    done

    printf '%s  Effective IRQ distribution%s\n' "$app_color_detail" "$app_color_reset"
    jq -r '.cpu.irq_distribution[] | [.effective_cpus,(.count|tostring)] | @tsv' "$rv_file" |
    while IFS="$(printf '\t')" read -r rv_cpus rv_count; do
        view_item "CPUs=$rv_cpus -> $rv_count IRQ(s)"
    done

    printf '%s  Global workqueue masks%s\n' "$app_color_detail" "$app_color_reset"
    jq -r '.cpu.isolation.workqueues | group_by(.mask)[] | [(.[0].mask//"not-exposed"),(length|tostring),(map(.name)|join(", "))] | @tsv' "$rv_file" |
    while IFS="$(printf '\t')" read -r rv_mask rv_count rv_names; do
        view_item "mask=$rv_mask ($rv_count): $rv_names"
    done

    view_section "CPU firmware / microcode / RAS"
    view_kv "Loaded microcode versions" "$(jq -r '[.cpu.firmware_ras.per_cpu[]?.microcode_version // empty]|unique|join(", ")|if .=="" then "not-exposed" else . end' "$rv_file")"
    view_kv "Kernel vulnerability files" "$(jq -r '.cpu.firmware_ras.vulnerabilities|length' "$rv_file")"
    view_kv "EDAC evidence fields" "$(jq -r '.cpu.firmware_ras.edac|length' "$rv_file")"
    view_kv "Machine-check records" "$(jq -r '.cpu.firmware_ras.machinecheck|length' "$rv_file")"

    view_section "Platform architecture / firmware settings"
    view_kv "ACPI tables" "$(jq -r '.platform_architecture.acpi_tables|length' "$rv_file")"
    view_kv "IOMMU firmware table" "$(jq -r '[.platform_architecture.acpi_tables[]?.name]|if index("IVRS") then "IVRS" elif index("DMAR") then "DMAR" else "not observed" end' "$rv_file")"
    view_kv "Firmware attribute files" "$(jq -r '.firmware_settings.firmware_attributes|length' "$rv_file")"
    view_kv "fwupd BIOS settings rc" "$(jq -r '.firmware_settings.fwupd_bios_settings.rc // "unavailable"' "$rv_file")"

    view_section "Passive IRQ / scheduler pressure"
    view_kv "IRQ activity sample" "$(jq -r '.irq_activity.sample_seconds // "unavailable"' "$rv_file") seconds"
    jq -r '.irq_activity.irqs[0:10][]?|[.irq,.total_delta,.source]|@tsv' "$rv_file" |
    while IFS="$(printf '\t')" read -r rv_irq rv_delta rv_source; do view_item "IRQ $rv_irq delta=$rv_delta source=$rv_source"; done
    view_kv "CPU PSI" "$(jq -r '.runtime_pressure.pressure.cpu.t1 // "not-exposed"' "$rv_file")"
    view_kv "Context-switch delta" "$(jq -r '.runtime_pressure.deltas.context_switches // "unavailable"' "$rv_file")"

    view_section "Timers / watchdogs"
    view_kv "Clocksource" "$(jq -r '.cpu.timers_watchdogs.clocksource.current // "unknown"' "$rv_file")"
    view_kv "Available clocks" "$(jq -r '.cpu.timers_watchdogs.clocksource.available // "unknown"' "$rv_file")"
    view_kv "NMI watchdog" "$(jq -r '.cpu.timers_watchdogs.watchdog.nmi_watchdog // "not-exposed"' "$rv_file")"
    view_kv "Watchdog CPU mask" "$(jq -r '.cpu.timers_watchdogs.watchdog.watchdog_cpumask // "not-exposed"' "$rv_file")"

    view_section "KVM / virtualization stack"
    view_kv "/dev/kvm" "$(jq -r 'if .virtualization_stack.kvm_device.exists==true then "present mode="+(.virtualization_stack.kvm_device.mode//"?") else "absent/not-observed" end' "$rv_file")"
    view_kv "CPU virtualization flags" "$(jq -r '(.virtualization_stack.cpu_virtualization_flags // []) | join(", ") | if .=="" then "none observed" else . end' "$rv_file")"
    view_kv "io_uring disabled" "$(jq -r '.virtualization_stack.io_uring.disabled // "not-exposed"' "$rv_file")"
    view_kv "io_uring group" "$(jq -r '.virtualization_stack.io_uring.group // "not-exposed"' "$rv_file")"
    view_kv "KVM debugfs" "$(jq -r 'if .virtualization_stack.debugfs_kvm.present==true then "present files="+((.virtualization_stack.debugfs_kvm.top_level_file_count//0)|tostring) elif .virtualization_stack.debugfs_kvm.present==false then "not-present" else "unknown" end' "$rv_file")"
    printf '%s  Loaded virtualization modules%s\n' "$app_color_detail" "$app_color_reset"
    jq -r '.virtualization_stack.module_parameters[]? | select(.loaded==true) | [.module,((.parameters|to_entries|length)|tostring)] | @tsv' "$rv_file" |
    while IFS="$(printf '\t')" read -r rv_vmod rv_vparams; do
        view_item "$rv_vmod parameters=$rv_vparams"
    done
    view_kv "QEMU userspace" "$(jq -r 'if .virtualization_stack.raw.qemu_system.available==true then ((.virtualization_stack.raw.qemu_system.stdout//"")|split("\n")[0]) else "unavailable" end' "$rv_file")"

    view_section "GPU / VFIO / PCIe"
    rv_gpu_count=$(jq -r '.gpu.devices|length' "$rv_file")
    view_kv "GPU devices" "$rv_gpu_count"
    view_kv "vfio-pci loaded" "$(jq -r '.gpu.vfio.module_loaded|tostring' "$rv_file")"
    jq -r '.gpu.devices[] | [.bdf,.vendor,.device,(.driver//"unbound"),(.iommu_group//"none"),(.pci.current_link_speed//"n/a"),(.pci.current_link_width//"n/a"),(.pci.max_link_speed//"n/a"),(.pci.max_link_width//"n/a"),(.boot_vga//"?"),(.irq_correlation.method//"none"),(.irq_correlation.matches|length|tostring)] | @tsv' "$rv_file" |
    while IFS="$(printf '\t')" read -r rv_bdf rv_vendor rv_device rv_driver rv_group rv_cur rv_cw rv_max rv_mw rv_boot rv_method rv_irqcount; do
        printf '%s  GPU %s%s\n' "$app_color_detail" "$rv_bdf" "$app_color_reset"
        view_item "PCI ID=$rv_vendor:$rv_device driver=$rv_driver IOMMU-group=$rv_group boot_vga=$rv_boot"
        view_item "link=$rv_cur x$rv_cw (max $rv_max x$rv_mw)"
        rv_pcie_adv=$(jq -r --arg bdf "$rv_bdf" '.gpu.devices[]|select(.bdf==$bdf)|.pci.advanced|[(.local_cpulist//"n/a"),(.d3cold_allowed//"n/a"),(.power.runtime_status//"n/a"),(.reset.methods//"n/a")]|@tsv' "$rv_file")
        if [ -n "$rv_pcie_adv" ]; then
            IFS="$(printf '\t')" read -r rv_local rv_d3 rv_runtime rv_reset <<EOF
$rv_pcie_adv
EOF
            view_item "advanced localCPUs=$rv_local d3cold=$rv_d3 runtime-power=$rv_runtime reset=$rv_reset"
        fi
        rv_configured_msi=$(jq -r --arg bdf "$rv_bdf" '.gpu.devices[] | select(.bdf==$bdf) | (.irq_correlation.configured_vectors//[])|length' "$rv_file")
        view_item "IRQ correlation=$rv_method observed-vectors=$rv_irqcount configured-MSI-vectors=$rv_configured_msi"
        jq -r --arg bdf "$rv_bdf" '.gpu.devices[] | select(.bdf==$bdf) | .irq_correlation.matches[]? | [.irq,(.effective_affinity_list//"none"),(.source//"unknown")] | @tsv' "$rv_file" |
        while IFS="$(printf '\t')" read -r rv_irq rv_cpu rv_source_name; do
            view_item "IRQ $rv_irq -> effective CPUs=$rv_cpu source=$rv_source_name"
        done
        jq -r --arg bdf "$rv_bdf" '.gpu.devices[] | select(.bdf==$bdf) | .slot_functions[]? | [.bdf,.class,(.driver//"unbound")] | @tsv' "$rv_file" |
        while IFS="$(printf '\t')" read -r rv_fbdf rv_class rv_fdriver; do
            view_item "function $rv_fbdf class=$rv_class driver=$rv_fdriver"
        done
    done

    view_section "Storage path / PCI / IRQ"
    jq -r '.storage.nvme_controllers[] | [.controller,.model,.bdf,(.pci.iommu_group//"none"),(.pci.current_link_speed//"n/a"),(.pci.current_link_width//"n/a"),(.pci.max_link_speed//"n/a"),(.pci.max_link_width//"n/a"),(.irq_correlation.matches|length|tostring)] | @tsv' "$rv_file" |
    while IFS="$(printf '\t')" read -r rv_ctrl rv_model rv_bdf rv_group rv_cur rv_cw rv_max rv_mw rv_count; do
        printf '%s  NVMe %s%s\n' "$app_color_detail" "$rv_ctrl" "$app_color_reset"
        view_item "$rv_model BDF=$rv_bdf IOMMU-group=$rv_group"
        view_item "link=$rv_cur x$rv_cw (max $rv_max x$rv_mw)"
        rv_irq_summary=$(jq -r --arg ctrl "$rv_ctrl" '.storage.nvme_controllers[] | select(.controller==$ctrl) | [.irq_correlation.matches[]? | ((.irq|tostring)+"->CPU"+(.effective_affinity_list//"?"))] | join(", ")' "$rv_file")
        view_item "IRQs ($rv_count): ${rv_irq_summary:-none}"
        rv_nvhealth=$(jq -r --arg ctrl "$rv_ctrl" '.storage.nvme_controllers[]|select(.controller==$ctrl)|.health_power|[(.smart_log.rc//"unavailable"|tostring),(.features.apst.rc//"unavailable"|tostring),(.features.interrupt_coalescing.rc//"unavailable"|tostring)]|@tsv' "$rv_file")
        if [ -n "$rv_nvhealth" ]; then
            IFS="$(printf '\t')" read -r rv_smart rv_apst rv_coal <<EOF
$rv_nvhealth
EOF
            view_item "health smart-rc=$rv_smart APST-rc=$rv_apst interrupt-coalescing-rc=$rv_coal"
        fi
    done

    printf '%s  Proxmox storage backing%s\n' "$app_color_detail" "$app_color_reset"
    jq -r '.storage.pve_storages[] | [.name,.type,(.status.status//"unknown"),(.status.percent//"?"),(.backing.vg//"none"),(.backing.thinpool//"none"),(.backing.base_block//"unknown"),(.backing.pci_bdf//"none"),(.backing.pci_correlation_method//"none")] | @tsv' "$rv_file" |
    while IFS="$(printf '\t')" read -r rv_name rv_type rv_status rv_pct rv_vg rv_pool rv_block rv_bdf rv_method; do
        view_item "$rv_name type=$rv_type status=$rv_status used=$rv_pct backing=$rv_block BDF=$rv_bdf method=$rv_method vg=$rv_vg pool=$rv_pool"
    done

    view_section "Network path / bridge / IRQ"
    jq -r '.network.physical_interfaces[] | [.name,.operstate,.driver,.bdf,(.pci.iommu_group//"none"),(.pci.current_link_speed//"n/a"),(.pci.current_link_width//"n/a"),(.irq_correlation.matches|length|tostring)] | @tsv' "$rv_file" |
    while IFS="$(printf '\t')" read -r rv_if rv_state rv_driver rv_bdf rv_group rv_speed rv_width rv_irqcount; do
        printf '%s  Interface %s%s\n' "$app_color_detail" "$rv_if" "$app_color_reset"
        view_item "state=$rv_state driver=$rv_driver BDF=$rv_bdf group=$rv_group link=$rv_speed x$rv_width"
        rv_irq_summary=$(jq -r --arg name "$rv_if" '.network.physical_interfaces[] | select(.name==$name) | [.irq_correlation.matches[]? | ((.irq|tostring)+"->CPU"+(.effective_affinity_list//"?")+"("+(.source//"?")+")")] | join(", ")' "$rv_file")
        view_item "IRQs ($rv_irqcount): ${rv_irq_summary:-none}"
        rv_rps=$(jq -r --arg name "$rv_if" '.network.physical_interfaces[] | select(.name==$name) | [.queues[]? | select(.values.rps_cpus? != null) | (.queue+"="+.values.rps_cpus)] | join(", ")' "$rv_file")
        rv_xps=$(jq -r --arg name "$rv_if" '.network.physical_interfaces[] | select(.name==$name) | [.queues[]? | select(.values.xps_cpus? != null) | (.queue+"="+.values.xps_cpus)] | join(", ")' "$rv_file")
        view_item "RPS=${rv_rps:-not-exposed} XPS=${rv_xps:-not-exposed}"
        rv_netadv=$(jq -r --arg name "$rv_if" '.network.physical_interfaces[]|select(.name==$name)|.advanced|[(.rss.rc//"unavailable"|tostring),(.eee.rc//"unavailable"|tostring),(.pause.rc//"unavailable"|tostring),(.statistics.rc//"unavailable"|tostring)]|@tsv' "$rv_file")
        if [ -n "$rv_netadv" ]; then
            IFS="$(printf '\t')" read -r rv_rss rv_eee rv_pause rv_stats <<EOF
$rv_netadv
EOF
            view_item "advanced RSS-rc=$rv_rss EEE-rc=$rv_eee pause-rc=$rv_pause stats-rc=$rv_stats"
        fi
    done

    printf '%s  Linux bridges / configured vs runtime attachment%s\n' "$app_color_detail" "$app_color_reset"
    jq -r '.network.bridges[] | [.name,(.ports|join(",")),(.configured_vm_guests|length|tostring),(.running_vm_guests|length|tostring),([.running_vm_guests[]? | (.vmid+":"+(.name//"unnamed"))]|join(", ")),(.configured_lxc_guests|length|tostring),(.running_lxc_guests|length|tostring),([.running_lxc_guests[]? | (.vmid+":"+(.name//"unnamed"))]|join(", "))] | @tsv' "$rv_file" |
    while IFS="$(printf '\t')" read -r rv_bridge rv_ports rv_vm_cfg rv_vm_run rv_vms rv_ct_cfg rv_ct_run rv_cts; do
        view_item "$rv_bridge ports=$rv_ports VMs configured=$rv_vm_cfg running=$rv_vm_run ${rv_vms:+[$rv_vms]}"
        view_item "$rv_bridge LXCs configured=$rv_ct_cfg running=$rv_ct_run ${rv_cts:+[$rv_cts]}"
    done

    view_section "Memory / VM memory model"
    view_kv "THP selected" "$(jq -r '.memory.transparent_hugepages.enabled_selected // "unknown"' "$rv_file")"
    view_kv "THP defrag selected" "$(jq -r '.memory.transparent_hugepages.defrag_selected // "unknown"' "$rv_file")"
    view_kv "KSM run" "$(jq -r '.memory.ksm.run // "unknown"' "$rv_file")"
    view_kv "KSM pages sharing" "$(jq -r '.memory.ksm.pages_sharing // "unknown"' "$rv_file")"
    view_kv "Swap active" "$(jq -r '.memory.swap.active|tostring' "$rv_file")"
    view_kv "Swappiness" "$(jq -r '.memory.swap.swappiness // "unknown"' "$rv_file")"
    view_kv "zswap enabled" "$(jq -r '.memory.zswap.enabled // "unknown"' "$rv_file")"
    printf '%s  HugeTLB pools%s\n' "$app_color_detail" "$app_color_reset"
    jq -r '.memory.hugetlb[] | [.size,(.values.nr_hugepages//"?"),(.values.free_hugepages//"?")] | @tsv' "$rv_file" |
    while IFS="$(printf '\t')" read -r rv_size rv_total rv_free; do
        view_item "$rv_size total=$rv_total free=$rv_free"
    done

    view_section "Memory hardware / EDAC"
    view_kv "EDAC controllers" "$(jq -r '.memory.hardware.edac_controllers|length' "$rv_file")"
    view_kv "dmidecode memory rc" "$(jq -r '.memory.hardware.dmidecode_memory.rc // "unavailable"' "$rv_file")"
    view_kv "decode-dimms rc" "$(jq -r '.memory.hardware.decode_dimms.rc // "unavailable"' "$rv_file")"

    view_section "USB / input / audio topology"
    view_kv "USB devices" "$(jq -r '.peripherals.usb_devices|length' "$rv_file")"
    view_kv "Input events" "$(jq -r '.peripherals.input_devices|length' "$rv_file")"
    view_kv "ALSA cards" "$(jq -r '.peripherals.sound_cards|length' "$rv_file")"
    view_kv "PCM devices" "$(jq -r '(.peripherals.pcm_devices//[])|length' "$rv_file")"
    jq -r '.peripherals.usb_devices[]?|select(.pci_ancestor!=null)|[.sysfs,(.product//"unknown"),.pci_ancestor]|@tsv' "$rv_file" | head -15 |
    while IFS="$(printf '\t')" read -r rv_usb rv_product rv_bdf; do view_item "$rv_usb $rv_product -> $rv_bdf"; done

    view_section "Final host-side latency audit domains"
    view_kv "Kernel event observations" "$(jq -r '.kernel_events.total_observations // 0' "$rv_file")"
    view_kv "Guest runtime-detail VMs" "$(jq -r '.guest_runtime_detail.qemu_count // 0' "$rv_file")"
    view_kv "Kernel housekeeping threads" "$(jq -r '.kernel_housekeeping.thread_count // 0' "$rv_file")"
    view_kv "PM-QoS device records" "$(jq -r '.pm_qos.devices|length // 0' "$rv_file")"
    view_kv "Desktop I/O USB devices" "$(jq -r '.desktop_io_path.usb|length // 0' "$rv_file")"
    view_kv "Passive sample duration" "$(jq -r '(.latency_sample.sample.duration_seconds // 0|tostring)+" seconds"' "$rv_file")"
    jq -r '.kernel_events.counts_by_severity // {} | to_entries[]? | "kernel-event severity \(.key)=\(.value)"' "$rv_file" |
      while IFS= read -r rv_line; do view_item "$rv_line"; done
    jq -r '.latency_sample.softirq_deltas // [] | sort_by(.total_delta)|reverse|.[0:5][]? |
      "sample softirq \(.name)=\(.total_delta)"' "$rv_file" |
      while IFS= read -r rv_line; do view_item "$rv_line"; done

    view_section "Depth audit / capabilities / graph"
    view_kv "Topology graph nodes / edges" "$(jq -r '(.topology_graph.nodes|length|tostring)+" / "+(.topology_graph.edges|length|tostring)' "$rv_file")"
    view_kv "Graph source/target integrity" "$(jq -r '((.topology_graph.integrity.all_edge_sources_have_nodes//false)|tostring)+" / "+((.topology_graph.integrity.all_edge_targets_have_nodes//false)|tostring)' "$rv_file")"
    view_kv "resctrl supported / mounted / groups" "$(jq -r '(.capability_matrix.resctrl.supported|tostring)+" / "+(.capability_matrix.resctrl.mounted|tostring)+" / "+((.capability_matrix.resctrl.group_count//0)|tostring)' "$rv_file")"
    view_kv "PMU sources" "$(jq -r '.capability_matrix.pmu.source_count // 0' "$rv_file")"
    view_kv "Frequency-residency CPUs" "$(jq -r '(.capability_matrix.cpu_limits.frequency_residency//[])|length' "$rv_file")"
    view_kv "ReBAR-capability devices" "$(jq -r '.capability_matrix.pcie.rebar_devices|length' "$rv_file")"
    view_kv "ATS / PRI / PASID / TPH devices" "$(jq -r '[(.capability_matrix.pcie.ats_devices|length),(.capability_matrix.pcie.pri_devices|length),(.capability_matrix.pcie.pasid_devices|length),(.capability_matrix.pcie.tph_devices|length)]|map(tostring)|join(" / ")' "$rv_file")"
    view_kv "VRR-capable connectors" "$(jq -r '.capability_matrix.display.vrr_capable_connectors|length' "$rv_file")"
    view_kv "EDID-present connectors" "$(jq -r '(.capability_matrix.display.edid_connectors//[])|length' "$rv_file")"
    view_kv "Memory fragmentation zones" "$(jq -r '.memory_fragmentation.buddy_highest_order|length // 0' "$rv_file")"
    view_kv "IRQ architecture records" "$(jq -r '.irq_architecture.irqs|length // 0' "$rv_file")"
    view_kv "Security mitigation records" "$(jq -r '.security_mitigations.vulnerabilities|length // 0' "$rv_file")"
    view_kv "IOMMU groups" "$(jq -r '.capability_matrix.iommu.group_count // 0' "$rv_file")"
    view_kv "IOMMU interrupt remapping" "$(jq -r '(.capability_matrix.iommu.interrupt_remapping_observed // false)|tostring' "$rv_file")"
    view_kv "IOMMU cmdline args" "$(jq -r '(.capability_matrix.iommu.cmdline_arguments//[])|if length==0 then "none" else join(" ") end' "$rv_file")"
    view_kv "PCIe ACS override" "$(jq -r '.capability_matrix.iommu.acs_override_argument // "none"' "$rv_file")"
    view_kv "VM network path records" "$(jq -r '(.correlations.desktop_network_paths//[])|length' "$rv_file")"
    jq -r '.evidence_catalog[]?|"evidence \(.domain) scope=\(.scope) confidence=\(.confidence)"' "$rv_file" |
      while IFS= read -r rv_line; do view_item "$rv_line"; done

    view_section "Proxmox guests / cross-domain configuration"
    view_kv "Node" "$(jq -r '.proxmox.node // "unknown"' "$rv_file")"
    view_kv "Version" "$(jq -r '.proxmox.version // "unknown"' "$rv_file")"
    view_kv "QEMU configured / running" "$(jq -r '(.proxmox.guest_counts.configured_qemu // (.proxmox.virtual_machines|length)) as $c | (.proxmox.guest_counts.running_qemu // ([.proxmox.virtual_machines[]|select(.status=="running")]|length)) as $r | ($c|tostring)+" / "+($r|tostring)' "$rv_file")"
    view_kv "LXC configured / running" "$(jq -r '(.proxmox.guest_counts.configured_lxc // (.proxmox.containers|length)) as $c | (.proxmox.guest_counts.running_lxc // ([.proxmox.containers[]|select(.status=="running")]|length)) as $r | ($c|tostring)+" / "+($r|tostring)' "$rv_file")"
    view_kv "Runtime capability" "$(jq -r '"lxc-info="+((.proxmox.runtime_capabilities.lxc_info_available//false)|tostring)+" / cgroup-v2="+((.proxmox.runtime_capabilities.cgroup_v2_present//false)|tostring)' "$rv_file")"
    view_kv "Cluster probe" "$(jq -r '(.proxmox.cluster.rc|tostring)+" - "+((.proxmox.cluster.stderr//.proxmox.cluster.stdout//"")|split("\n")|map(select(length>0))|first//"")' "$rv_file")"

    printf '%s  Running QEMU VMs%s\n' "$app_color_detail" "$app_color_reset"
    jq -r '.proxmox.virtual_machines | map(select(.status=="running")) | sort_by((.vmid|tonumber))[] | [.vmid,.name,(.cpu.cores//0|tostring),(.cpu.type//"unknown"),(.cpu.affinity//"none"),(.memory.memory_mib//0|tostring),(.memory.balloon_mib//"none"|tostring),(.memory.hugepages//"none"),(.firmware.bios//"unknown"),(.firmware.machine//"unknown")] | @tsv' "$rv_file" |
    while IFS="$(printf '\t')" read -r rv_vmid rv_name rv_cores rv_cpu rv_aff rv_mem rv_balloon rv_huge rv_bios rv_machine; do
        printf '%s  VM %s %s%s\n' "$app_color_detail" "$rv_vmid" "$rv_name" "$app_color_reset"
        view_item "CPU cores=$rv_cores type=$rv_cpu affinity=$rv_aff"
        view_item "memory=${rv_mem}MiB balloon=$rv_balloon hugepages=$rv_huge"
        view_item "firmware=$rv_bios machine=$rv_machine"
        rv_snapshots=$(jq -r --arg id "$rv_vmid" '.proxmox.virtual_machines[] | select(.vmid==$id) | .config_scope.snapshot_count // 0' "$rv_file")
        view_item "active-config=top-level snapshot-sections=$rv_snapshots"
        rv_runtime=$(jq -r --arg id "$rv_vmid" '.proxmox.virtual_machines[] | select(.vmid==$id) | .runtime | [(.observed|tostring),(.process_cpus_allowed_list//"unknown"),(.process_online_cpus_allowed_list//"none"),(.threads|length|tostring),(.vhost_threads|length|tostring)] | @tsv' "$rv_file")
        IFS="$(printf '\t')" read -r rv_runtime_observed rv_runtime_cpus rv_runtime_online rv_runtime_threads rv_vhost_count <<EOF
$rv_runtime
EOF
        view_item "QEMU runtime observed=$rv_runtime_observed raw-affinity=$rv_runtime_cpus online-effective=$rv_runtime_online threads=$rv_runtime_threads vhost=$rv_vhost_count"
        rv_cgroup=$(jq -r --arg id "$rv_vmid" '.proxmox.virtual_machines[] | select(.vmid==$id) | .runtime.cgroup | [(.path//"unknown"),(.available|tostring),(.type//"unknown"),(.cpuset_interface_state//"unknown"),(.cpuset_cpus_state//"unknown"),(if .cpuset_cpus_state=="empty/inherited" then "inherited" else (.cpuset_cpus//"n/a") end),(.cpuset_cpus_effective_state//"unknown"),(.cpuset_cpus_effective//"n/a"),(.cpuset_cpus_effective_online//"none"),(.cpu_weight_state//"unknown"),(.cpu_weight//"n/a"),(.cpu_max_state//"unknown"),(.cpu_max//"n/a"),((.controller_values//[])|join(","))] | @tsv' "$rv_file")
        IFS="$(printf '\t')" read -r rv_cg_path rv_cg_available rv_cg_type rv_cg_cpif rv_cg_set_state rv_cg_set rv_cg_eff_state rv_cg_eff rv_cg_online rv_cg_weight_state rv_cg_weight rv_cg_max_state rv_cg_max rv_cg_controllers <<EOF
$rv_cgroup
EOF
        view_item "cgroup=$rv_cg_path available=$rv_cg_available type=$rv_cg_type controllers=${rv_cg_controllers:-unknown}"
        view_item "cpuset-interface=$rv_cg_cpif requested-state=$rv_cg_set_state requested=$rv_cg_set effective-state=$rv_cg_eff_state effective=$rv_cg_eff online-effective=$rv_cg_online"
        view_item "cpu.weight-state=$rv_cg_weight_state value=$rv_cg_weight cpu.max-state=$rv_cg_max_state value=$rv_cg_max"
        jq -r --arg id "$rv_vmid" '.proxmox.virtual_machines[] | select(.vmid==$id) | .runtime.affinity_groups[]? | [.role,.cpus_allowed_list,.online_cpus_allowed_list,(.count|tostring)] | @tsv' "$rv_file" |
        while IFS="$(printf '\t')" read -r rv_role rv_cpus rv_online rv_count; do
            view_item "runtime $rv_role raw=$rv_cpus online=$rv_online threads=$rv_count"
        done
        rv_hostpci=$(jq -r --arg id "$rv_vmid" '.proxmox.virtual_machines[] | select(.vmid==$id) | [.hostpci[]? | (.key+"="+(.bdf//.value))] | join(", ")' "$rv_file")
        view_item "hostpci=${rv_hostpci:-none}"
        jq -r --arg id "$rv_vmid" '.proxmox.virtual_machines[] | select(.vmid==$id) | .disks | group_by(.storage)[] | [((.[0].storage//"unknown")),(length|tostring)] | @tsv' "$rv_file" |
        while IFS="$(printf '\t')" read -r rv_storage rv_disk_count; do
            rv_backing=$(jq -r --arg s "$rv_storage" '.storage.pve_storages[]? | select(.name==$s) | ((.backing.base_block//"unknown")+"/BDF="+(.backing.pci_bdf//"none"))' "$rv_file" | sed -n '1p')
            view_item "storage=$rv_storage disk-entries=$rv_disk_count -> ${rv_backing:-unresolved}"
        done
        jq -r --arg id "$rv_vmid" '.proxmox.virtual_machines[] | select(.vmid==$id) | .networks[]? | [.key,(.model//"unknown"),(.bridge//"none")] | @tsv' "$rv_file" |
        while IFS="$(printf '\t')" read -r rv_net rv_model rv_bridge; do
            rv_ports=$(jq -r --arg b "$rv_bridge" '.network.bridges[]? | select(.name==$b) | .ports|join(",")' "$rv_file" | sed -n '1p')
            view_item "$rv_net model=$rv_model bridge=$rv_bridge -> ports=${rv_ports:-unknown}"
        done
    done
    rv_qemu_status_only=$(jq -r '.proxmox.status_only_virtual_machines // [] | length' "$rv_file")
    [ "$rv_qemu_status_only" -eq 0 ] 2>/dev/null || view_item "status-only QEMU records without captured config: $rv_qemu_status_only"

    printf '%s  LXC configuration / runtime attachment%s\n' "$app_color_detail" "$app_color_reset"
    jq -r '.proxmox.containers | sort_by((.vmid|tonumber))[] | [.vmid,.name,.status,(.cpu.cores//"none"|tostring),(.cpu.cpulimit//"none"|tostring),(.cpu.cpuset//"none"),(.memory.memory_mib//"none"|tostring),(.memory.swap_mib//"none"|tostring)] | @tsv' "$rv_file" |
    while IFS="$(printf '\t')" read -r rv_vmid rv_name rv_status rv_cores rv_limit rv_cpuset rv_mem rv_swap; do
        printf '%s  LXC %s %s%s\n' "$app_color_detail" "$rv_vmid" "$rv_name" "$app_color_reset"
        view_item "status=$rv_status cores=$rv_cores cpulimit=$rv_limit cpuset=$rv_cpuset memory=${rv_mem}MiB swap=${rv_swap}MiB"
        rv_lxc_runtime=$(jq -r --arg id "$rv_vmid" '.proxmox.containers[] | select(.vmid==$id) | .runtime | [(.observed|tostring),(.pid//"none"|tostring),(.process_cpus_allowed_list//"unknown"),(.process_online_cpus_allowed_list//"none"),(.cgroup.path//"unknown"),(.cgroup.available|tostring),(.cgroup.type//"unknown"),(.cgroup.cpuset_interface_state//"unknown"),(.cgroup.cpuset_cpus_state//"unknown"),(if .cgroup.cpuset_cpus_state=="empty/inherited" then "inherited" else (.cgroup.cpuset_cpus//"n/a") end),(.cgroup.cpuset_cpus_effective_state//"unknown"),(.cgroup.cpuset_cpus_effective//"n/a"),(.cgroup.cpuset_cpus_effective_online//"none"),(.cgroup.cpu_weight_state//"unknown"),(.cgroup.cpu_weight//"n/a"),(.cgroup.cpu_max_state//"unknown"),(.cgroup.cpu_max//"n/a"),((.cgroup.controller_values//[])|join(","))] | @tsv' "$rv_file")
        IFS="$(printf '\t')" read -r rv_lxc_obs rv_lxc_pid rv_lxc_raw rv_lxc_online rv_lxc_cg rv_lxc_cg_available rv_lxc_cg_type rv_lxc_cpif rv_lxc_set_state rv_lxc_cg_set rv_lxc_eff_state rv_lxc_cg_eff rv_lxc_cg_online rv_lxc_weight_state rv_lxc_weight rv_lxc_max_state rv_lxc_max rv_lxc_controllers <<EOF
$rv_lxc_runtime
EOF
        if [ "$rv_lxc_obs" = true ]; then
            view_item "runtime pid=$rv_lxc_pid raw-affinity=$rv_lxc_raw online-effective=$rv_lxc_online"
            view_item "cgroup=$rv_lxc_cg available=$rv_lxc_cg_available type=$rv_lxc_cg_type controllers=${rv_lxc_controllers:-unknown}"
            view_item "cpuset-interface=$rv_lxc_cpif requested-state=$rv_lxc_set_state requested=$rv_lxc_cg_set effective-state=$rv_lxc_eff_state effective=$rv_lxc_cg_eff online-effective=$rv_lxc_cg_online"
            view_item "cpu.weight-state=$rv_lxc_weight_state value=$rv_lxc_weight cpu.max-state=$rv_lxc_max_state value=$rv_lxc_max"
        fi
        jq -r --arg id "$rv_vmid" '.proxmox.containers[] | select(.vmid==$id) | .networks[]? | [.key,(.name//"unknown"),(.bridge//"none"),(.runtime_interface//"none"),(.runtime_present|tostring)] | @tsv' "$rv_file" |
        while IFS="$(printf '\t')" read -r rv_net rv_netname rv_bridge rv_runtime_if rv_present; do
            view_item "$rv_net name=$rv_netname bridge=$rv_bridge runtime=$rv_runtime_if present=$rv_present"
        done
    done
    rv_status_only=$(jq -r '.proxmox.status_only_containers|length' "$rv_file")
    [ "$rv_status_only" -eq 0 ] 2>/dev/null || view_item "status-only LXC records without captured config: $rv_status_only"

    view_section "Background services"
    for rv_unit in pvestatd.service pvedaemon.service pveproxy.service pvescheduler.service irqbalance.service ksmtuned.service smartmontools.service; do
        rv_state=$(jq -r --arg u "$rv_unit" '.background.important_units[]? | select(.unit==$u) | [(.state.LoadState//"unknown"),(.state.ActiveState//"unknown"),(.state.EffectiveCPUs//""),(.state.AllowedCPUs//"")] | @tsv' "$rv_file" | sed -n '1p')
        [ -n "$rv_state" ] || continue
        IFS="$(printf '\t')" read -r rv_load rv_active rv_effective rv_allowed <<EOF
$rv_state
EOF
        view_item "$rv_unit load=$rv_load active=$rv_active effectiveCPUs=${rv_effective:-not-exposed} allowedCPUs=${rv_allowed:-unrestricted/not-set}"
    done

    view_section "Thermal / power observation"
    jq -r '.thermal_power.hwmon[] | .name as $dev | .values as $v | $v | to_entries[] | select(.key|test("^temp[0-9]+_input$")) | (.key|capture("^temp(?<n>[0-9]+)_input$").n) as $n | [$dev,($v["temp"+$n+"_label"]//("temp"+$n)),(try (((.value|tonumber)/1000)|tostring) catch .value)] | @tsv' "$rv_file" |
    while IFS="$(printf '\t')" read -r rv_dev rv_label rv_temp; do
        view_item "$rv_dev / $rv_label = ${rv_temp} C"
    done
    rv_turbo=$(jq -r '.thermal_power.turbostat_snapshot.stdout // "" | split("\n") | .[0:2] | join(" | ")' "$rv_file")
    [ -n "$rv_turbo" ] && view_item "turbostat: $rv_turbo"

    view_section "Evidence limits / unknowns"
    jq -r '.limitations[]' "$rv_file" |
    while IFS= read -r rv_limit; do
        printf '    %s-%s %s\n' "$app_color_note" "$app_color_reset" "$rv_limit"
    done
    jq -r '.correlations.notes[]' "$rv_file" |
    while IFS= read -r rv_note; do
        printf '    %s-%s %s\n' "$app_color_dim" "$app_color_reset" "$rv_note"
    done
    return 0
}

# ============================================================
# main
# Coordinates dependency/input resolution and rendering.
#
# Version:
#   1.0.0
# ============================================================
main() {
    case "$vhp_action" in
        help) usage; return 0 ;;
        version) printf '%s %s\n' "$app_name" "$app_version"; return 0 ;;
    esac
    resolve_input || return $?
    render_view "$vhi_file"
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
