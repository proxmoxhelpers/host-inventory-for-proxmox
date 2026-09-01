#!/bin/sh
# ============================================================
# run_complete.sh
# End-to-end Host Inventory for Proxmox workflow:
#   1. full test suite
#   2. one fresh run_all.sh collection
#   3. one harmonization pass
#   4. every terminal and interactive HTML report
#   5. passive timing/profiling reports
#
# Version:
#   0.9.2
#
# No intrusive measurement tool is started automatically.
# ============================================================
app_name=run_complete
app_version=0.9.2
app_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || exit 2
app_color_mode=auto
app_install_mode=ask
app_skip_tests=0
app_compact=0
app_output=
app_from_run=
app_reports_dir=
app_tmp=
app_test_results=
app_test_timings=
app_workflow_timings=
app_run_dir=
app_rc=0

cleanup() {
    [ -n "$app_tmp" ] && [ -d "$app_tmp" ] && rm -rf -- "$app_tmp"
    return 0
}
trap cleanup EXIT HUP INT TERM

usage() {
cat <<'EOF'
run_complete.sh - test, collect, summarize, report and passively profile the suite

Usage:
  ./run_complete.sh
  ./run_complete.sh --output host-inventory-baseline
  ./run_complete.sh --skip-tests
  ./run_complete.sh --from-run host-inventory-YYYYMMDD-HHMMSS

Default workflow:
  1. Run test/test_all.sh and stop if any focused test fails.
  2. Run one fresh run_all.sh collection.
  3. Harmonize that exact capture once.
  4. Generate all terminal/text reports.
  5. Generate every self-contained interactive HTML report.
  6. Generate collector/workflow performance timing reports.

Options:
  --output DIR       Fresh run_all.sh output directory.
  --reports-dir DIR  Report directory (default: RUN_DIR/reports).
  --skip-tests       Skip test/test_all.sh but still perform a fresh collection.
  --from-run DIR     Reports-only mode for an existing saved run; no test or
                     collection is performed.
  --compact          Ask run_all.sh for compact collector JSON.
  --install-missing  Let preparation install missing safe diagnostic packages.
  --no-install       Never install missing packages.
  --color            Force wrapper status color.
  --no-color         Disable wrapper status color.
  --help             Show help.
  --version          Show version.

Performance measurements are passive elapsed-time instrumentation only.
measure_osnoise.sh, measure_timerlat.sh, measure_kvm_exits.sh,
measure_qemu_perf.sh, measure_irqsoff.sh and measure_hwlat.sh are never
started automatically by this workflow.
EOF
}

parse_options() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --output)
                shift
                [ "$#" -gt 0 ] || { printf 'ERROR: --output requires a directory.\n' >&2; return 2; }
                app_output=$1
                ;;
            --reports-dir)
                shift
                [ "$#" -gt 0 ] || { printf 'ERROR: --reports-dir requires a directory.\n' >&2; return 2; }
                app_reports_dir=$1
                ;;
            --skip-tests) app_skip_tests=1 ;;
            --from-run)
                shift
                [ "$#" -gt 0 ] || { printf 'ERROR: --from-run requires a directory.\n' >&2; return 2; }
                app_from_run=$1
                ;;
            --compact) app_compact=1 ;;
            --install-missing) app_install_mode=always ;;
            --no-install) app_install_mode=never ;;
            --color) app_color_mode=always ;;
            --no-color) app_color_mode=never ;;
            --help|-h) usage; exit 0 ;;
            --version) printf '%s %s\n' "$app_name" "$app_version"; exit 0 ;;
            *) printf 'ERROR: Unknown argument: %s\n' "$1" >&2; return 2 ;;
        esac
        shift
    done
    if [ -n "$app_from_run" ] && [ -n "$app_output" ]; then
        printf 'ERROR: --from-run and --output cannot be used together.\n' >&2
        return 2
    fi
    return 0
}

