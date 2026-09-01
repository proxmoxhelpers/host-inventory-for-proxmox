#!/bin/sh
# ============================================================
# report_desktop_evaluation.sh
# Complete human-readable Layer 3 evaluation for a virtualized desktop.
#
# Version:
#   0.9.2
# ============================================================
app_name=report_desktop_evaluation
app_version=0.9.2
app_file=
app_from_run=
app_color_mode=auto
app_temp=
app_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || exit 2
cleanup() { [ -n "$app_temp" ] && [ -d "$app_temp" ] && rm -rf -- "$app_temp"; }
trap cleanup EXIT HUP INT TERM
usage() {
cat <<'EOF'
report_desktop_evaluation.sh - complete low-latency desktop evaluation

Usage:
  ./report_desktop_evaluation.sh --file host-map.json
  ./report_desktop_evaluation.sh --from-run RUN_DIR

Options:
  --file FILE       Existing host-map.json.
  --from-run DIR    Harmonize and evaluate a saved inventory run.
  --color           Force ANSI color.
  --no-color        Disable ANSI color.
  --help            Show help.
  --version         Show version.

This is an evaluative Layer 3 report. The underlying evaluator does not re-probe
or modify the host; it consumes host-map evidence only.
EOF
}
while [ "$#" -gt 0 ]; do
    case "$1" in
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
app_temp=$(mktemp -d "${TMPDIR:-/tmp}/hfip-eval-report.XXXXXX") || exit 2
app_eval=$app_temp/evaluation.json
if [ -n "$app_file" ]; then
    "$app_dir/evaluate_desktop.sh" --file "$app_file" --output "$app_eval" || exit $?
else
    "$app_dir/evaluate_desktop.sh" --from-run "$app_from_run" --output "$app_eval" || exit $?
fi

app_color_enable=0
[ -n "${NO_COLOR-}" ] && app_color_mode=never
case "$app_color_mode" in
    always) app_color_enable=1 ;;
    never) app_color_enable=0 ;;
    auto) [ -t 1 ] && app_color_enable=1 ;;
esac
if [ "$app_color_enable" -eq 1 ]; then
    c_reset=$(printf '\033[0m'); c_title=$(printf '\033[1;96m'); c_pass=$(printf '\033[1;92m')
    c_warn=$(printf '\033[1;93m'); c_fail=$(printf '\033[1;91m'); c_unknown=$(printf '\033[1;96m')
    c_key=$(printf '\033[95m'); c_dim=$(printf '\033[90m'); c_section=$(printf '\033[1;94m')
else
    c_reset=; c_title=; c_pass=; c_warn=; c_fail=; c_unknown=; c_key=; c_dim=; c_section=
fi
status_color() {
    case "$1" in PASS) printf '%s' "$c_pass";; WARN) printf '%s' "$c_warn";; FAIL) printf '%s' "$c_fail";; *) printf '%s' "$c_unknown";; esac
}

host=$(jq -r '.source.host // "unknown"' "$app_eval")
win=$(jq -r '(.source.collection_window.start // "unknown")+" → "+(.source.collection_window.end // "unknown")' "$app_eval")
printf '%sHypervisor Desktop — complete latency / stutter / jitter evaluation%s\n' "$c_title" "$c_reset"
printf '%s%s  %s%s\n' "$c_dim" "$host" "$win" "$c_reset"
jq -r '"Policy: "+.policy.id+"\nObjective: "+.policy.objective+
       "\nFindings: "+(.summary.total|tostring)+"  FAIL="+(.summary.fail|tostring)+" WARN="+(.summary.warn|tostring)+
       " UNKNOWN="+(.summary.unknown|tostring)+" PASS="+(.summary.pass|tostring)+
       "  high/critical open="+(.summary.high_or_critical_open|tostring)' "$app_eval"

printf '\n%sPriority findings%s\n' "$c_section" "$c_reset"
jq -r '.findings[] | [.status,.severity,.confidence,.category,.id,.title,.scope,
        (.evidence|join(" || ")),.rationale,.recommendation] | @tsv' "$app_eval" |
while IFS="$(printf '\t')" read -r er_status er_sev er_conf er_cat er_id er_title er_scope er_evidence er_why er_rec; do
    er_color=$(status_color "$er_status")
    printf '%s%-7s%s %-8s %-7s %s%s%s  %s[%s]%s\n' "$er_color" "$er_status" "$c_reset" "$er_sev" "$er_conf" "$c_key" "$er_title" "$c_reset" "$c_dim" "$er_cat" "$c_reset"
    printf '  %sEvidence:%s %s\n' "$c_key" "$c_reset" "$er_evidence"
    printf '  %sWhy:%s      %s\n' "$c_key" "$c_reset" "$er_why"
    printf '  %sAction:%s   %s\n' "$c_key" "$c_reset" "$er_rec"
    printf '  %sScope:%s    %s  id=%s\n' "$c_dim" "$c_reset" "$er_scope" "$er_id"
done

printf '\n%sEpistemic limits%s\n' "$c_section" "$c_reset"
jq -r '.epistemic_limits[] | "  - "+.' "$app_eval"
exit 0
