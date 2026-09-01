# Host Inventory for Proxmox v0.9.2

A read-only host inventory suite for mapping the hardware, kernel, Proxmox and latency-relevant configuration of a Proxmox VE host.

The project intentionally separates:

1. **Collection** — factual machine-readable observations.
2. **Summary** — factual human-readable presentation.
3. **Harmonization** — implemented cross-collector correlation into `host-map.json`.
4. **Evaluation** — implemented Layer 3 PASS/WARN/FAIL/UNKNOWN comparison against an explicit low-latency virtualized-desktop policy.




## v0.9.2 jq 1.6 reporting compatibility fix

v0.9.2 fixes descriptive report generation on Proxmox hosts using jq 1.6. `build_report_model.sh` no longer uses the jq-reserved binder names `label` or `end`, and `reporting_test.sh` now has a source-level guard for these known jq 1.6 binder hazards.

Collector evidence, collector envelope schema `0.5.0`, host-map schema `0.8.9`, descriptive report-model schema `0.1.0`, desktop-evaluation schema `0.1.0`, replay behavior, evaluator policy, and passive timing semantics are unchanged.

## v0.9.1 complete-workflow and passive profiling release

v0.9.1 keeps collector envelope schema `0.5.0`, host-map schema `0.8.9`, descriptive report-model schema `0.1.0`, and desktop-evaluation schema `0.1.0`.

`run_complete.sh` is the end-to-end entry point:

```sh
./run_complete.sh
```

By default it runs `test/test_all.sh`, stops on any test failure, performs one fresh `run_all.sh` capture, harmonizes that exact capture once, generates every terminal/text report, generates all interactive HTML reports, and writes passive performance timing reports. `--skip-tests` retains the same fresh-collection/report workflow without the test pass. `--from-run DIR` is reports-only replay mode and never recollects the host.

The wrapper deliberately harmonizes once and reuses `host-map.json` for all normalized reports instead of repeatedly harmonizing the same saved run. It also preserves `report-model.json` and `desktop-evaluation.json`.

`run_all.sh` now writes two passive timing artifacts in every fresh run:

- `collector-timings.tsv`: collection, summary-rendering and total elapsed milliseconds per collector.
- `run-timings.tsv`: preparation, collector phase, finalization and total elapsed milliseconds.

`run_complete.sh` adds `reports/workflow-timings.tsv` and generates `performance.txt`, `performance.json`, and self-contained interactive `performance.html`. These timings start no benchmark and no extra hardware probe; they only measure elapsed time around work the suite already performs. The six opt-in measurement tools remain excluded from normal orchestration.

The passive timing report is also independently reusable:

```sh
./report_performance.sh --from-run RUN
./report_performance.sh --from-run RUN --json --output performance.json
./report_performance.sh --from-run RUN --html --output performance.html
```

All generated terminal reports and HTML reports are tied to the same explicit run directory. The complete wrapper avoids parsing its own console output to discover that directory; it chooses the destination first and passes it directly to `run_all.sh`.

## v0.9.0 reporting and desktop-evaluation release

v0.9.0 keeps collector envelope schema `0.5.0` and host-map schema `0.8.9`, and adds two presentation schemas without changing collector evidence: descriptive `report-model` schema `0.1.0` and Layer 3 `desktop-evaluation` schema `0.1.0`.

The new descriptive terminal reporting stack is intentionally verdict-free:

```sh
./report_host.sh --from-run host-inventory-YYYYMMDD-HHMMSS --short
./report_host.sh --from-run host-inventory-YYYYMMDD-HHMMSS --dense-summary
./report_host.sh --from-run host-inventory-YYYYMMDD-HHMMSS --dense

./report_desktop.sh --from-run host-inventory-YYYYMMDD-HHMMSS --short
./report_desktop.sh --from-run host-inventory-YYYYMMDD-HHMMSS --dense-summary
./report_desktop.sh --from-run host-inventory-YYYYMMDD-HHMMSS --dense
```

`report_host.sh` summarizes the complete normalized host model. `report_desktop.sh` is a factual subset containing only evidence relevant to latency, stutter, jitter and smoothness for a virtualized desktop. Domain colors are presentation only and never imply PASS/WARN/FAIL.

`report_html.sh` creates fully self-contained interactive HTML with no CDN, remote JavaScript, remote fonts, or network dependency. It supports search, collapsible sections, expand/collapse controls, light/dark display and evaluation-status filtering:

```sh
./report_html.sh --from-run RUN --mode all --output host-all.html
./report_html.sh --from-run RUN --mode short --output host-short.html
./report_html.sh --from-run RUN --mode dense-summary --output host-dense-summary.html
./report_html.sh --from-run RUN --mode dense --output host-dense.html
./report_html.sh --from-run RUN --mode desktop-short --output desktop-short.html
./report_html.sh --from-run RUN --mode desktop-dense-summary --output desktop-dense-summary.html
./report_html.sh --from-run RUN --mode desktop-dense --output desktop-dense.html
./report_html.sh --from-run RUN --mode desktop-evaluation --output desktop-evaluation.html
```

`--mode all` is a saved-data interactive HTML equivalent of `view_all.sh`. The other modes are generated from the harmonized host-map and therefore keep one coherent capture/provenance model.

