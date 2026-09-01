#!/bin/sh
# ============================================================
# report_performance.sh
# Reports passive wall-clock timing evidence for one inventory run
# and, when supplied, the surrounding test/workflow timings.
#
# Version:
#   0.9.2
#
# This program performs no hardware probe and starts no benchmark.
# ============================================================
app_name=report_performance
app_version=0.9.2
app_from_run=
app_test_timings=
app_workflow_timings=
app_format=text
app_output=
app_color_mode=auto
app_tmp=

cleanup() {
    [ -n "$app_tmp" ] && [ -d "$app_tmp" ] && rm -rf -- "$app_tmp"
    return 0
}
trap cleanup EXIT HUP INT TERM

usage() {
cat <<'EOF'
report_performance.sh - passive workflow / collector timing report

Usage:
  ./report_performance.sh --from-run RUN_DIR
  ./report_performance.sh --from-run RUN_DIR --json --output performance.json
  ./report_performance.sh --from-run RUN_DIR --html --output performance.html

Options:
  --from-run DIR          Saved run_all.sh output directory (required).
  --test-timings FILE     Optional test/test_all.sh timings.tsv.
  --workflow-timings FILE Optional run_complete.sh workflow-timings.tsv.
  --text                  Human terminal/text report (default).
  --json                  Machine-readable timing report.
  --html                  Self-contained interactive HTML report.
  --output FILE           Write output to FILE instead of stdout.
  --color                 Force ANSI color in text mode.
  --no-color              Disable ANSI color.
  --help                  Show help.
  --version               Show version.

Only already-recorded wall-clock timings are read. No collector, benchmark,
measurement tool, or host probe is started by this report.
EOF
}

parse_options() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --from-run)
                shift
                [ "$#" -gt 0 ] || { printf 'ERROR: --from-run requires a directory.\n' >&2; return 2; }
                app_from_run=$1
                ;;
            --test-timings)
                shift
                [ "$#" -gt 0 ] || { printf 'ERROR: --test-timings requires a file.\n' >&2; return 2; }
                app_test_timings=$1
                ;;
            --workflow-timings)
                shift
                [ "$#" -gt 0 ] || { printf 'ERROR: --workflow-timings requires a file.\n' >&2; return 2; }
                app_workflow_timings=$1
                ;;
            --text) app_format=text ;;
            --json) app_format=json ;;
            --html) app_format=html ;;
            --output)
                shift
                [ "$#" -gt 0 ] || { printf 'ERROR: --output requires a file.\n' >&2; return 2; }
                app_output=$1
                ;;
            --color) app_color_mode=always ;;
            --no-color) app_color_mode=never ;;
            --help|-h) usage; exit 0 ;;
            --version) printf '%s %s\n' "$app_name" "$app_version"; exit 0 ;;
            *) printf 'ERROR: Unknown argument: %s\n' "$1" >&2; return 2 ;;
        esac
        shift
    done
    return 0
}

color_init() {
    rpi_enable=0
    [ -n "${NO_COLOR-}" ] && app_color_mode=never
    case "$app_color_mode" in
        always) rpi_enable=1 ;;
        never) rpi_enable=0 ;;
        auto) [ -t 1 ] && rpi_enable=1 ;;
    esac
    if [ "$rpi_enable" -eq 1 ]; then
        c0=$(printf '\033[0m'); ctitle=$(printf '\033[1;96m'); ckey=$(printf '\033[95m')
        cfast=$(printf '\033[92m'); cmid=$(printf '\033[93m'); cslow=$(printf '\033[91m'); cdim=$(printf '\033[90m')
    else
        c0=; ctitle=; ckey=; cfast=; cmid=; cslow=; cdim=
    fi
}

