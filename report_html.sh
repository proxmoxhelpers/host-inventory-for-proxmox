#!/bin/sh
# ============================================================
# report_html.sh
# Self-contained interactive HTML reports for saved Host Inventory data.
#
# Version:
#   0.9.2
# ============================================================
app_name=report_html
app_version=0.9.2
app_mode=short
app_file=
app_from_run=
app_output=
app_temp=
app_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || exit 2
cleanup() { [ -n "$app_temp" ] && [ -d "$app_temp" ] && rm -rf -- "$app_temp"; }
trap cleanup EXIT HUP INT TERM
usage() {
cat <<'EOF'
report_html.sh - self-contained interactive HTML report

Usage:
  ./report_html.sh --from-run RUN_DIR --mode all --output host-all.html
  ./report_html.sh --from-run RUN_DIR --mode short --output host-short.html
  ./report_html.sh --from-run RUN_DIR --mode dense-summary --output host-dense-summary.html
  ./report_html.sh --from-run RUN_DIR --mode dense --output host-dense.html
  ./report_html.sh --from-run RUN_DIR --mode desktop-short --output desktop-short.html
  ./report_html.sh --from-run RUN_DIR --mode desktop-dense-summary --output desktop-summary.html
  ./report_html.sh --from-run RUN_DIR --mode desktop-dense --output desktop-dense.html
  ./report_html.sh --from-run RUN_DIR --mode desktop-evaluation --output desktop-evaluation.html

Options:
  --mode MODE       all, short, dense-summary, dense, desktop-short,
                    desktop-dense-summary, desktop-dense, desktop-evaluation.
  --file FILE       Existing host-map.json (all mode requires --from-run).
  --from-run DIR    Saved inventory run.
  --output FILE     HTML output path (required).
  --help            Show help.
  --version         Show version.

The HTML is fully self-contained: no network, CDN or external JavaScript.
EOF
}
while [ "$#" -gt 0 ]; do
    case "$1" in
        --mode) shift; [ "$#" -gt 0 ] || { printf 'ERROR: --mode requires a value.\n' >&2; exit 2; }; app_mode=$1 ;;
        --file) shift; [ "$#" -gt 0 ] || { printf 'ERROR: --file requires a path.\n' >&2; exit 2; }; app_file=$1 ;;
        --from-run) shift; [ "$#" -gt 0 ] || { printf 'ERROR: --from-run requires a directory.\n' >&2; exit 2; }; app_from_run=$1 ;;
        --output) shift; [ "$#" -gt 0 ] || { printf 'ERROR: --output requires a path.\n' >&2; exit 2; }; app_output=$1 ;;
        --help|-h) usage; exit 0 ;;
        --version) printf '%s %s\n' "$app_name" "$app_version"; exit 0 ;;
        *) printf 'ERROR: Unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done
case "$app_mode" in
    all|short|dense-summary|dense|desktop-short|desktop-dense-summary|desktop-dense|desktop-evaluation) ;;
    *) printf 'ERROR: unsupported mode: %s\n' "$app_mode" >&2; exit 2 ;;
