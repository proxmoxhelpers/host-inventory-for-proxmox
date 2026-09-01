# Extended latency/performance observation domains

Host Inventory for Proxmox v0.8.14 uses **38 normal collector/view domains** for host-side observation of a latency-sensitive virtualized desktop. Collector envelopes remain schema `0.5.0`; observation remains separate from policy evaluation.

## Evidence classes

The project keeps these evidence classes distinct:

1. **Static host observation** — procfs, sysfs, DMI, ACPI, driver/module and configuration state.
2. **Firmware-reported setting** — literal values exposed by Linux firmware-attributes or `fwupdmgr` when supported.
3. **Passive runtime sample** — bounded counter/pressure deltas without generated workload.
4. **Derived correlation** — joins between observed identifiers such as PCI BDF, IRQ, block device, NIC, USB controller, CPU and guest.
5. **Vendor-documented design** — reference evidence only; never silently promoted into a live BIOS/board observation.
6. **Opt-in measurement** — explicit tracing/profiling that can perturb the host and is excluded from `run_all.sh`.
7. **Evaluation** — Layer 3 PASS/WARN/FAIL/UNKNOWN policy derived from host-map only; never produced by collectors.

## Deep-observation domains introduced in v0.8.5

| Collector | Main evidence |
|---|---|
| `collect_cpu_firmware_ras.sh` | loaded microcode, vulnerability files, EDAC/MCE/RAS evidence |
| `collect_acpi_platform.sh` | ACPI/APIC/IOMMU table inventory, selected table dumps, SMBIOS architecture |
| `collect_firmware_settings.sh` | firmware-attributes and fwupd BIOS settings when exposed |
| `collect_irq_activity.sh` | passive hardware IRQ and softirq deltas by CPU |
| `collect_pcie_advanced.sh` | PCI locality, AER, ASPM/LTR/ACS/ReBAR, reset, D3 and SR-IOV |
| `collect_storage_health_power.sh` | SMART/NVMe health/features, queue controls and SATA/NVMe power state |
| `collect_network_advanced.sh` | RSS, EEE, pause, rings, coalescing, statistics and queue steering |
| `collect_usb_input_audio.sh` | USB/HID/input/ALSA topology and PCI ancestry |
| `collect_memory_hardware.sh` | DIMM/SMBIOS/SPD and EDAC CE/UE evidence |
| `collect_timers_watchdogs.sh` | clocksource/clockevents, NMI/lockup watchdogs and timer evidence |
| `collect_virtualization_stack.sh` | KVM/QEMU/vhost/VFIO module parameters and runtime capabilities |
| `collect_runtime_pressure.sh` | PSI/load/context-switch/page-fault/swap deltas |

## Final host-side audit domains introduced in v0.8.7

| Collector | Main evidence |
|---|---|
| `collect_kernel_events.sh` | current-boot OOM, lockup/stall, RAS/MCE, IOMMU/AER, storage, network, thermal and kernel warning history |
| `collect_guest_runtime_detail.sh` | QEMU scheduler/schedstat/context-switch state, memory residency/THP/NUMA maps and cgroup CPU/memory/I/O/PSI evidence |
| `collect_kernel_housekeeping.sh` | ksoftirqd/RCU/migration/watchdog/kworker/reclaim/IRQ-thread placement, workqueue masks, local timer/IPI and softirq evidence |
| `collect_pm_qos.sh` | CPU/device PM-QoS resume latency, runtime PM and `/dev/cpu_dma_latency` holder evidence |
| `collect_desktop_io_path.sh` | DRM/VT/framebuffer ownership; USB endpoint intervals and runtime power/LPM; HDA power state; bridge/RFS/NAPI/XDP-capable link/tc/nft policy; active QEMU device configs |
| `collect_latency_sample.sh` | default five-second passive sample of PSI, CPU ticks, paging/reclaim/compaction/swap, softirq/IPI, block, NIC, QEMU schedstat/migrations, frequency and optional SMI evidence |

### Passive sample semantics

`collect_latency_sample.sh` defaults to five seconds and accepts `--duration` and `--interval`. Tests may set `HFIP_LATENCY_SAMPLE_DURATION=1`; that does not change the shipped default.