color_init() {
    rci_enable=0
    [ -n "${NO_COLOR-}" ] && app_color_mode=never
    case "$app_color_mode" in
        always) rci_enable=1 ;;
        never) rci_enable=0 ;;
        auto) [ -t 1 ] && rci_enable=1 ;;
    esac
    if [ "$rci_enable" -eq 1 ]; then
        c0=$(printf '\033[0m'); ctitle=$(printf '\033[1;96m'); cinfo=$(printf '\033[96m')
        cok=$(printf '\033[92m'); cwarn=$(printf '\033[93m'); cbad=$(printf '\033[91m')
    else
        c0=; ctitle=; cinfo=; cok=; cwarn=; cbad=
    fi
}

status() {
    rs_kind=$1
    shift
    case "$rs_kind" in
        title) rs_color=$ctitle ;;
        ok) rs_color=$cok ;;
        warn) rs_color=$cwarn ;;
        error) rs_color=$cbad ;;
        *) rs_color=$cinfo ;;
    esac
    printf '%s%s%s\n' "$rs_color" "$*" "$c0"
}

timing_now_ms() {
    rtm_value=$(date '+%s%3N' 2>/dev/null || :)
    case "$rtm_value" in
        ''|*[!0-9]*)
            rtm_seconds=$(date '+%s' 2>/dev/null || printf '0')
            printf '%s\n' $((rtm_seconds * 1000))
            ;;
        *) printf '%s\n' "$rtm_value" ;;
    esac
}

require_programs() {
    for rrp in test/test_all.sh run_all.sh harmonize_host.sh build_report_model.sh \
               report_host.sh report_desktop.sh evaluate_desktop.sh \
               report_desktop_evaluation.sh report_html.sh report_performance.sh \
               view_all.sh; do
        [ -x "$app_dir/$rrp" ] || { status error "ERROR: Missing executable: $app_dir/$rrp"; return 2; }
    done
    command -v jq >/dev/null 2>&1 || { status error "ERROR: jq is required."; return 2; }
    return 0
}

run_logged() {
    rlg_log=$1
    shift
    rlg_rc_file=$app_tmp/command.rc
    rm -f -- "$rlg_rc_file"
    (
        "$@"
        printf '%s\n' "$?" > "$rlg_rc_file"
    ) 2>&1 | tee "$rlg_log"
    [ -r "$rlg_rc_file" ] || return 2
    rlg_rc=$(cat "$rlg_rc_file" 2>/dev/null)
    case "$rlg_rc" in ''|*[!0-9]*) return 2 ;; esac
    return "$rlg_rc"
}

