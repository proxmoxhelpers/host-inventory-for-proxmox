# Reporting and Layer 3 evaluation

Host Inventory for Proxmox v0.9.x adds a reporting layer on top of the existing collector and host-map contracts. The collector envelope remains `0.5.0`; the harmonized host-map remains `0.8.9`.

## Trust boundaries

The reporting stack has two intentionally different classes.

Descriptive reports (`build_report_model.sh`, `report_host.sh`, `report_desktop.sh`, and the non-evaluation modes of `report_html.sh`) only reorganize observed host-map evidence. They do not contain PASS/WARN/FAIL verdicts. Their color palette identifies domains such as CPU, memory, storage and networking rather than good/bad status.

The Layer 3 evaluator (`evaluate_desktop.sh`) consumes a host-map only. It does not invoke collectors, `run_all.sh`, firmware tools, tracing tools, measurement programs or host configuration commands. It emits PASS/WARN/FAIL/UNKNOWN findings for the explicit policy target of a single high-performance virtualized desktop. The evaluator's terminal and HTML renderers consume that evaluation JSON.

## Descriptive report styles

`report_host.sh` covers the complete normalized host. `report_desktop.sh` contains only evidence that can materially affect latency, stutter, jitter or smoothness on the host side of a virtualized desktop.

Both support:

- `--short`: the most important facts.
- `--dense-summary`: one highly compact line per domain.
- `--dense`: detailed normalized evidence with minimal vertical decoration.

Input is either an existing `host-map.json` with `--file` or a saved `run_all.sh` directory with `--from-run`. Saved-run mode harmonizes the capture but does not recollect it.

## Interactive HTML

`report_html.sh` emits a self-contained HTML file. There are no external stylesheets, scripts, web fonts, CDNs, analytics calls or network resources.

Modes:

- `all`: exact saved-data `view_all.sh` replay split into interactive collapsible cards.
- `short`
- `dense-summary`
- `dense`
- `desktop-short`
- `desktop-dense-summary`
- `desktop-dense`
- `desktop-evaluation`

The browser UI provides text filtering, collapse/expand, light/dark display and, for the evaluation report, PASS/WARN/FAIL/UNKNOWN filters.

## Evaluation schema 0.1.0

`evaluate_desktop.sh` emits:

- policy identity, objective and explicit runtime thresholds;
- source host, host-map schema and collection window;
- finding counts;
- an ordered `findings[]` list;
- explicit measurement gaps;
- epistemic limits.

Each finding contains:

- `id`
- `category`
- `status`: PASS, WARN, FAIL or UNKNOWN
- `severity`
- `confidence`
- `title`
- `scope`
- `evidence[]`
- `rationale`
- `recommendation`

Missing evidence must produce UNKNOWN where the rule depends on that evidence. A runtime-window sample cannot be promoted to a permanent configuration conclusion. Historical/current-boot evidence remains scoped as history. A missing firmware attribute does not become a guessed BIOS toggle.

## Policy coverage

The first desktop policy evaluates CPU isolation and housekeeping, workqueue/service placement, CPU frequency policy, NMI watchdog state, AMD AVIC exposure, GPU/VFIO readiness, GPU IOMMU grouping, ACS override use, HugeTLB/KSM/swap state, sampled paging and I/O pressure, PVE storage fullness, normalized storage errors and OOM history, NIC EEE/coalescing, HDA power saving, thermal headroom/throttle evidence, security-mitigation posture, and direct host/guest measurement gaps.

Recommendations are advisory and evidence-scoped. They are not automatically applied. Potentially intrusive or security-reducing changes are not performed by the suite.

## Measurement boundary

The evaluator deliberately leaves direct host latency and guest frame pacing as UNKNOWN until measured. Static inventory cannot prove deterministic frame time. The opt-in measurement tools remain separate from `run_all.sh`, and intrusive tracing still requires explicit acknowledgement.

## Complete workflow and passive timing

v0.9.2 adds `run_complete.sh` as a convenience/orchestration layer. The default command:

```sh
./run_complete.sh
```

runs the full test suite, performs one fresh inventory capture, harmonizes that capture once, and emits the complete text and HTML report set under `RUN_DIR/reports/`.

The wrapper reuses the single generated `host-map.json` for normalized reports. This avoids repeated harmonization of the same capture while preserving the evaluator boundary: evaluation still consumes host-map evidence only.

`run_all.sh` records passive wall-clock timing in `collector-timings.tsv` and `run-timings.tsv`. `run_complete.sh` adds `workflow-timings.tsv`. `report_performance.sh` renders those existing timing artifacts as text, JSON or self-contained interactive HTML. The performance report does not call collectors, benchmark devices, or invoke any opt-in measurement tool.

Timing values are observations of one run. They can include timeout waits, current host load, process startup cost, device count and renderer cost. A long observed collector duration identifies where elapsed time was spent; it does not by itself establish why that collector was slow.

