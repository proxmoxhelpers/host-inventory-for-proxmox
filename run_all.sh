#!/bin/sh
# ============================================================
# run_all.sh
# Runs the complete Host Inventory for Proxmox suite, preserving one
# JSON file per collector and producing a valid combined array.
#
# Version:
#   0.9.2
#
# Usage:
#   sudo ./run_all.sh
#   sudo ./run_all.sh --output inventory-baseline
#
# Output:
#   Colorized progress on the console.
#   A timestamped output directory containing individual JSON,
#   inventory.json, manifest.json, collector-timings.tsv, and
#   run-timings.tsv.
#
# Returns:
#   0 when all collectors succeed
#   1 when one or more collectors fail
#   2 on setup/argument/preparation failure
#
# Dependencies:
#   prepare_host.sh and the collect_*.sh files beside this script.
#   jq after preparation completes.
#
# Side Effects:
#   Calls prepare_host.sh, which may install explicitly approved
#   APT packages. Collection itself is read-only.
# ============================================================
app_name=run_all
app_version=0.9.2
app_rc=0
app_color_mode=auto
app_install_mode=ask
app_compact=0
app_skip_prepare=0
app_output=
app_prepare_ms=0
app_collectors_ms=0
app_finalize_ms=0
app_total_ms=0
app_script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || exit 2

app_collectors="
collect_platform.sh
collect_firmware_settings.sh
collect_acpi_platform.sh
collect_security_mitigations.sh
collect_boot_kernel.sh
collect_cpu_topology.sh
collect_cpu_firmware_ras.sh
collect_cpu_power_idle.sh
collect_cpu_limits_pmu.sh
collect_cache_resource_qos.sh
collect_timers_watchdogs.sh
collect_kernel_events.sh
collect_virtualization_stack.sh
collect_kernel_housekeeping.sh
collect_pm_qos.sh
collect_pcie_iommu.sh
collect_pcie_advanced.sh
collect_irq_architecture.sh
collect_gpu_vfio.sh
collect_isolation_scheduler.sh
collect_memory.sh
collect_memory_hardware.sh
collect_memory_fragmentation.sh
collect_irqs.sh
collect_irq_activity.sh
collect_runtime_pressure.sh
collect_latency_sample.sh
collect_storage.sh
collect_storage_health_power.sh
collect_network.sh
collect_network_advanced.sh
collect_usb_input_audio.sh
collect_desktop_io_path.sh
collect_display_timing.sh
collect_services_background.sh
collect_thermal_power.sh
collect_proxmox_host.sh
collect_guest_runtime_detail.sh
"

# ============================================================
# color_init
# Defines semantic ANSI colors.
#
# Version:
#   1.0.0
#
# Returns:
#   0
# ============================================================
color_init() {
    ci_enable=0
    [ -n "${NO_COLOR-}" ] && app_color_mode=never
    case "$app_color_mode" in
        always) ci_enable=1 ;;
        never) ci_enable=0 ;;
        auto) [ -t 1 ] || [ -t 2 ] && ci_enable=1 ;;
        *) app_color_mode=auto; [ -t 1 ] || [ -t 2 ] && ci_enable=1 ;;
    esac
    if [ "$ci_enable" -eq 1 ]; then
        app_color_reset=$(printf '\033[0m')
        app_color_dim=$(printf '\033[90m')
        app_color_title=$(printf '\033[1;96m')
        app_color_info=$(printf '\033[96m')
        app_color_ok=$(printf '\033[92m')
        app_color_warn=$(printf '\033[93m')
        app_color_error=$(printf '\033[91m')
        app_color_accent=$(printf '\033[95m')
    else
        app_color_reset=; app_color_dim=; app_color_title=; app_color_info=; app_color_ok=; app_color_warn=; app_color_error=; app_color_accent=
    fi
    return 0
}

# ============================================================
# message
# Prints one semantic status line.
#
# Version:
#   1.0.0
#
# Returns:
#   0
# ============================================================
message() {
    msg_role=$1
    shift
    case "$msg_role" in
        title) msg_color=$app_color_title ;;
        info) msg_color=$app_color_info ;;
        ok) msg_color=$app_color_ok ;;
        warn) msg_color=$app_color_warn ;;
        error) msg_color=$app_color_error ;;
        accent) msg_color=$app_color_accent ;;
        *) msg_color=$app_color_dim ;;
    esac
    printf '%s%s%s\n' "$msg_color" "$*" "$app_color_reset"
    return 0
}

