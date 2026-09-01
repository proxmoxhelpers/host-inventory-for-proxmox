#!/bin/sh
# ============================================================
# evaluate_desktop.sh
# Layer 3 policy evaluator for a low-latency virtualized desktop.
# Consumes host-map.json only; it never probes or modifies the host.
#
# Version:
#   0.9.2
# ============================================================
app_name=evaluate_desktop
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
evaluate_desktop.sh - low-latency hypervisor desktop evaluator

Usage:
  ./evaluate_desktop.sh --file host-map.json
  ./evaluate_desktop.sh --from-run RUN_DIR
  ./evaluate_desktop.sh --from-run RUN_DIR --output desktop-evaluation.json

Options:
  --file FILE       Existing host-map.json.
  --from-run DIR    Harmonize a saved inventory run, then evaluate it.
  --output FILE     Write evaluation JSON.
  --compact         Compact JSON.
  --help            Show help.
  --version         Show version.

The evaluator consumes host-map evidence only. It never re-probes or changes the host.
PASS/WARN/FAIL/UNKNOWN are policy verdicts for the stated low-latency desktop target,
not generic Proxmox correctness judgments.
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
[ -n "$app_file" ] && [ -n "$app_from_run" ] && { printf 'ERROR: choose --file or --from-run.\n' >&2; exit 2; }
[ -n "$app_file$app_from_run" ] || { printf 'ERROR: --file or --from-run is required.\n' >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { printf 'ERROR: jq is required.\n' >&2; exit 2; }

if [ -n "$app_from_run" ]; then
    [ -d "$app_from_run" ] || { printf 'ERROR: saved run not found: %s\n' "$app_from_run" >&2; exit 2; }
    app_temp=$(mktemp -d "${TMPDIR:-/tmp}/hfip-eval.XXXXXX") || exit 2
    app_file=$app_temp/host-map.json
    "$app_dir/harmonize_host.sh" --from-run "$app_from_run" --output "$app_file" --no-color >/dev/null 2>&1 || {
        printf 'ERROR: could not harmonize saved run.\n' >&2; exit 2;
    }
fi
jq -e '.model=="host-map"' "$app_file" >/dev/null 2>&1 || { printf 'ERROR: input is not a host-map.\n' >&2; exit 2; }

app_jq_args=
[ "$app_compact" -eq 1 ] && app_jq_args=-c
app_tmpout=
[ -n "$app_output" ] && app_tmpout=$(mktemp "${TMPDIR:-/tmp}/hfip-evaluation.XXXXXX") || :

jq $app_jq_args '
def arr($x): if ($x|type)=="array" then $x else [] end;
def str($x): if $x==null then "unknown" elif ($x|type)=="array" then ($x|map(tostring)|join(", ")) else ($x|tostring) end;
def finding($id;$category;$status;$severity;$confidence;$title;$scope;$evidence;$rationale;$recommendation):
  {id:$id,category:$category,status:$status,severity:$severity,confidence:$confidence,title:$title,scope:$scope,
   evidence:($evidence|map(select(.!=null and .!=""))),rationale:$rationale,recommendation:$recommendation};
def psi10($s):
  if ($s|type)!="string" then null
  else ([try ($s|capture("some avg10=(?<n>[0-9.]+)").n|tonumber) catch empty][0] // null) end;
def percent($s):
  if ($s|type)!="string" then null
  else ([try ($s|capture("(?<n>[0-9.]+)%").n|tonumber) catch empty][0] // null) end;
def capture_num($s;$re):
  if ($s|type)!="string" then null
  else ([try ($s|capture($re).n|tonumber) catch empty][0] // null) end;
def same_slot($members;$bdf):
  ($bdf|sub("\\.[0-7]$";"")) as $slot |
  (($members|length)>0 and ($members|all((sub("\\.[0-7]$";""))==$slot)));
def stat_rank($s): if $s=="FAIL" then 0 elif $s=="WARN" then 1 elif $s=="UNKNOWN" then 2 else 3 end;

. as $h |
arr($h.cpu.isolation.isolated.cpus) as $isol |
arr($h.cpu.isolation.nohz_full.cpus) as $nohz |
arr($h.cpu.isolation.rcu_nocb.cpus) as $rcu |
arr($h.cpu.isolation.workqueues) as $wq |
arr($h.background.important_units) as $units |
arr($h.cpu.power.governors) as $gov |
arr($h.virtualization_stack.cpu_virtualization_flags) as $vflags |
arr($h.gpu.devices) as $gpus |
arr($h.pci.iommu_groups) as $groups |
arr($h.memory.hugetlb) as $huge |
arr($h.storage.pve_storages) as $pvest |
arr($h.network.physical_interfaces) as $nics |
arr($h.cpu_limits_pmu.cpus) as $cpulimits |
arr($h.kernel_events.events) as $events |
(psi10($h.runtime_pressure.pressure.io.t1)) as $iopsi |
([ $pvest[]? | {name:.name,pct:percent(.status.percent)} | select(.pct!=null) ]) as $storage_pct |
([ $nics[]? | select(.operstate=="up") | select((.advanced.eee.stdout//"")|test("EEE status:[[:space:]]*enabled";"i")) | .name ]) as $eee_up |
([ $nics[]? | select(.operstate=="up") |
    {name:.name,rx:capture_num((.advanced.coalesce.stdout//"");"rx-usecs:[[:space:]]*(?<n>[0-9]+)"),
                tx:capture_num((.advanced.coalesce.stdout//"");"tx-usecs:[[:space:]]*(?<n>[0-9]+)")} |
    select((.rx//0)>0 or (.tx//0)>0) ]) as $coal |
([ $h.desktop_io_path.audio.snd_hda_intel_parameters[]? | select(.name=="power_save") | .value ][0] // null) as $hda_ps |
([ $h.thermal_power.hwmon[]? | select(.name=="k10temp") | .values.temp1_input | tonumber ][0] // null) as $tctl_milli |
([ $cpulimits[]? | .thermal_throttle | .core_count,.package_count | select(.!=null) | tonumber ] | add // 0) as $throttle_count |
([ $events[]? | select(.category=="storage" and .severity=="error") | .occurrences ] | add // 0) as $storage_errors |
([ $events[]? | select(.category=="memory" and .event_type=="oom" and .severity=="error") | .occurrences ] | add // 0) as $oom_occ |
(
[
  (if ($h.cpu.isolation|type)!="object" then
    finding("cpu-isolation";"CPU/Scheduler";"UNKNOWN";"high";"low";"Dedicated CPU isolation";"configuration";["isolation evidence unavailable"];
      "CPU partitioning cannot be evaluated without explicit isolation evidence.";
      "Collect a complete current host-map, then define a CPU-partition strategy only if the desktop design requires dedicated pCPUs.")
   elif (($isol|length)==0 and ($nohz|length)==0 and ($rcu|length)==0) then
    finding("cpu-isolation";"CPU/Scheduler";"WARN";"high";"high";"Dedicated CPU isolation";"configuration";
      ["isolated CPUs: none","nohz_full CPUs: none","RCU nocb CPUs: none"];
      "All online CPUs remain eligible for ordinary host scheduling/tick/RCU work, so a latency-critical VM has no protected CPU set.";
      "Design an explicit host/desktop-VM CPU partition, keeping housekeeping CPUs separate. Validate the chosen CPU set against SMT siblings, IRQ routing and actual timer/osnoise measurements before making it persistent.")
   else
    finding("cpu-isolation";"CPU/Scheduler";"PASS";"high";"high";"Dedicated CPU isolation";"configuration";
      ["isolated="+str($isol),"nohz_full="+str($nohz),"rcu_nocb="+str($rcu)];
      "Explicit CPU-isolation mechanisms are present.";
      "Keep the isolation masks internally consistent and confirm with runtime thread/IRQ placement and latency measurements.")
   end),

  (if ($wq|length)==0 then
    finding("workqueue-affinity";"CPU/Scheduler";"UNKNOWN";"medium";"low";"Global workqueue affinity";"configuration";["workqueue evidence unavailable"];
      "Host workqueue placement is not known.";
      "Collect workqueue cpumasks and compare them with the intended housekeeping/desktop CPU partition.")
   elif ([ $wq[] | select((.mask//"")|test("^f+$";"i")) ]|length)>0 then
    finding("workqueue-affinity";"CPU/Scheduler";"WARN";"medium";"high";"Global workqueue affinity";"configuration";
      [([ $wq[] | select((.mask//"")|test("^f+$";"i")) | .name ]|join(", "))];
      "One or more global workqueues can run across the full observed CPU mask.";
      "After defining housekeeping CPUs, constrain only the workqueues that support safe cpumask control; verify kernel semantics and do not blindly rewrite per-driver workqueues.")
   else
    finding("workqueue-affinity";"CPU/Scheduler";"PASS";"medium";"medium";"Global workqueue affinity";"configuration";
      [([ $wq[] | .name+"="+(.mask//"unknown") ]|join(", "))];
      "Observed workqueue masks are not all-CPU masks.";
      "Retain the arrangement and verify that latency-critical CPUs remain free of avoidable workqueue activity under load.")
   end),

  (if ($units|length)==0 then
    finding("service-affinity";"CPU/Scheduler";"UNKNOWN";"medium";"low";"Background service CPU scope";"configuration";["service affinity evidence unavailable"];
      "Important service placement cannot be evaluated.";
      "Collect systemd EffectiveCPUs/AllowedCPUs before designing service housekeeping placement.")
   elif ([ $units[]? | select(.state.ActiveState=="active") | select((.state.EffectiveCPUs//"")==($h.cpu.online.raw//"")) ]|length)>0 then
    finding("service-affinity";"CPU/Scheduler";"WARN";"medium";"high";"Background service CPU scope";"configuration";
      [([ $units[]? | select(.state.ActiveState=="active") | select((.state.EffectiveCPUs//"")==($h.cpu.online.raw//"")) | .unit ]|join(", "))];
      "Active host services can execute on every online CPU.";
      "Place routine host services on housekeeping CPUs with systemd CPU affinity only after the desktop CPU partition is defined; preserve enough host capacity for Proxmox management and storage/network work.")
   else
    finding("service-affinity";"CPU/Scheduler";"PASS";"medium";"medium";"Background service CPU scope";"configuration";
      ["active important services are not uniformly scoped to every online CPU"];
      "Observed important services are not all exposed across the full online CPU set.";
      "Retain and verify runtime placement during representative desktop load.")
   end),

  (if ($gov|length)==0 then
    finding("cpu-governor";"CPU/Power";"UNKNOWN";"medium";"low";"CPU frequency policy";"configuration";["governor unavailable"];
      "Frequency policy is not exposed.";
      "Measure frequency residency and latency under load before changing CPU power policy.")
   elif ($gov|index("performance"))!=null then
    finding("cpu-governor";"CPU/Power";"PASS";"medium";"high";"CPU frequency policy";"configuration";
      ["governor="+($gov|join(",")),"driver="+(arr($h.cpu.power.scaling_drivers)|join(",")),"boost="+str($h.cpu.power.boost)];
      "The observed scaling policy requests performance behavior.";
      "Keep it unless measurements show a better latency/power trade-off; frequency residency is more authoritative than the governor name alone.")
   else
    finding("cpu-governor";"CPU/Power";"WARN";"medium";"medium";"CPU frequency policy";"configuration";
      ["governor="+($gov|join(","))];
      "The active governor is not the performance governor for this latency-oriented policy.";
      "Benchmark performance versus the current governor under representative VM load and compare timerlat/osnoise plus power/thermals before changing it.")
   end),

  (if $h.cpu.timers_watchdogs.watchdog.nmi_watchdog==null then
    finding("nmi-watchdog";"CPU/Interrupts";"UNKNOWN";"medium";"low";"NMI watchdog";"configuration";["nmi_watchdog unavailable"];
      "Periodic watchdog NMI activity is unknown.";
      "Collect the watchdog state.")
   elif ($h.cpu.timers_watchdogs.watchdog.nmi_watchdog|tostring)=="1" then
    finding("nmi-watchdog";"CPU/Interrupts";"WARN";"medium";"high";"NMI watchdog";"configuration";
      ["nmi_watchdog=1","watchdog_cpumask="+str($h.cpu.timers_watchdogs.watchdog.watchdog_cpumask)];
      "The NMI watchdog adds periodic host activity and performance-monitor interrupts.";
      "For a dedicated low-latency desktop host, benchmark with and without the NMI watchdog only if your operational/security requirements permit it; do not disable watchdogs solely from static inventory.")
   else
    finding("nmi-watchdog";"CPU/Interrupts";"PASS";"medium";"high";"NMI watchdog";"configuration";
      ["nmi_watchdog="+str($h.cpu.timers_watchdogs.watchdog.nmi_watchdog)];
      "The NMI watchdog is not enabled in the observed configuration.";
      "No change indicated from this evidence.")
   end),

  (if ($vflags|index("avic"))==null then
    finding("avic";"Virtualization";"UNKNOWN";"medium";"medium";"AMD AVIC acceleration";"capability";["AVIC CPU capability not observed"];
      "AVIC applicability cannot be established from this map.";
      "Treat AVIC as unavailable/unknown unless the CPU/KVM stack explicitly exposes support.")
   elif ($h.capability_matrix.virtualization.avic_parameter//"unknown")=="N" then
    finding("avic";"Virtualization";"WARN";"medium";"high";"AMD AVIC acceleration";"configuration";
      ["CPU flag avic observed","kvm_amd avic=N"];
      "The CPU advertises AVIC but the KVM AMD module parameter is disabled, so interrupt virtualization may take a less direct path.";
      "Check the running Proxmox kernel/KVM support and known device/guest compatibility, then benchmark AVIC enabled versus disabled using KVM-exit and latency measurements before persisting a change.")
   else
    finding("avic";"Virtualization";"PASS";"medium";"medium";"AMD AVIC acceleration";"configuration";
      ["AVIC capability observed","avic="+str($h.capability_matrix.virtualization.avic_parameter)];
      "AVIC is not observed disabled.";
      "Retain if stable and verify actual interrupt-exit behavior with measurements.")
   end),

  (if ($gpus|length)==0 then
    finding("gpu-vfio";"GPU/Passthrough";"UNKNOWN";"high";"low";"GPU passthrough readiness";"configuration";["no GPU endpoint in host-map"];
      "A desktop GPU path cannot be evaluated.";
      "Collect GPU/VFIO evidence for the intended passthrough adapter.")
   elif ([ $gpus[] | select(.driver=="vfio-pci") ]|length)==($gpus|length) then
    finding("gpu-vfio";"GPU/Passthrough";"PASS";"high";"high";"GPU passthrough readiness";"configuration";
      [($gpus|map(.bdf+"="+(.driver//"unknown"))|join(", "))];
      "Observed GPU endpoints are bound to vfio-pci.";
      "Keep the GPU and all required multifunction siblings assigned consistently and verify reset behavior.")
   else
    finding("gpu-vfio";"GPU/Passthrough";"WARN";"high";"high";"GPU passthrough readiness";"configuration";
      [($gpus|map(.bdf+"="+(.driver//"unknown"))|join(", ")),"vfio-pci loaded="+str($h.gpu.vfio.module_loaded)];
      "At least one GPU is host-bound rather than vfio-pci, so the host is not currently in a passthrough-ready state for that adapter.";
      "For the intended desktop GPU, bind the complete required device set to vfio-pci at boot and remove conflicting host framebuffer/GPU bindings; preserve a separate host-management path and verify reset/rebind behavior.")
   end),

  (if ($gpus|length)==0 or ($groups|length)==0 then
    finding("gpu-iommu-group";"GPU/Passthrough";"UNKNOWN";"high";"low";"GPU IOMMU isolation";"topology";["GPU or IOMMU group evidence unavailable"];
      "Isolation of the passthrough group cannot be checked.";
      "Collect full GPU and IOMMU membership.")
   else
    ([ $gpus[] as $g | [ $groups[] | select((.group|tostring)==($g.iommu_group|tostring)) ][0] as $grp |
       {bdf:$g.bdf,group:$g.iommu_group,members:($grp.members//[]),same_slot:same_slot(($grp.members//[]);$g.bdf)} ]) as $gg |
    if ($gg|all(.same_slot)) then
      finding("gpu-iommu-group";"GPU/Passthrough";"PASS";"high";"high";"GPU IOMMU isolation";"topology";
        [($gg|map(.bdf+" group="+(.group|tostring)+" members="+(.members|join(",")))|join(" | "))];
        "Each observed GPU group contains only functions from the same PCI slot.";
        "Pass through all required functions in the group together; this verdict does not claim physical lane routing.")
    else
      finding("gpu-iommu-group";"GPU/Passthrough";"WARN";"high";"high";"GPU IOMMU isolation";"topology";
        [($gg|map(.bdf+" group="+(.group|tostring)+" members="+(.members|join(",")))|join(" | "))];
        "At least one GPU IOMMU group contains devices outside the GPU multifunction slot.";
        "Do not rely on ACS override as proof of hardware isolation. Prefer hardware/firmware topology that yields a clean group or pass through the entire safe group when feasible.")
    end
   end),

  (if $h.capability_matrix.pcie.acs_override_configured==null then
    finding("acs-override";"PCIe/IOMMU";"UNKNOWN";"high";"low";"ACS override";"configuration";["ACS override state unavailable"];
      "Synthetic IOMMU group splitting cannot be excluded.";
      "Collect the kernel command line and PCIe capability evidence.")
   elif $h.capability_matrix.pcie.acs_override_configured==true then
    finding("acs-override";"PCIe/IOMMU";"WARN";"high";"high";"ACS override";"configuration";
      ["pcie_acs_override configured"];
      "ACS override changes Linux grouping but does not create hardware transaction isolation.";
      "Remove reliance on ACS override for security/isolation-sensitive passthrough where possible; select slots/topology with native isolation.")
   else
    finding("acs-override";"PCIe/IOMMU";"PASS";"high";"high";"ACS override";"configuration";
      ["ACS override not configured"];
      "The observed grouping is not produced by pcie_acs_override.";
      "Retain native grouping and evaluate whole-group assignment.")
   end),

  (if ($huge|length)==0 then
    finding("hugetlb";"Memory";"UNKNOWN";"medium";"low";"Explicit HugeTLB pool";"configuration";["HugeTLB evidence unavailable"];
      "Explicit hugepage availability cannot be evaluated.";
      "Collect HugeTLB pools and fragmentation evidence.")
   elif ([ $huge[] | (.values.nr_hugepages//0) | tonumber ]|add//0)>0 then
    finding("hugetlb";"Memory";"PASS";"medium";"high";"Explicit HugeTLB pool";"configuration";
      [($huge|map((.size//"unknown")+" total="+((.values.nr_hugepages//0)|tostring))|join(", "))];
      "An explicit HugeTLB pool is reserved.";
      "Size the VM allocation conservatively and verify NUMA locality/boot reservation rather than reserving more than required.")
   else
    finding("hugetlb";"Memory";"WARN";"medium";"high";"Explicit HugeTLB pool";"configuration";
      [($huge|map((.size//"unknown")+" total="+((.values.nr_hugepages//0)|tostring))|join(", "))];
      "No explicit HugeTLB pages are reserved.";
      "For a dedicated latency-sensitive desktop VM, benchmark explicit hugepages versus the current THP setup. If they help, reserve them at boot with enough host memory left for Proxmox and I/O.")
   end),

  (if $h.memory.ksm.run==null then
    finding("ksm";"Memory";"UNKNOWN";"medium";"low";"KSM scanning";"configuration";["KSM run state unavailable"];
      "KSM background scanning state is unknown.";
      "Collect KSM state.")
   elif ($h.memory.ksm.run|tostring)=="0" then
    finding("ksm";"Memory";"PASS";"medium";"high";"KSM scanning";"configuration";
      ["ksm.run=0"];
      "KSM scanning is not currently running.";
      "Keep KSM disabled for the latency-critical desktop unless memory-density requirements justify it and measurements show acceptable overhead.")
   else
    finding("ksm";"Memory";"WARN";"medium";"high";"KSM scanning";"configuration";
      ["ksm.run="+str($h.memory.ksm.run)];
      "KSM scanning is active and can add background memory work.";
      "For a dedicated desktop host, compare with KSM disabled if memory overcommit/deduplication is not required; retain it if density requirements outweigh latency sensitivity.")
   end),

  (if $h.memory.swap.active==null then
    finding("swap";"Memory";"UNKNOWN";"high";"low";"Swap exposure";"configuration";["swap state unavailable"];
      "Swap exposure is unknown.";
      "Collect /proc/swaps and runtime paging counters.")
   elif $h.memory.swap.active==true then
    finding("swap";"Memory";"WARN";"high";"high";"Swap exposure";"configuration";
      ["swap active=yes","swappiness="+str($h.memory.swap.swappiness),"sample pswpin/pswpout="+str($h.latency_sample.vmstat_deltas.pswpin)+"/"+str($h.latency_sample.vmstat_deltas.pswpout)];
      "Swap is enabled; paging a latency-critical VM or host working set can cause severe stalls even when the short sample shows no swap I/O.";
      "Provision enough RAM to avoid swapping the desktop VM. Consider lower swappiness or disabling swap only after validating host OOM behavior and operational recovery requirements.")
   else
    finding("swap";"Memory";"PASS";"high";"high";"Swap exposure";"configuration";
      ["swap active=no"];
      "Swap is not active.";
      "Keep sufficient RAM headroom so this remains safe under peak host load.")
   end),

  (if $h.latency_sample.vmstat_deltas==null then
    finding("paging-sample";"Memory";"UNKNOWN";"high";"low";"Paging during latency sample";"runtime-window";["latency sample paging counters unavailable"];
      "Current paging stalls were not measured.";
      "Run the passive sample during representative desktop activity.")
   elif (($h.latency_sample.vmstat_deltas.pswpin//0)>0 or ($h.latency_sample.vmstat_deltas.pswpout//0)>0 or ($h.latency_sample.vmstat_deltas.pgmajfault//0)>0) then
    finding("paging-sample";"Memory";"WARN";"high";"medium";"Paging during latency sample";"runtime-window";
      ["pswpin="+str($h.latency_sample.vmstat_deltas.pswpin),"pswpout="+str($h.latency_sample.vmstat_deltas.pswpout),"pgmajfault="+str($h.latency_sample.vmstat_deltas.pgmajfault)];
      "The sample observed paging/major-fault activity that can create long stalls.";
      "Identify the process/guest causing paging, restore RAM headroom, and re-measure during the intended desktop workload.")
   else
    finding("paging-sample";"Memory";"PASS";"high";"medium";"Paging during latency sample";"runtime-window";
      ["pswpin=0","pswpout=0","pgmajfault=0"];
      "No swap I/O or major faults were observed in the short passive sample.";
      "Retain RAM headroom and repeat under representative peak load; a clean five-second sample is not proof of absence.")
   end),

  (if $iopsi==null then
    finding("io-psi";"Runtime";"UNKNOWN";"high";"low";"I/O pressure";"runtime-window";["I/O PSI avg10 unavailable"];
      "I/O stall pressure cannot be scored.";
      "Collect PSI during representative desktop and storage load.")
   elif $iopsi>=20 then
    finding("io-psi";"Runtime";"FAIL";"high";"medium";"I/O pressure";"runtime-window";
      ["io some avg10="+($iopsi|tostring)+"%"];
      "The host spent a very large fraction of recent time with tasks stalled on I/O; this is directly hostile to smooth interactive latency.";
      "Identify the saturated storage/network path, correlate with block deltas and guest I/O, reduce contention or move the desktop workload to lower-latency storage, then re-measure.")
   elif $iopsi>=5 then
    finding("io-psi";"Runtime";"WARN";"high";"medium";"I/O pressure";"runtime-window";
      ["io some avg10="+($iopsi|tostring)+"%"];
      "Recent I/O stall pressure is material for an interactive desktop.";
      "Correlate PSI with block-device and guest deltas under representative load and remove the dominant contention source.")
   else
    finding("io-psi";"Runtime";"PASS";"high";"medium";"I/O pressure";"runtime-window";
      ["io some avg10="+($iopsi|tostring)+"%"];
      "Recent I/O PSI is below the policy 5% warning threshold.";
      "Re-test during the actual desktop workload; PSI is a runtime-window observation.")
   end),

  (if ($storage_pct|length)==0 then
    finding("storage-capacity";"Storage";"UNKNOWN";"medium";"low";"PVE storage utilization";"configuration";["storage utilization unavailable"];
      "Thin-pool/filesystem fullness cannot be evaluated.";
      "Collect PVE storage status.")
   elif ([ $storage_pct[] | select(.pct>=98) ]|length)>0 then
    finding("storage-capacity";"Storage";"FAIL";"high";"high";"PVE storage utilization";"configuration";
      [($storage_pct|map(.name+"="+(.pct|tostring)+"%")|join(", "))];
      "At least one PVE storage target is at or above 98% utilization, leaving little allocation/metadata headroom.";
      "Free or migrate data immediately and verify thin-pool metadata/data health before placing latency-sensitive desktop storage there.")
   elif ([ $storage_pct[] | select(.pct>=95) ]|length)>0 then
    finding("storage-capacity";"Storage";"WARN";"high";"high";"PVE storage utilization";"configuration";
      [($storage_pct|map(.name+"="+(.pct|tostring)+"%")|join(", "))];
      "At least one PVE storage target is above 95% utilization.";
      "Increase free space or move workloads before using that target for a latency-sensitive desktop; preserve thin-pool and filesystem headroom.")
   else
    finding("storage-capacity";"Storage";"PASS";"medium";"high";"PVE storage utilization";"configuration";
      [($storage_pct|map(.name+"="+(.pct|tostring)+"%")|join(", "))];
      "No observed PVE storage target exceeds the policy 95% warning threshold.";
      "Maintain capacity headroom and monitor the actual desktop datastore separately.")
   end),

  (if $storage_errors>0 then
    finding("storage-errors";"Storage";"FAIL";"critical";"high";"Kernel storage I/O errors";"current-boot-history";
      ["storage error occurrences="+($storage_errors|tostring),
       ([ $events[]? | select(.category=="storage" and .severity=="error") | "x"+(.occurrences|tostring)+" "+(.message//"") ][0:5]|join(" | "))];
      "Uncorrected storage I/O errors are present in current-boot history; these can cause severe stalls, filesystem damage and guest failures.";
      "Treat storage reliability as a prerequisite: map affected dm/loop/block devices to backing storage, inspect SMART/NVMe/controller/cabling/filesystem/LVM health, repair the root cause, then obtain a clean boot/workload history before latency tuning.")
   elif $h.kernel_events.counts_by_category.storage==null then
    finding("storage-errors";"Storage";"UNKNOWN";"critical";"low";"Kernel storage I/O errors";"current-boot-history";["kernel storage event history unavailable"];
      "Storage reliability history is unavailable.";
      "Collect kernel-event history before tuning.")
   else
    finding("storage-errors";"Storage";"PASS";"critical";"high";"Kernel storage I/O errors";"current-boot-history";["no storage error-severity events in normalized current-boot history"];
      "No uncorrected storage error entity is present in the normalized history.";
      "Continue monitoring under the real desktop workload.")
   end),

  (if $oom_occ>0 then
    finding("oom-history";"Memory";"FAIL";"critical";"high";"Host/QEMU OOM history";"current-boot-history";
      ["OOM occurrences="+($oom_occ|tostring),"QEMU OOM VMIDs="+str($h.kernel_events.qemu_oom_vmids)];
      "The host has killed processes/VMs for memory exhaustion during the current boot. That is incompatible with deterministic desktop availability and smoothness.";
      "Reduce memory overcommit, stop relying on swap as capacity, size guests with host headroom, review ballooning/KSM policy, and verify the host can sustain peak desktop plus background load without OOM.")
   elif $h.kernel_events.qemu_oom_vmids==null then
    finding("oom-history";"Memory";"UNKNOWN";"critical";"low";"Host/QEMU OOM history";"current-boot-history";["OOM history unavailable"];
      "OOM reliability cannot be scored.";
      "Collect normalized kernel-event history.")
   else
    finding("oom-history";"Memory";"PASS";"critical";"high";"Host/QEMU OOM history";"current-boot-history";["no normalized OOM error occurrence observed"];
      "No OOM event is present in current-boot history.";
      "Maintain RAM headroom and re-check after representative load.")
   end),

  (if ($eee_up|length)>0 then
    finding("nic-eee";"Network";"WARN";"medium";"high";"Ethernet Energy Efficient Ethernet";"configuration";
      ["EEE enabled on active NIC(s): "+($eee_up|join(", "))];
      "EEE low-power transitions can add wake latency on the desktop network path.";
      "For an interactive wired desktop path, benchmark with EEE disabled on the relevant physical NIC only; retain it if measurements show no latency benefit.")
   elif ([ $nics[]? | select(.operstate=="up") ]|length)==0 then
    finding("nic-eee";"Network";"UNKNOWN";"medium";"low";"Ethernet Energy Efficient Ethernet";"configuration";["no active physical NIC with EEE evidence"];
      "EEE state on the relevant desktop network path is unknown.";
      "Collect EEE state for the active physical NIC.")
   else
    finding("nic-eee";"Network";"PASS";"medium";"medium";"Ethernet Energy Efficient Ethernet";"configuration";
      ["no active NIC reported EEE enabled"];
      "EEE is not observed enabled on an active physical NIC.";
      "No change indicated; validate with packet-latency measurements if networking is on the critical path.")
   end),

  (if ($coal|length)>0 then
    finding("nic-coalescing";"Network";"WARN";"medium";"medium";"NIC interrupt coalescing";"configuration";
      [($coal|map(.name+" rx-usecs="+str(.rx)+" tx-usecs="+str(.tx))|join(", "))];
      "Non-zero interrupt coalescing intentionally batches packets and can add small latency in exchange for lower interrupt load.";
      "Benchmark lower coalescing on the desktop NIC against CPU/IRQ cost and network tail latency; do not assume zero coalescing is globally optimal.")
   elif ($nics|length)==0 then
    finding("nic-coalescing";"Network";"UNKNOWN";"medium";"low";"NIC interrupt coalescing";"configuration";["NIC coalescing evidence unavailable"];
      "Network interrupt moderation is unknown.";
      "Collect ethtool coalescing state.")
   else
    finding("nic-coalescing";"Network";"PASS";"medium";"medium";"NIC interrupt coalescing";"configuration";
      ["no active NIC exposed non-zero rx/tx usecs"];
      "No non-zero active NIC coalescing delay was observed.";
      "Retain unless packet/IRQ measurements suggest another trade-off.")
   end),

  (if $hda_ps==null then
    finding("audio-powersave";"Audio";"UNKNOWN";"medium";"low";"HDA controller power saving";"configuration";["snd_hda_intel power_save unavailable"];
      "Host HDA power-saving behavior is unknown.";
      "Collect snd_hda_intel parameters for host-bound audio.")
   elif ([try ($hda_ps|tonumber) catch 0][0] // 0)>0 then
    finding("audio-powersave";"Audio";"WARN";"medium";"high";"HDA controller power saving";"configuration";
      ["snd_hda_intel power_save="+($hda_ps|tostring)];
      "Host-bound HDA audio is allowed to enter power-save states, which can add resume latency/pops on first use.";
      "If host HDA is part of the interactive audio path, benchmark power_save=0; if audio is passed through and the host driver is not used, prioritize clean VFIO assignment instead.")
   else
    finding("audio-powersave";"Audio";"PASS";"medium";"high";"HDA controller power saving";"configuration";
      ["snd_hda_intel power_save="+($hda_ps|tostring)];
      "HDA power saving is not enabled by a positive timeout.";
      "No change indicated for host HDA wake latency.")
   end),

  (if $throttle_count>0 then
    finding("thermal-throttle";"Thermal";"FAIL";"high";"high";"Thermal throttling evidence";"cumulative";
      ["thermal throttle count aggregate="+($throttle_count|tostring)];
      "Cumulative thermal-throttle counters are non-zero.";
      "Resolve cooling/power-limit causes and confirm sustained clocks under the desktop workload before scheduler/IRQ micro-tuning.")
   elif $tctl_milli==null then
    finding("thermal-throttle";"Thermal";"UNKNOWN";"high";"low";"Thermal headroom";"runtime-window";["CPU temperature/throttle evidence unavailable"];
      "Thermal headroom cannot be evaluated.";
      "Collect temperature and throttle counters during sustained desktop load.")
   elif $tctl_milli>=95000 then
    finding("thermal-throttle";"Thermal";"FAIL";"high";"medium";"Thermal headroom";"runtime-window";
      ["Tctl="+(($tctl_milli/1000)|tostring)+" C","no explicit throttle counter observed"];
      "The sampled CPU control temperature is extremely high and may leave little boost/throttle headroom.";
      "Improve cooling/power limits and repeat a sustained frequency/thermal measurement; do not infer throttling solely from temperature.")
   elif $tctl_milli>=85000 then
    finding("thermal-throttle";"Thermal";"WARN";"medium";"medium";"Thermal headroom";"runtime-window";
      ["Tctl="+(($tctl_milli/1000)|tostring)+" C"];
      "The sampled CPU temperature is warm enough to justify checking sustained frequency headroom.";
      "Measure clocks and thermal counters under the real desktop workload before changing CPU tuning.")
   else
    finding("thermal-throttle";"Thermal";"PASS";"medium";"medium";"Thermal headroom";"runtime-window";
      ["Tctl="+(($tctl_milli/1000)|tostring)+" C","explicit throttle counters="+($throttle_count|tostring)];
      "No throttle counter is observed and sampled Tctl is below the policy 85 C warning threshold.";
      "Repeat under sustained representative load; this is not proof of permanent thermal headroom.")
   end),

  finding("security-mitigations";"Security";"PASS";"high";"high";"Security mitigation posture";"configuration";
    [("explicit mitigation args="+str($h.security_mitigations.explicit_mitigation_arguments))];
    "The evaluator does not treat enabled security mitigations as a latency defect and does not recommend weakening them.";
    "Keep security mitigations enabled unless you have a separate threat-modelled security decision; performance tuning should work around them rather than disabling protections."),

  finding("host-latency-measurement";"Measurement";"UNKNOWN";"high";"high";"Direct host latency measurement";"measurement-gap";
    ["osnoise/timerlat/irqsoff/hwlat results are not part of normal inventory orchestration"];
    "Static configuration and passive pressure samples cannot prove low long-tail scheduling/interrupt latency.";
    "Run the opt-in osnoise and timerlat tools under representative desktop load; use irqsoff/hwlat only with their explicit acknowledgements when deeper tracing is justified."),

  finding("guest-frame-measurement";"Measurement";"UNKNOWN";"high";"high";"Guest frame pacing / DPC / ISR";"measurement-gap";
    ["guest-side Present timing, DPC/ISR and frame-time telemetry are outside the host inventory"];
    "Host evidence cannot prove end-to-end frame pacing or guest interrupt latency.";
    "Measure frame times/PresentMon-style telemetry plus guest DPC/ISR under the intended workload and correlate timestamps with host timerlat/osnoise, storage and network samples.")
]
) as $findings |
($findings | sort_by(stat_rank(.status), .category, .id)) as $sorted |
{
  schema_version:"0.1.0",
  model:"desktop-evaluation",
  policy:{
    id:"low-latency-virtualized-desktop-v1",
    objective:"deterministic frametimes, low long-tail latency, low host interference",
    target:"single high-performance virtualized desktop on Proxmox",
    note:"PASS/WARN/FAIL/UNKNOWN are policy verdicts for this target, not generic Proxmox health labels.",
    runtime_thresholds:{
      io_psi_avg10_warn_percent:5,
      io_psi_avg10_fail_percent:20,
      pve_storage_warn_percent:95,
      pve_storage_fail_percent:98,
      thermal_warn_c:85,
      thermal_fail_c:95
    }
  },
  source:{
    host:($h.source.hostname//"unknown"),
    host_map_schema:($h.schema_version//"unknown"),
    collection_window:($h.source.collection_window//null),
    kind:($h.source.kind//"unknown")
  },
  summary:{
    total:($sorted|length),
    pass:([$sorted[]|select(.status=="PASS")]|length),
    warn:([$sorted[]|select(.status=="WARN")]|length),
    fail:([$sorted[]|select(.status=="FAIL")]|length),
    unknown:([$sorted[]|select(.status=="UNKNOWN")]|length),
    high_or_critical_open:([$sorted[]|select((.status=="FAIL" or .status=="WARN") and (.severity=="critical" or .severity=="high"))]|length)
  },
  findings:$sorted,
  measurement_gaps:[$sorted[]|select(.scope=="measurement-gap")|.id],
  epistemic_limits:[
    "Runtime samples are windowed observations and can change immediately.",
    "Current-boot history is not equivalent to a permanent hardware diagnosis.",
    "Missing evidence produces UNKNOWN rather than an inferred tuning conclusion.",
    "Firmware toggles are not inferred from functional Linux evidence.",
    "Guest-side frame pacing, DPC/ISR and application scheduling require guest measurements."
  ]
}
' "$app_file" >"${app_tmpout:-/dev/stdout}" || { [ -n "$app_tmpout" ] && rm -f "$app_tmpout"; exit 1; }

if [ -n "$app_output" ]; then
    mv -- "$app_tmpout" "$app_output" || exit 1
    app_tmpout=
fi
exit 0
