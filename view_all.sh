#!/bin/sh
# ============================================================
# view_all.sh
# Presents every Host Inventory for Proxmox aspect in one ordered,
# colorized terminal view.
#
# Version:
#   0.9.2
#
# Usage:
#   sudo ./view_all.sh
#   ./view_all.sh --from-run
#   ./view_all.sh --from-run host-inventory-YYYYMMDD-HHMMSS
#
# Output:
#   Human-readable views on stdout.
#   Progress / warnings on stderr.
#
# Returns:
#   0 when all aspect views render successfully
#   1 when one or more aspect views fail
#   2 on invalid arguments, preparation failure, or missing scripts/data
#
# Dependencies:
#   The view_*.sh scripts beside this script.
#   prepare_host.sh for live preparation.
#
# Side Effects:
#   Live mode may install explicitly approved diagnostic packages through
#   prepare_host.sh. Rendering saved data is read-only.
# ============================================================
app_name=view_all
app_version=0.9.2
app_rc=0
app_color_mode=auto
app_install_mode=ask
app_skip_prepare=0
app_from_run=
app_script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || exit 2

app_views="
view_platform.sh
view_firmware_settings.sh
view_acpi_platform.sh
view_security_mitigations.sh
view_boot_kernel.sh
view_cpu_topology.sh
view_cpu_firmware_ras.sh
view_cpu_power_idle.sh
view_cpu_limits_pmu.sh
view_cache_resource_qos.sh
view_timers_watchdogs.sh
view_kernel_events.sh
view_virtualization_stack.sh
view_kernel_housekeeping.sh
view_pm_qos.sh
view_pcie_iommu.sh
view_pcie_advanced.sh
view_irq_architecture.sh
view_gpu_vfio.sh
view_isolation_scheduler.sh
view_memory.sh
view_memory_hardware.sh
view_memory_fragmentation.sh
view_irqs.sh
view_irq_activity.sh
view_runtime_pressure.sh
view_latency_sample.sh
view_storage.sh
view_storage_health_power.sh
view_network.sh
view_network_advanced.sh
view_usb_input_audio.sh
view_desktop_io_path.sh
view_display_timing.sh
view_services_background.sh
view_thermal_power.sh
view_proxmox_host.sh
view_guest_runtime_detail.sh
"
app_view_count=$(printf '%s\n' "$app_views" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')

# ============================================================
# color_init
# Defines semantic ANSI colors for view_all presentation.
#
# Version:
#   1.0.0
#
# Returns:
#   0
# ============================================================
color_init() {
    va_enable=0
    [ -n "${NO_COLOR-}" ] && app_color_mode=never
    case "$app_color_mode" in
        always) va_enable=1 ;;
        never) va_enable=0 ;;
        auto) [ -t 1 ] || [ -t 2 ] && va_enable=1 ;;
        *) app_color_mode=auto; [ -t 1 ] || [ -t 2 ] && va_enable=1 ;;
    esac
    if [ "$va_enable" -eq 1 ]; then
        app_color_reset=$(printf '\033[0m')
        app_color_title=$(printf '\033[1;96m')
        app_color_info=$(printf '\033[96m')
        app_color_ok=$(printf '\033[92m')
        app_color_warn=$(printf '\033[93m')
        app_color_error=$(printf '\033[91m')
        app_color_dim=$(printf '\033[90m')
    else
        app_color_reset=; app_color_title=; app_color_info=; app_color_ok=; app_color_warn=; app_color_error=; app_color_dim=
    fi
    return 0
}

# ============================================================
# message
# Prints one semantic progress message to stderr.
#
# Version:
#   1.0.0
#
# Usage:
#   message role text
#
# Returns:
#   0
# ============================================================
message() {
    vam_role=$1
    shift
    case "$vam_role" in
        title) vam_color=$app_color_title ;;
        info) vam_color=$app_color_info ;;
        ok) vam_color=$app_color_ok ;;
        warn) vam_color=$app_color_warn ;;
        error) vam_color=$app_color_error ;;
        *) vam_color=$app_color_dim ;;
    esac
    printf '%s%s%s\n' "$vam_color" "$*" "$app_color_reset" >&2
    return 0
}