resolve_run() {
    [ -n "$app_from_run" ] || { printf 'ERROR: --from-run is required.\n' >&2; return 2; }
    [ -d "$app_from_run" ] || { printf 'ERROR: Run directory does not exist: %s\n' "$app_from_run" >&2; return 2; }
    app_from_run=$(CDPATH= cd -- "$app_from_run" 2>/dev/null && pwd -P) || return 2
    if [ -r "$app_from_run/collector-timings.tsv" ]; then
        app_run_dir=$app_from_run
    elif [ -r "$app_from_run/inventory/collector-timings.tsv" ]; then
        app_run_dir=$app_from_run/inventory
    else
        printf 'ERROR: No collector-timings.tsv found in run: %s\n' "$app_from_run" >&2
        return 2
    fi
    app_collector_timings=$app_run_dir/collector-timings.tsv
    app_run_timings=$app_run_dir/run-timings.tsv
    [ -r "$app_run_timings" ] || { printf 'ERROR: Missing run-timings.tsv in %s\n' "$app_run_dir" >&2; return 2; }
    [ -z "$app_test_timings" ] || [ -r "$app_test_timings" ] || { printf 'ERROR: Test timings file not readable: %s\n' "$app_test_timings" >&2; return 2; }
    [ -z "$app_workflow_timings" ] || [ -r "$app_workflow_timings" ] || { printf 'ERROR: Workflow timings file not readable: %s\n' "$app_workflow_timings" >&2; return 2; }
    return 0
}

