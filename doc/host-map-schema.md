# Harmonized Host Map Schema v0.8.9

`harmonize_host.sh` consumes one `run_all.sh` output directory and emits one descriptive cross-collector model. Collector envelopes remain schema `0.5.0`; the harmonized model has its own schema version, `0.8.9`.

## Top-level contract

```json
{
  "schema_version": "0.8.9",
  "model": "host-map",
  "generated_at": "ISO timestamp",
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
  "virtualization_stack": {},
  "irq_activity": {},
  "runtime_pressure": {},
  "kernel_events": {},
  "guest_runtime_detail": {},
  "kernel_housekeeping": {},
  "pm_qos": {},
  "desktop_io_path": {},
  "latency_sample": {},
  "peripherals": {},
  "thermal_power": {},
  "correlations": {},
  "limitations": []
}
```

## Source provenance

`source` distinguishes `saved-run`, `live-ephemeral`, and `test-fixture` inputs. A live ephemeral model intentionally stores `directory: null` because the temporary run directory is removed after rendering.

`source.collector_provenance` contains one record per collector with the collector name, its exact `collected_at` timestamp, collector schema version and collector error count. This preserves the fact that dynamic IRQ, guest, storage, network and thermal observations are not simultaneous.

## Validation

Strict mode requires all 38 collectors for a current v0.8.9/v0.8.10/v0.8.11/v0.8.12/v0.8.13/v0.8.14/v0.9.0/v0.9.1/v0.9.2 capture, a consistent hostname and a failure-free manifest. Saved v0.8.7/v0.8.8 captures retain their 32-collector contract, v0.8.5/v0.8.6 captures retain their 26-collector contract, and historical core captures remain replayable with the original 14-collector contract. `--allow-partial` retains missing collectors explicitly.

## CPU and runtime scheduling

The CPU model preserves physical cores, SMT siblings, NUMA, isolation, cpufreq/idle, workqueue masks and IRQ distribution.

For each running QEMU VM, `proxmox.virtual_machines[].runtime` may include point-in-time `/proc` evidence:

- QEMU process `Cpus_allowed_list`;
- every QEMU task TID, `comm`, allowed CPU list and scheduler policy/priority when exposed;
- normalized roles: `emulator-main`, `vcpu`, `vhost`, `iothread`, `io-uring-worker`, `helper`;
- vCPU index when the task name exposes `CPU N/KVM`;
- matching `vhost-<qemu-pid>` kernel threads;
- grouped runtime affinity summaries.

This is observation only. Configured `affinity` and actual runtime task affinity remain separate fields.

## QEMU active config and snapshots

The active QEMU configuration is defined as top-level `key: value` lines before the first `[snapshot-name]` section. Snapshot sections cannot override active CPU, memory, disk, network or firmware fields. `config_scope.snapshot_names` and `snapshot_count` preserve their existence without merging historical values into current configuration.


## Virtualization stack

`virtualization_stack` preserves `/dev/kvm` presence/permissions, KVM/KVM-vendor/VFIO/vhost module parameters, selected CPU virtualization flags, io_uring policy, KVM debugfs presence and read-only userspace version/kernel-message probes. These are observations only; CPU flags do not prove a literal firmware toggle and no debugfs facility is enabled by the collector.

## PCI / MSI / IRQ

Each PCI record preserves the collected `msi_irqs` array from `/sys/bus/pci/devices/<BDF>/msi_irqs/*` when available. This is the configured vector inventory. `/proc/interrupts` remains a point-in-time observation and is correlated by exact MSI/MSI-X BDF descriptor when the descriptor contains the PCI BDF. Source-name matching is only a fallback.

The model therefore distinguishes configured vectors from observed interrupt lines. CPU-direct versus chipset attachment and literal firmware Above-4G state remain uninferred.

## Storage

Storage joins Proxmox storage -> LVM/LVM-thin or mount -> backing base block device. `block_queues[].device_path` is the resolved `/sys/block/<device>/device` ancestry. When that path contains one or more PCI BDFs, the harmonizer uses the last observed BDF as the closest PCI controller ancestor and records `pci_correlation_method: sysfs-block-device-ancestry`.