Layer 3 is now explicit and separate:

```sh
./evaluate_desktop.sh --from-run RUN --output desktop-evaluation.json
./report_desktop_evaluation.sh --from-run RUN
./report_html.sh --from-run RUN --mode desktop-evaluation --output desktop-evaluation.html
```

`evaluate_desktop.sh` consumes host-map evidence only and never calls a collector or `run_all.sh`. Every finding has `status`, `severity`, `confidence`, `scope`, `evidence`, `rationale` and `recommendation`. Missing evidence becomes `UNKNOWN`. Runtime-window measurements remain scoped as runtime observations; current-boot history is not relabeled as a permanent hardware diagnosis; firmware switches are not inferred from Linux effects. Direct osnoise/timerlat and guest frame-pacing/DPC/ISR evidence remain explicit measurement gaps until measured.

The policy target is a single high-performance virtualized desktop with deterministic frametimes, low long-tail latency and low host interference. Its PASS/WARN/FAIL labels are policy verdicts for that target, not generic Proxmox correctness labels. Security mitigations are not treated as a latency defect and the evaluator does not recommend weakening them.

`test/reporting_test.sh` covers descriptive/evaluative separation, UNKNOWN-on-missing-evidence behavior, the no-live-reprobe evaluator boundary, terminal color/no-color rendering and all eight self-contained HTML modes.

## v0.8.14 saved-run discovery release

v0.8.14 keeps collector envelope schema `0.5.0` and host-map schema `0.8.9`. The v0.8.13 real-host umbrella suite completed successfully with 1,457 validations in 361 seconds (return code 0), using one retained live fixture across later tests.

`view_all.sh --from-run` without a directory now lists saved `host-inventory-*` runs visible from the current working directory and the suite directory, newest first. Each entry reports the saved collector count and whether it is complete for the current 38-view replay. `--list-runs` provides the same explicit discovery mode. Supplying a directory to `--from-run` retains the existing replay behavior.

`view_scripts_test.sh` now covers both replay-ready and incomplete run discovery in addition to the existing 38-pair embedded collector/view parity guard.

## v0.8.13 collector/view parity release

v0.8.13 keeps collector envelope schema `0.5.0` and host-map schema `0.8.9`. Real-host v0.8.12 validation confirmed the repaired `collect_kernel_events.sh` emitted the intended normalized event model, but also exposed that the independently usable `view_kernel_events.sh` still embedded the pre-fix live collection implementation. As a result, saved `run_all.sh` data was correct while a no-argument live `view_all.sh` could still show the old malformed two-event history.

The kernel-event standalone view now embeds the same line-oriented collection and rendering implementation as its collector. `view_scripts_test.sh` also contains a suite-wide parity guard across all 38 collector-backed views, so future domain changes cannot silently update a collector while leaving its standalone live view behind. The saved-data view assertion additionally requires the normalized event counters and cross-source de-duplication fields.

## v0.8.12 kernel-event integrity release

v0.8.12 keeps collector envelope schema `0.5.0` and host-map schema `0.8.9`. It corrects the current-boot kernel-event normalizer after real-host validation exposed two parser defects: an escaped newline token caused whole dmesg/journal blobs to be classified as one event, and the IOMMU fault pattern could match the substring `fault` inside the word `Default`.

Kernel history is now parsed as individual log records, identical dmesg/journal records are counted once, repetitive records are grouped by a bounded normalized signature, and representative evidence plus first/last boot-relative occurrence times are retained. OOM records preserve direct `qemu.slice` VM correlation and can correlate the killed-process line to the same VM when the PID matches within five boot-seconds. Current `dm-*` names remain only low-confidence historical guest hints because device identities can be reused. Generic kernel `WARNING:` records are warnings rather than errors, while actual BUG/Oops/panic/fault records remain errors.

The test suite adds a deterministic mocked kernel-log regression covering line tokenization, cross-source de-duplication, storage-event aggregation, OOM VM correlation, AER initialization, warning severity and the IOMMU `Default` false-positive case.

## v0.8.11 test-efficiency release

v0.8.11 keeps the v0.8.10 observation and harmonization semantics unchanged while reducing redundant live probing in the complete regression suite. Collector envelope schema remains `0.5.0` and host-map schema remains `0.8.9`.

`run_all_test.sh` is the authoritative live pass and still executes all 38 collectors against the current Proxmox host. When `test_all.sh` subsequently runs the extended-domain, depth-domain and collector command tests, it supplies that exact retained live fixture for schema, semantic, renderer and interface validation instead of re-probing the same hardware several more times. Focused tests run directly without a supplied fixture retain their exhaustive live behavior.

This changes test orchestration, not evidence depth: no collector field, observation domain, replay tier, harmonization rule, view contract or measurement safety gate is removed. `test_all.sh` also records elapsed seconds for every focused suite in `timings.tsv` and in the final report so regression cost remains observable.

## v0.8.10 regression-fix release

v0.8.10 carries the 38-domain observation model introduced during v0.8.9 development while retaining collector envelope schema `0.5.0` and host-map schema `0.8.9`. It is an application/regression release, not a new observation-schema generation.

