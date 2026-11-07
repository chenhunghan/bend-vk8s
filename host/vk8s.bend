import Base
import 0x88887434395ee9936f9b6f658e234140/main.bend as V
import ../src/cli/cli.bend as C
import ../src/cli/kubeconfig.bend as K
import ../src/guest/plan.bend as P

# vk8s: one binary. On the host it manages virtual clusters, each a bend-vmm
# VM that this same binary runs as `vk8s vmm ...` (bend-vmm as a library,
# one VM per process).

type Sh is Data:
  Sh{ok: Bool, out: String}

def Vk8s.sh.got(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> Sh:
  match r:
    case Fail{(c, m)}:
      Sh{False{}, m}
    case Done{(st, (out, err))}:
      Sh{U32.is_eq(st, 0), out ++ err}

# Run a shell command line on the host.
def Vk8s.sh(+cmd: String) -> IO(Sh):
  do IO<Sh>:
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/bin/sh", ["-c", cmd], "", 4194304, 600000)
    return Vk8s.sh.got(r)

def Vk8s.q(s: String) -> String:
  P.Plan.sh_quote(s)

def Vk8s.env(r: Result<&1, &1, U32 & String, String>, +dflt: String) -> String:
  match r:
    case Fail{e}:
      dflt
    case Done{s}:
      s

def Vk8s.getenv(+k: String, +dflt: String) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env(k)
    return Vk8s.env(r, dflt)

def Vk8s.say(+s: String) -> IO(Unit):
  IO.print(s)

def Vk8s.die(+s: String) -> IO(Unit):
  do IO<Unit>:
    IO.print_err(s)
    IO.exit(1)

def Vk8s.sh_ok.of(r: Sh) -> Bool:
  match r:
    case Sh{ok, out}:
      ok

def Vk8s.sh_ok(+cmd: String) -> IO(Bool):
  do IO<Bool>:
    r : Sh <- Vk8s.sh(cmd)
    return Vk8s.sh_ok.of(r)

def Vk8s.sh_out.of(r: Sh) -> String:
  match r:
    case Sh{ok, out}:
      String.trim(out)

def Vk8s.sh_out(+cmd: String) -> IO(String):
  do IO<String>:
    r : Sh <- Vk8s.sh(cmd)
    return Vk8s.sh_out.of(r)

# One line to the VM's control socket; its one-line answer.
def Vk8s.control(+dir: String, +line: String) -> IO(String):
  Vk8s.sh_out("printf '%s\\n' " ++ Vk8s.q(line) ++ " | nc -U -w 5 " ++ Vk8s.q(dir ++ "/ctl.sock") ++ " 2>/dev/null")

def Vk8s.sleep_then(next: IO(Bool)) -> IO(Bool):
  do IO<Bool>:
    IO.sleep(500)
    next

def Vk8s.or_retry(ok: Bool, retry: IO(Bool)) -> IO(Bool):
  match ok:
    case True{}:
      IO.pure(Bool, True{})
    case False{}:
      retry

# Wait until a file exists (n tries, 500 ms apart).
def Vk8s.wait_file(n: Nat, +path: String) -> IO(Bool):
  match n:
    case 0n:
      IO.pure(Bool, False{})
    case 1n+p:
      do IO<Bool>:
        ok : Bool <- Vk8s.sh_ok("test -s " ++ Vk8s.q(path))
        Vk8s.or_retry(ok, Vk8s.sleep_then(Vk8s.wait_file(p, path)))

def Vk8s.when(ok: Bool, act: IO(Unit)) -> IO(Unit):
  match ok:
    case True{}:
      act
    case False{}:
      IO.pure(Unit, Unit{})

def Vk8s.unless(ok: Bool, act: IO(Unit)) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      act

def Vk8s.home() -> IO(String):
  Vk8s.getenv("HOME", "/tmp")

def Vk8s.assets(+home: String) -> IO(String):
  Vk8s.getenv("VK8S_ASSETS", home ++ "/.vk8s/assets/v1.36.6")

def Vk8s.self.prog(args: List<String>) -> String:
  match args:
    case Con{p, rest}:
      p
    case Nil{}:
      "vk8s"

def Vk8s.self.abs(+p: String) -> IO(String):
  Vk8s.sh_out("p=" ++ Vk8s.q(p) ++ "; case $p in /*) echo $p;; */*) echo $PWD/$p;; *) command -v $p;; esac")

# This program's absolute path, to start `vk8s vmm` children.
def Vk8s.self() -> IO(String):
  do IO<String>:
    args : List<String> <- IO.args()
    Vk8s.self.abs(Vk8s.self.prog(args))

# Start worker VMs i..i+n-1 (vcluster private nodes; vind's extra node
# containers), each joining with the control plane's token.
def Vk8s.workers(n: Nat, +i: U32, +self: String, +dir: String, +assets: String, +name: String, +token: String) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+rest:
      do IO<Unit>:
        +node : String = C.Cli.worker_name(name, i)
        +ndir : String = dir ++ "/nodes/" ++ node
        Vk8s.say("Starting node " ++ node ++ " (" ++ C.Cli.lan_ip(i) ++ ")...")
        made : Bool <- Vk8s.sh_ok("mkdir -p " ++ Vk8s.q(ndir ++ "/share") ++ " && cp -c " ++ Vk8s.q(assets ++ "/data.img") ++ " "
          ++ Vk8s.q(ndir ++ "/data.img") ++ " && cp " ++ Vk8s.q(dir ++ "/share/discovery.conf") ++ " " ++ Vk8s.q(ndir ++ "/share/"))
        Vk8s.unless(made, Vk8s.die("could not set up " ++ ndir))
        +flags : +List<String> = C.Cli.worker_flags(dir, ndir, assets, node, i, token, 2, 2048)
        started : Bool <- Vk8s.sh_ok("cd " ++ Vk8s.q(ndir) ++ " && { nohup " ++ Vk8s.q(self) ++ " vmm"
          ++ P.Plan.sh_words(flags) ++ " </dev/null >console.log 2>&1 & } && echo $! > vmm.pid")
        Vk8s.unless(started, Vk8s.die("could not start " ++ node))
        Vk8s.workers(rest, (i + 1 : U32), self, dir, assets, name, token)

def Vk8s.and_then(ok: Bool, next: IO(Bool)) -> IO(Bool):
  match ok:
    case True{}:
      next
    case False{}:
      IO.pure(Bool, False{})

def Vk8s.wait_workers(n: Nat, +i: U32, +dir: String, +name: String) -> IO(Bool):
  match n:
    case 0n:
      IO.pure(Bool, True{})
    case 1n+rest:
      do IO<Bool>:
        ok : Bool <- Vk8s.wait_file(U32.to_nat(1200), dir ++ "/nodes/" ++ C.Cli.worker_name(name, i) ++ "/share/joined")
        Vk8s.and_then(ok, Vk8s.wait_workers(rest, (i + 1 : U32), dir, name))

def Vk8s.pick_port(auto: Bool, +p: U32, +seed: U32) -> U32:
  match auto:
    case True{}:
      C.Cli.port_from(seed)
    case False{}:
      p

def Vk8s.create(+name: String, +port0: U32, +cpus: U32, +mem: U32, +etcd: Bool, +nodes: U32) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +assets : String <- Vk8s.assets(home)
    +dir : String = C.Cli.dir(home, name)
    exists : Bool <- Vk8s.sh_ok("test -e " ++ Vk8s.q(dir))
    Vk8s.when(exists, Vk8s.die("vCluster " ++ name ++ " already exists, delete it first"))
    have : Bool <- Vk8s.sh_ok("test -f " ++ Vk8s.q(assets ++ "/vk8s.cpio") ++ " -a -f " ++ Vk8s.q(assets ++ "/data.img"))
    Vk8s.unless(have, Vk8s.die("vk8s assets not found in " ++ assets ++ " (set VK8S_ASSETS)"))
    now : Nat <- IO.now()
    +port : U32 = Vk8s.pick_port(U32.is_eq(port0, 0), port0, U32.from_nat(now))
    +self : String <- Vk8s.self()
    Vk8s.say("Creating vCluster " ++ name ++ " (API on 127.0.0.1:" ++ U32.show(port) ++ ")...")
    made : Bool <- Vk8s.sh_ok("mkdir -p " ++ Vk8s.q(dir ++ "/share") ++ " && chmod 700 " ++ Vk8s.q(dir)
      ++ " && cp -c " ++ Vk8s.q(assets ++ "/data.img") ++ " " ++ Vk8s.q(dir ++ "/data.img")
      ++ " && echo " ++ U32.show(port) ++ " > " ++ Vk8s.q(dir ++ "/port"))
    Vk8s.unless(made, Vk8s.die("could not set up " ++ dir))
    +flags : +List<String> = C.Cli.vmm_flags(dir, assets, name, port, cpus, mem, etcd)
    started : Bool <- Vk8s.sh_ok("cd " ++ Vk8s.q(dir) ++ " && { nohup " ++ Vk8s.q(self) ++ " vmm"
      ++ P.Plan.sh_words(flags) ++ " </dev/null >console.log 2>&1 & } && echo $! > vmm.pid")
    Vk8s.unless(started, Vk8s.die("could not start the VM"))
    up : Bool <- Vk8s.wait_file(360n, dir ++ "/share/kubeconfig.yaml")
    Vk8s.unless(up, Vk8s.die("vCluster " ++ name ++ " did not come up in 3 minutes; see " ++ dir ++ "/console.log"))
    token : String <- Vk8s.sh_out("cat " ++ Vk8s.q(dir ++ "/share/join-token") ++ " 2>/dev/null")
    _ : Unit <- Vk8s.workers(U32.to_nat(nodes), 1, self, dir, assets, name, token)
    joined : Bool <- Vk8s.wait_workers(U32.to_nat(nodes), 1, dir, name)
    Vk8s.unless(joined, Vk8s.die("a worker node of " ++ name ++ " did not join in 10 minutes; see " ++ dir ++ "/nodes/*/console.log"))
    Vk8s.say("Successfully created virtual cluster " ++ name ++ ".")
    Vk8s.say("- Use 'vk8s connect " ++ name ++ "' to access the virtual cluster")
    Vk8s.say("  export KUBECONFIG=" ++ dir ++ "/share/kubeconfig.yaml")

def Vk8s.raw.got(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> Sh:
  match r:
    case Fail{(c, m)}:
      Sh{False{}, ""}
    case Done{(st, (out, err))}:
      Sh{U32.is_eq(st, 0), out}

def Vk8s.raw.out(r: Sh) -> String:
  match r:
    case Sh{ok, out}:
      out

# A file's bytes, untrimmed; a missing file reads as "" (ok), an unreadable
# one fails.
def Vk8s.read(+path: String) -> IO(Sh):
  do IO<Sh>:
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/bin/sh",
      ["-c", "[ ! -e \"$1\" ] || cat \"$1\"", "sh", path], "", 16777216, 10000)
    return Vk8s.raw.got(r)

# Replaces a file atomically (a temp file beside it, mode 0600, renamed over
# it), creating its directory, as clientcmd writes a kubeconfig.
def Vk8s.put_file(+path: String, data: String) -> IO(Bool):
  do IO<Bool>:
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/bin/sh",
      ["-c", "d=$(dirname \"$1\") && mkdir -p \"$d\" && t=$(mktemp \"$d/.vk8s-kubeconfig.XXXXXX\") || exit 1; "
        ++ "{ cat > \"$t\" && chmod 600 \"$t\" && mv -f \"$t\" \"$1\"; } || { rm -f \"$t\"; exit 1; }", "sh", path],
      data, 65536, 10000)
    return Vk8s.sh_ok.of(Vk8s.raw.got(r))