The sampler records deltas rather than synthetic load. It normalizes, where exposed:

- per-CPU user/system/idle/iowait and busy tick deltas;
- context switches and process creation;
- page faults, reclaim, compaction and swap deltas;
- per-softirq-class/per-CPU deltas;
- local timer/IPI interrupt deltas;
- block-device read/write/completion deltas;
- network interface packet/byte/drop/error deltas;
- QEMU sched runtime/wait/timeslice/migration deltas;
- CPU frequency end state/delta;
- PSI samples;
- optional `turbostat` SMI evidence.

A sample describes only its collection window and is never treated as a permanent host property.

### Desktop I/O path semantics

The desktop path collector keeps each host-visible layer separate:

- DRM connector/device and VT/framebuffer ownership;
- USB device/controller ancestry, endpoint address/type attributes, `bInterval`, max packet size, autosuspend, wakeup, USB2 hardware LPM and USB3 U1/U2 LPM where exposed;
- ALSA card inventory and HDA power-save module state;
- network busy polling, RFS, bridge netfilter sysctls, NAPI knobs, `ip -j link` state (including XDP fields when reported), qdisc/tc filter and nftables evidence;
- active QEMU configuration text for device-model correlation.

Guest-side DPC/ISR latency, Windows scheduling, Present/flip timing and frame pacing remain outside host observation.


## Observation-depth domains introduced in v0.8.9

| Collector | Main evidence |
|---|---|
| `collect_cache_resource_qos.sh` | cache sharing, NUMA distances, resctrl capability and already-active group/task/CPU assignments |
| `collect_cpu_limits_pmu.sh` | thermal pressure/throttle evidence, CPU frequency limits and normalized residency, PMU capability inventory |
| `collect_irq_architecture.sh` | IRQ chip/hwirq/type/actions, affinity hints, special/IPI architecture and device-vector context |
| `collect_memory_fragmentation.sh` | buddy/pagetype/zone state, compaction/reclaim/THP counters and hugepage feasibility evidence |
| `collect_display_timing.sh` | DRM connector state, active/supported modes, EDID, link state, VRR and bpc evidence |
| `collect_security_mitigations.sh` | vulnerability/mitigation state and explicit boot controls with performance relevance kept separate from policy |

The v0.8.9 harmonizer additionally builds a referentially checked topology graph; a capability/current-state matrix covering IOMMU, PCIe, resctrl, PMU, display, network, audio and virtualization capabilities; and a path-aware evidence catalog with source, scope, confidence, stability and capture timestamp. `compare_hosts.sh` compares two host maps descriptively.

Existing domains are deepened with ACPI table decoding, PCIe upstream paths plus ACS/ATS/PRI/PASID/TPH evidence, IOMMU group type/reserved-region evidence, semantic kernel-event deduplication/severity/correlation, audio PCM/substream state, QEMU device-path options and VM network-to-vhost-to-NIC correlation.

## Dependencies and safety

All normal collectors are standalone POSIX shell programs and preserve unavailable evidence rather than failing merely because an optional diagnostic tool is missing. Safe optional tools include `acpidump`, `decode-dimms` and `aplay`. `fwupdmgr` and `smartctl` remain capability-only because installing their packages solely for inventory can add service behavior.

`rtla` and `linux-perf` are optional dependencies for the separate measurement layer. Measurement programs are never invoked by `run_all.sh`.

## Compatibility tiers

`harmonize_host.sh` preserves four explicit capture generations:

- **38-domain v0.8.9/v0.8.10/v0.8.11/v0.8.12/v0.8.13/v0.8.14/v0.9.0/v0.9.1/v0.9.2** captures: all current collectors are required in strict mode;
- **32-domain v0.8.7/v0.8.8** captures: the six v0.8.9 depth domains remain unavailable;
- **26-domain v0.8.5/v0.8.6** captures: all v0.8.7 and v0.8.9 additions remain unavailable;
- **14-domain historical core** captures: all later extended domains remain unavailable.

Missing historical evidence stays unavailable; the harmonizer does not fabricate it.
