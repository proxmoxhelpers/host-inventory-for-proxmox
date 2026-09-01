#!/bin/sh
# ============================================================
# measure_qemu_perf.sh
# Runs bounded perf stat counters against one running QEMU process.
#
# Version:
#   0.9.2
#
# Safety:
#   Opt-in measurement only. Never invoked by run_all.sh.
# ============================================================
app_name=measure_qemu_perf
app_version=0.9.2
app_duration=5
app_cpus=
app_vmid=
app_dry_run=0
app_ack_tracing=0
app_ack_intrusive=0

usage() {
    cat <<'EOF'
measure_qemu_perf.sh - measure QEMU process counters with perf stat

Usage:
  ./measure_qemu_perf.sh [options]

Options:
  --duration SEC     Bounded measurement duration (default 5).
  --cpus LIST        CPU list when supported, e.g. 4-15.
  --vmid VMID        Target QEMU VM when required.
  --dry-run          Print the command/action without measuring.
  --ack-tracing      Required by irqsoff tracing.
  --ack-intrusive    Required by hwlat tracing.
  --help             Show help.
  --version          Show version.

This program is deliberately separate from normal inventory collection because
tracing/performance-counter activity can perturb the system being measured.
EOF
}
parse_options() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --duration) shift; [ "$#" -gt 0 ] || return 2; case "$1" in *[!0-9]*|""|0) return 2;; esac; app_duration=$1 ;;
            --cpus) shift; [ "$#" -gt 0 ] || return 2; app_cpus=$1 ;;
            --vmid) shift; [ "$#" -gt 0 ] || return 2; app_vmid=$1 ;;
            --dry-run) app_dry_run=1 ;;
            --ack-tracing) app_ack_tracing=1 ;;
            --ack-intrusive) app_ack_intrusive=1 ;;
            --help|-h) usage; exit 0 ;;
            --version) printf '%s %s\n' "$app_name" "$app_version"; exit 0 ;;
            *) printf 'ERROR: Unknown argument: %s\n' "$1" >&2; return 2 ;;
        esac
        shift
    done
}
resolve_vmid_pid() {
    case "$app_vmid" in *[!0-9]*|"") printf 'ERROR: --vmid is required.\n' >&2; return 2;; esac
    [ -r "/run/qemu-server/$app_vmid.pid" ] || { printf 'ERROR: VM %s is not running or PID file is unavailable.\n' "$app_vmid" >&2; return 2; }
    app_pid=$(cat "/run/qemu-server/$app_vmid.pid" 2>/dev/null)
    case "$app_pid" in *[!0-9]*|"") return 2;; esac
    [ -d "/proc/$app_pid" ] || return 2
}
find_tracefs() {
    if [ -d /sys/kernel/tracing ]; then app_tracefs=/sys/kernel/tracing
    elif [ -d /sys/kernel/debug/tracing ]; then app_tracefs=/sys/kernel/debug/tracing
    else printf 'ERROR: tracefs is not available.\n' >&2; return 2
    fi
}


main() {
    app_events="task-clock,context-switches,cpu-migrations,cycles,instructions,cache-references,cache-misses,branches,branch-misses"
    if [ "$app_dry_run" -eq 1 ]; then
        case "$app_vmid" in *[!0-9]*|"") printf 'ERROR: --vmid is required.\n' >&2; return 2;; esac
        printf 'DRY-RUN: perf stat -p <pid-for-vmid-%s> -e %s -- sleep %s\n' "$app_vmid" "$app_events" "$app_duration"
        return 0
    fi
    command -v perf >/dev/null 2>&1 || { printf 'ERROR: perf is required; prepare_host.sh can install linux-perf.\n' >&2; return 2; }
    resolve_vmid_pid || return $?
    exec perf stat -p "$app_pid" -e "$app_events" -- sleep "$app_duration"
}

parse_options "$@" || exit $?
main
exit $?
