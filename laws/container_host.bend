import Base
import ../src/guest/container_host.bend as H
import ../src/guest/container.bend as C
import ../src/guest/plan.bend as P

# Proposed: shared-kernel lifecycle rules, Phase 6 C3. Linux documents
# CLOCK_REALTIME as outside time namespaces (time_namespaces(7)); the
# kernel's compact_memory sysctl acts on all zones. A container must not
# use the VM maintenance path.
law container_host.no_machine_maintenance:
  {H.Container.machine_maintenance(True{}) == False{} : Bool}

law container_host.vm_maintenance:
  {H.Container.machine_maintenance(False{}) == True{} : Bool}

law container_host.stop:
  {H.Container.stop_requested("stop\n") == True{} : Bool}

law container_host.no_stop:
  {H.Container.stop_requested("") == False{} : Bool}

law container_host.worker_no_modules:
  {C.Container.has_modules(H.Container.worker(P.WCfg{"demo-worker-1", "10.10.0.3", "abcdef.0123456789abcdef"})) == False{} : Bool}

law container_host.control_plane:
  for c: P.Cfg
  for w: P.WCfg
  {H.Container.boot(False{}, c, w) == C.Plan.boot_container(c) : +List<P.Step>}

law container_host.parent:
  {H.Container.parent("/sys/fs/cgroup/init.scope/cgroup.procs") == "/sys/fs/cgroup/init.scope" : String}

# Proposed: container role selection must not silently turn a cache or
# classic-mode request into a standalone control plane.
law container_host.refuse_classic:
  {H.Container.supported("control-plane", True{}) == False{} : Bool}

law container_host.refuse_cache:
  {H.Container.supported("cache", False{}) == False{} : Bool}