The harmonizer guarantees optional VM disk/network/hostpci token lookups emit an explicit `null` when absent rather than an empty jq stream that can delete a parent entity. Topology-graph IRQ nodes now also include configured PCI MSI/MSI-X vectors that are absent from the point-in-time IRQ inventory, preserving referential integrity without inventing runtime IRQ activity. Semantic tests cover those absent-option cases, configured-vector graph integrity, and host-independent bridge-to-physical-NIC correlation.

Strict replay remains 38-domain for v0.8.9/v0.8.10 captures, 32-domain for v0.8.7/v0.8.8, 26-domain for v0.8.5/v0.8.6, and 14-domain for historical captures. Missing newer evidence remains unavailable rather than inferred.

## v0.8.9 observation-depth release

v0.8.9 expands the normal read-only model from 32 to **38 collector/view domains** and bumps the harmonized host-map schema to **0.8.9**. This is a depth release rather than a new policy layer: collection remains factual and evaluation remains separate.

The six new depth domains cover cache/NUMA/resctrl resource QoS, CPU thermal/performance limits and PMU/frequency residency, IRQ hardware architecture, memory fragmentation/hugepage feasibility, display timing/EDID/VRR state, and security-mitigation performance evidence. Existing domains are also deepened with decoded ACPI topology, upstream PCIe/ACS/ATS/PRI/PASID/TPH evidence, IOMMU group metadata, semantic kernel-event normalization, audio PCM/substream state, VM device-path options, and stronger network-to-vhost correlations.

The harmonizer adds a referentially checked topology graph, a capability/current-state matrix, and a path-aware evidence catalog that records source collectors, evidence scope, confidence, stability and capture time. `compare_hosts.sh` provides descriptive cross-host comparison without assigning policy verdicts.

Compatibility remains explicit: v0.8.9/v0.8.10/v0.8.11/v0.8.12/v0.8.13/v0.8.14/v0.9.0/v0.9.1/v0.9.2 captures use 38 collectors; v0.8.7/v0.8.8 captures replay with their 32-domain contract; v0.8.5/v0.8.6 captures replay with 26 domains; historical core captures retain the original 14-domain contract. Missing newer evidence remains unavailable rather than inferred. The jq 1.6 reserved-variable compatibility guards from v0.8.6/v0.8.8 remain suite-wide.

## v0.8.7 final host-side observation expansion

v0.8.7 expands the normal read-only inventory from 26 to **32 collector/view domains** and bumps the harmonized host-map schema to **0.8.7**. It adds kernel-event history, detailed per-VM runtime scheduling/memory/cgroup evidence, kernel housekeeping/IPI placement, PM-QoS latency constraints, richer desktop I/O-path evidence and a longer passive latency/pressure sample.

The release also adds `view_desktop_vm.sh`, a derived per-VM host-path view, and six explicit `measure_*` programs for opt-in tracing/profiling. Measurement tools are deliberately excluded from `run_all.sh` because tracing and performance counters can perturb the system being measured.

At the v0.8.7 generation, current captures used 32 collectors; v0.8.5/v0.8.6 captures replayed with their 26-domain contract and older core captures with 14 domains. v0.8.9 adds a separate 38-domain current tier while retaining those historical contracts.

## Normal workflow

For a complete validation + collection + reporting pass:

```sh
chmod +x *.sh test/*.sh
sudo ./run_complete.sh
```

This runs the full test suite first, performs one fresh `run_all.sh` capture, harmonizes that capture once, and writes every text/HTML/performance report under the saved run's `reports/` directory.

For collection only:

```sh
sudo ./run_all.sh
```

`run_all.sh` calls `prepare_host.sh` automatically. Preparation checks the complete safe diagnostic-tool set and asks once before installing missing APT packages. Fresh v0.9.1/v0.9.2 runs also contain `collector-timings.tsv` and `run-timings.tsv`; these are passive elapsed-time measurements around work the suite already performs.

## Standalone collectors

Every `collect_*.sh` remains independently usable.

JSON:

```sh
sudo ./collect_cpu_topology.sh > cpu-topology.json
```

Preferred colorized view:

```sh
sudo ./collect_cpu_topology.sh --view
```

Colorized view from an existing JSON result, without probing the host again:

```sh
./collect_cpu_topology.sh --view-file cpu-topology.json
```

Backward-compatible summary aliases remain available:

```sh
sudo ./collect_cpu_topology.sh --summary
./collect_cpu_topology.sh --summary-file cpu-topology.json
```

All standalone collectors support:

```text
--compact
--summary
--summary-file FILE
--view
--view-file FILE
--color
--no-color
--install-missing
--no-install
--help
--version
```

## Collector / summary pairs

