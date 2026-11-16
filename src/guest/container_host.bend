import Base
import ./plan.bend as P
import ./container.bend as C
import ./values.bend as V

# Host integration of the C1 plan. The runtime supplies the network and
# mounts before starting PID 1. Keep the VM contracts unchanged.
def Container.post(s: V.Split) -> +List<P.Step>:
  match s:
    case V.Split{pre, post}:
      post

# The worker's cluster layer is shared with the VM worker. Its machine
# layer is replaced, as for the control plane in C.Plan.boot_container.
def Container.worker(+w: P.WCfg) -> +List<P.Step>:
  match w:
    case P.WCfg{+name, +ip, +token}:
      List.append(&2, P.Step, C.Container.system(),
      List.append(&2, P.Step, C.Container.cgroup_steps(),
      List.append(&2, P.Step, C.Container.sysctls(),
      List.append(&2, P.Step, [P.Write{"/etc/hosts", "127.0.0.1 localhost\n" ++ ip ++ " " ++ name ++ "\n"}, C.Container.share()],
        C.Container.kubelet_root(Container.post(V.Values.split(P.Plan.worker(P.WCfg{name, ip, token}))))))))

def Container.boot(worker: Bool, c: P.Cfg, w: P.WCfg) -> +List<P.Step>:
  match worker:
    case True{}:
      Container.worker(w)
    case False{}:
      C.Plan.boot_container(c)

def Container.select(enabled: Bool, worker: Bool, c: P.Cfg, w: P.WCfg, vm: +List<P.Step>) -> +List<P.Step>:
  match enabled:
    case True{}:
      Container.boot(worker, c, w)
    case False{}:
      vm

# The Linux time namespace does not isolate CLOCK_REALTIME. Memory
# compaction is host-wide too. Disk trimming belongs to the host that
# owns the data directory. Only VMs may run these maintenance steps.
def Container.machine_maintenance(container: Bool) -> Bool:
  Bool.not(container)

# A stop request on the private host share needs no signal handler or
# new C effect. PID 1 stops services in Sup.stop_order, then exits; the
# kernel ends the remaining processes in that PID namespace.
def Container.stop_path() -> String:
  P.Plan.host_dir() ++ "/stop"

def Container.stop_requested(text: String) -> Bool:
  String.eq(String.trim(text), "stop")

def Container.supported(+role: String, classic: Bool) -> Bool:
  Bool.not(classic) && (String.eq(role, "") || String.eq(role, "vk8s")
    || String.eq(role, "control-plane") || String.eq(role, "worker"))

# Pure parent path for Init.write: no shell expansion is needed.
def Container.parent.parts(xs: +List<String>) -> String:
  match xs:
    case Con{x, rest}:
      String.join(List.reverse(&2, String, rest), "/")
    case Nil{}:
      "/"

def Container.parent(path: String) -> String:
  Container.parent.parts(List.reverse(&2, String, String.split(path, '/')))

# --- The host executor's inputs (C2)

def Container.or_ip(empty: Bool, +old: String, +ip: String) -> String:
  match empty:
    case True{}:
      old
    case False{}:
      ip

def Container.with_ip(+c: P.Cfg, +ip: String) -> P.Cfg:
  match c:
    case P.Cfg{name, old, svc, pod, dom, port, etcd}:
      P.Cfg{name, Container.or_ip(String.is_empty(ip), old, ip), svc, pod, dom, port, etcd}

# A container's control plane is at the address its host gave its eth0
# (VK8S_NODE_IP, 10.10.<slot>.2: one host kernel holds every cluster's
# LAN, src/cli/ctr.bend), not at the VM LAN's fixed 10.10.0.2; the
# certificates, the discovery kubeconfig and kubelet's node IP follow it.
def Container.cfg(container: Bool, +ip: String, c: P.Cfg) -> P.Cfg:
  match container:
    case True{}:
      Container.with_ip(c, ip)
    case False{}:
      c

# kube-proxy must not set the host's conntrack table size from inside a
# node container, where nf_conntrack_max is read-only: kind's kubeadm
# config sets conntrack.maxPerCore to 0 for this
# (pkg/cluster/internal/kubeadm/config.go, KubeProxyConfiguration).
def Container.kube_proxy_conf() -> String:
  "---\napiVersion: kubeproxy.config.k8s.io/v1alpha1\nkind: KubeProxyConfiguration\nconntrack:\n  maxPerCore: 0\n"

def Container.conntrack.write(hit: Bool, +path: String, +text: String) -> P.Step:
  match hit:
    case True{}:
      P.Write{path, text ++ Container.kube_proxy_conf()}
    case False{}:
      P.Write{path, text}

def Container.conntrack.step(s: P.Step) -> P.Step:
  match s:
    case P.Mount{fs, src, dst, opts}:
      P.Mount{fs, src, dst, opts}
    case P.Write{+path, text}:
      Container.conntrack.write(String.eq(path, P.Plan.data() ++ "/kubeadm.yaml"), path, text)
    case P.Run{prog, args}:
      P.Run{prog, args}
    case P.Daemon{name, prog, args}:
      P.Daemon{name, prog, args}
    case P.Spawn{name, prog, args}:
      P.Spawn{name, prog, args}
    case P.WaitTcp{host, port, ms}:
      P.WaitTcp{host, port, ms}
    case P.Stop{names}:
      P.Stop{names}
    case P.WaitFile{path, ms}:
      P.WaitFile{path, ms}
    case P.Modules{path}:
      P.Modules{path}
    case P.Log{text}:
      P.Log{text}

# The kubeadm config of a plan gets Container.kube_proxy_conf.
def Container.conntrack(ss: +List<P.Step>) -> +List<P.Step>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      Con{Container.conntrack.step(s), Container.conntrack(t)}

def Container.conntrack_if(container: Bool, ss: +List<P.Step>) -> +List<P.Step>:
  match container:
    case True{}:
      Container.conntrack(ss)
    case False{}:
      ss

# The image cache is a VM the containers do not have: their containerd
# pulls from the registries, with no hosts.toml pointing at the cache's
# address (P.Plan.mirror_steps, 10.0.2.2 on bend-vmm's NAT), which on a
# Linux host would only delay each pull until it timed out.
def Container.mirror(s: P.Step) -> Bool:
  match s:
    case P.Write{path, text}:
      String.starts_with(path, "/etc/containerd/certs.d/")
    case _:
      False{}

def Container.keep(drop: Bool, s: P.Step, rest: +List<P.Step>) -> +List<P.Step>:
  match drop:
    case True{}:
      rest
    case False{}:
      Con{s, rest}

def Container.no_mirrors(ss: +List<P.Step>) -> +List<P.Step>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{+s, t}:
      Container.keep(Container.mirror(s), s, Container.no_mirrors(t))

# A container's plan, adapted for the host kernel and network: no cache
# mirrors, and kube-proxy leaves the conntrack size alone.
def Container.adapt(container: Bool, ss: +List<P.Step>) -> +List<P.Step>:
  match container:
    case True{}:
      Container.conntrack(Container.no_mirrors(ss))
    case False{}:
      ss
