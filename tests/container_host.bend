import Base
import ../src/guest/container_host.bend as H
import ../src/guest/container.bend as C
import ../src/guest/plan.bend as P

def T.check(+name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name)

def T.ip(c: P.Cfg) -> String:
  match c:
    case P.Cfg{name, ip, svc, pod, dom, port, etcd}:
      ip

def T.any_mirror(ss: +List<P.Step>) -> Bool:
  match ss:
    case Nil{}:
      False{}
    case Con{s, t}:
      H.Container.mirror(s) || T.any_mirror(t)

def main() -> IO(Unit):
  do IO<Unit>:
    T.check("container maintenance cannot change host clock", Bool.not(H.Container.machine_maintenance(True{})))
    T.check("VM maintenance stays enabled", H.Container.machine_maintenance(False{}))
    T.check("container stop is explicit", H.Container.stop_requested("stop\n"))
    T.check("an empty stop file does not stop PID 1", Bool.not(H.Container.stop_requested("")))
    T.check("worker plan loads no guest kernel modules", Bool.not(C.Container.has_modules(H.Container.worker(P.WCfg{"demo-worker-1", "10.10.0.3", "abcdef.0123456789abcdef"}))))
    T.check("control plane plan loads no guest kernel modules", Bool.not(C.Container.has_modules(H.Container.boot(False{}, P.Plan.default_cfg("demo", 6443, False{}), P.WCfg{"", "", ""}))))
    T.check("a container control plane takes its host-given address", String.eq(T.ip(H.Container.cfg(True{}, "10.10.4.2", P.Plan.default_cfg("demo", 6443, False{}))), "10.10.4.2"))
    T.check("a VM control plane keeps the LAN address", String.eq(T.ip(H.Container.cfg(False{}, "10.10.4.2", P.Plan.default_cfg("demo", 6443, False{}))), "10.10.0.2"))
    T.check("the container plan has no cache mirrors", Bool.not(T.any_mirror(H.Container.adapt(True{}, C.Plan.boot_container(P.Plan.default_cfg("demo", 6443, False{}))))))
    T.check("the VM plan keeps its cache mirrors", T.any_mirror(H.Container.adapt(False{}, P.Plan.boot(P.Plan.default_cfg("demo", 6443, False{})))))