esac
[ -n "$app_output" ] || { printf 'ERROR: --output is required.\n' >&2; exit 2; }
[ -n "$app_file" ] && [ -n "$app_from_run" ] && { printf 'ERROR: choose --file or --from-run.\n' >&2; exit 2; }
[ -n "$app_file$app_from_run" ] || { printf 'ERROR: --file or --from-run is required.\n' >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { printf 'ERROR: jq is required.\n' >&2; exit 2; }
if [ "$app_mode" = all ] && [ -z "$app_from_run" ]; then
    printf 'ERROR: --mode all requires --from-run so it can reproduce view_all.sh output.\n' >&2
    exit 2
fi
app_temp=$(mktemp -d "${TMPDIR:-/tmp}/hfip-html.XXXXXX") || exit 2
app_data=$app_temp/data.json
app_model=$app_temp/report-model.json
app_eval=$app_temp/evaluation.json
app_map=$app_file

if [ -n "$app_from_run" ] && [ "$app_mode" != all ]; then
    app_map=$app_temp/host-map.json
    "$app_dir/harmonize_host.sh" --from-run "$app_from_run" --output "$app_map" --no-color >/dev/null 2>&1 || {
        printf 'ERROR: failed to harmonize saved run.\n' >&2; exit 2;
    }
fi

case "$app_mode" in
    all)
        app_all=$app_temp/view-all.txt
        "$app_dir/view_all.sh" --from-run "$app_from_run" --skip-prepare --no-install --no-color >"$app_all" 2>"$app_temp/view-all.stderr" || {
            cat "$app_temp/view-all.stderr" >&2; exit 1;
        }
        jq -Rs --arg mode "$app_mode" '{kind:"all",mode:$mode,title:"Host Inventory — All Views",text:.}' "$app_all" >"$app_data" || exit 1
        ;;
    desktop-evaluation)
        "$app_dir/evaluate_desktop.sh" --file "$app_map" --output "$app_eval" || exit $?
        jq --arg mode "$app_mode" '{kind:"evaluation",mode:$mode,title:"Hypervisor Desktop — Complete Evaluation",evaluation:.}' "$app_eval" >"$app_data" || exit 1
        ;;
    *)
        "$app_dir/build_report_model.sh" --file "$app_map" --output "$app_model" || exit $?
        case "$app_mode" in
            short) app_jq_path='.reports.general.short'; app_title='Host Inventory — Short Summary' ;;
            dense-summary) app_jq_path='.reports.general.dense_summary'; app_title='Host Inventory — Dense Summary' ;;
            dense) app_jq_path='.reports.general.dense'; app_title='Host Inventory — Dense Report' ;;
            desktop-short) app_jq_path='.reports.desktop.short'; app_title='Hypervisor Desktop — Short Latency Summary' ;;
            desktop-dense-summary) app_jq_path='.reports.desktop.dense_summary'; app_title='Hypervisor Desktop — Dense Latency Summary' ;;
            desktop-dense) app_jq_path='.reports.desktop.dense'; app_title='Hypervisor Desktop — Dense Latency Report' ;;
        esac
        jq --arg mode "$app_mode" --arg title "$app_title" --arg path "$app_jq_path" '
          (if $path==".reports.general.short" then .reports.general.short
          elif $path==".reports.general.dense_summary" then .reports.general.dense_summary
          elif $path==".reports.general.dense" then .reports.general.dense
          elif $path==".reports.desktop.short" then .reports.desktop.short
          elif $path==".reports.desktop.dense_summary" then .reports.desktop.dense_summary
          else .reports.desktop.dense end) as $sections |
          {kind:"sections",mode:$mode,title:$title,host:.host,collection:.collection,sections:$sections}
        ' "$app_model" >"$app_data" || exit 1
        ;;
esac