# The kubeconfig vk8s writes to: the first entry of $KUBECONFIG, else
# ~/.kube/config.
def Vk8s.kubeconfig(+home: String) -> IO(String):
  do IO<String>:
    env : String <- Vk8s.getenv("KUBECONFIG", "")
    return K.Kubeconfig.target(env, home)

def Vk8s.connected(set: Bool, +ctx: String, +target: String) -> String:
  match set:
    case True{}:
      "Switched active kube context to " ++ ctx ++ "\n- Use `kubectl get namespaces` to access the vcluster"
    case False{}:
      "Added kube context " ++ ctx ++ " to " ++ target ++ "\n- Use `kubectl --context " ++ ctx ++ " get namespaces` to access the vcluster"

def Vk8s.connect.write(r: Result<&2, &2, String, String>, set: Bool, +ctx: String, +target: String) -> IO(Unit):
  match r:
    case Fail{e}:
      Vk8s.die("vk8s connect: " ++ e)
    case Done{s}:
      do IO<Unit>:
        ok : Bool <- Vk8s.put_file(target, s)
        Vk8s.unless(ok, Vk8s.die("vk8s connect: could not write " ++ target))
        Vk8s.say(Vk8s.connected(set, ctx, target))

# Merges the cluster's kubeconfig into the user's (vcluster writeKubeConfig
# with --update-current: clihelper.UpdateKubeConfig).
def Vk8s.connect.merge(set: Bool, incoming: String, +ctx: String, +home: String) -> IO(Unit):
  do IO<Unit>:
    +target : String <- Vk8s.kubeconfig(home)
    +cur : Sh <- Vk8s.read(target)
    Vk8s.unless(Vk8s.sh_ok.of(cur), Vk8s.die("vk8s connect: could not read " ++ target))
    Vk8s.connect.write(K.Kubeconfig.merge(Vk8s.raw.out(cur), incoming, ctx, set), set, ctx, target)