| Collector | Human-readable function |
|---|---|
| `collect_platform.sh` | `print_platform_summary` |
| `collect_boot_kernel.sh` | `print_boot_kernel_summary` |
| `collect_cpu_topology.sh` | `print_cpu_topology_summary` |
| `collect_cpu_power_idle.sh` | `print_cpu_power_idle_summary` |
| `collect_pcie_iommu.sh` | `print_pcie_iommu_summary` |
| `collect_gpu_vfio.sh` | `print_gpu_vfio_summary` |
| `collect_isolation_scheduler.sh` | `print_isolation_scheduler_summary` |
| `collect_memory.sh` | `print_memory_summary` |
| `collect_irqs.sh` | `print_irqs_summary` |
| `collect_storage.sh` | `print_storage_summary` |
| `collect_network.sh` | `print_network_summary` |
| `collect_services_background.sh` | `print_services_background_summary` |
| `collect_thermal_power.sh` | `print_thermal_power_summary` |
| `collect_proxmox_host.sh` | `print_proxmox_host_summary` |
| `collect_firmware_settings.sh` | `print_firmware_settings_summary` |
| `collect_acpi_platform.sh` | `print_acpi_platform_summary` |
| `collect_cpu_firmware_ras.sh` | `print_cpu_firmware_ras_summary` |
| `collect_timers_watchdogs.sh` | `print_timers_watchdogs_summary` |
| `collect_pcie_advanced.sh` | `print_pcie_advanced_summary` |
| `collect_memory_hardware.sh` | `print_memory_hardware_summary` |
| `collect_irq_activity.sh` | `print_irq_activity_summary` |
| `collect_runtime_pressure.sh` | `print_runtime_pressure_summary` |
| `collect_storage_health_power.sh` | `print_storage_health_power_summary` |
| `collect_network_advanced.sh` | `print_network_advanced_summary` |
| `collect_usb_input_audio.sh` | `print_usb_input_audio_summary` |
| `collect_virtualization_stack.sh` | `print_virtualization_stack_summary` |
| `collect_latency_sample.sh` | `print_latency_sample_summary` |
| `collect_kernel_housekeeping.sh` | `print_kernel_housekeeping_summary` |
| `collect_pm_qos.sh` | `print_pm_qos_summary` |
| `collect_guest_runtime_detail.sh` | `print_guest_runtime_detail_summary` |
| `collect_desktop_io_path.sh` | `print_desktop_io_path_summary` |
| `collect_kernel_events.sh` | `print_kernel_events_summary` |
| `collect_cache_resource_qos.sh` | `print_cache_resource_qos_summary` |
| `collect_cpu_limits_pmu.sh` | `print_cpu_limits_pmu_summary` |
| `collect_irq_architecture.sh` | `print_irq_architecture_summary` |
| `collect_memory_fragmentation.sh` | `print_memory_fragmentation_summary` |
| `collect_display_timing.sh` | `print_display_timing_summary` |
| `collect_security_mitigations.sh` | `print_security_mitigations_summary` |

Summary functions are descriptive only. They deliberately do not decide whether a setting is ideal.

## Run all

```sh
sudo ./run_all.sh
```

A run creates:

```text
host-inventory-YYYYMMDD-HHMMSS/
  collect_platform.json
  collect_boot_kernel.json
  ...
  collect_proxmox_host.json
  summaries/
    collect_platform.txt
    collect_boot_kernel.txt
    ...
    collect_proxmox_host.txt
  inventory.json
  manifest.json
  summary.txt
```

- `collect_*.json` — individual machine-readable collector envelopes.
- `summaries/*.txt` — individual factual human-readable summaries generated from the saved JSON.
- `inventory.json` — one valid JSON array of successful collectors.
- `manifest.json` — per-command execution status and output filenames.
- `summary.txt` — all collector summaries combined in collection order.
- `logs/` — retained collector/summary diagnostic stderr only when non-empty.

To list saved captures without probing the host:

```sh
./view_all.sh --from-run
# equivalent:
./view_all.sh --list-runs
```

To render the exact saved capture:

```sh
./view_all.sh --from-run host-inventory-YYYYMMDD-HHMMSS
```

A no-argument `view_all.sh` intentionally performs fresh live collection through each standalone view; use `--from-run` after `run_all.sh` when a coherent single capture window is desired.

## Preparation

```sh
sudo ./prepare_host.sh
```

Preparation aggregates safe diagnostic dependencies for the entire suite, shows the missing command→package mapping, and asks once before installation.
`fwupdmgr` and `smartctl` are capability-only probes: if those commands are already installed they are used read-only, but the suite does not auto-offer `fwupd` or `smartmontools` solely for inventory collection because those packages can introduce background service behavior.

Each standalone collector retains the same behavior for only its own dependencies.

Vendor GPU drivers are never installed automatically because doing so merely for inventory could interfere with VFIO-first passthrough design.

## Tests

Run everything:

```sh
./test/test_all.sh
```

Focused tests:

```sh
./test/prepare_host_test.sh
./test/run_all_test.sh
./test/extended_domains_test.sh
./test/depth_domains_test.sh
./test/collectors_test.sh
./test/view_scripts_test.sh
./test/harmonize_host_test.sh
./test/desktop_vm_view_test.sh
./test/compare_hosts_test.sh
./test/reporting_test.sh
./test/run_complete_test.sh
./test/measurement_tools_test.sh
```

### Persistent test results

Standalone tests create timestamped directories such as:

```text
test/results/20260827-111800-run_all_test-12345/
```

