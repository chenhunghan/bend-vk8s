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