def Vk8s.connect.print(r: Result<&2, &2, String, String>) -> IO(Unit):
  match r:
    case Fail{e}:
      Vk8s.die("vk8s connect: " ++ e)
    case Done{s}:
      IO.write(s)

def Vk8s.connect.go(print: Bool, set: Bool, incoming: String, +ctx: String, +home: String) -> IO(Unit):
  match print:
    case True{}:
      Vk8s.connect.print(K.Kubeconfig.rename(incoming, ctx))
    case False{}:
      Vk8s.connect.merge(set, incoming, ctx, home)

# vcluster connect --driver docker: the cluster's kubeconfig, with its
# cluster, context and user renamed to vk8s_NAME, printed (--print) or
# merged into the user's kubeconfig.
def Vk8s.connect(+name: String, print: Bool, set: Bool) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +kc : String = C.Cli.dir(home, name) ++ "/share/kubeconfig.yaml"
    ok : Bool <- Vk8s.sh_ok("test -s " ++ Vk8s.q(kc))
    Vk8s.unless(ok, Vk8s.die("vCluster " ++ name ++ " not found or not ready"))
    +got : Sh <- Vk8s.read(kc)
    Vk8s.unless(Vk8s.sh_ok.of(got), Vk8s.die("vk8s connect: could not read " ++ kc))
    Vk8s.connect.go(print, set, Vk8s.raw.out(got), K.Kubeconfig.context_name(name), home)