`test/test_all.sh` creates one parent result directory and groups every focused test beneath it. Result directories contain the command stdout/stderr, generated inventory artifacts, validation logs and a `report.txt`; `run_all_test.sh` also emits `report.json`. The umbrella suite also writes `timings.tsv` and records total/per-suite elapsed seconds in its final report. Results are intentionally not deleted automatically.

The tests exercise syntax, help/version, JSON collection, compact output, summary/view interfaces, saved-data replay, ANSI behavior, invalid arguments, preparation, complete 38-collector orchestration, passive timing artifacts, harmonization compatibility tiers, reporting/evaluation, the complete workflow wrapper, the derived desktop-VM view, and measurement-tool dry-run/safety gates. In the umbrella suite, the successful `run_all_test.sh` inventory is reused by replay-safe checks so every collector is probed live once rather than repeatedly. Running `collectors_test.sh`, `extended_domains_test.sh` or `depth_domains_test.sh` directly without `HFIP_TEST_FIXTURE_DIR` retains exhaustive direct-live execution. Every test narrates its validation stages and preserves timestamped evidence under `test/results/` instead of deleting temporary output.

## Color policy

Interactive human output is colorized with semantic ANSI roles.

Redirected JSON stays ANSI-free:

```sh
sudo ./collect_platform.sh > platform.json
```

Saved summaries generated by `run_all.sh` are also ANSI-free. Use `--color` to force terminal color and `--no-color`/`NO_COLOR=1` to suppress it.

## Safety

After optional approved package installation, collection and summary rendering are read-only. The suite does not change governors, CPU isolation, IRQ affinity, VFIO binding, boot parameters, storage layout, network configuration or VM configuration.


## v0.5.2 real-host corrections

Results from a real Proxmox 8.4 host exposed a summary-rendering error that the v0.5.1 test did not catch. v0.5.2:

- removes jq syntax that is not accepted by the host's jq version;
- numerically orders CPU frequency policies and IRQs;
- prevents empty TSV fields from shifting network summary columns;
- normalizes empty CPU-isolation evidence to `none`;
- captures collector/summary stderr under the run's `logs/` directory;
- treats a summary with nonzero status or unexpected stderr as a run failure;
- tests `--summary-file` for clean stderr, not merely a non-empty output file.


## v0.5.3 real-host corrections

A v0.5.2 retained test archive exposed two additional correctness issues:

- `run_all_test.sh` reused its persistent `rat_log` pathname as a diagnostic-loop variable. Because POSIX shell variables are global, later test messages were written into a literal wildcard log pathname. The loop now uses a unique private variable and tests explicitly reject literal wildcard diagnostic filenames.
- The standalone `inv_readlink` helper now requires the input to actually be a symlink. GNU `readlink -f` can canonicalize a nonexistent final path component, which previously made absent PCI driver/IOMMU-group links appear as the strings `driver` and `iommu_group`.
- PCIe summaries normalize unbound/no-group/no-link state explicitly.
- IRQ summaries preserve empty effective-affinity fields instead of shifting the NUMA node into the wrong column.
- `run_all_test.sh` now has 11 correctly numbered stages and includes collected-data sanity checks.


## v0.5.4 test/logging cleanup

- `run_all_test.sh` now uses a single `rat_total_stages=11` value, so stage labels render as `[1/11]` through `[11/11]`.
- `run_all.sh` removes its two known routine collector status lines from captured collector stderr before retaining diagnostic logs.
- A collector stderr log is retained only when meaningful diagnostic output remains.
- `run_all_test.sh` verifies diagnostic logs contain no routine collector chatter.


## v0.6.0 ergonomic collector views

Every collector now has a dedicated colorized, clean, complete terminal view.

- `--view` collects live data and renders an ergonomic aspect-specific view.
- `--view-file FILE` renders the same view from a previously saved collector JSON envelope.
- Existing `--summary` and `--summary-file` remain supported as backward-compatible aliases and now render the improved view output.
- Each aspect view uses sectioned layout, aligned key/value fields, focused detail lists, and collector metadata at the end.



## Harmonized host model

v0.8.0 adds a descriptive cross-domain model built from one immutable `run_all.sh` capture.

```sh
sudo ./run_all.sh --output host-inventory-snapshot
./harmonize_host.sh --from-run host-inventory-snapshot --output host-inventory-snapshot/host-map.json
./view_harmonized_host.sh --file host-inventory-snapshot/host-map.json
```

You can also harmonize and render in one command:

```sh
./view_harmonized_host.sh --from-run host-inventory-snapshot
```

`harmonize_host.sh` is strict by default. For current v0.8.9/v0.8.10/v0.8.11/v0.8.12/v0.8.13/v0.8.14/v0.9.0/v0.9.1/v0.9.2 captures it validates all 38 collector envelopes, hostname consistency, and the run manifest before building the model. Saved v0.8.7/v0.8.8 captures retain their 32-collector contract, v0.8.5/v0.8.6 captures retain their 26-collector contract, and historical core captures remain replayable with the original 14-collector contract. For intentionally incomplete captures:

```sh
./harmonize_host.sh --from-run partial-run --allow-partial > host-map.json
```

Missing collectors remain explicit under `validation.missing_collectors` and `limitations`; they are never guessed.

The harmonized model correlates:

