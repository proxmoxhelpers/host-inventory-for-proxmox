#!/bin/sh
# ============================================================
# report_host.sh
# Descriptive terminal report generated from host-map.json.
#
# Version:
#   0.9.2
# ============================================================
app_name=report_host
app_version=0.9.2
app_scope=general
app_style=short
app_file=
app_from_run=
app_color_mode=auto
app_temp=
app_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || exit 2
cleanup() { [ -n "$app_temp" ] && [ -d "$app_temp" ] && rm -rf -- "$app_temp"; }
trap cleanup EXIT HUP INT TERM
usage() {
cat <<'EOF'
report_host.sh - Host Inventory — compact host report

Usage:
  ./report_host.sh --from-run RUN_DIR [--short|--dense-summary|--dense]
  ./report_host.sh --file host-map.json [--short|--dense-summary|--dense]

Options:
  --short          Important compact summary (default).
  --dense-summary  Very dense domain summary, one line per section.
  --dense          Detailed dense report with normalized evidence rows.
  --file FILE      Existing host-map.json.
  --from-run DIR   Harmonize a saved inventory run.
  --color          Force ANSI color.
  --no-color       Disable ANSI color.
  --help           Show help.
  --version        Show version.

This report is descriptive only and never assigns PASS/WARN/FAIL.
EOF
}
while [ "$#" -gt 0 ]; do
    case "$1" in
        --short) app_style=short ;;
        --dense-summary) app_style=dense_summary ;;
        --dense) app_style=dense ;;
        --file) shift; [ "$#" -gt 0 ] || { printf 'ERROR: --file requires a path.\n' >&2; exit 2; }; app_file=$1 ;;
        --from-run) shift; [ "$#" -gt 0 ] || { printf 'ERROR: --from-run requires a directory.\n' >&2; exit 2; }; app_from_run=$1 ;;
        --color) app_color_mode=always ;;
        --no-color) app_color_mode=never ;;
        --help|-h) usage; exit 0 ;;
        --version) printf '%s %s\n' "$app_name" "$app_version"; exit 0 ;;
        *) printf 'ERROR: Unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done
[ -n "$app_file" ] && [ -n "$app_from_run" ] && { printf 'ERROR: choose --file or --from-run.\n' >&2; exit 2; }
[ -n "$app_file$app_from_run" ] || { printf 'ERROR: --file or --from-run is required.\n' >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { printf 'ERROR: jq is required.\n' >&2; exit 2; }
app_temp=$(mktemp -d "${TMPDIR:-/tmp}/hfip-terminal-report.XXXXXX") || exit 2
app_model=$app_temp/report-model.json
if [ -n "$app_file" ]; then
    "$app_dir/build_report_model.sh" --file "$app_file" --output "$app_model" || exit $?
else
    "$app_dir/build_report_model.sh" --from-run "$app_from_run" --output "$app_model" || exit $?
fi

app_color_enable=0
[ -n "${NO_COLOR-}" ] && app_color_mode=never
case "$app_color_mode" in
    always) app_color_enable=1 ;;
    never) app_color_enable=0 ;;
    auto) [ -t 1 ] && app_color_enable=1 ;;
esac
if [ "$app_color_enable" -eq 1 ]; then
    c_reset=$(printf '\033[0m'); c_title=$(printf '\033[1;96m'); c_section=$(printf '\033[1;94m')
    c_key=$(printf '\033[95m'); c_identity=$(printf '\033[96m'); c_cpu=$(printf '\033[95m')
    c_virtual=$(printf '\033[94m'); c_gpu=$(printf '\033[92m'); c_memory=$(printf '\033[92m')
    c_storage=$(printf '\033[93m'); c_network=$(printf '\033[96m'); c_irq=$(printf '\033[35m')
    c_events=$(printf '\033[38;5;209m'); c_runtime=$(printf '\033[37m'); c_dim=$(printf '\033[90m')
else
    c_reset=; c_title=; c_section=; c_key=; c_identity=; c_cpu=; c_virtual=; c_gpu=; c_memory=; c_storage=; c_network=; c_irq=; c_events=; c_runtime=; c_dim=
fi
tone_color() {
    case "$1" in
        identity|software|firmware) printf '%s' "$c_identity" ;;
        cpu) printf '%s' "$c_cpu" ;;
        virtual|pci) printf '%s' "$c_virtual" ;;
        gpu|memory) printf '%s' "$c_memory" ;;
        storage) printf '%s' "$c_storage" ;;
        network|display|peripheral) printf '%s' "$c_network" ;;
        irq) printf '%s' "$c_irq" ;;
        events) printf '%s' "$c_events" ;;
        runtime|background) printf '%s' "$c_runtime" ;;
        *) printf '%s' "$c_runtime" ;;
    esac
}

app_host=$(jq -r '.host // "unknown"' "$app_model")
app_start=$(jq -r '.collection.start // "unknown"' "$app_model")
app_end=$(jq -r '.collection.end // "unknown"' "$app_model")
printf '%s%s%s\n' "$c_title" "Host Inventory — compact host report" "$c_reset"
printf '%s%s  %s → %s%s\n' "$c_dim" "$app_host" "$app_start" "$app_end" "$c_reset"

if [ "$app_style" = dense_summary ]; then
    jq -r '.reports.general.dense_summary[] | [.title, ([.rows[] | (.label+"="+.value)] | join("  │  "))] | @tsv' "$app_model" |
    while IFS="$(printf '\t')" read -r rr_title rr_text; do
        printf '%s%-18s%s %s\n' "$c_section" "$rr_title" "$c_reset" "$rr_text"
    done
    exit 0
fi

if [ "$app_style" = short ]; then app_path='.reports.general.short'; else app_path='.reports.general.dense'; fi
jq -r "$app_path[] | \"@@SECTION\\t\"+.title, (.rows[] | [.tone,.label,.value] | @tsv)" "$app_model" |
while IFS="$(printf '\t')" read -r rr_a rr_b rr_c; do
    if [ "$rr_a" = "@@SECTION" ]; then
        printf '%s[%s]%s\n' "$c_section" "$rr_b" "$c_reset"
    else
        rr_color=$(tone_color "$rr_a")
        printf '%s%-20s%s %s%s%s\n' "$c_key" "$rr_b" "$c_reset" "$rr_color" "$rr_c" "$c_reset"
    fi
done
exit 0