app_tmp_html=$(mktemp "${TMPDIR:-/tmp}/hfip-html-output.XXXXXX") || exit 2
cat >"$app_tmp_html" <<'EOF'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Host Inventory for Proxmox</title>
<style>
:root{color-scheme:dark;--bg:#0b1017;--panel:#111a25;--panel2:#0e1620;--text:#d8e2ee;--muted:#8291a5;--line:#263446;--cyan:#56d4e8;--blue:#72a7ff;--mag:#d695ff;--green:#75d69c;--amber:#f2c66d;--orange:#ff9a76;--red:#ff6b78;--shadow:0 8px 30px #0005}
:root.light{color-scheme:light;--bg:#f2f5f8;--panel:#fff;--panel2:#f8fafc;--text:#17202b;--muted:#607086;--line:#d5dde7;--cyan:#087d95;--blue:#285fbe;--mag:#7b3eaa;--green:#237a4c;--amber:#8b6410;--orange:#a94619;--red:#b52335;--shadow:0 5px 20px #25354a16}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:13px/1.35 ui-monospace,SFMono-Regular,Consolas,"Liberation Mono",monospace}
header{position:sticky;top:0;z-index:5;background:color-mix(in srgb,var(--bg) 90%,transparent);backdrop-filter:blur(10px);border-bottom:1px solid var(--line);padding:10px 14px}
h1{font:700 18px/1.2 system-ui,sans-serif;margin:0;color:var(--cyan)}.sub{color:var(--muted);margin-top:3px}
.toolbar{display:flex;gap:7px;flex-wrap:wrap;margin-top:8px}.toolbar input{min-width:260px;flex:1;background:var(--panel2);border:1px solid var(--line);color:var(--text);padding:6px 8px;border-radius:6px}
button,.chip{background:var(--panel2);border:1px solid var(--line);color:var(--text);padding:5px 8px;border-radius:6px;cursor:pointer}button:hover,.chip:hover{border-color:var(--cyan)}
main{padding:10px 12px 40px;max-width:1800px;margin:auto}.stats{display:flex;gap:7px;flex-wrap:wrap;margin:0 0 8px}.metric{background:var(--panel);border:1px solid var(--line);padding:6px 9px;border-radius:7px;box-shadow:var(--shadow)}.metric b{color:var(--cyan);font-size:15px}
details.card{background:var(--panel);border:1px solid var(--line);border-radius:7px;margin:5px 0;box-shadow:var(--shadow);overflow:hidden}
details.card>summary{cursor:pointer;list-style:none;padding:7px 9px;font:700 13px system-ui,sans-serif;color:var(--blue);background:var(--panel2);display:flex;align-items:center;gap:7px}
details.card>summary::-webkit-details-marker{display:none}.count{margin-left:auto;color:var(--muted);font-weight:500}
.rows{display:grid;grid-template-columns:minmax(150px,230px) 1fr}.row{display:contents}.k,.v{border-top:1px solid var(--line);padding:4px 7px;min-width:0}.k{color:var(--mag);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.v{white-space:pre-wrap;overflow-wrap:anywhere}
.tone-cpu{color:var(--mag)}.tone-virtual,.tone-pci{color:var(--blue)}.tone-gpu,.tone-memory{color:var(--green)}.tone-storage{color:var(--amber)}.tone-network,.tone-display,.tone-peripheral{color:var(--cyan)}.tone-events{color:var(--orange)}
pre{margin:0;padding:8px 10px;white-space:pre-wrap;overflow-wrap:anywhere;color:var(--text);max-height:none}.hidden{display:none!important}
.status{font-weight:800;padding:2px 6px;border-radius:999px;border:1px solid currentColor}.PASS{color:var(--green)}.WARN{color:var(--amber)}.FAIL{color:var(--red)}.UNKNOWN{color:var(--cyan)}
.finding{padding:7px 9px;border-top:1px solid var(--line);display:grid;grid-template-columns:100px 1fr;gap:3px 8px}.finding .label{color:var(--muted)}.finding .action{color:var(--green)}.finding .why{color:var(--text)}.finding .evidence{color:var(--amber)}
.statusbar{display:flex;gap:5px;flex-wrap:wrap}.statusbar .chip.off{opacity:.35}
@media(max-width:720px){.rows{grid-template-columns:1fr}.row{display:block;border-top:1px solid var(--line)}.k,.v{border:0}.k{padding-bottom:0}.v{padding-top:1px}.finding{grid-template-columns:1fr}.toolbar input{min-width:100%}}
@media print{header{position:static}.toolbar{display:none}details.card{break-inside:avoid;box-shadow:none}body{background:#fff;color:#000}}
</style>
</head>
<body>
<header>
<h1 id="title">Host Inventory for Proxmox</h1>
<div class="sub" id="subtitle"></div>
<div class="toolbar">
<input id="search" type="search" placeholder="Filter sections, values, findings…">
<button id="expand">Expand all</button><button id="collapse">Collapse all</button><button id="theme">Light / dark</button>
<span class="statusbar hidden" id="statusbar">
<button class="chip PASS" data-status="PASS">PASS</button><button class="chip WARN" data-status="WARN">WARN</button><button class="chip FAIL" data-status="FAIL">FAIL</button><button class="chip UNKNOWN" data-status="UNKNOWN">UNKNOWN</button>
</span>
</div>
</header>
<main><div class="stats" id="stats"></div><div id="content"></div></main>
<script id="hfip-data" type="application/json">
EOF
# Escape an unlikely literal closing script tag while preserving valid JSON.
sed 's#</#<\\/#g' "$app_data" >>"$app_tmp_html"
cat >>"$app_tmp_html" <<'EOF'
</script>
<script>
const D=JSON.parse(document.getElementById('hfip-data').textContent);
const content=document.getElementById('content'),stats=document.getElementById('stats');
document.getElementById('title').textContent=D.title||'Host Inventory for Proxmox';
const esc=s=>String(s??'unknown').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function card(title,inner,count='',open=true,extra=''){const d=document.createElement('details');d.className='card '+extra;d.open=open;d.innerHTML=`<summary>${esc(title)}<span class="count">${esc(count)}</span></summary>${inner}`;return d}
function metric(k,v,cls=''){const x=document.createElement('div');x.className='metric '+cls;x.innerHTML=`${esc(k)} <b>${esc(v)}</b>`;stats.appendChild(x)}
function renderSections(){
 document.getElementById('subtitle').textContent=`${D.host||''}  ${D.collection?.start||''} → ${D.collection?.end||''}`;
 metric('Sections',D.sections.length); metric('Rows',D.sections.reduce((a,s)=>a+s.rows.length,0));
 D.sections.forEach((s,i)=>{let rows='<div class="rows">'+s.rows.map(r=>`<div class="row"><div class="k">${esc(r.label)}</div><div class="v tone-${esc(r.tone||'')}">${esc(r.value)}</div></div>`).join('')+'</div>';content.appendChild(card(s.title,rows,s.rows.length,i<5));});
}
function renderAll(){
 document.getElementById('subtitle').textContent='Exact saved-data replay of view_all.sh, split into interactive sections';
 let chunks=D.text.split(/\n#{20,}\n\n/).map(x=>x.trim()).filter(Boolean); metric('Views',chunks.length);
 chunks.forEach((x,i)=>{let lines=x.split('\n'),name=(lines.find((v,j)=>j>0&&v.trim()&& !/^=+$/.test(v.trim()))||lines[0]||`View ${i+1}`).trim();content.appendChild(card(name,`<pre>${esc(x)}</pre>`,`${x.split('\n').length} lines`,i<4));});
}
function renderEval(){
 const E=D.evaluation; document.getElementById('subtitle').textContent=`${E.source.host}  ${E.source.collection_window?.start||''} → ${E.source.collection_window?.end||''}  •  ${E.policy.id}`;
 ['fail','warn','unknown','pass'].forEach(k=>metric(k.toUpperCase(),E.summary[k],k.toUpperCase())); metric('High/critical open',E.summary.high_or_critical_open);
 document.getElementById('statusbar').classList.remove('hidden');
 E.findings.forEach((f,i)=>{let inner=`<div class="finding"><div class="label">Status</div><div><span class="status ${f.status}">${f.status}</span> ${esc(f.severity)} severity · ${esc(f.confidence)} confidence</div><div class="label">Evidence</div><div class="evidence">${f.evidence.map(esc).join(' · ')}</div><div class="label">Why</div><div class="why">${esc(f.rationale)}</div><div class="label">Recommendation</div><div class="action">${esc(f.recommendation)}</div><div class="label">Scope / ID</div><div>${esc(f.scope)} · ${esc(f.id)}</div></div>`;content.appendChild(card(`${f.status} — ${f.title}`,inner,f.category,i<8,`finding-card status-${f.status}`));});
 content.appendChild(card('Epistemic limits',`<pre>${esc(E.epistemic_limits.map(x=>'• '+x).join('\n'))}</pre>`,E.epistemic_limits.length,false));
}
if(D.kind==='sections')renderSections();else if(D.kind==='all')renderAll();else renderEval();
document.getElementById('search').addEventListener('input',e=>{let q=e.target.value.toLowerCase();document.querySelectorAll('details.card').forEach(x=>x.classList.toggle('hidden',q&&!x.textContent.toLowerCase().includes(q)))});
document.getElementById('expand').onclick=()=>document.querySelectorAll('details.card:not(.hidden)').forEach(x=>x.open=true);
document.getElementById('collapse').onclick=()=>document.querySelectorAll('details.card').forEach(x=>x.open=false);
document.getElementById('theme').onclick=()=>document.documentElement.classList.toggle('light');
const enabled=new Set(['PASS','WARN','FAIL','UNKNOWN']);
document.querySelectorAll('[data-status]').forEach(b=>b.onclick=()=>{let s=b.dataset.status;if(enabled.has(s)){enabled.delete(s);b.classList.add('off')}else{enabled.add(s);b.classList.remove('off')}document.querySelectorAll('.finding-card').forEach(x=>{let st=[...x.classList].find(c=>c.startsWith('status-'))?.slice(7);x.classList.toggle('hidden',st&&!enabled.has(st))})});
</script>
</body></html>
EOF

mv -- "$app_tmp_html" "$app_output" || exit 1
printf 'HTML report written: %s\n' "$app_output" >&2
exit 0
