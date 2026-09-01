#!/bin/sh
# ============================================================
# build_report_model.sh
# Builds a descriptive presentation model from host-map.json.
# It never probes the host and never assigns policy verdicts.
#
# Version:
#   0.9.2
# ============================================================
app_name=build_report_model
app_version=0.9.2
app_file=
app_from_run=
app_output=
app_compact=0
app_temp=
app_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || exit 2

cleanup() { [ -n "$app_temp" ] && [ -d "$app_temp" ] && rm -rf -- "$app_temp"; }
trap cleanup EXIT HUP INT TERM

usage() {
cat <<'EOF'
build_report_model.sh - descriptive report model builder

Usage:
  ./build_report_model.sh --file host-map.json
  ./build_report_model.sh --from-run host-inventory-YYYYMMDD-HHMMSS
  ./build_report_model.sh --from-run DIR --output report-model.json

Options:
  --file FILE       Existing host-map.json.
  --from-run DIR    Harmonize a saved inventory run, then build the report model.
  --output FILE     Write report-model JSON to FILE.
  --compact         Compact JSON.
  --help            Show help.
  --version         Show version.

This program is descriptive only. It does not assign PASS/WARN/FAIL.
EOF
}
while [ "$#" -gt 0 ]; do
    case "$1" in
        --file) shift; [ "$#" -gt 0 ] || { printf 'ERROR: --file requires a path.\n' >&2; exit 2; }; app_file=$1 ;;
        --from-run) shift; [ "$#" -gt 0 ] || { printf 'ERROR: --from-run requires a directory.\n' >&2; exit 2; }; app_from_run=$1 ;;
        --output) shift; [ "$#" -gt 0 ] || { printf 'ERROR: --output requires a path.\n' >&2; exit 2; }; app_output=$1 ;;
        --compact) app_compact=1 ;;
        --help|-h) usage; exit 0 ;;
        --version) printf '%s %s\n' "$app_name" "$app_version"; exit 0 ;;
        *) printf 'ERROR: Unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done