# ============================================================
# timing_now_ms
# Returns a passive wall-clock timestamp in milliseconds.
# GNU date is available on supported Proxmox/Debian hosts; the
# fallback keeps the script functional if millisecond formatting
# is unavailable.
#
# Version:
#   1.0.0
# ============================================================
timing_now_ms() {
    tnm_value=$(date '+%s%3N' 2>/dev/null || :)
    case "$tnm_value" in
        ''|*[!0-9]*)
            tnm_seconds=$(date '+%s' 2>/dev/null || printf '0')
            printf '%s\n' $((tnm_seconds * 1000))
            ;;
        *) printf '%s\n' "$tnm_value" ;;
    esac
    return 0
}

# ============================================================
# write_run_timings
# Writes passive orchestration timings. These measurements do not
# run any additional probe or workload.
#
# Version:
#   1.0.0
# ============================================================
write_run_timings() {
    wrt_file=$app_output/run-timings.tsv
    {
        printf 'phase\telapsed_ms\n'
        printf 'preparation\t%s\n' "$app_prepare_ms"
        printf 'collectors\t%s\n' "$app_collectors_ms"
        printf 'finalization\t%s\n' "$app_finalize_ms"
        printf 'total\t%s\n' "$app_total_ms"
    } > "$wrt_file" || return 2
    return 0
}

# ============================================================
# usage
# Prints command usage.
#
# Version:
#   1.0.0
#
# Returns:
#   0
# ============================================================
usage() {
    cat <<'EOF'
run_all.sh - collect the complete Host Inventory for Proxmox inventory

Usage:
  sudo ./run_all.sh
  sudo ./run_all.sh --output inventory-baseline

Options:
  --output DIR       Use DIR instead of a timestamped inventory-* directory.
  --compact          Ask collectors for compact JSON.
  --install-missing  Let preparation install the missing package list automatically.
  --no-install       Never install packages.
  --skip-prepare     Do not run prepare_host.sh.
  --color            Force ANSI color for progress.
  --no-color         Disable ANSI color.
  --help             Show help.
  --version          Show version.

The output directory is created under the caller's current working directory
unless an explicit path is supplied. collector-timings.tsv and run-timings.tsv
contain passive elapsed-time measurements only; no extra probe is run for timing.
EOF
    return 0
}

# ============================================================
# parse_options
# Parses run-all options.
#
# Version:
#   1.0.0
#
# Returns:
#   0 on success
#   2 on invalid arguments
# ============================================================
parse_options() {
    po_action=run
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --output)
                shift
                [ "$#" -gt 0 ] || { printf 'ERROR: --output requires a directory.\n' >&2; return 2; }
                app_output=$1
                ;;
            --compact) app_compact=1 ;;
            --install-missing) app_install_mode=always ;;
            --no-install) app_install_mode=never ;;
            --skip-prepare) app_skip_prepare=1 ;;
            --color) app_color_mode=always ;;
            --no-color) app_color_mode=never ;;
            --help|-h|-\?|/h|/\?) po_action=help ;;
            --version) po_action=version ;;
            *) printf 'ERROR: Unknown argument: %s\n' "$1" >&2; return 2 ;;
        esac
        shift
    done
    return 0
}

# ============================================================
# run_preparation
# Runs preparation exactly once for the suite.
#
# Version:
#   1.0.0
#
# Returns:
#   prepare_host.sh return code
# ============================================================
run_preparation() {
    rp_script=$app_script_dir/prepare_host.sh
    [ -x "$rp_script" ] || { message error "Missing executable: $rp_script"; return 2; }
    case "$app_install_mode" in
        always) rp_install=--install-missing ;;
        never) rp_install=--no-install ;;
        *) rp_install= ;;
    esac
    case "$app_color_mode" in
        always) rp_color=--color ;;
        never) rp_color=--no-color ;;
        *) rp_color= ;;
    esac
    if [ -n "$rp_install" ] && [ -n "$rp_color" ]; then "$rp_script" "$rp_install" "$rp_color"
    elif [ -n "$rp_install" ]; then "$rp_script" "$rp_install"
    elif [ -n "$rp_color" ]; then "$rp_script" "$rp_color"
    else "$rp_script"
    fi
}

# ============================================================
# create_output_dir
# Creates a new immutable collection directory.
#
# Version:
#   1.0.0
#
# Returns:
#   0 on success
#   2 when the destination already exists or cannot be created
# ============================================================
create_output_dir() {
    if [ -z "$app_output" ]; then app_output="host-inventory-$(date '+%Y%m%d-%H%M%S')"; fi
    if [ -e "$app_output" ]; then
        message error "Output path already exists: $app_output"
        return 2
    fi
    mkdir -p -- "$app_output" || return 2
    app_output=$(CDPATH= cd -- "$app_output" 2>/dev/null && pwd -P) || return 2
    mkdir -p -- "$app_output/summaries" "$app_output/logs" || return 2
    return 0
}

