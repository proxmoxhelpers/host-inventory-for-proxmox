# Opt-in latency measurement tools

The `measure_*` programs are intentionally separate from normal inventory. They can alter scheduling, consume performance counters, enable tracers, or otherwise perturb the machine being measured. `run_all.sh`, `view_all.sh` and normal collectors never invoke them.

## Programs

| Program | Purpose | Primary facility |
|---|---|---|
| `measure_osnoise.sh` | bounded host-noise measurement | `rtla osnoise` |
| `measure_timerlat.sh` | bounded timer IRQ/thread wakeup latency measurement | `rtla timerlat` |
| `measure_kvm_exits.sh` | KVM VM-exit statistics for a selected VM | `perf kvm stat` |
| `measure_qemu_perf.sh` | bounded QEMU process performance-counter profile | `perf stat` |
| `measure_irqsoff.sh` | trace long interrupt-disabled sections | tracefs `irqsoff` tracer |
| `measure_hwlat.sh` | detect long hardware/firmware stalls | tracefs `hwlat` tracer |

## Safety model

All tools support `--help`, `--version`, bounded `--duration`, and `--dry-run`. CPU and/or VM targeting options are provided where meaningful.

`measure_irqsoff.sh` requires explicit `--ack-tracing` before a real trace. `measure_hwlat.sh` requires explicit `--ack-intrusive` because hwlat deliberately monopolizes a CPU for sampling windows and disables interrupts during portions of the measurement.

The test suite exercises syntax, help/version, dry-run plans, invalid-option rejection and acknowledgement gates. Tests do **not** execute intrusive measurements.

## Dependencies

`rtla` and `linux-perf` are safe optional preparation dependencies. A missing tracing facility, performance counter, debugfs/tracefs mount or kernel configuration remains an unavailable capability rather than causing normal inventory failure.

## Evidence boundary

Measurement output is point-in-time experiment evidence. It is not merged into collector envelopes automatically and must not be treated as a permanent property of the host. A later evaluation/report layer may reference saved measurements explicitly with their duration, CPU/VM target and timestamp.