def Vk8s.forget.put(same: Bool, +s: String, +ctx: String, +target: String) -> IO(Unit):
  match same:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        ok : Bool <- Vk8s.put_file(target, s)
        Vk8s.when(ok, Vk8s.say("Deleted kube context " ++ ctx))
        Vk8s.unless(ok, Vk8s.say("Failed to delete kube context: could not write " ++ target))

def Vk8s.forget.write(r: Result<&2, &2, String, String>, +existing: String, +ctx: String, +target: String) -> IO(Unit):
  match r:
    case Fail{e}:
      Vk8s.say("Failed to delete kube context: " ++ e)
    case Done{+s}:
      Vk8s.forget.put(String.eq(s, existing), s, ctx, target)

def Vk8s.forget.go(ok: Bool, +existing: String, +ctx: String, +target: String) -> IO(Unit):
  match ok:
    case False{}:
      Vk8s.say("Failed to delete kube context: could not read " ++ target)
    case True{}:
      Vk8s.forget.write(K.Kubeconfig.remove(existing, ctx), existing, ctx, target)

# vcluster delete --delete-context (deleteKubeContext): context vk8s_NAME
# leaves the user's kubeconfig; a failure only warns.
def Vk8s.forget(+name: String, +home: String) -> IO(Unit):
  do IO<Unit>:
    +target : String <- Vk8s.kubeconfig(home)
    +cur : Sh <- Vk8s.read(target)
    Vk8s.forget.go(Vk8s.sh_ok.of(cur), Vk8s.raw.out(cur), K.Kubeconfig.context_name(name), target)