# ============================================================
# run_collectors
# Runs all collectors in the defined order.
#
# Version:
#   1.0.0
#
# Output:
#   Individual collector JSON files and internal status stream.
#
# Returns:
#   0 when all succeed
#   1 when one or more fail
# ============================================================
run_collectors() {
    rc_any_failure=0
    rc_stream=$app_output/.inventory.stream
    rc_status=$app_output/.status.jsonl
    rc_timings=$app_output/collector-timings.tsv
    : > "$rc_stream" || return 2
    : > "$rc_status" || return 2
    printf 'collector\tcollection_ms\tsummary_ms\ttotal_ms\tcollector_rc\tsummary_rc\tsuccess\n' > "$rc_timings" || return 2

    for rc_script in $app_collectors; do
        rc_path=$app_script_dir/$rc_script
        rc_base=${rc_script%.sh}
        rc_file=$app_output/$rc_base.json
        rc_started_ms=$(timing_now_ms)
        rc_collect_end_ms=$rc_started_ms
        rc_summary_end_ms=$rc_started_ms
        rc_summary_code=0

        if [ ! -x "$rc_path" ]; then
            message error "MISSING  $rc_script"
            jq -n --arg script "$rc_script" --arg file "$rc_base.json" '{script:$script,file:$file,summary_file:null,rc:127,success:false}' >> "$rc_status"
            printf '%s\t0\t0\t0\t127\t-\tfalse\n' "$rc_script" >> "$rc_timings"
            rc_any_failure=1
            continue
        fi

        message info "RUN      $rc_script"
        rc_collect_stderr=$app_output/logs/$rc_base.collect.stderr.log
        rc_summary_stderr=$app_output/logs/$rc_base.summary.stderr.log
        if [ "$app_compact" -eq 1 ]; then
            "$rc_path" --compact --no-install --no-color > "$rc_file" 2> "$rc_collect_stderr"
        else
            "$rc_path" --no-install --no-color > "$rc_file" 2> "$rc_collect_stderr"
        fi
        rc_code=$?
        rc_collect_end_ms=$(timing_now_ms)
        rc_summary_end_ms=$rc_collect_end_ms

        if [ -s "$rc_collect_stderr" ]; then
            sed -e '/^Host Inventory for Proxmox - collect_[^ ]* [0-9][0-9.]*$/d' -e '/^Collecting host state\.\.\.$/d' "$rc_collect_stderr" > "$rc_collect_stderr.filtered"
            mv -- "$rc_collect_stderr.filtered" "$rc_collect_stderr"
        fi

        if [ "$rc_code" -eq 0 ] && jq -e 'type=="object" and (.collector|type=="string")' "$rc_file" >/dev/null 2>&1; then
            rc_summary="summaries/$rc_base.txt"
            "$rc_path" --summary-file "$rc_file" --no-install --no-color > "$app_output/$rc_summary" 2> "$rc_summary_stderr"
            rc_summary_code=$?
            rc_summary_end_ms=$(timing_now_ms)
            if [ "$rc_summary_code" -ne 0 ] || [ -s "$rc_summary_stderr" ]; then
                message warn "SUMMARY  $rc_script failed validation; JSON collection is retained."
                rm -f -- "$app_output/$rc_summary"
                rc_summary=
                rc_any_failure=1
            fi
            cat "$rc_file" >> "$rc_stream"
            printf '\n' >> "$rc_stream"
            jq -n --arg script "$rc_script" --arg file "$rc_base.json" --arg summary "$rc_summary" '{script:$script,file:$file,summary_file:(if $summary=="" then null else $summary end),rc:0,success:true}' >> "$rc_status"
            [ -s "$rc_collect_stderr" ] || rm -f -- "$rc_collect_stderr"
            [ -s "$rc_summary_stderr" ] || rm -f -- "$rc_summary_stderr"
            message ok "PASS     $rc_script"
            rc_success=true
        else
            rm -f -- "$rc_file"
            jq -n --arg script "$rc_script" --arg file "$rc_base.json" --argjson rc "$rc_code" '{script:$script,file:$file,summary_file:null,rc:$rc,success:false}' >> "$rc_status"
            message error "FAIL     $rc_script (rc=$rc_code)"
            rc_any_failure=1
            rc_success=false
            rc_summary_code=-
        fi

        rc_collection_ms=$((rc_collect_end_ms - rc_started_ms))
        rc_summary_ms=$((rc_summary_end_ms - rc_collect_end_ms))
        rc_total_ms=$((rc_summary_end_ms - rc_started_ms))
        [ "$rc_collection_ms" -ge 0 ] 2>/dev/null || rc_collection_ms=0
        [ "$rc_summary_ms" -ge 0 ] 2>/dev/null || rc_summary_ms=0
        [ "$rc_total_ms" -ge 0 ] 2>/dev/null || rc_total_ms=0
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$rc_script" "$rc_collection_ms" "$rc_summary_ms" "$rc_total_ms" "$rc_code" "$rc_summary_code" "$rc_success" >> "$rc_timings"
    done
    return "$rc_any_failure"
}

