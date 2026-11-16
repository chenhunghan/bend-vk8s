import Base
import ../src/guest/plan.bend as P
import ../src/guest/container.bend as C

# The renderer of tests/container_runc.sh, the runc smoke of
# src/guest/container.bend (runc is only the test's harness):
# - `config CLUSTER NODE ROOTFS DATA SHARE ASSETS [ENV...]` prints the
#   node's config.json (C.Container.json);
# - `steps` prints PID 1's first container steps (C.Plan.boot_container's
#   applets, shared mounts and cgroup delegation, then C.Container.sysctls)
#   as shell lines, each followed by a PASS or FAIL line;
# - no argument (scripts/check.sh): checks that both render.

def R.plus(xs: List<String>) -> +List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, t}:
      Con{x, R.plus(t)}

def R.head(xs: +List<String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, t}:
      x

def R.at(xs: +List<String>, n: Nat) -> String:
  R.head(List.drop(&2, String, xs, n))

def R.q(s: String) -> String:
  P.Plan.sh_quote(s)

# One step as a shell command; only the kinds the first steps use.
def R.cmd(s: P.Step) -> String:
  match s:
    case P.Run{prog, args}:
      R.q(prog) ++ P.Plan.sh_words(args)
    case P.Write{+path, text}:
      "mkdir -p \"$(dirname " ++ R.q(path) ++ ")\" && printf %s " ++ R.q(text) ++ " > " ++ R.q(path)
    case P.Mount{fs, src, +dst, opts}:
      "mkdir -p " ++ R.q(dst) ++ " && mount -t " ++ R.q(fs) ++ " -o " ++ R.q(opts) ++ " " ++ R.q(src) ++ " " ++ R.q(dst)
    case _:
      "false"

def R.line(s: P.Step) -> String:
  +c = R.cmd(s)
  "if { " ++ c ++ "; }; then echo " ++ R.q("PASS step: " ++ c) ++ "; else echo " ++ R.q("FAIL step: " ++ c) ++ "; fi"

def R.lines(ss: +List<P.Step>) -> String:
  match ss:
    case Nil{}:
      ""
    case Con{s, t}:
      R.line(s) ++ "\n" ++ R.lines(t)

def R.steps() -> +List<P.Step>:
  List.append(&2, P.Step, List.take(&2, P.Step, C.Plan.boot_container(P.Plan.default_cfg("smoke", 6443, False{})), 7n), C.Container.sysctls())

def R.spec(+args: +List<String>) -> C.Spec:
  C.Spec{R.at(args, 2n), R.at(args, 3n), R.at(args, 4n), R.at(args, 5n), R.at(args, 6n), R.at(args, 7n), List.drop(&2, String, args, 8n)}

def R.check(+name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name)

def R.self_check() -> IO(Unit):
  do IO<Unit>:
    R.check("container_runc: the config renders",
      String.starts_with(C.Container.json(R.spec(["r", "config", "c", "n", "/r", "/d", "/s", "/a", "X=1"])), "{\"ociVersion\":\"1.0.2\","))
    R.check("container_runc: the steps render, with the cgroup delegation",
      String.contains(R.lines(R.steps()), "printf %s '1' > '/sys/fs/cgroup/init.scope/cgroup.procs'"))

def R.mode(config: Bool, steps: Bool, +args: +List<String>) -> IO(Unit):
  match config steps:
    case True{} _:
      IO.print(C.Container.json(R.spec(args)))
    case False{} True{}:
      IO.print(R.lines(R.steps()))
    case False{} False{}:
      R.self_check()

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<String> <- IO.args()
    +args : +List<String> = R.plus(xs)
    R.mode(String.eq(R.at(args, 1n), "config"), String.eq(R.at(args, 1n), "steps"), args)