- physical cores, SMT siblings, NUMA, isolation, workqueues and effective IRQ placement;
- PCI BDFs, negotiated links, drivers and IOMMU groups;
- configured PCI MSI/MSI-X vectors from sysfs plus point-in-time `/proc/interrupts` BDF/IRQ observations;
- NVMe controller -> block device -> PCI BDF -> IRQ vectors/CPU affinity -> Proxmox storage backing;
- physical NIC -> PCI BDF -> IRQ vectors/CPU affinity -> Linux bridge -> QEMU VM NICs;
- GPU -> multifunction siblings -> IOMMU group -> PCI link -> current driver -> IRQ CPU;
- snapshot-safe active QEMU configuration plus observed QEMU/vCPU/IOThread/vhost/io_uring affinity and cgroup CPU controls for running VMs;
- LXC CPU/memory/rootfs/mount/network configuration plus status, runtime veth presence, and observed init/cgroup CPU controls when available;
- memory, background-service and thermal/power observations in the same host model.

The harmonizer is still **observation/correlation only**. It deliberately does not emit tuning `PASS/WARN/FAIL` judgments.

### Harmonized output schema

The new model has its own schema version, independent of the collector-envelope schema:

```json
{
  "schema_version": "0.8.7",
  "model": "host-map",
  "source": {},
  "validation": {},
  "cpu": {},
  "pci": {},
  "storage": {},
  "network": {},
  "gpu": {},
  "memory": {},
  "proxmox": {},
  "background": {},
  "platform_architecture": {},
  "firmware_settings": {},
  "irq_activity": {},
  "runtime_pressure": {},
  "latency_sample": {},
  "kernel_housekeeping": {},
  "pm_qos": {},
  "guest_runtime_detail": {},
  "desktop_io_path": {},
  "kernel_events": {},
  "peripherals": {},
  "thermal_power": {},
  "correlations": {},
  "limitations": []
}
```

See `doc/host-map-schema.md` for the detailed contract.

### Harmonization tests

```sh
./test/harmonize_host_test.sh
```

The test covers strict/partial validation, snapshot-safe VM parsing, QEMU thread affinity, PCI MSI vector inventory, block-to-PCI ancestry, LXC normalization, configured-vs-runtime network joins, provenance, rendering and failure paths. `test/test_all.sh` includes it.

## Dedicated standalone view programs

v0.7.0 separates the human presentation entry points from the collector names.

Each aspect now has both:

```text
collect_cpu_topology.sh
view_cpu_topology.sh
```

The dedicated `view_*.sh` files are **not wrappers or symlinks**. Each is a self-contained program with its own copy of:

- collection logic;
- dependency detection / optional APT installation;
- JSON serialization;
- semantic ANSI colors;
- the aspect-specific view renderer.

Typical use:

```sh
# Live view; this is the default.
sudo ./view_cpu_topology.sh

# Replay previously collected data.
./view_cpu_topology.sh --file collect_cpu_topology.json

# The dedicated view can still emit the raw collector envelope.
sudo ./view_cpu_topology.sh --json > collect_cpu_topology.json
```

Dedicated views:

```text
view_platform.sh
view_boot_kernel.sh
view_cpu_topology.sh
view_cpu_power_idle.sh
view_pcie_iommu.sh
view_gpu_vfio.sh
view_isolation_scheduler.sh
view_memory.sh
view_irqs.sh
view_storage.sh
view_network.sh
view_services_background.sh
view_thermal_power.sh
view_proxmox_host.sh
view_firmware_settings.sh
view_acpi_platform.sh
view_cpu_firmware_ras.sh
view_timers_watchdogs.sh
view_pcie_advanced.sh
view_memory_hardware.sh
view_irq_activity.sh
view_runtime_pressure.sh
view_storage_health_power.sh
view_network_advanced.sh
view_usb_input_audio.sh
view_virtualization_stack.sh
view_latency_sample.sh
view_kernel_housekeeping.sh
view_pm_qos.sh
view_guest_runtime_detail.sh
view_desktop_io_path.sh
view_kernel_events.sh
```

### View everything

Live:

```sh
sudo ./view_all.sh
```

Replay a previous `run_all.sh` directory:

```sh
./view_all.sh --from-run host-inventory-YYYYMMDD-HHMMSS
```

`view_all.sh` renders the aspects in a fixed logical order and runs suite preparation only once in live mode.

### View tests

The dedicated view test is:

```sh
./test/view_scripts_test.sh
```

It reuses or creates one 32-collector fixture set, tests every collector-backed dedicated `view_*.sh`, copies each view script into an isolated directory to prove it can render as a single standalone file, validates forced/no-color behavior, and tests `view_all.sh` replay orchestration.

`test/test_all.sh` includes the dedicated collector-backed view test plus a separate `desktop_vm_view_test.sh` for the derived per-VM host-path view.


## v0.7.1 ergonomic view refinement

The first real-host `view_all.sh` run confirmed correctness but exposed presentation density in several domains. v0.7.1 keeps the complete JSON evidence unchanged while making the human view easier to scan:

- CPU topology distinguishes present/possible/online/raw-offline CPU sets and treats CPU0's missing `online` sysfs file as `online (fixed)`.
- CPU frequency values are rendered in MHz.
- PCIe is organized into latency-relevant endpoints, bridges/root ports, and complete IOMMU group membership.
- GPU view shows all multifunction slot functions.
- Workqueues are grouped by CPU mask instead of repeated one-per-line masks.
- Memory shows active swap and KSM sharing counters.
- IRQs show effective-affinity distribution plus latency-relevant device IRQ sources instead of a flat dump of every IRQ.
- Storage shows physical devices individually and groups the large device-mapper population by queue profile.
- Network separates physical NICs, host/firewall bridges, and guest/container virtual interfaces.
- Services separate services from timers.
- Thermal view displays actual temperatures, fan RPM, voltage inputs, powercap counters, and the aggregate turbostat sample.
- Proxmox view groups VMs/containers by running state and includes the PVE storage table.
- Dedicated view scripts support `--quiet`; `view_all.sh` uses it to avoid duplicate child banners/progress chatter.


## v0.8.1 live harmonized view

`view_harmonized_host.sh` now follows the same ergonomic convention as the
standalone aspect views: **no input means collect live**.

```sh
sudo ./view_harmonized_host.sh
```

The live path is:

```text
view_harmonized_host.sh
  -> run_all.sh (temporary collection)
  -> harmonize_host.sh
  -> Harmonized Host View
  -> remove private temporary collection
```

Collection/preparation progress is sent to stderr; stdout contains only the
final harmonized view.

Replay remains available:

```sh
./view_harmonized_host.sh --from-run host-inventory-YYYYMMDD-HHMMSS
./view_harmonized_host.sh --file host-map.json
```

Common test-result wrappers are also recognized automatically. These both work:

```sh
./view_harmonized_host.sh --from-run test/results/<run_all_test-result>/
./view_harmonized_host.sh --from-run test/results/<view_scripts_test-result>/
```

The first resolves its `inventory/` child and the second resolves its `fixture/`
child. A broad parent such as `test/results/` is intentionally not guessed when
it can contain multiple independent runs.

Use `--skip-prepare` only when you deliberately want the no-argument live mode
to skip `prepare_host.sh`.


## v0.8.2 model-quality evidence

v0.8.2 strengthens the descriptive model before policy evaluation. Collector envelope schema remains `0.5.0`; the harmonized host-map schema is now `0.8.2`.

New evidence and joins:

- PCI devices collect `/sys/bus/pci/devices/<BDF>/msi_irqs/*` as configured MSI/MSI-X vector inventory.
- Storage block queue objects collect resolved `/sys/block/<device>/device` ancestry. The harmonizer uses the last observed PCI BDF in that path, allowing SATA/SCSI disks to resolve to their PCI controller without guessing.
- Proxmox collection includes `/etc/pve/lxc/*.conf` and point-in-time `/proc` affinity for running QEMU processes, vCPU threads, IOThreads/helpers and matching `vhost-<pid>` kernel threads.
- QEMU config normalization uses only the active top-level config before the first `[snapshot]` section. Snapshot section names/counts are preserved separately.
- Linux bridge records distinguish configured versus currently running QEMU/LXC attachments and record whether the expected TAP/veth runtime interface was observed.
- `source.collector_provenance` records the individual collection timestamp/schema/error count for every collector. Live harmonized views use `source.kind=live-ephemeral` and do not expose a temporary directory that is deleted after rendering.
- Older v0.8.0/v0.8.1 collector captures remain usable as input; evidence introduced in v0.8.2 stays unavailable when it was not collected.


## v0.8.3 runtime-affinity corrections

v0.8.3 closes the final runtime-placement gaps found in the first real-host
v0.8.2 capture.

- `vhost-<QEMU PID>` is now derived from the already observed QEMU task set.
  This avoids the v0.8.2 top-level `/proc` scan that missed non-leader vhost
  thread TIDs.
- QEMU thread roles now distinguish `vhost` and `io-uring-worker` from generic
  helpers.
- Every QEMU task retains its raw `Cpus_allowed_list` and also gains the
  intersection with the host's observed online CPU set.
- Running QEMU records include their actual cgroup-v2 `cpuset.cpus`,
  `cpuset.cpus.effective`, `cpu.weight`, and `cpu.max` controls when exposed.
- Running LXC containers gain point-in-time init-process affinity and cgroup-v2
  CPU controls when `lxc-info` is available.
- Raw CPU masks are never silently rewritten: `0-31` can remain the raw kernel
  task affinity while `0-15` is separately represented as the currently
  runnable online intersection.
- `run_all_test.sh` now uses one `rat_test_version` variable for its header and
  persistent text/JSON reports so those values cannot drift independently.

Collector envelope schema remains `0.5.0`. The harmonized host-map schema is
`0.8.3`.


## v0.8.4 Layer-2 hardening

v0.8.5 freezes the observation/harmonization boundary more carefully before
policy evaluation begins.

The harmonizer now preserves configured guest inventory independently from
runtime observations. A missing QEMU/LXC runtime record, PCI match, IRQ-affinity
record, or storage sub-join can no longer erase the parent entity from
`host-map.json`.

The Proxmox model carries explicit counts:

```text
configured QEMU / running QEMU
configured LXC  / running LXC
```

