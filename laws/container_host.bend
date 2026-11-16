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

# Proposed: the host executor's inputs (Phase 6 C2). A container's control
# plane takes the address its host gave it; a VM's keeps the LAN's.
law container_host.cfg:
  {H.Container.cfg(True{}, "10.10.1.2", P.Plan.default_cfg("demo", 6443, False{})) ==
    P.Cfg{"demo", "10.10.1.2", "10.96.0.0/12", "10.244.0.0/16", "cluster.local", 6443, False{}} : P.Cfg}

law container_host.cfg_unset:
  {H.Container.cfg(True{}, "", P.Plan.default_cfg("demo", 6443, True{})) == P.Plan.default_cfg("demo", 6443, True{}) : P.Cfg}

law container_host.cfg_vm:
  for c: P.Cfg
  {H.Container.cfg(False{}, "10.10.1.2", c) == c : P.Cfg}

# kube-proxy leaves the host's conntrack size alone (kind's kubeadm config,
# conntrack.maxPerCore: 0); other steps stay.
law container_host.conntrack:
  {H.Container.conntrack([P.Write{"/var/lib/vcluster/kubeadm.yaml", "kind: InitConfiguration\n"}, P.Write{"/x", "y"}, P.Log{"z"}]) ==
    [ P.Write{"/var/lib/vcluster/kubeadm.yaml", "kind: InitConfiguration\n---\napiVersion: kubeproxy.config.k8s.io/v1alpha1\nkind: KubeProxyConfiguration\nconntrack:\n  maxPerCore: 0\n"},
      P.Write{"/x", "y"}, P.Log{"z"} ] : +List<P.Step>}

law container_host.conntrack_vm:
  for ss: +List<P.Step>
  {H.Container.conntrack_if(False{}, ss) == ss : +List<P.Step>}

# The containers' containerd pulls from the registries: no hosts.toml for
# the cache VM, which only VMs reach.
law container_host.no_mirrors:
  {H.Container.no_mirrors([P.Write{"/etc/containerd/certs.d/docker.io/hosts.toml", "server"}, P.Write{"/etc/containerd/config.toml", "version = 3\n"}]) ==
    [P.Write{"/etc/containerd/config.toml", "version = 3\n"}] : +List<P.Step>}

law container_host.adapt_vm:
  for ss: +List<P.Step>
  {H.Container.adapt(False{}, ss) == ss : +List<P.Step>}