normalize_path() {
    rnp_input=$1
    case "$rnp_input" in
        /*) rnp_path=$rnp_input ;;
        *) rnp_path=$PWD/$rnp_input ;;
    esac
}

resolve_existing_run() {
    [ -d "$app_from_run" ] || { status error "ERROR: Run directory does not exist: $app_from_run"; return 2; }
    app_run_dir=$(CDPATH= cd -- "$app_from_run" 2>/dev/null && pwd -P) || return 2
    if [ ! -r "$app_run_dir/inventory.json" ] && [ -r "$app_run_dir/inventory/inventory.json" ]; then
        app_run_dir=$app_run_dir/inventory
    fi
    [ -r "$app_run_dir/inventory.json" ] || { status error "ERROR: inventory.json not found in: $app_run_dir"; return 2; }
    [ -r "$app_run_dir/manifest.json" ] || { status error "ERROR: manifest.json not found in: $app_run_dir"; return 2; }
    return 0
}

prepare_fresh_output() {
    if [ -z "$app_output" ]; then
        app_output="host-inventory-$(date '+%Y%m%d-%H%M%S')"
    fi
    normalize_path "$app_output"
    app_run_dir=$rnp_path
    [ ! -e "$app_run_dir" ] || { status error "ERROR: Output path already exists: $app_run_dir"; return 2; }
    return 0
}

run_tests() {
    [ "$app_skip_tests" -eq 0 ] || { app_test_ms=0; return 0; }
    status title "=== Full test suite ==="
    rt_started=$(timing_now_ms)
    rt_log=$app_tmp/test_all.console.log
    run_logged "$rt_log" "$app_dir/test/test_all.sh"
    rt_rc=$?
    rt_finished=$(timing_now_ms)
    app_test_ms=$((rt_finished - rt_started))
    [ "$rt_rc" -eq 0 ] || { status error "ERROR: Complete test suite failed; fresh collection was not started."; return "$rt_rc"; }

    app_test_results=$(sed -n 's/^Test results kept at: //p' "$rt_log" | tail -n 1)
    if [ -n "$app_test_results" ] && [ -r "$app_test_results/timings.tsv" ]; then
        app_test_timings=$app_test_results/timings.tsv
    else
        app_test_timings=
    fi
    return 0
}

run_collection() {
    status title "=== Fresh inventory collection ==="
    rc_started=$(timing_now_ms)
    rc_log=$app_tmp/run_all.console.log
    set -- "$app_dir/run_all.sh" --output "$app_run_dir"
    [ "$app_compact" -eq 0 ] || set -- "$@" --compact
    case "$app_install_mode" in
        always) set -- "$@" --install-missing ;;
        never) set -- "$@" --no-install ;;
    esac
    case "$app_color_mode" in
        always) set -- "$@" --color ;;
        never) set -- "$@" --no-color ;;
    esac
    run_logged "$rc_log" "$@"
    rc_code=$?
    rc_finished=$(timing_now_ms)
    app_collection_ms=$((rc_finished - rc_started))
    [ "$rc_code" -eq 0 ] || { status error "ERROR: run_all.sh failed (rc=$rc_code)."; return "$rc_code"; }
    [ -r "$app_run_dir/inventory.json" ] || { status error "ERROR: Fresh inventory.json is missing."; return 2; }
    return 0
}

prepare_reports_dir() {
    if [ -z "$app_reports_dir" ]; then
        app_reports_dir=$app_run_dir/reports
    else
        normalize_path "$app_reports_dir"
        app_reports_dir=$rnp_path
    fi
    if [ -e "$app_reports_dir" ]; then
        status error "ERROR: Reports directory already exists: $app_reports_dir"
        status error "       Choose --reports-dir DIR or remove the old report directory."
        return 2
    fi
    mkdir -p -- "$app_reports_dir" || return 2
    app_workflow_timings=$app_reports_dir/workflow-timings.tsv
    return 0
}

harmonize_once() {
    status title "=== Harmonize once for all reports ==="
    rh_started=$(timing_now_ms)
    app_host_map=$app_reports_dir/host-map.json
    "$app_dir/harmonize_host.sh" --from-run "$app_run_dir" --output "$app_host_map" --no-install --no-color || return $?
    rh_finished=$(timing_now_ms)
    app_harmonize_ms=$((rh_finished - rh_started))
    return 0
}

build_models_once() {
    status title "=== Build reusable report/evaluation models ==="
    rb_started=$(timing_now_ms)
    app_report_model=$app_reports_dir/report-model.json
    app_evaluation=$app_reports_dir/desktop-evaluation.json
    "$app_dir/build_report_model.sh" --file "$app_host_map" --output "$app_report_model" || return $?
    "$app_dir/evaluate_desktop.sh" --file "$app_host_map" --output "$app_evaluation" || return $?
    rb_finished=$(timing_now_ms)
    app_model_ms=$((rb_finished - rb_started))
    return 0
}

generate_text_reports() {
    status title "=== Terminal/text reports ==="
    rg_started=$(timing_now_ms)
    "$app_dir/view_all.sh" --from-run "$app_run_dir" --no-color > "$app_reports_dir/view-all.txt" || return $?
    "$app_dir/report_host.sh" --file "$app_host_map" --short --no-color > "$app_reports_dir/host-short.txt" || return $?
    "$app_dir/report_host.sh" --file "$app_host_map" --dense-summary --no-color > "$app_reports_dir/host-dense-summary.txt" || return $?
    "$app_dir/report_host.sh" --file "$app_host_map" --dense --no-color > "$app_reports_dir/host-dense.txt" || return $?
    "$app_dir/report_desktop.sh" --file "$app_host_map" --short --no-color > "$app_reports_dir/desktop-short.txt" || return $?
    "$app_dir/report_desktop.sh" --file "$app_host_map" --dense-summary --no-color > "$app_reports_dir/desktop-dense-summary.txt" || return $?
    "$app_dir/report_desktop.sh" --file "$app_host_map" --dense --no-color > "$app_reports_dir/desktop-dense.txt" || return $?
    "$app_dir/report_desktop_evaluation.sh" --file "$app_host_map" --no-color > "$app_reports_dir/desktop-evaluation.txt" || return $?
    rg_finished=$(timing_now_ms)
    app_text_ms=$((rg_finished - rg_started))
    return 0
}

generate_html_reports() {
    status title "=== Interactive HTML reports ==="
    rh_started=$(timing_now_ms)
    "$app_dir/report_html.sh" --from-run "$app_run_dir" --mode all --output "$app_reports_dir/view-all.html" || return $?
    "$app_dir/report_html.sh" --file "$app_host_map" --mode short --output "$app_reports_dir/host-short.html" || return $?
    "$app_dir/report_html.sh" --file "$app_host_map" --mode dense-summary --output "$app_reports_dir/host-dense-summary.html" || return $?
    "$app_dir/report_html.sh" --file "$app_host_map" --mode dense --output "$app_reports_dir/host-dense.html" || return $?
    "$app_dir/report_html.sh" --file "$app_host_map" --mode desktop-short --output "$app_reports_dir/desktop-short.html" || return $?
    "$app_dir/report_html.sh" --file "$app_host_map" --mode desktop-dense-summary --output "$app_reports_dir/desktop-dense-summary.html" || return $?
    "$app_dir/report_html.sh" --file "$app_host_map" --mode desktop-dense --output "$app_reports_dir/desktop-dense.html" || return $?
    "$app_dir/report_html.sh" --file "$app_host_map" --mode desktop-evaluation --output "$app_reports_dir/desktop-evaluation.html" || return $?
    rh_finished=$(timing_now_ms)
    app_html_ms=$((rh_finished - rh_started))
    return 0
}

write_workflow_timings() {
    rwt_total_ms=$1
    {
        printf 'phase\telapsed_ms\n'
        printf 'test_suite\t%s\n' "${app_test_ms:-0}"
        printf 'fresh_collection\t%s\n' "${app_collection_ms:-0}"
        printf 'harmonization_once\t%s\n' "${app_harmonize_ms:-0}"
        printf 'report_model_and_evaluation\t%s\n' "${app_model_ms:-0}"
        printf 'text_reports\t%s\n' "${app_text_ms:-0}"
        printf 'html_reports\t%s\n' "${app_html_ms:-0}"
        printf 'performance_reports\t%s\n' "${app_performance_ms:-0}"
        printf 'total\t%s\n' "$rwt_total_ms"
    } > "$app_workflow_timings" || return 2
    return 0
}

generate_performance_reports() {
    if [ ! -r "$app_run_dir/collector-timings.tsv" ] || [ ! -r "$app_run_dir/run-timings.tsv" ]; then
        status warn "Performance timing files are unavailable in this saved run; performance reports skipped."
        printf 'Performance timing unavailable: this capture predates passive run_all.sh timing instrumentation.\n' > "$app_reports_dir/performance-unavailable.txt"
        app_performance_ms=0
        return 0
    fi

    status title "=== Passive performance reports ==="
    rp_started=$(timing_now_ms)
    set -- "$app_dir/report_performance.sh" --from-run "$app_run_dir" --workflow-timings "$app_workflow_timings"
    if [ -n "$app_test_timings" ]; then set -- "$@" --test-timings "$app_test_timings"; fi
    "$@" --text --no-color --output "$app_reports_dir/performance.txt" || return $?
    "$@" --json --output "$app_reports_dir/performance.json" || return $?
    "$@" --html --output "$app_reports_dir/performance.html" || return $?
    rp_finished=$(timing_now_ms)
    app_performance_ms=$((rp_finished - rp_started))
    return 0
}

# Refresh the rendered performance files after the final workflow timing
# values are written. This second render is reporter overhead and is not
# folded back into the measured workflow, avoiding a self-referential timer.
refresh_performance_reports() {
    [ -r "$app_run_dir/collector-timings.tsv" ] || return 0
    set -- "$app_dir/report_performance.sh" --from-run "$app_run_dir" --workflow-timings "$app_workflow_timings"
    if [ -n "$app_test_timings" ]; then set -- "$@" --test-timings "$app_test_timings"; fi
    "$@" --text --no-color --output "$app_reports_dir/performance.txt" || return $?
    "$@" --json --output "$app_reports_dir/performance.json" || return $?
    "$@" --html --output "$app_reports_dir/performance.html" || return $?
    return 0
}

copy_workflow_logs() {
    [ -r "$app_tmp/test_all.console.log" ] && cp -- "$app_tmp/test_all.console.log" "$app_reports_dir/test-all.console.log"
    [ -r "$app_tmp/run_all.console.log" ] && cp -- "$app_tmp/run_all.console.log" "$app_reports_dir/run-all.console.log"
    if [ -n "$app_test_results" ]; then
        printf '%s\n' "$app_test_results" > "$app_reports_dir/test-results-directory.txt"
    fi
    return 0
}

show_final_summary() {
    status ok ""
    status ok "Everything completed successfully."
    status info "Inventory: $app_run_dir"
    status info "Reports:   $app_reports_dir"
    [ -n "$app_test_results" ] && status info "Tests:     $app_test_results"
    if [ -r "$app_reports_dir/performance.txt" ]; then
        status info ""
        status title "Largest observed collector contributors:"
        awk '
          /^Largest collector contributors/ {show=1; next}
          show && /^Concentration/ {exit}
          show {print}
        ' "$app_reports_dir/performance.txt" | sed -n '1,8p'
    fi
    return 0
}

main() {
    app_tmp=$(mktemp -d "${TMPDIR:-/tmp}/hfip-complete.XXXXXX") || return 2
    app_started_ms=$(timing_now_ms)

    require_programs || return $?

    app_test_ms=0
    app_collection_ms=0
    app_harmonize_ms=0
    app_model_ms=0
    app_text_ms=0
    app_html_ms=0
    app_performance_ms=0

    if [ -n "$app_from_run" ]; then
        status title "Host Inventory for Proxmox - Complete Workflow $app_version (reports-only replay)"
        resolve_existing_run || return $?
    else
        status title "Host Inventory for Proxmox - Complete Workflow $app_version"
        # Validate an explicit destination before spending time on tests.
        # For the default timestamped destination, choose the name immediately
        # before collection so its timestamp reflects the capture, not test start.
        if [ -n "$app_output" ]; then
            prepare_fresh_output || return $?
        fi
        run_tests || return $?
        if [ -z "$app_run_dir" ]; then
            prepare_fresh_output || return $?
        fi
        run_collection || return $?
    fi

    prepare_reports_dir || return $?
    harmonize_once || return $?
    build_models_once || return $?
    generate_text_reports || return $?
    generate_html_reports || return $?

    app_before_perf_ms=$(timing_now_ms)
    write_workflow_timings $((app_before_perf_ms - app_started_ms)) || return $?
    generate_performance_reports || return $?

    app_finished_ms=$(timing_now_ms)
    app_total_ms=$((app_finished_ms - app_started_ms))
    write_workflow_timings "$app_total_ms" || return $?
    refresh_performance_reports || return $?
    copy_workflow_logs || return $?

    show_final_summary
    return 0
}

parse_options "$@" || exit $?
color_init
main
app_rc=$?
exit "$app_rc"