# Every VM of a cluster: the control plane, then its worker nodes (vind
# pauses the control plane, then the workers).
def Vk8s.pause(+name: String, +line: String, +done: String) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +dir : String = C.Cli.dir(home, name)
    out : String <- Vk8s.sh_out("for s in " ++ Vk8s.q(dir) ++ "/ctl.sock " ++ Vk8s.q(dir) ++ "/nodes/*/ctl.sock; do [ -S \"$s\" ] && printf '%s\\n' "
      ++ Vk8s.q(line) ++ " | nc -U -w 5 \"$s\" 2>/dev/null; done | sort | uniq -c | tr -s ' '")
    Vk8s.say("vCluster " ++ name ++ ": " ++ done ++ " (" ++ out ++ ")")

def Vk8s.delete(+name: String, ctx: Bool) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +dir : String = C.Cli.dir(home, name)
    exists : Bool <- Vk8s.sh_ok("test -d " ++ Vk8s.q(dir))
    Vk8s.unless(exists, Vk8s.die("vCluster " ++ name ++ " not found"))
    _ : Bool <- Vk8s.sh_ok("for d in " ++ Vk8s.q(dir) ++ " " ++ Vk8s.q(dir) ++ "/nodes/*; do [ -S \"$d/ctl.sock\" ] && printf 'quit\\n' | nc -U -w 5 \"$d/ctl.sock\" >/dev/null 2>&1; done; "
      ++ "for d in " ++ Vk8s.q(dir) ++ " " ++ Vk8s.q(dir) ++ "/nodes/*; do pid=$(cat \"$d/vmm.pid\" 2>/dev/null); [ -n \"$pid\" ] || continue; "
      ++ "for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 $pid 2>/dev/null || break; sleep 0.5; done; kill -9 $pid 2>/dev/null; done; true")
    Vk8s.when(ctx, Vk8s.forget(name, home))
    _ : Bool <- Vk8s.sh_ok("rm -rf " ++ Vk8s.q(dir))
    Vk8s.say("Successfully deleted virtual cluster " ++ name)

def Vk8s.list() -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +root : String = home ++ "/.vk8s/clusters"
    out : String <- Vk8s.sh_out("printf '%-24s %-10s %s\\n' NAME STATUS API; for d in " ++ Vk8s.q(root)
      ++ "/*/; do [ -d \"$d\" ] || continue; n=$(basename \"$d\"); s=$(printf 'status\\n' | nc -U -w 2 \"$d/ctl.sock\" 2>/dev/null); "
      ++ "printf '%-24s %-10s https://127.0.0.1:%s\\n' \"$n\" \"${s:-stopped}\" \"$(cat \"$d/port\" 2>/dev/null)\"; done")
    Vk8s.say(out)

def Vk8s.lin(xs: +List<String>) -> List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      Con{x, Vk8s.lin(t)}

@unsafe def Vk8s.run(c: C.Cmd) -> IO(Unit):
  match c:
    case C.Create{name, port, cpus, mem, etcd, nodes}:
      Vk8s.create(name, port, cpus, mem, etcd, nodes)
    case C.Delete{name, ctx}:
      Vk8s.delete(name, ctx)
    case C.List{}:
      Vk8s.list()
    case C.Connect{name, print, set}:
      Vk8s.connect(name, print, set)
    case C.Pause{name}:
      Vk8s.pause(name, "pause", "paused")
    case C.Resume{name}:
      Vk8s.pause(name, "resume", "resumed")
    case C.Vmm{flags}:
      V.Vmm.run(["vk8s", "vmm"], Vk8s.lin(flags))
    case C.Version{}:
      Vk8s.say("vk8s 0.1.0-dev (Kubernetes v1.36.6)")
    case C.Help{msg}:
      IO.print_err(msg)

def Vk8s.plus(xs: List<String>) -> +List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      Con{x, Vk8s.plus(t)}

@unsafe def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    Vk8s.run(C.Cli.parse(List.drop(&2, String, Vk8s.plus(args), 1n)))