# ============================================================
# usage
# Prints view_all usage.
#
# Version:
#   1.0.0
#
# Returns:
#   0
# ============================================================
usage() {
    cat <<'EOF'
view_all.sh - present every Host Inventory for Proxmox aspect

Usage:
  sudo ./view_all.sh
  ./view_all.sh --from-run
  ./view_all.sh --from-run host-inventory-YYYYMMDD-HHMMSS
  ./view_all.sh --list-runs

Modes:
  Live (default)
    Runs prepare_host.sh once, then invokes each standalone view_*.sh
    with per-script installation disabled.

  Replay
    --from-run DIR
    Reads DIR/collect_*.json and renders each aspect without probing
    the host again.

  Saved-run discovery
    --from-run
    --list-runs
    Lists saved host-inventory-* directories visible from the current
    directory and the suite directory, newest first. Each entry shows
    whether the current 38-view replay is complete.

Options:
  --from-run [DIR]   Render DIR, or list available saved runs when DIR is omitted.
  --list-runs        List available saved run directories without rendering.
  --install-missing  Approve the preparation package list automatically.
  --no-install       Never install packages.
  --skip-prepare     Skip prepare_host.sh in live mode.
  --color            Force ANSI color.
  --no-color         Disable ANSI color.
  --help             Show help.
  --version          Show version.
EOF
    return 0
}

# ============================================================
# parse_options
# Parses view_all command-line options.
#
# Version:
#   1.0.0
#
# Returns:
#   0 on success
#   2 on invalid arguments
# ============================================================
parse_options() {
    vao_action=run
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --from-run)
                if [ "$#" -ge 2 ]; then
                    case "$2" in
                        -*) vao_action=list-runs ;;
                        *) shift; app_from_run=$1 ;;
                    esac
                else
                    vao_action=list-runs
                fi
                ;;
            --list-runs) vao_action=list-runs ;;
            --install-missing) app_install_mode=always ;;
            --no-install) app_install_mode=never ;;
            --skip-prepare) app_skip_prepare=1 ;;
            --color) app_color_mode=always ;;
            --no-color) app_color_mode=never ;;
            --help|-h|-\?|/h|/\?) vao_action=help ;;
            --version) vao_action=version ;;
            *) message error "ERROR: Unknown argument: $1"; return 2 ;;
        esac
        shift
    done
    return 0
}

# ============================================================
# list_saved_runs
# Lists run_all.sh output directories visible from the current working
# directory and the suite directory. Current replay completeness is
# determined only from saved collector JSON files; no host probe occurs.
#
# Version:
#   1.0.0
#
# Returns:
#   0
# ============================================================
list_saved_runs() {
    vls_cwd=$(pwd -P 2>/dev/null || pwd)
    vls_runs=$(
        {
            for vls_base in "$vls_cwd" "$app_script_dir"; do
                for vls_dir in "$vls_base"/host-inventory-*; do
                    [ -d "$vls_dir" ] || continue
                    (CDPATH= cd -- "$vls_dir" 2>/dev/null && pwd -P)
                done
            done
        } | LC_ALL=C sort -r | awk '!vls_seen[$0]++'
    )

    printf 'Available saved runs (newest first):\n'
    if [ -z "$vls_runs" ]; then
        printf '  none found\n'
        printf '\nSearched:\n  %s\n' "$vls_cwd"
        [ "$app_script_dir" = "$vls_cwd" ] || printf '  %s\n' "$app_script_dir"
        return 0
    fi

    printf '%-36s  %-13s  %s\n' 'RUN' 'COLLECTORS' 'REPLAY'
    printf '%s\n' "$vls_runs" | while IFS= read -r vls_dir; do
        [ -n "$vls_dir" ] || continue
        vls_count=0
        for vls_json in "$vls_dir"/collect_*.json; do
            [ -f "$vls_json" ] || continue
            vls_count=$((vls_count+1))
        done
        if [ "$vls_count" -eq "$app_view_count" ]; then
            vls_state=ready
        else
            vls_state=incomplete
        fi
        vls_name=${vls_dir##*/}
        printf '%-36s  %3s/%-9s  %s\n' "$vls_name" "$vls_count" "$app_view_count" "$vls_state"
    done
    printf '\nUse: ./view_all.sh --from-run RUN\n'
    return 0
}

# ============================================================
# prepare_live
# Runs suite preparation once before live view collection.
#
# Version:
#   1.0.0
#
# Returns:
#   prepare_host.sh return code
#   2 if the preparation script is unavailable
# ============================================================
prepare_live() {
    vpl_script=$app_script_dir/prepare_host.sh
    [ -x "$vpl_script" ] || { message error "Missing executable: $vpl_script"; return 2; }
    case "$app_install_mode" in
        always) vpl_install=--install-missing ;;
        never) vpl_install=--no-install ;;
        *) vpl_install= ;;
    esac
    case "$app_color_mode" in
        always) vpl_color=--color ;;
        never) vpl_color=--no-color ;;
        *) vpl_color= ;;
    esac
    if [ -n "$vpl_install" ] && [ -n "$vpl_color" ]; then "$vpl_script" "$vpl_install" "$vpl_color"
    elif [ -n "$vpl_install" ]; then "$vpl_script" "$vpl_install"
    elif [ -n "$vpl_color" ]; then "$vpl_script" "$vpl_color"
    else "$vpl_script"
    fi
}