This supports SATA/SCSI controller correlation without inferring a controller from device names. NVMe controller sysfs remains a fallback for older captures.

## Network

Physical NICs join sysfs BDF, link/IOMMU state, configured MSI vectors, point-in-time IRQ placement, queue RPS/XPS and ethtool evidence.

Bridge objects separate:

- configured QEMU guests;
- running QEMU guests;
- configured LXC guests;
- running LXC guests.

Each configured guest network entry includes the expected TAP/veth interface and whether that runtime interface was observed in the network collector.

## LXC

`proxmox.containers` joins `pct list` status with captured `/etc/pve/lxc/<VMID>.conf` and normalizes CPU cores/cpulimit/cpuset, memory/swap, rootfs/mounts, features/unprivileged state and network bridge/runtime-veth evidence. `status_only_containers` preserves status entries for which no config was captured.

## GPU

GPU records retain multifunction siblings, current driver, IOMMU group, negotiated/max link, configured MSI vectors, point-in-time IRQ placement and VFIO observations. No passthrough policy judgment is emitted.

## Epistemic limits

The model still does not infer physical CPU-lane versus chipset PCI attachment or literal firmware toggle state. QEMU task/vhost affinity and `/proc/interrupts` are point-in-time observations. Older captures can lack newer additive evidence; absence is not converted into a negative conclusion.


## Runtime CPU placement additions in 0.8.3

For running QEMU VMs, `runtime` now separates the raw kernel task affinity from
the online-runnable intersection:

```json
{
  "process_cpus_allowed_list": "0-31",
  "process_online_cpus_allowed_list": "0-15",
  "cgroup": {
    "path": "/qemu.slice/102.scope",
    "cpuset_cpus": null,
    "cpuset_cpus_effective": "0-15",
    "cpuset_cpus_effective_online": "0-15",
    "cpu_weight": "100",
    "cpu_max": "max 100000"
  }
}
```

Each QEMU thread has `cpus_allowed_list`, `online_cpus_allowed_list`, and one of
the descriptive roles `emulator-main`, `vcpu`, `vhost`, `iothread`,
`io-uring-worker`, or `helper`.

Running LXC records gain the same process/cgroup runtime shape when their init
PID can be observed. Missing runtime evidence remains `observed:false`; it is
not converted into an unrestricted/limited conclusion.


## Parent-preserving optional joins (introduced in 0.8.4)

Optional correlation failure never removes a successfully collected parent
entity. A configured VM without runtime evidence remains a VM with
`runtime.observed:false`; the same rule applies to LXC runtime. Physical NICs,
GPUs, NVMe controllers, interrupt-source records and Proxmox storage objects
remain present when an optional PCI/IRQ/storage match is unavailable, with the
join fields left null/empty as appropriate.

`proxmox.guest_counts` distinguishes configured inventory and current runtime:

```json
{
  "configured_qemu": 14,
  "running_qemu": 3,
  "configured_lxc": 12,
  "running_lxc": 8
}
```

## Presence-aware cgroup evidence (introduced in 0.8.4)

Fresh collectors record raw cgroup-v2 values and file-presence booleans. The
normalized cgroup object therefore includes states such as:

```json
{
  "cpuset_cpus_present": true,
  "cpuset_cpus": "",
  "cpuset_cpus_state": "empty/inherited",
  "cpuset_cpus_effective_present": true,
  "cpuset_cpus_effective": "0-15",
  "cpuset_interface_state": "exposed"
}
```

If both cpuset files are explicitly absent in a fresh capture,
`cpuset_interface_state` is `not-exposed`. If the capture predates the presence
booleans, the state is `unknown`; the current model does not retroactively assume either
inheritance or absence.


## Extended observation domains in 0.8.5

The 0.8.5 host map adds descriptive evidence from eleven new collectors:

- `cpu-firmware-ras`: per-CPU loaded microcode, vulnerability files, EDAC and machine-check evidence;
- `acpi-platform`: ACPI table inventory, selected APIC/IVRS/DMAR/MCFG/SRAT/SLIT/FADT/HPET dumps and SMBIOS platform data;
- `firmware-settings`: Linux firmware-attributes and `fwupdmgr get-bios-settings` output when firmware exposes it;
- `irq-activity`: a passive one-second hardware IRQ and softirq delta sample;
- `pcie-advanced`: locality masks, runtime power, D3cold, reset methods, SR-IOV, AER counters and capability text including ASPM/LTR/ACS/ReBAR evidence;
- `storage-health-power`: advanced block queue fields, SMART, NVMe identify/health and read-only feature probes such as APST/interrupt coalescing/queue counts;
- `network-advanced`: physical NIC RSS, EEE, pause, queue/ring/coalescing/statistics and RPS/XPS evidence;
- `usb-input-audio`: USB/HID/input/ALSA topology with sysfs PCI-controller ancestry where observable;
- `memory-hardware`: SMBIOS DIMM information, optional SPD decode and EDAC CE/UE counters;
- `timers-watchdogs`: clocksource, clockevents, NMI/lockup watchdog settings, RTC/HPET and relevant boot log evidence;
- `runtime-pressure`: passive PSI/load/context-switch/page-fault/swap activity sampling.

These domains are observations, not policy. A passive sample describes only its collection interval. Firmware/manual-derived facts are not converted into observed BIOS toggle state unless the running firmware exposes the literal setting through a supported interface.


## Final host-side latency audit domains in 0.8.7

The 0.8.7 host map preserves six additional collector envelopes as descriptive top-level domains:

- `kernel_events` — categorized current-boot reliability/event history including OOM, lockup/stall, RAS/MCE, IOMMU/AER, storage, network, thermal and kernel-warning evidence;
- `guest_runtime_detail` — QEMU process/task scheduling, schedstat/context switches, memory residency/THP/NUMA maps and cgroup CPU/memory/I/O/PSI evidence;
- `kernel_housekeeping` — kernel-thread placement, workqueue masks, local timer/IPI and softirq evidence;
- `pm_qos` — CPU/device PM-QoS and runtime-power evidence plus `/dev/cpu_dma_latency` holders;
- `desktop_io_path` — display/VT, USB endpoint and runtime-power/LPM, audio power, interactive network policy and QEMU device-model evidence;
- `latency_sample` — bounded passive per-CPU/IRQ/softirq/IPI/block/NIC/QEMU/frequency/PSI/paging deltas.

These fields preserve the collector data rather than assigning policy status. A passive sample is point-in-time evidence only.

## Capture-generation compatibility

The model schema is always `0.8.9` when emitted by this release, but source completeness is preserved in `validation` and provenance. Strict replay recognizes four source contracts: current 38-domain v0.8.9/v0.8.10/v0.8.11/v0.8.12/v0.8.13/v0.8.14/v0.9.0/v0.9.1/v0.9.2, 32-domain v0.8.7/v0.8.8, 26-domain v0.8.5/v0.8.6, and historical 14-domain core captures. Later-domain fields for older captures remain unavailable and are not inferred.


## Observation-depth model in 0.8.9

v0.8.9 adds six depth collector domains and promotes the harmonized schema to `0.8.9`. The host map retains those envelopes and adds three derived descriptive structures:

- `topology_graph`: typed nodes/edges across CPU/core/cache/NUMA, IOMMU groups, PCI, IRQ, block, network, USB, display, sound and QEMU entities. `integrity` records referential validity; optional joins must never erase parent nodes.
- `capability_matrix`: capability versus current-state evidence for resctrl/cache QoS, CPU PMU/frequency residency, IOMMU/remapping/group metadata, PCIe ACS/ATS/PRI/PASID/TPH/ReBAR/SR-IOV, display/VRR/EDID, audio, network and virtualization features.
- `evidence_catalog`: path-aware provenance entries for all 38 collector domains plus derived graph/capability layers, including source collectors, path prefixes, scope, confidence, stability, collector presence/error count and capture time.

Kernel-event records are semantically deduplicated/classified and can carry VM/device correlation where identifiers are directly recoverable. ACPI decoding, upstream PCIe paths, VM virtual-device options and VM network-to-vhost paths remain evidence/correlation, not policy evaluation.