# ============================================================
# finalize_outputs
# Creates the combined JSON array and collection manifest.
#
# Version:
#   1.0.0
#
# Returns:
#   0 on success
#   2 on serialization failure
# ============================================================
finalize_outputs() {
    fo_time=$(date '+%Y-%m-%dT%H:%M:%S%z')
    fo_host=$(hostname 2>/dev/null || uname -n)
    jq -s '.' "$app_output/.inventory.stream" > "$app_output/inventory.json" || return 2
    : > "$app_output/summary.txt" || return 2
    for fo_script in $app_collectors; do
        fo_base=${fo_script%.sh}
        fo_summary=$app_output/summaries/$fo_base.txt
        [ -f "$fo_summary" ] || continue
        cat "$fo_summary" >> "$app_output/summary.txt" || return 2
        printf '\n\n' >> "$app_output/summary.txt"
    done
    jq -s --arg schema "0.5.0" --arg collected_at "$fo_time" --arg hostname "$fo_host" --arg output_directory "$app_output" '{schema_version:$schema,collected_at:$collected_at,hostname:$hostname,output_directory:$output_directory,collectors:.,success_count:([.[]|select(.success==true)]|length),failure_count:([.[]|select(.success!=true)]|length)}' "$app_output/.status.jsonl" > "$app_output/manifest.json" || return 2
    rm -f -- "$app_output/.inventory.stream" "$app_output/.status.jsonl"
    return 0
}

# ============================================================
# main
# Coordinates preparation, collection and finalization.
#
# Version:
#   1.0.0
#
# Returns:
#   0 when all collectors succeed
#   1 when one or more collectors fail
#   2 on orchestration failure
# ============================================================
main() {
    case "$po_action" in
        help) usage; return 0 ;;
        version) printf '%s %s\n' "$app_name" "$app_version"; return 0 ;;
    esac

    main_started_ms=$(timing_now_ms)
    message title "Host Inventory for Proxmox - Run All $app_version"

    if [ "$app_skip_prepare" -eq 0 ]; then
        message info "Running suite preparation..."
        main_prepare_started_ms=$(timing_now_ms)
        run_preparation || return 2
        main_prepare_finished_ms=$(timing_now_ms)
        app_prepare_ms=$((main_prepare_finished_ms - main_prepare_started_ms))
    else
        app_prepare_ms=0
    fi

    command -v jq >/dev/null 2>&1 || { message error "jq is required by run_all.sh. Run prepare_host.sh first."; return 2; }
    create_output_dir || return $?
    message accent "Output directory: $app_output"

    main_collect_started_ms=$(timing_now_ms)
    run_collectors
    main_collect_rc=$?
    main_collect_finished_ms=$(timing_now_ms)
    app_collectors_ms=$((main_collect_finished_ms - main_collect_started_ms))

    main_finalize_started_ms=$(timing_now_ms)
    finalize_outputs || return 2
    main_finalize_finished_ms=$(timing_now_ms)
    app_finalize_ms=$((main_finalize_finished_ms - main_finalize_started_ms))

    main_finished_ms=$(timing_now_ms)
    app_total_ms=$((main_finished_ms - main_started_ms))
    write_run_timings || return 2

    if [ "$main_collect_rc" -eq 0 ]; then
        message ok "Collection complete: all collectors passed."
    else
        message warn "Collection complete with one or more collector failures."
    fi
    message info "Combined inventory: $app_output/inventory.json"
    message info "Run manifest:       $app_output/manifest.json"
    message info "Combined summary:   $app_output/summary.txt"
    message info "Collector timings:  $app_output/collector-timings.tsv"
    message info "Run timings:        $app_output/run-timings.tsv"
    message info "Diagnostic logs:    $app_output/logs/"
    return "$main_collect_rc"
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