Cgroup-v2 collection is now presence-aware. For each observed guest cgroup the
collector records whether the following files exist as well as their raw value:

```text
cgroup.controllers
cgroup.subtree_control
cgroup.type
cpuset.cpus
cpuset.cpus.effective
cpuset.mems
cpuset.mems.effective
cpu.weight
cpu.max
```

This allows the host-map/view to distinguish:

```text
not-exposed
empty/inherited
value
unknown (older capture without presence evidence)
```

rather than converting both an absent file and an empty inherited file to the
same `null` value.

The harmonized model schema is `0.8.4`; collector envelope schema remains
`0.5.0`.


## v0.8.5 deep latency/performance observation expansion

v0.8.5 introduced the first deep-observation expansion (26 collectors). v0.8.7 extends that architecture to **32 collectors** for a virtualized desktop where long-tail latency, interrupt placement, firmware behavior, scheduler noise and complete host-side device paths matter.

New standalone collector/view pairs cover:

- CPU loaded microcode, vulnerability state and RAS/EDAC/MCE evidence;
- ACPI/APIC/IOMMU platform architecture and SMBIOS topology;
- literal firmware/BIOS settings when exposed by Linux firmware-attributes or fwupd;
- passive one-second hardware IRQ and softirq activity deltas by CPU;
- advanced PCIe locality, runtime power, D3cold, reset, SR-IOV, AER, ASPM/LTR/ACS/ReBAR evidence;
- SMART/NVMe health, APST/interrupt-coalescing/queue feature probes and advanced block queue controls;
- NIC RSS, EEE, pause, statistics and queue steering;
- USB/HID/input/audio topology with PCI-controller ancestry;
- DIMM/SMBIOS/SPD/EDAC evidence;
- clocksource/clockevents and NMI/lockup watchdog state;
- passive PSI/load/context-switch/page-fault/swap-pressure sampling;
- KVM/QEMU/vhost/VFIO module parameters and virtualization runtime capabilities.

The new passive samplers do **not** generate synthetic load. Their results describe only the sampled interval. Firmware-reported settings remain separate from inferred functional state, and generic Linux PCI topology is still not used to invent CPU-lane versus chipset attachment.

See `doc/extended-observation-domains.md` for the evidence model.


## v0.8.7 final host-side latency audit domains

Six additional read-only collector/view pairs complete the normal host-side observation layer:

- `collect_kernel_events.sh` / `view_kernel_events.sh` — timestamped OOM, lockup/stall, RAS/MCE, IOMMU, AER, storage, network, thermal and kernel warning history.
- `collect_guest_runtime_detail.sh` / `view_guest_runtime_detail.sh` — QEMU task scheduler state, schedstat/context switches, memory residency/THP evidence and cgroup CPU/memory/I/O/PSI statistics.
- `collect_kernel_housekeeping.sh` / `view_kernel_housekeeping.sh` — ksoftirqd/RCU/migration/watchdog/kworker/reclaim/IRQ-thread placement plus local/IPI interrupt evidence.
- `collect_pm_qos.sh` / `view_pm_qos.sh` — CPU/device PM-QoS resume-latency interfaces, runtime PM and `/dev/cpu_dma_latency` holder evidence.
- `collect_desktop_io_path.sh` / `view_desktop_io_path.sh` — host display/VT ownership, USB endpoint intervals, HDA power settings, interactive network policy and active VM device-model configuration.
- `collect_latency_sample.sh` / `view_latency_sample.sh` — a default five-second passive multi-sample window for PSI, scheduling, paging/reclaim/swap and interrupt/softirq deltas. It accepts `--duration` and `--interval`; it never generates synthetic load.

The harmonizer preserves all six domains directly and emits host-map schema `0.8.7`. It keeps separate compatibility tiers for 32-domain v0.8.7, 26-domain v0.8.5/v0.8.6 and historical 14-domain captures.

### Per-desktop-VM host path

`view_desktop_vm.sh` is a derived view over `host-map.json`; it does not probe hardware itself.

```sh
./view_desktop_vm.sh --from-run host-inventory-YYYYMMDD-HHMMSS --vmid 111
./view_desktop_vm.sh --file host-map.json --vmid 111
./view_desktop_vm.sh --file host-map.json --list
```

It places one VM's host-side CPU/runtime affinity, overlapping IRQs, memory pressure, GPU/hostpci, storage, bridge/TAP/network, USB/input/audio, PM-QoS and kernel-noise evidence in one view. It explicitly does not claim guest-side DPC/ISR, Present timing, game-thread scheduling or frame pacing.

### Opt-in measurement layer

The following programs are deliberately separate from collection and are never invoked by `run_all.sh`:

```text
measure_osnoise.sh
measure_timerlat.sh
measure_kvm_exits.sh
measure_qemu_perf.sh
measure_irqsoff.sh
measure_hwlat.sh
```

All support bounded duration and `--dry-run`. `irqsoff` requires `--ack-tracing`; `hwlat` requires `--ack-intrusive`. `rtla` and `linux-perf` are optional preparation dependencies. These tools can perturb the system, so their output is measurement evidence rather than ordinary inventory state. See `doc/measurement-tools.md`.