[ -n "$app_file" ] && [ -n "$app_from_run" ] && { printf 'ERROR: choose --file or --from-run, not both.\n' >&2; exit 2; }
[ -n "$app_file$app_from_run" ] || { printf 'ERROR: --file or --from-run is required.\n' >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { printf 'ERROR: jq is required.\n' >&2; exit 2; }

if [ -n "$app_from_run" ]; then
    [ -d "$app_from_run" ] || { printf 'ERROR: saved run not found: %s\n' "$app_from_run" >&2; exit 2; }
    app_temp=$(mktemp -d "${TMPDIR:-/tmp}/hfip-report.XXXXXX") || exit 2
    app_file=$app_temp/host-map.json
    "$app_dir/harmonize_host.sh" --from-run "$app_from_run" --output "$app_file" --no-color >/dev/null 2>&1 || {
        printf 'ERROR: could not harmonize saved run: %s\n' "$app_from_run" >&2; exit 2;
    }
fi
[ -r "$app_file" ] || { printf 'ERROR: host-map not readable: %s\n' "$app_file" >&2; exit 2; }
jq -e '.model=="host-map" and (.schema_version|type=="string")' "$app_file" >/dev/null 2>&1 || {
    printf 'ERROR: input is not a valid host-map.\n' >&2; exit 2;
}

app_jq_args=
[ "$app_compact" -eq 1 ] && app_jq_args=-c
app_tmpout=
if [ -n "$app_output" ]; then
    app_tmpout=$(mktemp "${TMPDIR:-/tmp}/hfip-report-model.XXXXXX") || exit 2
fi

jq $app_jq_args '
def val:
  if . == null then "unknown"
  elif type=="boolean" then (if . then "yes" else "no" end)
  elif type=="array" then (map(if .==null then "unknown" else tostring end)|join(", "))
  else tostring end;
def v: val;
def row($row_label;$row_value;$row_tone): {label:$row_label,value:($row_value|val),tone:$row_tone};
def sec($id;$title;$rows): {id:$id,title:$title,rows:$rows};
def arr($x): if ($x|type)=="array" then $x else [] end;
def psi10($s):
  if ($s|type)!="string" then null
  else ([try ($s|capture("some avg10=(?<n>[0-9.]+)").n|tonumber) catch empty][0] // null)
  end;
def mib($kb): if $kb==null then null else (($kb/1024)|floor|tostring)+" MiB" end;
def gibbytes($b): if $b==null then null else (($b/1073741824*10|round)/10|tostring)+" GiB" end;
def pctnum($s): if ($s|type)=="string" then ([try ($s|capture("(?<n>[0-9.]+)%").n|tonumber) catch empty][0] // null) else null end;
def cpuset_text($x): if (($x.cpus//[])|length)==0 then "none" else (($x.raw//($x.cpus|map(tostring)|join(",")))|tostring) end;
def huge_total($x): ([ $x[]? | (.values.nr_hugepages//0) | tonumber ] | add // 0);

. as $h |
($h.source.hostname // "unknown") as $host |
($h.source.collection_window.start // "unknown") as $start |
($h.source.collection_window.end // "unknown") as $capture_end |
(arr($h.cpu.power.scaling_drivers)) as $drivers |
(arr($h.cpu.power.governors)) as $govs |
(arr($h.gpu.devices)) as $gpus |
(arr($h.storage.physical_block_devices)) as $disks |
(arr($h.storage.pve_storages)) as $pvest |
(arr($h.network.physical_interfaces)) as $nics |
(arr($h.network.bridges)) as $bridges |
(arr($h.proxmox.virtual_machines)) as $vms |
(arr($h.proxmox.containers)) as $lxcs |
(arr($h.kernel_events.events)) as $events |
(arr($h.background.important_units)) as $units |
(arr($h.pci.devices)) as $pcidev |
(arr($h.pci.iommu_groups)) as $groups |
(arr($h.irq_architecture.irqs)) as $irqarch |
(arr($h.peripherals.usb_devices)) as $usb |
(arr($h.peripherals.sound_cards)) as $sound |
(arr($h.display_timing.connectors)) as $conn |
(arr($h.evidence_catalog)) as $evidence |
{
  schema_version:"0.1.0",
  model:"report-model",
  source_host_map_schema:($h.schema_version // "unknown"),
  generated_at:($h.generated_at // "unknown"),
  host:$host,
  collection:{start:$start,end:$capture_end,kind:($h.source.kind // "unknown"),collectors:($h.validation.present_collectors // 0)},
  reports:{
    general:{
      short:[
        sec("identity";"Host";
          [row("Host";$host;"identity"),
           row("Capture";($start+" → "+$capture_end);"identity"),
           row("Proxmox";($h.proxmox.version);"software"),
           row("BIOS";(($h.firmware_settings.bios.vendor//"")+" "+($h.firmware_settings.bios.version//"")+" "+($h.firmware_settings.bios.date//""));"firmware")]),
        sec("compute";"Compute";
          [row("CPU";(($h.cpu.physical_core_count|v)+" cores / "+($h.cpu.logical_cpu_count|v)+" threads / SMT="+($h.cpu.smt.active|v));"cpu"),
           row("NUMA";(arr($h.cpu.numa_nodes)|length);"cpu"),
           row("Power";(($drivers|join(","))+" / "+($govs|join(","))+" / boost="+($h.cpu.power.boost|v));"cpu"),
           row("Isolation";("isolated="+cpuset_text($h.cpu.isolation.isolated)+" nohz_full="+cpuset_text($h.cpu.isolation.nohz_full)+" rcu_nocb="+cpuset_text($h.cpu.isolation.rcu_nocb));"cpu")]),
        sec("virtual";"Virtualization";
          [row("KVM";($h.capability_matrix.virtualization.kvm_available);"virtual"),
           row("IOMMU";((($groups|length)|tostring)+" groups; interrupt-remap="+($h.capability_matrix.iommu.interrupt_remapping_observed|v));"virtual"),
           row("GPU";(if ($gpus|length)>0 then ($gpus|map(.bdf+" "+(.driver//"unknown")+" group="+(.iommu_group//"unknown"))|join(" | ")) else "none observed" end);"gpu"),
           row("Guests";("QEMU "+($h.proxmox.guest_counts.running_qemu|v)+"/"+($h.proxmox.guest_counts.configured_qemu|v)+" running/configured; LXC "+($h.proxmox.guest_counts.running_lxc|v)+"/"+($h.proxmox.guest_counts.configured_lxc|v));"virtual")]),
        sec("io";"I/O";
          [row("Storage";(if ($disks|length)>0 then ($disks|map(.name+" "+(.model//"")+" "+gibbytes(.size))|join(" | ")) else "none" end);"storage"),
           row("PVE storage";(if ($pvest|length)>0 then ($pvest|map(.name+"="+(.status.percent//"unknown"))|join(" | ")) else "none" end);"storage"),
           row("NIC";(if ($nics|length)>0 then ($nics|map(.name+" "+(.driver//"unknown")+" "+(.operstate//"unknown"))|join(" | ")) else "none" end);"network"),
           row("Display";((($h.display_timing.connected_count//0)|tostring)+" connected host-visible connector(s)");"display")]),
        sec("runtime";"Runtime evidence";
          [row("Kernel events";(($h.kernel_events.total_unique_events|v)+" entities / "+($h.kernel_events.total_observations|v)+" observations; errors="+($h.kernel_events.counts_by_severity.error|v)+" warnings="+($h.kernel_events.counts_by_severity.warning|v));"events"),
           row("Pressure";("CPU PSI10="+(psi10($h.runtime_pressure.pressure.cpu.t1)|v)+"% MEM PSI10="+(psi10($h.runtime_pressure.pressure.memory.t1)|v)+"% IO PSI10="+(psi10($h.runtime_pressure.pressure.io.t1)|v)+"%");"runtime"),
           row("Latency sample";(($h.latency_sample.sample.duration_seconds|v)+"s; ctxt="+($h.latency_sample.system_deltas.ctxt|v)+" major-faults="+($h.latency_sample.vmstat_deltas.pgmajfault|v)+" swap-in/out="+($h.latency_sample.vmstat_deltas.pswpin|v)+"/"+($h.latency_sample.vmstat_deltas.pswpout|v));"runtime"),
           row("Thermal";(([ $h.thermal_power.hwmon[]? | select(.name=="k10temp") | .values.temp1_input ][0] // null) as $t | if $t!=null then (($t|tonumber/1000|tostring)+" C Tctl") else "unknown" end);"thermal")])
      ],
      dense_summary:[
        sec("platform";"PLATFORM";
          [row("host / capture";($host+" | "+$start+" → "+$capture_end);"identity"),
           row("PVE / BIOS";(($h.proxmox.version//"unknown")+" | "+($h.firmware_settings.bios.version//"unknown")+" "+($h.firmware_settings.bios.date//""));"software")]),
        sec("cpu";"CPU";
          [row("topology";(($h.cpu.physical_core_count|v)+"C/"+($h.cpu.logical_cpu_count|v)+"T pkg="+($h.cpu.package_count|v)+" numa="+((arr($h.cpu.numa_nodes)|length)|tostring)+" smt="+($h.cpu.smt.active|v));"cpu"),
           row("freq/idle";(($drivers|join(","))+" gov="+($govs|join(","))+" boost="+($h.cpu.power.boost|v)+" clock="+($h.cpu.timers_watchdogs.clocksource.current|v));"cpu"),
           row("isolation";("isolated="+cpuset_text($h.cpu.isolation.isolated)+" nohz="+cpuset_text($h.cpu.isolation.nohz_full)+" rcu="+cpuset_text($h.cpu.isolation.rcu_nocb));"cpu")]),
        sec("virt";"VIRTUALIZATION";
          [row("KVM / AVIC";("kvm="+($h.capability_matrix.virtualization.kvm_available|v)+" avic="+($h.capability_matrix.virtualization.avic_parameter|v)+" nested="+($h.capability_matrix.virtualization.nested_parameter|v));"virtual"),
           row("IOMMU / ACS";((($groups|length)|tostring)+" groups remap="+($h.capability_matrix.iommu.interrupt_remapping_observed|v)+" acs-override="+($h.capability_matrix.pcie.acs_override_configured|v));"virtual"),
           row("GPU / VFIO";(if ($gpus|length)>0 then ($gpus|map(.bdf+":"+(.driver//"?")+"@g"+(.iommu_group//"?"))|join(" ")) else "none" end)+" vfio-loaded="+($h.gpu.vfio.module_loaded|v);"gpu")]),
        sec("memory";"MEMORY";
          [row("THP / KSM";("THP="+($h.memory.transparent_hugepages.enabled_selected|v)+"/defrag="+($h.memory.transparent_hugepages.defrag_selected|v)+" KSM-run="+($h.memory.ksm.run|v));"memory"),
           row("swap / huge";("swap-active="+($h.memory.swap.active|v)+" swappiness="+($h.memory.swap.swappiness|v)+" hugetlb-pages="+(huge_total(arr($h.memory.hugetlb))|tostring));"memory"),
           row("fragmentation";(if (arr($h.memory_fragmentation.buddy_highest_order)|length)>0 then (arr($h.memory_fragmentation.buddy_highest_order)|map((.node|tostring)+"/"+(.zone//"?")+"=o"+(.highest_order_with_free|tostring))|join(" ")) else "unknown" end);"memory")]),
        sec("irq";"IRQ / TIMER";
          [row("IRQ inventory";((arr($h.irq_architecture.irqs)|length|tostring)+" records; remapped-MSI="+([ $h.irq_architecture.irqs[]? | select(.interrupt_remapped_msi==true) ]|length|tostring));"irq"),
           row("watchdogs";("nmi="+($h.cpu.timers_watchdogs.watchdog.nmi_watchdog|v)+" watchdog="+($h.cpu.timers_watchdogs.watchdog.watchdog|v)+" mask="+($h.cpu.timers_watchdogs.watchdog.watchdog_cpumask|v));"irq"),
           row("sample";(($h.irq_activity.sample_seconds|v)+"s softirq top="+(if (arr($h.irq_activity.softirqs)|length)>0 then (arr($h.irq_activity.softirqs)|sort_by(-(.total_delta//0))|.[0:3]|map((.name//"?")+"="+(.total_delta|tostring))|join(" ")) else "unknown" end));"irq")]),
        sec("io";"STORAGE / NETWORK";
          [row("disks";(if ($disks|length)>0 then ($disks|map(.name+":"+(.tran//"?")+":"+(.model//"?"))|join(" ")) else "none" end);"storage"),
           row("PVE utilization";(if ($pvest|length)>0 then ($pvest|map(.name+"="+(.status.percent//"?"))|join(" ")) else "none" end);"storage"),
           row("NICs";(if ($nics|length)>0 then ($nics|map(.name+":"+(.driver//"?")+":"+(.operstate//"?"))|join(" ")) else "none" end);"network"),
           row("bridges";(if ($bridges|length)>0 then ($bridges|map(.name+"<-"+((.ports//[])|join(",")))|join(" ")) else "none" end);"network")]),
        sec("guest";"GUEST / BACKGROUND";
          [row("guests";("QEMU "+($h.proxmox.guest_counts.running_qemu|v)+"/"+($h.proxmox.guest_counts.configured_qemu|v)+" LXC "+($h.proxmox.guest_counts.running_lxc|v)+"/"+($h.proxmox.guest_counts.configured_lxc|v));"virtual"),
           row("QEMU runtime detail";(($h.guest_runtime_detail.qemu_count|v)+" processes; delayacct="+($h.guest_runtime_detail.task_delayacct|v));"virtual"),
           row("important services";(([ $units[]? | select(.state.ActiveState=="active") ]|length|tostring)+" active of "+($units|length|tostring));"background")]),
        sec("runtime";"PRESSURE / EVENTS";
          [row("PSI10";("cpu="+(psi10($h.runtime_pressure.pressure.cpu.t1)|v)+" mem="+(psi10($h.runtime_pressure.pressure.memory.t1)|v)+" io="+(psi10($h.runtime_pressure.pressure.io.t1)|v));"runtime"),
           row("5s sample";("ctxt="+($h.latency_sample.system_deltas.ctxt|v)+" pgmaj="+($h.latency_sample.vmstat_deltas.pgmajfault|v)+" swap="+($h.latency_sample.vmstat_deltas.pswpin|v)+"/"+($h.latency_sample.vmstat_deltas.pswpout|v));"runtime"),
           row("kernel history";(($h.kernel_events.total_unique_events|v)+" entities/"+($h.kernel_events.total_observations|v)+" obs; storage="+($h.kernel_events.occurrences_by_category.storage|v)+" memory="+($h.kernel_events.occurrences_by_category.memory|v));"events")])
      ],
      dense:(
        [
          sec("platform";"Platform / provenance";
            [row("host";$host;"identity"),row("capture";($start+" → "+$capture_end);"identity"),row("model schema";$h.schema_version;"identity"),
             row("PVE";$h.proxmox.version;"software"),row("BIOS";(($h.firmware_settings.bios.vendor//"")+" "+($h.firmware_settings.bios.version//"")+" "+($h.firmware_settings.bios.date//""));"firmware"),
             row("evidence catalog";(($evidence|length|tostring)+" sources");"identity")]),
          sec("cpu";"CPU / topology / frequency";
            [row("topology";(($h.cpu.physical_core_count|v)+" cores "+($h.cpu.logical_cpu_count|v)+" threads pkg="+($h.cpu.package_count|v)+" NUMA="+($h.cpu.numa_nodes|v));"cpu"),
             row("present / online";(($h.cpu.present.raw|v)+" / "+($h.cpu.online.raw|v));"cpu"),
             row("SMT";("active="+($h.cpu.smt.active|v)+" control="+($h.cpu.smt.control|v));"cpu"),
             row("scaling";(($drivers|join(","))+" governors="+($govs|join(","))+" boost="+($h.cpu.power.boost|v));"cpu"),
             row("isolation";("isolated="+cpuset_text($h.cpu.isolation.isolated)+" nohz_full="+cpuset_text($h.cpu.isolation.nohz_full)+" rcu_nocb="+cpuset_text($h.cpu.isolation.rcu_nocb));"cpu")] +
            [ $h.cpu.cores[]? | row(("core "+(.core_id|v));("pkg="+(.package_id|v)+" cpus="+(.cpus|v)+" node="+(.node|v));"cpu") ]),
          sec("pci";"PCI / IOMMU / GPU";
            [row("PCI devices";($pcidev|length);"pci"),row("IOMMU groups";($groups|length);"pci"),
             row("interrupt remapping";$h.capability_matrix.iommu.interrupt_remapping_observed;"pci"),
             row("ACS override";$h.capability_matrix.pcie.acs_override_configured;"pci"),
             row("ReBAR devices";$h.capability_matrix.pcie.rebar_devices;"pci")] +
            [ $gpus[]? | row(("GPU "+(.bdf//"?"));("driver="+(.driver//"?")+" group="+(.iommu_group//"?")+" link="+(.pci.current_link_speed//"?")+" x"+(.pci.current_link_width//"?")+"/"+(.pci.max_link_speed//"?")+" x"+(.pci.max_link_width//"?"));"gpu") ] +
            [ $groups[]? | row(("IOMMU group "+(.group|v));((.members//[])|join(", "));"pci") ]),
          sec("memory";"Memory";
            [row("THP";("enabled="+($h.memory.transparent_hugepages.enabled_selected|v)+" defrag="+($h.memory.transparent_hugepages.defrag_selected|v));"memory"),
             row("KSM";("run="+($h.memory.ksm.run|v)+" shared="+($h.memory.ksm.pages_shared|v)+" sharing="+($h.memory.ksm.pages_sharing|v));"memory"),
             row("swap";("active="+($h.memory.swap.active|v)+" swappiness="+($h.memory.swap.swappiness|v));"memory")] +
            [ $h.memory.hugetlb[]? | row(("HugeTLB "+(.size|v));("total="+(.values.nr_hugepages|v)+" free="+(.values.free_hugepages|v)+" reserved="+(.values.resv_hugepages|v));"memory") ] +
            [ $h.memory_fragmentation.buddy_highest_order[]? | row(("buddy "+((.node|v)|sub(",";""))+"/"+(.zone//"?"));("highest-order="+(.highest_order_with_free|v));"memory") ]),
          sec("storage";"Storage";
            [ $disks[]? | row((.name//"?");((.model//"?")+" "+(.tran//"?")+" "+gibbytes(.size)+" rotational="+(.rota|v));"storage") ] +
            [ $pvest[]? | row(("PVE "+(.name//"?"));((.type//"?")+" "+(.status.status//"?")+" used="+(.status.percent//"?")+" base="+(.backing.base_block//"?")+" pci="+(.backing.pci_bdf//"?"));"storage") ]),
          sec("network";"Network";
            [ $nics[]? | row((.name//"?");("state="+(.operstate//"?")+" driver="+(.driver//"?")+" bdf="+(.bdf//"?")+" mtu="+(.mtu//"?"));"network") ] +
            [ $bridges[]? | row(("bridge "+(.name//"?"));("ports="+((.ports//[])|join(","))+" running-vm="+((.running_vm_guests//[])|length|tostring)+" running-lxc="+((.running_lxc_guests//[])|length|tostring));"network") ]),
          sec("irq";"IRQ / timers";
            [row("clocksource";$h.cpu.timers_watchdogs.clocksource.current;"irq"),row("watchdog";("nmi="+($h.cpu.timers_watchdogs.watchdog.nmi_watchdog|v)+" generic="+($h.cpu.timers_watchdogs.watchdog.watchdog|v));"irq"),
             row("IRQ records";($irqarch|length);"irq")] +
            [ $h.irq_activity.irqs[]? | select((.total_delta//0)>0) | row(("IRQ "+(.irq|v));("delta="+(.total_delta|v)+" source="+(.source//"?"));"irq") ]),
          sec("guests";"Proxmox guests";
            [ $vms[]? | row(("VM "+(.vmid//"?")+" "+(.name//""));("status="+(.status//"?")+" cpu="+(.cpu.cores|v)+" type="+(.cpu.type|v)+" affinity="+(.cpu.affinity|v)+" mem="+(.memory.memory_mib|v)+"MiB hostpci="+((.hostpci//[])|length|tostring));"virtual") ] +
            [ $lxcs[]? | row(("LXC "+(.vmid//"?")+" "+(.name//""));("status="+(.status//"?"));"virtual") ]),
          sec("events";"Kernel reliability history";
            [row("totals";(($h.kernel_events.total_unique_events|v)+" entities / "+($h.kernel_events.total_observations|v)+" observations");"events")] +
            [ $events[]? | select(.severity!="info") | row(("["+(.severity//"?")+"/"+(.category//"?")+"]");(("x"+(.occurrences|v)+" "+(.message//"")));"events") ]),
          sec("peripherals";"Display / USB / audio";
            [row("connectors";(($conn|length|tostring)+" total / "+($h.display_timing.connected_count|v)+" connected");"display"),
             row("USB";($usb|length);"peripheral"),row("sound cards";($sound|length);"peripheral")] +
            [ $conn[]? | row((.name//"?");("status="+(.status//"?")+" VRR="+(.vrr_capable|v)+" active="+(.active|v));"display") ]),
          sec("runtime";"Runtime samples";
            [row("PSI10";("cpu="+(psi10($h.runtime_pressure.pressure.cpu.t1)|v)+" mem="+(psi10($h.runtime_pressure.pressure.memory.t1)|v)+" io="+(psi10($h.runtime_pressure.pressure.io.t1)|v));"runtime"),
             row("1s context switches";$h.runtime_pressure.deltas.context_switches;"runtime"),
             row("5s context switches";$h.latency_sample.system_deltas.ctxt;"runtime"),
             row("5s major faults";$h.latency_sample.vmstat_deltas.pgmajfault;"runtime"),
             row("5s swap in/out";(($h.latency_sample.vmstat_deltas.pswpin|v)+"/"+($h.latency_sample.vmstat_deltas.pswpout|v));"runtime")])
        ]
      )
    },
    desktop:{
      short:[
        sec("scope";"Desktop latency snapshot";
          [row("Scope";"host-side evidence affecting latency, stutter, jitter and smoothness; descriptive only";"identity"),
           row("Capture";($start+" → "+$capture_end);"identity")]),
        sec("cpu";"CPU / scheduling";
          [row("Topology";(($h.cpu.physical_core_count|v)+"C/"+($h.cpu.logical_cpu_count|v)+"T SMT="+($h.cpu.smt.active|v));"cpu"),
           row("Isolation";("isolated="+cpuset_text($h.cpu.isolation.isolated)+" nohz="+cpuset_text($h.cpu.isolation.nohz_full)+" rcu="+cpuset_text($h.cpu.isolation.rcu_nocb));"cpu"),
           row("Power";(($drivers|join(","))+" gov="+($govs|join(","))+" boost="+($h.cpu.power.boost|v));"cpu"),
           row("Watchdog";("NMI="+($h.cpu.timers_watchdogs.watchdog.nmi_watchdog|v));"irq")]),
        sec("virt";"Virtualization / passthrough";
          [row("KVM";("available="+($h.capability_matrix.virtualization.kvm_available|v)+" AVIC="+($h.capability_matrix.virtualization.avic_parameter|v));"virtual"),
           row("IOMMU";((($groups|length)|tostring)+" groups remap="+($h.capability_matrix.iommu.interrupt_remapping_observed|v)+" ACS-override="+($h.capability_matrix.pcie.acs_override_configured|v));"virtual"),
           row("GPU";(if ($gpus|length)>0 then ($gpus|map(.bdf+" driver="+(.driver//"?")+" group="+(.iommu_group//"?"))|join(" | ")) else "none" end);"gpu")]),
        sec("memory";"Memory";
          [row("THP/KSM";("THP="+($h.memory.transparent_hugepages.enabled_selected|v)+" defrag="+($h.memory.transparent_hugepages.defrag_selected|v)+" KSM="+($h.memory.ksm.run|v));"memory"),
           row("Swap/HugeTLB";("swap="+($h.memory.swap.active|v)+" huge-pages="+(huge_total(arr($h.memory.hugetlb))|tostring));"memory")]),
        sec("runtime";"Observed runtime";
          [row("PSI10";("CPU="+(psi10($h.runtime_pressure.pressure.cpu.t1)|v)+" MEM="+(psi10($h.runtime_pressure.pressure.memory.t1)|v)+" IO="+(psi10($h.runtime_pressure.pressure.io.t1)|v));"runtime"),
           row("5s sample";("ctxt="+($h.latency_sample.system_deltas.ctxt|v)+" majflt="+($h.latency_sample.vmstat_deltas.pgmajfault|v)+" swap="+($h.latency_sample.vmstat_deltas.pswpin|v)+"/"+($h.latency_sample.vmstat_deltas.pswpout|v));"runtime"),
           row("Kernel history";("storage-occ="+($h.kernel_events.occurrences_by_category.storage|v)+" memory-occ="+($h.kernel_events.occurrences_by_category.memory|v)+" OOM-VMs="+($h.kernel_events.qemu_oom_vmids|v));"events")]),
        sec("io";"Interactive I/O";
          [row("Storage";(if ($pvest|length)>0 then ($pvest|map(.name+"="+(.status.percent//"?"))|join(" ")) else "unknown" end);"storage"),
           row("NIC";(if ($nics|length)>0 then ($nics|map(.name+":"+(.driver//"?")+":"+(.operstate//"?"))|join(" ")) else "unknown" end);"network"),
           row("Audio power-save";([ $h.desktop_io_path.audio.snd_hda_intel_parameters[]? | select(.name=="power_save") | .value ][0] // "unknown");"peripheral"),
           row("Display";(($h.display_timing.connected_count|v)+" connected; VRR-capable="+(if (arr($h.capability_matrix.display.vrr_capable_connectors)|length)>0 then (arr($h.capability_matrix.display.vrr_capable_connectors)|join(",")) else "none observed" end));"display")])
      ],
      dense_summary:[
        sec("cpu";"CPU/SCHED";
          [row("topology";(($h.cpu.physical_core_count|v)+"C/"+($h.cpu.logical_cpu_count|v)+"T SMT="+($h.cpu.smt.active|v)+" online="+($h.cpu.online.raw|v));"cpu"),
           row("isolation";("isolated="+cpuset_text($h.cpu.isolation.isolated)+" nohz="+cpuset_text($h.cpu.isolation.nohz_full)+" rcu="+cpuset_text($h.cpu.isolation.rcu_nocb));"cpu"),
           row("freq";(($drivers|join(","))+" "+($govs|join(","))+" boost="+($h.cpu.power.boost|v));"cpu"),
           row("workqueues";((arr($h.cpu.isolation.workqueues)|length|tostring)+" observed");"cpu")]),
        sec("virt";"KVM/VFIO";
          [row("KVM";("AVIC="+($h.capability_matrix.virtualization.avic_parameter|v)+" nested="+($h.capability_matrix.virtualization.nested_parameter|v));"virtual"),
           row("IOMMU";("groups="+($groups|length|tostring)+" remap="+($h.capability_matrix.iommu.interrupt_remapping_observed|v)+" ACSovr="+($h.capability_matrix.pcie.acs_override_configured|v));"virtual"),
           row("GPU";(if ($gpus|length)>0 then ($gpus|map(.bdf+":"+(.driver//"?")+"@g"+(.iommu_group//"?"))|join(" ")) else "none" end);"gpu")]),
        sec("irq";"IRQ/TIMER";
          [row("watchdog";("nmi="+($h.cpu.timers_watchdogs.watchdog.nmi_watchdog|v)+" mask="+($h.cpu.timers_watchdogs.watchdog.watchdog_cpumask|v));"irq"),
           row("irq sample";(($h.irq_activity.sample_seconds|v)+"s hw-active="+([ $h.irq_activity.irqs[]? | select((.total_delta//0)>0) ]|length|tostring));"irq"),
           row("clock";($h.cpu.timers_watchdogs.clocksource.current|v);"irq")]),
        sec("memory";"MEMORY";
          [row("THP";(($h.memory.transparent_hugepages.enabled_selected|v)+"/"+($h.memory.transparent_hugepages.defrag_selected|v));"memory"),
           row("KSM/swap";("ksm="+($h.memory.ksm.run|v)+" swap="+($h.memory.swap.active|v)+" swappiness="+($h.memory.swap.swappiness|v));"memory"),
           row("HugeTLB";(if (arr($h.memory.hugetlb)|length)>0 then (arr($h.memory.hugetlb)|map((.size|v)+":"+(.values.nr_hugepages|v))|join(" ")) else "none observed" end);"memory")]),
        sec("io";"STORAGE/NET/AUDIO/DISPLAY";
          [row("storage";(if ($pvest|length)>0 then ($pvest|map(.name+"="+(.status.percent//"?"))|join(" ")) else "unknown" end);"storage"),
           row("NIC";(if ($nics|length)>0 then ($nics|map(.name+":"+(.driver//"?"))|join(" ")) else "unknown" end);"network"),
           row("net busy poll";("busy_read="+($h.desktop_io_path.network_policy.busy_read|v)+" busy_poll="+($h.desktop_io_path.network_policy.busy_poll|v)+" RFS="+($h.desktop_io_path.network_policy.rps_sock_flow_entries|v));"network"),
           row("HDA power_save";([ $h.desktop_io_path.audio.snd_hda_intel_parameters[]? | select(.name=="power_save") | .value ][0] // "unknown");"peripheral"),
           row("display";("connected="+($h.display_timing.connected_count|v)+" VRR="+(if (arr($h.capability_matrix.display.vrr_capable_connectors)|length)>0 then (arr($h.capability_matrix.display.vrr_capable_connectors)|join(",")) else "none observed" end));"display")]),
        sec("runtime";"RUNTIME/EVENTS";
          [row("PSI10";("cpu="+(psi10($h.runtime_pressure.pressure.cpu.t1)|v)+" mem="+(psi10($h.runtime_pressure.pressure.memory.t1)|v)+" io="+(psi10($h.runtime_pressure.pressure.io.t1)|v));"runtime"),
           row("5s";("ctxt="+($h.latency_sample.system_deltas.ctxt|v)+" majflt="+($h.latency_sample.vmstat_deltas.pgmajfault|v)+" swap="+($h.latency_sample.vmstat_deltas.pswpin|v)+"/"+($h.latency_sample.vmstat_deltas.pswpout|v));"runtime"),
           row("events";("storage="+($h.kernel_events.occurrences_by_category.storage|v)+" memory="+($h.kernel_events.occurrences_by_category.memory|v)+" OOM-vm="+($h.kernel_events.qemu_oom_vmids|v));"events"),
           row("background";(([ $units[]? | select(.state.ActiveState=="active") ]|length|tostring)+" important active units");"background")])
      ],
      dense:[
        sec("scope";"Desktop-latency evidence scope";
          [row("host";$host;"identity"),row("capture";($start+" → "+$capture_end);"identity"),
           row("meaning";"observations only; no PASS/WARN/FAIL in this report";"identity")]),
        sec("cpu";"CPU / scheduler / housekeeping";
          [row("topology";(($h.cpu.physical_core_count|v)+"C/"+($h.cpu.logical_cpu_count|v)+"T SMT="+($h.cpu.smt.active|v));"cpu"),
           row("present/online";(($h.cpu.present.raw|v)+"/"+($h.cpu.online.raw|v));"cpu"),
           row("isolation";("isolated="+cpuset_text($h.cpu.isolation.isolated)+" nohz="+cpuset_text($h.cpu.isolation.nohz_full)+" rcu="+cpuset_text($h.cpu.isolation.rcu_nocb));"cpu"),
           row("frequency";(($drivers|join(","))+" gov="+($govs|join(","))+" boost="+($h.cpu.power.boost|v));"cpu"),
           row("housekeeping threads";$h.kernel_housekeeping.thread_count;"cpu")] +
          [ $h.cpu.isolation.workqueues[]? | row(("wq "+(.name//"?"));("mask="+(.mask//"unknown"));"cpu") ]),
        sec("virt";"KVM / IOMMU / passthrough";
          [row("KVM";("available="+($h.capability_matrix.virtualization.kvm_available|v)+" AVIC="+($h.capability_matrix.virtualization.avic_parameter|v)+" nested="+($h.capability_matrix.virtualization.nested_parameter|v));"virtual"),
           row("IOMMU";("groups="+($groups|length|tostring)+" remap="+($h.capability_matrix.iommu.interrupt_remapping_observed|v));"virtual"),
           row("ACS override";$h.capability_matrix.pcie.acs_override_configured;"virtual")] +
          [ $gpus[]? | row(("GPU "+(.bdf//"?"));("driver="+(.driver//"?")+" group="+(.iommu_group//"?")+" link="+(.pci.current_link_speed//"?")+"x"+(.pci.current_link_width//"?")+" max="+(.pci.max_link_speed//"?")+"x"+(.pci.max_link_width//"?"));"gpu") ]),
        sec("irq";"IRQ / interrupt architecture";
          [row("NMI watchdog";$h.cpu.timers_watchdogs.watchdog.nmi_watchdog;"irq"),row("watchdog mask";$h.cpu.timers_watchdogs.watchdog.watchdog_cpumask;"irq"),
           row("clocksource";$h.cpu.timers_watchdogs.clocksource.current;"irq")] +
          [ $h.irq_activity.irqs[]? | select((.total_delta//0)>0) | row(("IRQ "+(.irq|v));("delta="+(.total_delta|v)+" "+(.source//"?"));"irq") ]),
        sec("memory";"Memory / hugepage feasibility";
          [row("THP";("enabled="+($h.memory.transparent_hugepages.enabled_selected|v)+" defrag="+($h.memory.transparent_hugepages.defrag_selected|v));"memory"),
           row("KSM";("run="+($h.memory.ksm.run|v)+" sharing="+($h.memory.ksm.pages_sharing|v));"memory"),
           row("swap";("active="+($h.memory.swap.active|v)+" swappiness="+($h.memory.swap.swappiness|v));"memory")] +
          [ $h.memory.hugetlb[]? | row(("HugeTLB "+(.size|v));("total="+(.values.nr_hugepages|v)+" free="+(.values.free_hugepages|v)+" reserved="+(.values.resv_hugepages|v));"memory") ] +
          [ $h.memory_fragmentation.buddy_highest_order[]? | row(("buddy "+((.node|v)|sub(",";""))+"/"+(.zone//"?"));("highest-order="+(.highest_order_with_free|v));"memory") ]),
        sec("storage";"Storage path / pressure";
          [ $pvest[]? | row((.name//"?");("used="+(.status.percent//"?")+" base="+(.backing.base_block//"?")+" pci="+(.backing.pci_bdf//"?"));"storage") ] +
          [ $h.latency_sample.block_deltas[]? | select(((.reads_completed_delta//0)+(.writes_completed_delta//0))>0) | row(("sample "+(.device//"?"));("read="+(.reads_completed_delta|v)+" write="+(.writes_completed_delta|v)+" io-ticks="+(.io_ticks_delta|v));"storage") ]),
        sec("network";"Network path / steering";
          [row("busy polling";("busy_read="+($h.desktop_io_path.network_policy.busy_read|v)+" busy_poll="+($h.desktop_io_path.network_policy.busy_poll|v)+" RFS="+($h.desktop_io_path.network_policy.rps_sock_flow_entries|v));"network")] +
          [ $nics[]? | row((.name//"?");("driver="+(.driver//"?")+" bdf="+(.bdf//"?")+" state="+(.operstate//"?")+" mtu="+(.mtu//"?"));"network") ] +
          [ $h.correlations.desktop_network_paths[]? | row(("VM "+(.vmid|v)+" net");("bridge="+(.bridge//"?")+" tap="+(.tap_interface//"?")+" physical="+((.physical_paths//[])|map(.interface//"?")|join(",")));"network") ]),
        sec("interactive";"Display / HID / audio";
          [row("display";("connected="+($h.display_timing.connected_count|v)+" VRR-capable="+(if (arr($h.capability_matrix.display.vrr_capable_connectors)|length)>0 then (arr($h.capability_matrix.display.vrr_capable_connectors)|join(",")) else "none observed" end));"display"),
           row("USB devices";($usb|length);"peripheral"),
           row("sound cards";($sound|length);"peripheral"),
           row("HDA power_save";([ $h.desktop_io_path.audio.snd_hda_intel_parameters[]? | select(.name=="power_save") | .value ][0] // "unknown");"peripheral")] +
          [ $h.peripherals.usb_devices[]? | row(("USB "+(.device//.name//"?"));("speed="+(.speed//"?")+" controller="+(.controller_bdf//"?")+" power="+(.power.control//"?"));"peripheral") ]),
        sec("runtime";"Runtime pressure / latency sample";
          [row("PSI10";("cpu="+(psi10($h.runtime_pressure.pressure.cpu.t1)|v)+" mem="+(psi10($h.runtime_pressure.pressure.memory.t1)|v)+" io="+(psi10($h.runtime_pressure.pressure.io.t1)|v));"runtime"),
           row("1s";("ctxt="+($h.runtime_pressure.deltas.context_switches|v)+" major="+($h.runtime_pressure.deltas.pgmajfault|v)+" swap="+($h.runtime_pressure.deltas.pswpin|v)+"/"+($h.runtime_pressure.deltas.pswpout|v));"runtime"),
           row("5s";("ctxt="+($h.latency_sample.system_deltas.ctxt|v)+" major="+($h.latency_sample.vmstat_deltas.pgmajfault|v)+" swap="+($h.latency_sample.vmstat_deltas.pswpin|v)+"/"+($h.latency_sample.vmstat_deltas.pswpout|v));"runtime")] +
          [ $h.latency_sample.qemu_deltas[]? | row(("VM "+(.vmid|v));("runtime-ns="+(.sched_runtime_ns_delta|v)+" wait-ns="+(.sched_wait_ns_delta|v)+" migrations="+(.migrations_delta|v));"runtime") ]),
        sec("events";"Reliability history relevant to smoothness";
          [row("totals";(($h.kernel_events.total_unique_events|v)+" entities/"+($h.kernel_events.total_observations|v)+" observations; OOM VMs="+($h.kernel_events.qemu_oom_vmids|v));"events")] +
          [ $events[]? | select(.category=="storage" or .category=="memory" or .category=="pcie" or .category=="network") | select(.severity!="info") |
            row(("["+(.severity//"?")+"/"+(.category//"?")+"]");("x"+(.occurrences|v)+" "+(.message//""));"events") ]),
        sec("background";"Background host work";
          [ $units[]? | row((.unit//.name//"?");("state="+(.state.ActiveState//"?")+" EffectiveCPUs="+(.state.EffectiveCPUs//"?")+" AllowedCPUs="+(.state.AllowedCPUs//"?"));"background") ])
      ]
    }
  }
}
' "$app_file" >"${app_tmpout:-/dev/stdout}" || { [ -n "$app_tmpout" ] && rm -f "$app_tmpout"; exit 1; }

if [ -n "$app_output" ]; then
    mv -- "$app_tmpout" "$app_output" || exit 1
    app_tmpout=
fi
exit 0