# ============================================================
# view_separator
# Prints a large separator between aspect views.
#
# Version:
#   1.0.0
#
# Returns:
#   0
# ============================================================
view_separator() {
    printf '\n%s%s%s\n\n' "$app_color_dim" '########################################################################' "$app_color_reset"
    return 0
}

# ============================================================
# render_all
# Invokes all standalone view scripts in defined logical order.
#
# Version:
#   1.0.0
#
# Returns:
#   0 when every view succeeds
#   1 when one or more views fail
#   2 for missing required view scripts or replay files
# ============================================================
render_all() {
    vra_failed=0
    vra_index=0
    for vra_view in $app_views; do
        vra_index=$((vra_index+1))
        vra_path=$app_script_dir/$vra_view
        [ -x "$vra_path" ] || { message error "Missing executable: $vra_view"; return 2; }

        vra_aspect=${vra_view#view_}
        vra_aspect=${vra_aspect%.sh}
        message info "[$vra_index/$app_view_count] Rendering $vra_aspect"

        [ "$vra_index" -eq 1 ] || view_separator

        case "$app_color_mode" in
            always) vra_color=--color ;;
            never) vra_color=--no-color ;;
            *) vra_color= ;;
        esac

        if [ -n "$app_from_run" ]; then
            vra_json=$app_from_run/collect_$vra_aspect.json
            [ -r "$vra_json" ] || { message error "Missing replay data: $vra_json"; return 2; }
            if [ -n "$vra_color" ]; then "$vra_path" --file "$vra_json" --no-install --quiet "$vra_color"
            else "$vra_path" --file "$vra_json" --no-install --quiet
            fi
        else
            if [ -n "$vra_color" ]; then "$vra_path" --no-install --quiet "$vra_color"
            else "$vra_path" --no-install --quiet
            fi
        fi
        vra_rc=$?
        if [ "$vra_rc" -eq 0 ]; then
            message ok "PASS  $vra_view"
        else
            message error "FAIL  $vra_view (rc=$vra_rc)"
            vra_failed=1
        fi
    done
    return "$vra_failed"
}

# ============================================================
# main
# Coordinates live preparation or replay rendering.
#
# Version:
#   1.0.0
#
# Returns:
#   view_all application return code
# ============================================================
main() {
    case "$vao_action" in
        help) usage; return 0 ;;
        version) printf '%s %s\n' "$app_name" "$app_version"; return 0 ;;
        list-runs) list_saved_runs; return $? ;;
    esac

    message title "Host Inventory for Proxmox - All Views $app_version"

    if [ -n "$app_from_run" ]; then
        [ -d "$app_from_run" ] || { message error "Replay directory does not exist: $app_from_run"; return 2; }
        app_from_run=$(CDPATH= cd -- "$app_from_run" 2>/dev/null && pwd -P) || return 2
        message info "Replay source: $app_from_run"
    elif [ "$app_skip_prepare" -eq 0 ]; then
        message info "Running suite preparation once before live views..."
        prepare_live || return 2
    fi

    render_all
}

# ------------------------------ setup ------------------------------
color_init
parse_options "$@"
app_rc=$?
color_init

# ------------------------------- main -------------------------------
if [ "$app_rc" -eq 0 ]; then main; app_rc=$?; fi

# -------------------------------- end -------------------------------
exit "$app_rc"
