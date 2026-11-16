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

def main() -> IO(Unit):
  do IO<Unit>:
    T.check("container maintenance cannot change host clock", Bool.not(H.Container.machine_maintenance(True{})))
    T.check("VM maintenance stays enabled", H.Container.machine_maintenance(False{}))
    T.check("container stop is explicit", H.Container.stop_requested("stop\n"))
    T.check("an empty stop file does not stop PID 1", Bool.not(H.Container.stop_requested("")))
    T.check("worker plan loads no guest kernel modules", Bool.not(C.Container.has_modules(H.Container.worker(P.WCfg{"demo-worker-1", "10.10.0.3", "abcdef.0123456789abcdef"}))))
    T.check("control plane plan loads no guest kernel modules", Bool.not(C.Container.has_modules(H.Container.boot(False{}, P.Plan.default_cfg("demo", 6443, False{}), P.WCfg{"", "", ""}))))
