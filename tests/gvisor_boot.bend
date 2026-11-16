import Base
import ../src/guest/plan.bend as P

# The renderer of the gVisor boot in tests/kernel16k_boot.sh (role
# gvisor, docs/GOAL.md section 8). That harness has no vk8s-init as PID 1
# (it needs bend and zig), so this prints the real boot plan's steps for
# a standalone node as shell, and the test's PID 1 runs them:
#   Plan.network, Plan.pki_steps, the store (kine), the control plane
#   without the join server (vk8s-guest is not in the harness),
#   Plan.node up to the kubelet (Plan.runtime: the containerd config with
#   the runsc runtime and runsc.toml), and the RuntimeClass steps of
#   Plan.node. The one extra step is a bridge CNI config
#   (Plan.cni_config), in place of flannel, whose image the harness has
#   no network to pull.
# Waits are 5 times the plan's: qemu emulates the CPU (TCG).
# - `steps` prints the script;
# - no argument (scripts/check.sh): checks that it renders.

def G.plus(xs: List<String>) -> +List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, t}:
      Con{x, G.plus(t)}

def G.head(xs: +List<String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, t}:
      x

def G.q(s: String) -> String:
  P.Plan.sh_quote(s)

def G.cfg() -> P.Cfg:
  P.Plan.default_cfg("gvisor", 6443, False{})

# seconds to wait for a plan wait of ms, under TCG
def G.secs(ms: U32) -> String:
  U32.show((ms / 200 : U32))

# a wait loop in a subshell: fails after n seconds
def G.wait(+cond: String, +n: String) -> String:
  "( i=0; until " ++ cond ++ "; do [ $i -ge " ++ n ++ " ] && exit 1; sleep 1; i=$((i+1)); done )"

# a TCP port in LISTEN (state 0A) in /proc/net/tcp or tcp6
def G.listening(port: U32) -> String:
  "awk -v p=\":$(printf %04X " ++ U32.show(port) ++ ")\" '$2 ~ p\"$\" && $4 == \"0A\" { f = 1 } END { exit !f }' /proc/net/tcp /proc/net/tcp6 2>/dev/null"

# One step as a shell command, and what the log line names it.
def G.cmd(s: P.Step) -> String:
  match s:
    case P.Mount{fs, src, +dst, opts}:
      "mkdir -p " ++ G.q(dst) ++ " && mount -t " ++ G.q(fs) ++ " -o " ++ G.q(opts) ++ " " ++ G.q(src) ++ " " ++ G.q(dst)
    case P.Write{+path, text}:
      "mkdir -p \"$(dirname " ++ G.q(path) ++ ")\" && printf %s " ++ G.q(text) ++ " > " ++ G.q(path)
    case P.Run{prog, args}:
      G.q(prog) ++ P.Plan.sh_words(args)
    case P.Daemon{name, prog, args}:
      P.Plan.daemon_cmd(name, prog, args)
    case P.Spawn{name, prog, args}:
      P.Plan.daemon_cmd(name, prog, args)
    case P.WaitTcp{host, port, ms}:
      G.wait(G.listening(port), G.secs(ms))
    case P.Stop{names}:
      "true"
    case P.WaitFile{+path, ms}:
      G.wait("[ -e " ++ G.q(path) ++ " ]", G.secs(ms))
    case P.Modules{path}:
      "true"
    case P.Log{text}:
      "echo " ++ G.q(text)

def G.name(s: P.Step) -> String:
  match s:
    case P.Mount{fs, src, dst, opts}:
      "mount " ++ dst
    case P.Write{path, text}:
      "write " ++ path
    case P.Run{prog, args}:
      "run " ++ prog ++ " " ++ G.head(args)
    case P.Daemon{name, prog, args}:
      "daemon " ++ name
    case P.Spawn{name, prog, args}:
      "spawn " ++ name
    case P.WaitTcp{host, port, ms}:
      "wait tcp " ++ U32.show(port)
    case P.Stop{names}:
      "stop"
    case P.WaitFile{path, ms}:
      "wait file " ++ path
    case P.Modules{path}:
      "modules"
    case P.Log{text}:
      "log"

# Each step stops the script when it fails, as PID 1 stops the boot.
def G.line(+s: P.Step) -> String:
  +n = G.q(G.name(s))
  "if { " ++ G.cmd(s) ++ "; }; then echo \"vk8s-test: gvisor step ok: \"" ++ n
    ++ "; else echo \"vk8s-test: gvisor step failed: \"" ++ n ++ "; exit 1; fi"

def G.lines(ss: +List<P.Step>) -> String:
  match ss:
    case Nil{}:
      ""
    case Con{s, t}:
      G.line(s) ++ "\n" ++ G.lines(t)

def G.plan() -> +List<P.Step>:
  List.append(&2, P.Step, P.Plan.network(G.cfg()),
  List.append(&2, P.Step, P.Plan.pki_steps(G.cfg()),
  List.append(&2, P.Step, P.Plan.store(False{}, "gvisor"),
  List.append(&2, P.Step, List.take(&2, P.Step, P.Plan.control_plane.k8s(G.cfg()), 5n),
  List.append(&2, P.Step, [P.Write{"/etc/cni/net.d/10-vk8s.conflist", P.Plan.cni_config()}],
  List.append(&2, P.Step, List.take(&2, P.Step, P.Plan.node(G.cfg()), 15n),
    List.take(&2, P.Step, List.drop(&2, P.Step, P.Plan.node(G.cfg()), 27n), 2n)))))))

def G.script() -> String:
  "set -u\nexport PATH=" ++ P.Plan.path() ++ "\nmkdir -p " ++ P.Plan.host_dir() ++ "/logs\n" ++ G.lines(G.plan())
    ++ "echo 'vk8s-test: gvisor plan done'\n"

def G.check(+name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name)

def G.self_check() -> IO(Unit):
  do IO<Unit>:
    G.check("gvisor_boot: the plan writes the runsc runtime and runsc.toml",
      String.contains(G.script(), G.q(P.Plan.containerd_config.v2()) ++ " > '/etc/containerd/config.toml'")
        && String.contains(G.script(), G.q(P.Plan.runsc_toml()) ++ " > '/etc/containerd/runsc.toml'"))
    G.check("gvisor_boot: the plan starts containerd and the kubelet",
      String.contains(G.script(), "step ok: \"'daemon containerd'")
        && String.contains(G.script(), "step ok: \"'daemon kubelet'"))
    G.check("gvisor_boot: the plan applies the gvisor RuntimeClass last",
      String.contains(G.script(), "step ok: \"'run /var/lib/vcluster/bin/kubectl --kubeconfig'; else")
        && String.contains(G.script(), "'apply' '-f' '/etc/vk8s/runtimeclass-gvisor.yaml'"))
    G.check("gvisor_boot: no join server (vk8s-guest is not in the harness)",
      Bool.not(String.contains(G.script(), "join-server")))

def G.mode(steps: Bool) -> IO(Unit):
  match steps:
    case True{}:
      IO.print(G.script())
    case False{}:
      G.self_check()

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<String> <- IO.args()
    +args : +List<String> = G.plus(xs)
    G.mode(String.eq(G.head(List.drop(&2, String, args, 1n)), "steps"))