build_json() {
    command -v jq >/dev/null 2>&1 || { printf 'ERROR: jq is required.\n' >&2; return 2; }
    app_tmp=$(mktemp -d "${TMPDIR:-/tmp}/hfip-performance.XXXXXX") || return 2
    rp_collectors_json=$app_tmp/collectors.json
    rp_run_json=$app_tmp/run.json
    rp_test_json=$app_tmp/test.json
    rp_workflow_json=$app_tmp/workflow.json
    rp_out_json=$app_tmp/performance.json

    awk -F '\t' '
      NR==1 { next }
      NF>=7 {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n",$1,$2,$3,$4,$5,$6,$7
      }
    ' "$app_collector_timings" |
    jq -Rn '
      [inputs | split("\t") |
       {collector:.[0],
        collection_ms:(.[1]|tonumber),
        summary_ms:(.[2]|tonumber),
        total_ms:(.[3]|tonumber),
        collector_rc:(if .[4]=="-" then null else (.[4]|tonumber) end),
        summary_rc:(if .[5]=="-" then null else (.[5]|tonumber) end),
        success:(.[6]=="true")}]
    ' > "$rp_collectors_json" || return 2

    awk -F '\t' 'NR>1 && NF>=2 {printf "%s\t%s\n",$1,$2}' "$app_run_timings" |
    jq -Rn 'reduce (inputs|split("\t")) as $r ({}; .[$r[0]]=($r[1]|tonumber))' > "$rp_run_json" || return 2

    if [ -n "$app_test_timings" ]; then
        awk -F '\t' 'NR>1 && NF>=2 {printf "%s\t%s\n",$1,$2}' "$app_test_timings" |
        jq -Rn '[inputs|split("\t")|{test:.[0],seconds:(.[1]|tonumber)}]' > "$rp_test_json" || return 2
    else
        printf '[]\n' > "$rp_test_json"
    fi

    if [ -n "$app_workflow_timings" ]; then
        awk -F '\t' 'NR>1 && NF>=2 {printf "%s\t%s\n",$1,$2}' "$app_workflow_timings" |
        jq -Rn '[inputs|split("\t")|{phase:.[0],elapsed_ms:(.[1]|tonumber)}]' > "$rp_workflow_json" || return 2
    else
        printf '[]\n' > "$rp_workflow_json"
    fi

    jq -n \
      --arg schema "0.1.0" \
      --arg model "performance-timing" \
      --arg run "$app_run_dir" \
      --slurpfile collectors "$rp_collectors_json" \
      --slurpfile runp "$rp_run_json" \
      --slurpfile tests "$rp_test_json" \
      --slurpfile workflow "$rp_workflow_json" '
      ($collectors[0] // []) as $c |
      ($runp[0] // {}) as $r |
      ($tests[0] // []) as $t |
      ($workflow[0] // []) as $w |
      ($c|map(.total_ms)|add // 0) as $collector_total |
      ($c|map(.summary_ms)|add // 0) as $summary_total |
      ($c|sort_by(.total_ms)|reverse) as $sorted |
      {
        schema_version:$schema,
        model:$model,
        run_directory:$run,
        measurement:{
          kind:"passive-wall-clock",
          extra_workload:false,
          note:"Durations include host load, command startup, timeout waits and rendering overhead observed during this run."
        },
        run_phases:$r,
        collectors:$sorted,
        collector_totals:{
          summed_ms:$collector_total,
          summary_ms:$summary_total,
          summary_share_percent:(if $collector_total>0 then (($summary_total*10000/$collector_total)|round/100) else 0 end),
          top5_ms:($sorted[0:5]|map(.total_ms)|add // 0),
          top5_share_percent:(if $collector_total>0 then (((($sorted[0:5]|map(.total_ms)|add // 0)*10000/$collector_total)|round)/100) else 0 end),
          orchestration_gap_ms:(if (($r.collectors//0)-$collector_total)>0 then (($r.collectors//0)-$collector_total) else 0 end)
        },
        tests:($t|sort_by(.seconds)|reverse),
        workflow:$w
      }
    ' > "$rp_out_json" || return 2
    return 0
}

render_text() {
    color_init
    rp_collector_phase=$(jq -r '.run_phases.collectors // 0' "$rp_out_json")
    rp_collector_sum=$(jq -r '.collector_totals.summed_ms // 0' "$rp_out_json")
    rp_total_phase=$(jq -r '.run_phases.total // 0' "$rp_out_json")
    rp_top5_share=$(jq -r '.collector_totals.top5_share_percent' "$rp_out_json")
    rp_summary_share=$(jq -r '.collector_totals.summary_share_percent' "$rp_out_json")
    {
        printf '%sHost Inventory for Proxmox — Performance Timing%s\n' "$ctitle" "$c0"
        printf '%sRun:%s %s\n' "$ckey" "$c0" "$app_run_dir"
        printf '%sMeasurement:%s passive wall clock only; no additional workload\n' "$ckey" "$c0"
        printf '\n%sRun phases%s\n' "$ctitle" "$c0"
        jq -r '.run_phases|to_entries[]|[.key,.value]|@tsv' "$rp_out_json" |
        while IFS="$(printf '\t')" read -r rp_phase rp_ms; do
            rp_s=$(awk -v m="$rp_ms" 'BEGIN{printf "%.3f",m/1000}')
            printf '  %-18s %9s ms  %8s s\n' "$rp_phase" "$rp_ms" "$rp_s"
        done

        printf '\n%sLargest collector contributors%s\n' "$ctitle" "$c0"
        printf '  %-34s %10s %10s %10s %8s\n' 'collector' 'collect' 'summary' 'total' 'share'
        jq -r --argjson denom "${rp_collector_sum:-0}" '
          .collectors[0:15][] |
          [.collector,.collection_ms,.summary_ms,.total_ms,
           (if $denom>0 then ((.total_ms*10000/$denom|round)/100) else 0 end)] | @tsv
        ' "$rp_out_json" |
        while IFS="$(printf '\t')" read -r rp_name rp_collect rp_summary rp_total rp_share; do
            case "$rp_share" in
                ''|*[!0-9.]* ) rp_color=$cdim ;;
                *) rp_color=$(awk -v p="$rp_share" -v slow="$cslow" -v mid="$cmid" -v fast="$cfast" 'BEGIN{if(p>=15)printf "%s",slow; else if(p>=5)printf "%s",mid; else printf "%s",fast}') ;;
            esac
            printf '  %s%-34s%s %8sms %8sms %8sms %7s%%\n' "$rp_color" "$rp_name" "$c0" "$rp_collect" "$rp_summary" "$rp_total" "$rp_share"
        done

        printf '\n%sConcentration%s\n' "$ctitle" "$c0"
        printf '  Top five collectors: %s%% of summed collector time\n' "$rp_top5_share"
        printf '  Summary rendering:   %s%% of summed collector time\n' "$rp_summary_share"
        rp_gap=$(jq -r '.collector_totals.orchestration_gap_ms // 0' "$rp_out_json")
        printf '  Orchestration gap:   %sms between summed collector totals and collector phase\n' "$rp_gap"

        if jq -e '.tests|length>0' "$rp_out_json" >/dev/null 2>&1; then
            printf '\n%sTest-suite timings%s\n' "$ctitle" "$c0"
            jq -r '.tests[]|[.test,.seconds]|@tsv' "$rp_out_json" |
            while IFS="$(printf '\t')" read -r rp_test rp_seconds; do
                printf '  %-34s %8ss\n' "$rp_test" "$rp_seconds"
            done
        fi

        if jq -e '.workflow|length>0' "$rp_out_json" >/dev/null 2>&1; then
            printf '\n%sComplete-workflow timings%s\n' "$ctitle" "$c0"
            jq -r '.workflow[]|[.phase,.elapsed_ms]|@tsv' "$rp_out_json" |
            while IFS="$(printf '\t')" read -r rp_phase rp_ms; do
                rp_s=$(awk -v m="$rp_ms" 'BEGIN{printf "%.3f",m/1000}')
                printf '  %-24s %9sms  %8ss\n' "$rp_phase" "$rp_ms" "$rp_s"
            done
        fi

        printf '\n%sInterpretation%s\n' "$ctitle" "$c0"
        jq -r '
          .collectors[0:5][] |
          "  - " + .collector + ": " + ((.total_ms/1000)|tostring) +
          " s observed total (" + ((.collection_ms/1000)|tostring) + " s collection, " +
          ((.summary_ms/1000)|tostring) + " s summary)."
        ' "$rp_out_json"
        printf '  - These timings identify where elapsed time was observed; they do not by themselves prove why a command was slow.\n'
        printf '  - Timeout waits, device count, filesystem/device-mapper scale and current host load can all affect a run.\n'
    }
}

render_html() {
    rp_json_escaped=$app_tmp/performance-html.json
    sed 's#</#<\\/#g' "$rp_out_json" > "$rp_json_escaped"
    cat <<'EOF'
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Host Inventory — Performance Timing</title>
<style>
:root{color-scheme:dark;--bg:#0a1017;--panel:#111a25;--panel2:#0e1620;--text:#d9e3ee;--muted:#8291a5;--line:#263446;--cyan:#56d4e8;--green:#75d69c;--amber:#f2c66d;--red:#ff6b78;--blue:#72a7ff}
:root.light{color-scheme:light;--bg:#f2f5f8;--panel:#fff;--panel2:#f8fafc;--text:#17202b;--muted:#607086;--line:#d5dde7;--cyan:#087d95;--green:#237a4c;--amber:#8b6410;--red:#b52335;--blue:#285fbe}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:12px/1.35 ui-monospace,SFMono-Regular,Consolas,"Liberation Mono",monospace}
header{position:sticky;top:0;z-index:5;padding:10px 14px;background:var(--bg);border-bottom:1px solid var(--line)}h1{margin:0;color:var(--cyan);font:700 18px system-ui,sans-serif}
.sub{color:var(--muted);margin:3px 0 8px}.tools{display:flex;gap:6px;flex-wrap:wrap}.tools input{flex:1;min-width:240px;background:var(--panel2);color:var(--text);border:1px solid var(--line);border-radius:6px;padding:6px}
button{background:var(--panel2);color:var(--text);border:1px solid var(--line);border-radius:6px;padding:5px 8px;cursor:pointer}main{max-width:1500px;margin:auto;padding:10px 12px 40px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:6px}.metric,.card{background:var(--panel);border:1px solid var(--line);border-radius:7px;padding:8px}.metric b{display:block;font-size:18px;color:var(--cyan)}
h2{font:700 14px system-ui,sans-serif;color:var(--blue);margin:14px 0 5px}.table{border:1px solid var(--line);border-radius:7px;overflow:hidden}.row{display:grid;grid-template-columns:minmax(220px,2fr) repeat(4,minmax(85px,1fr));border-top:1px solid var(--line);align-items:center}.row:first-child{border-top:0}.row>div{padding:4px 7px;min-width:0}.head{background:var(--panel2);font-weight:bold;color:var(--muted)}.bar{height:6px;background:var(--panel2);border-radius:9px;overflow:hidden}.bar>i{display:block;height:100%;background:var(--cyan)}
.slow{color:var(--red)}.mid{color:var(--amber)}.fast{color:var(--green)}.hidden{display:none!important}.note{color:var(--muted);margin-top:8px}
@media(max-width:720px){.row{grid-template-columns:1.8fr repeat(2,1fr)}.optional{display:none}}
</style></head><body>
<header><h1>Host Inventory — Performance Timing</h1><div class="sub" id="sub"></div><div class="tools"><input id="search" placeholder="Filter collectors/tests/phases…"><button id="theme">Light / dark</button></div></header>
<main><div class="grid" id="metrics"></div><h2>Collector elapsed time</h2><div class="table" id="collectors"></div><div id="extra"></div><p class="note">Passive wall-clock evidence only. No benchmark or measurement workload is started by this report.</p></main>
<script id="data" type="application/json">
EOF
    cat "$rp_json_escaped"
    cat <<'EOF'
</script><script>
const D=JSON.parse(document.getElementById('data').textContent),q=document.getElementById('search');
document.getElementById('sub').textContent=D.run_directory;
const m=document.getElementById('metrics');const metric=(k,v)=>{const x=document.createElement('div');x.className='metric';x.innerHTML=`${k}<b>${v}</b>`;m.appendChild(x)};
const total=D.run_phases.total||0,cp=D.run_phases.collectors||0,cs=D.collector_totals.summed_ms||0;
metric('run_all total',(total/1000).toFixed(2)+' s');metric('collector phase',(cp/1000).toFixed(2)+' s');metric('top 5 share',D.collector_totals.top5_share_percent+'%');metric('summary share',D.collector_totals.summary_share_percent+'%');metric('orchestration gap',(D.collector_totals.orchestration_gap_ms/1000).toFixed(3)+' s');
const c=document.getElementById('collectors');c.innerHTML='<div class="row head"><div>collector</div><div>collect</div><div class="optional">summary</div><div>total</div><div class="optional">share / bar</div></div>';
D.collectors.forEach(x=>{const s=cs?x.total_ms*100/cs:0,cls=s>=15?'slow':s>=5?'mid':'fast',r=document.createElement('div');r.className='row searchable';r.dataset.search=x.collector.toLowerCase();r.innerHTML=`<div class="${cls}">${x.collector}</div><div>${(x.collection_ms/1000).toFixed(3)}s</div><div class="optional">${(x.summary_ms/1000).toFixed(3)}s</div><div>${(x.total_ms/1000).toFixed(3)}s</div><div class="optional">${s.toFixed(2)}%<div class="bar"><i style="width:${Math.min(100,s)}%"></i></div></div>`;c.appendChild(r)});
const extra=document.getElementById('extra');
function simple(title,items,key,val,unit){if(!items.length)return;const h=document.createElement('h2');h.textContent=title;extra.appendChild(h);const t=document.createElement('div');t.className='table';items.forEach(x=>{const r=document.createElement('div');r.className='row searchable';r.dataset.search=String(x[key]).toLowerCase();r.innerHTML=`<div>${x[key]}</div><div>${x[val]}${unit}</div><div class="optional"></div><div></div><div class="optional"></div>`;t.appendChild(r)});extra.appendChild(t)}
simple('Test suite',D.tests,'test','seconds','s');simple('Complete workflow',D.workflow,'phase','elapsed_ms','ms');
q.oninput=()=>{const s=q.value.toLowerCase();document.querySelectorAll('.searchable').forEach(x=>x.classList.toggle('hidden',!x.dataset.search.includes(s)))};
document.getElementById('theme').onclick=()=>document.documentElement.classList.toggle('light');
</script></body></html>
EOF
}

emit_output() {
    case "$app_format" in
        json) rp_rendered=$rp_out_json ;;
        text)
            rp_rendered=$app_tmp/performance.txt
            render_text > "$rp_rendered" || return 2
            ;;
        html)
            rp_rendered=$app_tmp/performance.html
            render_html > "$rp_rendered" || return 2
            ;;
    esac
    if [ -n "$app_output" ]; then
        cp -- "$rp_rendered" "$app_output" || return 2
    else
        cat "$rp_rendered"
    fi
    return 0
}

parse_options "$@" || exit $?
resolve_run || exit $?
build_json || exit $?
emit_output || exit $?
exit 0
