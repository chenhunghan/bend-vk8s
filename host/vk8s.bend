import Base
import 0x88887434395ee9936f9b6f658e234140/main.bend as V
import ../src/cli/cli.bend as C
import ../src/cli/kubeconfig.bend as K
import ../src/cli/assets.bend as A
import ../src/cli/manifest.bend as M
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

def Vk8s.wait_vm.go(up: Bool, dead: Bool, again: IO(Bool)) -> IO(Bool):
  match up dead:
    case True{} _:
      IO.pure(Bool, True{})
    case False{} True{}:
      IO.pure(Bool, False{})
    case False{} False{}:
      again

# Wait for file `rel` of a VM's directory while its VMM runs (n tries,
# 500 ms apart): False at once when the VMM has exited.
def Vk8s.wait_vm(n: Nat, +vdir: String, +rel: String) -> IO(Bool):
  match n:
    case 0n:
      IO.pure(Bool, False{})
    case 1n+p:
      do IO<Bool>:
        r : String <- Vk8s.sh_out("d=" ++ Vk8s.q(vdir) ++ "; if test -s \"$d" ++ rel ++ "\"; then echo up; elif kill -0 \"$(cat \"$d/vmm.pid\" 2>/dev/null)\" 2>/dev/null; then echo wait; else echo dead; fi")
        +st : String = String.trim(r)
        Vk8s.wait_vm.go(String.eq(st, "up"), String.eq(st, "dead"), Vk8s.sleep_then(Vk8s.wait_vm(p, vdir, rel)))

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

def Vk8s.raw.out(r: Sh) -> String:
  match r:
    case Sh{ok, out}:
      out

def Vk8s.assets.fetch(have: Bool, +dir: String) -> IO(String):
  match have:
    case True{}:
      IO.pure(String, dir)
    case False{}:
      do IO<String>:
        Vk8s.say("Downloading vk8s guest assets " ++ M.Manifest.version() ++ " (about 360 MB, once) into " ++ dir ++ "...")
        +base : String <- Vk8s.getenv("VK8S_ASSETS_URL", A.Assets.default_base())
        +r : Sh <- Vk8s.sh(A.Assets.fetch_sh(dir, base, M.Manifest.version(), M.Manifest.files()))
        Vk8s.unless(Vk8s.sh_ok.of(r), Vk8s.die("could not fetch the guest assets: " ++ String.trim(Vk8s.raw.out(r))))
        return dir

def Vk8s.assets.pick(local: Bool, +env: String, +home: String) -> IO(String):
  match local:
    case True{}:
      IO.pure(String, env)
    case False{}:
      do IO<String>:
        +dir : String = A.Assets.dir(home, M.Manifest.version())
        have : Bool <- Vk8s.sh_ok(A.Assets.have_sh(dir))
        Vk8s.assets.fetch(have, dir)

# The guest assets: VK8S_ASSETS (a local build), else the release this
# binary pins, fetched and verified on first use.
def Vk8s.assets(+home: String) -> IO(String):
  do IO<String>:
    +env : String <- Vk8s.getenv("VK8S_ASSETS", "")
    Vk8s.assets.pick(Bool.not(String.is_empty(env)), env, home)

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
def Vk8s.workers(ws: List<&2, U32>, +self: String, +dir: String, +assets: String, +name: String, +token: String) -> IO(Unit):
  match ws:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+i, rest}:
      do IO<Unit>:
        +node : String = C.Cli.worker_name(name, i)
        +ndir : String = C.Cli.node_dir(dir, i)
        Vk8s.say("Starting node " ++ node ++ " (" ++ C.Cli.lan_ip(i) ++ ")...")
        made : Bool <- Vk8s.sh_ok("mkdir -p " ++ Vk8s.q(ndir ++ "/share") ++ " && rm -f " ++ Vk8s.q(ndir ++ "/data.img") ++ " " ++ Vk8s.q(ndir ++ "/share/joined")
          ++ " && cp -c " ++ Vk8s.q(assets ++ "/data.img") ++ " " ++ Vk8s.q(ndir ++ "/data.img") ++ " && cp " ++ Vk8s.q(dir ++ "/discovery.conf") ++ " " ++ Vk8s.q(ndir ++ "/share/"))
        Vk8s.unless(made, Vk8s.die("could not set up " ++ ndir))
        +flags : +List<String> = C.Cli.worker_flags(dir, ndir, assets, node, i, token, 2, 2048)
        started : Bool <- Vk8s.sh_ok("cd " ++ Vk8s.q(ndir) ++ " && { nohup " ++ Vk8s.q(self) ++ " vmm"
          ++ P.Plan.sh_words(flags) ++ " </dev/null >console.log 2>&1 & } && echo $! > vmm.pid")
        Vk8s.unless(started, Vk8s.die("could not start " ++ node))
        Vk8s.workers(rest, self, dir, assets, name, token)

def Vk8s.and_then(ok: Bool, next: IO(Bool)) -> IO(Bool):
  match ok:
    case True{}:
      next
    case False{}:
      IO.pure(Bool, False{})

def Vk8s.wait_workers(ws: List<&2, U32>, +dir: String) -> IO(Bool):
  match ws:
    case Nil{}:
      IO.pure(Bool, True{})
    case Con{+i, rest}:
      do IO<Bool>:
        ok : Bool <- Vk8s.wait_vm(U32.to_nat(1200), C.Cli.node_dir(dir, i), "/share/joined")
        Vk8s.and_then(ok, Vk8s.wait_workers(rest, dir))

def Vk8s.pick_port(auto: Bool, +p: U32, +seed: U32) -> U32:
  match auto:
    case True{}:
      C.Cli.port_from(seed)
    case False{}:
      p

def Vk8s.cache_dir(+home: String) -> String:
  home ++ "/.vk8s/cache"

def Vk8s.cache_running(+dir: String) -> IO(Bool):
  Vk8s.sh_ok("printf 'status json\\n' | nc -U -w 2 " ++ Vk8s.q(dir ++ "/ctl.sock") ++ " 2>/dev/null | grep -q running")

def Vk8s.cache_boot(+dir: String, +assets: String) -> IO(Bool):
  do IO<Bool>:
    +self : String <- Vk8s.self()
    started : Bool <- Vk8s.sh_ok("mkdir -p " ++ Vk8s.q(dir ++ "/share") ++ " && chmod 700 " ++ Vk8s.q(dir) ++ " && cd " ++ Vk8s.q(dir)
      ++ " && { [ -f data.img ] || cp -c " ++ Vk8s.q(assets ++ "/data.img") ++ " data.img; } && rm -f share/ready && { nohup " ++ Vk8s.q(self) ++ " vmm"
      ++ P.Plan.sh_words(C.Cli.cache_flags(dir, assets)) ++ " </dev/null >console.log 2>&1 & } && echo $! > vmm.pid")
    Vk8s.and_then(started, Vk8s.wait_vm(120n, dir, "/share/ready"))

def Vk8s.cache_start.go(running: Bool, +dir: String, +assets: String) -> IO(Bool):
  match running:
    case True{}:
      IO.pure(Bool, True{})
    case False{}:
      do IO<Bool>:
        Vk8s.say("Starting the image cache (pull-through registries on 127.0.0.1:15001-15004)...")
        Vk8s.cache_boot(dir, assets)

# Start the image cache VM unless it runs.
def Vk8s.cache_start(+home: String, +assets: String) -> IO(Bool):
  do IO<Bool>:
    +dir : String = Vk8s.cache_dir(home)
    running : Bool <- Vk8s.cache_running(dir)
    Vk8s.cache_start.go(running, dir, assets)

def Vk8s.cache_ensure.go(+home: String, +assets: String) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Vk8s.cache_start(home, assets)
    Vk8s.unless(ok, Vk8s.say("warning: the image cache did not start (see " ++ Vk8s.cache_dir(home) ++ "/console.log); pulling from the registries directly"))

# Before a cluster boots: the cache, unless VK8S_CACHE=off. A cache that
# does not start is not fatal: containerd then pulls from the upstreams.
def Vk8s.cache_ensure(+home: String, +assets: String) -> IO(Unit):
  do IO<Unit>:
    +mode : String <- Vk8s.getenv("VK8S_CACHE", "on")
    Vk8s.unless(String.eq(mode, "off"), Vk8s.cache_ensure.go(home, assets))

# Read a file the guest wrote on its share (untrusted, security review F4):
# opened with O_NOFOLLOW, a regular file only, at most `max` bytes.
def Vk8s.share_read(+path: String, +max: U32) -> IO(String):
  Vk8s.sh_out("perl -e 'use Fcntl; sysopen(my $f, $ARGV[0], O_RDONLY | O_NOFOLLOW) or exit 1; -f $f or exit 1; read($f, my $b, $ARGV[1]); print $b' "
    ++ Vk8s.q(path) ++ " " ++ U32.show(max) ++ " 2>/dev/null")

def Vk8s.own_kubeconfig.go(kc: Result<&2, &2, String, String>, disc: Result<&2, &2, String, String>, +dir: String) -> IO(Unit):
  match kc disc:
    case Done{k} Done{d}:
      do IO<Unit>:
        ok : Bool <- Vk8s.sh_ok("umask 077; printf %s " ++ Vk8s.q(k) ++ " > " ++ Vk8s.q(dir ++ "/kubeconfig.yaml") ++ " && printf %s " ++ Vk8s.q(d)
          ++ " > " ++ Vk8s.q(dir ++ "/discovery.conf"))
        Vk8s.unless(ok, Vk8s.die("could not write " ++ dir ++ "/kubeconfig.yaml"))
    case Fail{e} _:
      Vk8s.die("refusing the cluster's kubeconfig: " ++ e)
    case _ Fail{e}:
      Vk8s.die("refusing the cluster's kubeconfig: " ++ e)

# The host-owned files a cluster's commands use: kubeconfig.yaml, made
# from the guest's by Kubeconfig.sanitize (only its certificates survive,
# the server is the host's forward), and discovery.conf for workers.
def Vk8s.own_kubeconfig(+name: String, +dir: String, +port: U32) -> IO(Unit):
  do IO<Unit>:
    +text : String <- Vk8s.share_read(dir ++ "/share/kubeconfig.yaml", 1048576)
    Vk8s.own_kubeconfig.go(K.Kubeconfig.sanitize(text, "https://127.0.0.1:" ++ U32.show(port), K.Kubeconfig.context_name(name)),
      K.Kubeconfig.discovery(text, "https://" ++ C.Cli.lan_ip(0) ++ ":6443"), dir)

# The join token the control plane published, checked against kubeadm's
# token pattern before it goes on a worker's command line.
def Vk8s.join_token(+dir: String) -> IO(String):
  do IO<String>:
    t : String <- Vk8s.share_read(dir ++ "/share/join-token", 128)
    +tok : String = String.trim(t)
    Vk8s.unless(C.Cli.token_ok(tok), Vk8s.die("the cluster published an invalid join token"))
    return tok

def Vk8s.boot_ws(+name: String, +guest: String, +dir: String, +assets: String, +port: U32, +cpus: U32, +mem: U32, +etcd: Bool,
  +ws: List<&2, U32>) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    Vk8s.cache_ensure(home, assets)
    +self : String <- Vk8s.self()
    +flags : +List<String> = C.Cli.vmm_flags(dir, assets, guest, port, cpus, mem, etcd)
    started : Bool <- Vk8s.sh_ok("cd " ++ Vk8s.q(dir) ++ " && rm -f share/kubeconfig.yaml share/join-token && { nohup " ++ Vk8s.q(self) ++ " vmm"
      ++ P.Plan.sh_words(flags) ++ " </dev/null >console.log 2>&1 & } && echo $! > vmm.pid")
    Vk8s.unless(started, Vk8s.die("could not start the VM"))
    up : Bool <- Vk8s.wait_vm(360n, dir, "/share/kubeconfig.yaml")
    Vk8s.unless(up, Vk8s.die("vCluster " ++ name ++ " did not come up; see " ++ dir ++ "/console.log"))
    Vk8s.own_kubeconfig(name, dir, port)
    +token : String <- Vk8s.join_token(dir)
    _ : Unit <- Vk8s.workers(ws, self, dir, assets, guest, token)
    joined : Bool <- Vk8s.wait_workers(ws, dir)
    Vk8s.unless(joined, Vk8s.die("a worker node of " ++ name ++ " did not join; see " ++ dir ++ "/nodes/*/console.log"))

# Boot a cluster whose directory holds its data disk: the control plane VM,
# then the workers once it publishes its kubeconfig. `guest` names the
# node inside the VMs (the cluster's original name after a restore).
def Vk8s.boot(+name: String, +guest: String, +dir: String, +assets: String, +port: U32, +cpus: U32, +mem: U32, +etcd: Bool,
  +nodes: U32) -> IO(Unit):
  Vk8s.boot_ws(name, guest, dir, assets, port, cpus, mem, etcd, C.Cli.workers_upto(nodes))

# The cluster's settings, kept beside its disk (read by list, describe,
# snapshot and restore).
def Vk8s.env_file(+name: String, +guest: String, +port: U32, +cpus: U32, +mem: U32, +etcd: Bool, +nodes: U32) -> String:
  "NAME=" ++ name ++ "\nGUEST=" ++ guest ++ "\nPORT=" ++ U32.show(port) ++ "\nCPUS=" ++ U32.show(cpus) ++ "\nMEMORY="
    ++ U32.show(mem) ++ "\nSTORE=" ++ C.Cli.store_name(etcd) ++ "\nNODES=" ++ U32.show(nodes) ++ "\nWORKERS=" ++ C.Cli.workers_show(C.Cli.workers_upto(nodes))
    ++ "\nKUBERNETES=v1.36.6\n"

def Vk8s.created_msg(+name: String, +dir: String) -> IO(Unit):
  do IO<Unit>:
    Vk8s.say("- Use 'vk8s connect " ++ name ++ "' to access the virtual cluster")
    Vk8s.say("- Use `vk8s connect " ++ name ++ " -- kubectl get ns` to run a command directly within the vcluster")

def Vk8s.create(+name: String, +port0: U32, +cpus: U32, +mem: U32, +etcd: Bool, +nodes: U32) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +assets : String <- Vk8s.assets(home)
    +dir : String = C.Cli.dir(home, name)
    exists : Bool <- Vk8s.sh_ok("test -e " ++ Vk8s.q(dir))
    Vk8s.when(exists, Vk8s.die("vCluster " ++ name ++ " already exists, use --upgrade to upgrade it"))
    Vk8s.unless(C.Cli.paths_fit(dir), Vk8s.die("the cluster directory " ++ dir ++ " is too long for its sockets (macOS allows 103 bytes); use a shorter name"))
    have : Bool <- Vk8s.sh_ok("test -f " ++ Vk8s.q(assets ++ "/vk8s.cpio") ++ " -a -f " ++ Vk8s.q(assets ++ "/data.img"))
    Vk8s.unless(have, Vk8s.die("vk8s assets not found in " ++ assets ++ " (set VK8S_ASSETS)"))
    now : Nat <- IO.now()
    +port : U32 = Vk8s.pick_port(U32.is_eq(port0, 0), port0, U32.from_nat(now))
    Vk8s.say("Creating vCluster " ++ name ++ " (API on 127.0.0.1:" ++ U32.show(port) ++ ")...")
    made : Bool <- Vk8s.sh_ok("mkdir -p " ++ Vk8s.q(dir ++ "/share") ++ " && chmod 700 " ++ Vk8s.q(dir)
      ++ " && cp -c " ++ Vk8s.q(assets ++ "/data.img") ++ " " ++ Vk8s.q(dir ++ "/data.img")
      ++ " && echo " ++ U32.show(port) ++ " > " ++ Vk8s.q(dir ++ "/port")
      ++ " && printf %s " ++ Vk8s.q(Vk8s.env_file(name, name, port, cpus, mem, etcd, nodes)) ++ " > " ++ Vk8s.q(dir ++ "/cluster.env")
      ++ " && echo CREATED=$(date +%s) >> " ++ Vk8s.q(dir ++ "/cluster.env"))
    Vk8s.unless(made, Vk8s.die("could not set up " ++ dir))
    Vk8s.boot(name, name, dir, assets, port, cpus, mem, etcd, nodes)
    Vk8s.say("Successfully created virtual cluster " ++ name ++ ". ")
    Vk8s.created_msg(name, dir)

def Vk8s.raw.got(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> Sh:
  match r:
    case Fail{(c, m)}:
      Sh{False{}, ""}
    case Done{(st, (out, err))}:
      Sh{U32.is_eq(st, 0), out}

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
        +ok : Bool <- Vk8s.put_file(target, s)
        Vk8s.unless(ok, Vk8s.die("vk8s connect: could not write " ++ target))
        Vk8s.say(Vk8s.connected(set, ctx, target))

# Merges the cluster's kubeconfig into the user's (vcluster writeKubeConfig
# with --update-current: clihelper.UpdateKubeConfig).
def Vk8s.connect.merge(+set: Bool, incoming: String, +ctx: String, +home: String) -> IO(Unit):
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
    +kc : String = C.Cli.dir(home, name) ++ "/kubeconfig.yaml"
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
        +ok : Bool <- Vk8s.put_file(target, s)
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

# Stop every VM of a cluster gracefully, as vind stops its containers:
# press each guest's power button (PID 1 stops the daemons, unmounts and
# powers off), wait up to 60 s, then quit the VMM, then kill it.
def Vk8s.stop_vms(+dir: String) -> String:
  +all : String = "for d in " ++ Vk8s.q(dir) ++ " " ++ Vk8s.q(dir) ++ "/nodes/*; do "
  all ++ "[ -S \"$d/ctl.sock\" ] && printf 'powerdown\\n' | nc -U -w 2 \"$d/ctl.sock\" >/dev/null 2>&1; done; "
    ++ all ++ "pid=$(cat \"$d/vmm.pid\" 2>/dev/null); [ -n \"$pid\" ] || continue; "
    ++ "i=0; while kill -0 $pid 2>/dev/null && [ $i -lt 120 ]; do sleep 0.5; i=$((i+1)); done; "
    ++ "kill -0 $pid 2>/dev/null && printf 'quit\\n' | nc -U -w 2 \"$d/ctl.sock\" >/dev/null 2>&1; "
    ++ "i=0; while kill -0 $pid 2>/dev/null && [ $i -lt 10 ]; do sleep 0.5; i=$((i+1)); done; kill -9 $pid 2>/dev/null; done; true"

def Vk8s.delete(+name: String, ctx: Bool) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +dir : String = C.Cli.dir(home, name)
    exists : Bool <- Vk8s.sh_ok("test -d " ++ Vk8s.q(dir))
    Vk8s.unless(exists, Vk8s.die("vCluster " ++ name ++ " not found"))
    _ : Bool <- Vk8s.sh_ok(Vk8s.stop_vms(dir))
    Vk8s.when(ctx, Vk8s.forget(name, home))
    _ : Bool <- Vk8s.sh_ok("rm -rf " ++ Vk8s.q(dir))
    Vk8s.say("Successfully deleted virtual cluster " ++ name)

def Vk8s.entry.of(fs: List<&2, String>) -> List<&2, C.Entry>:
  match fs:
    case Con{n, Con{st, Con{+c, Con{at, Con{+con, Nil{}}}}}}:
      [C.Entry{n, st, C.Cli.num(U32.read(c), 0), at, String.eq(con, "1")}]
    case _:
      Nil{}

def Vk8s.entries.of(ls: List<&2, String>) -> List<&2, C.Entry>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{l, t}:
      List.append(&2, C.Entry, Vk8s.entry.of(String.split(l, '\t')), Vk8s.entries.of(t))

# The VM state of the cluster in "$d" (bend-vmm `status json`), or stopped.
def Vk8s.state_sh() -> String:
  "s=$(printf 'status json\\n' | nc -U -w 2 \"$d/ctl.sock\" 2>/dev/null | sed -n 's/.*\"state\":\"\\([a-z]*\\)\".*/\\1/p'); s=${s:-stopped}; "

# Every cluster: name, state, created (Unix s and RFC 3339), connected.
def Vk8s.entries(+home: String) -> IO(List<&2, C.Entry>):
  do IO<List<&2, C.Entry>>:
    out : String <- Vk8s.sh_out("cur=$(kubectl config current-context 2>/dev/null); for d in " ++ Vk8s.q(home ++ "/.vk8s/clusters")
      ++ "/*/; do [ -d \"$d\" ] || continue; d=${d%/}; n=$(basename \"$d\"); " ++ Vk8s.state_sh()
      ++ "c=$(sed -n 's/^CREATED=//p' \"$d/cluster.env\" 2>/dev/null); [ -n \"$c\" ] || c=$(stat -f %B \"$d\"); "
      ++ "at=$(date -r \"$c\" +%Y-%m-%dT%H:%M:%S%z | sed -E 's/([0-9]{2})([0-9]{2})$/\\1:\\2/'); "
      ++ "con=0; [ \"$cur\" = \"vk8s_$n\" ] && con=1; printf '%s\\t%s\\t%s\\t%s\\t%s\\n' \"$n\" \"$s\" \"$c\" \"$at\" \"$con\"; done")
    return Vk8s.entries.of(String.lines(out))

def Vk8s.epoch() -> IO(U32):
  do IO<U32>:
    out : String <- Vk8s.sh_out("date +%s")
    return C.Cli.num(U32.read(String.trim(out)), 0)

def Vk8s.list.out(json: Bool, es: List<&2, C.Entry>, +now: U32) -> String:
  match json:
    case True{}:
      C.Cli.list_json(es, now)
    case False{}:
      C.Cli.list_table(es, now)

def Vk8s.list(json: Bool) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    es : List<&2, C.Entry> <- Vk8s.entries(home)
    +now : U32 <- Vk8s.epoch()
    IO.write(Vk8s.list.out(json, es, now))

def Vk8s.exists(+name: String) -> IO(String):
  do IO<String>:
    +home : String <- Vk8s.home()
    +dir : String = C.Cli.dir(home, name)
    ok : Bool <- Vk8s.sh_ok("test -d " ++ Vk8s.q(dir))
    Vk8s.unless(ok, Vk8s.die("vCluster " ++ name ++ " not found"))
    return dir

# A setting of the cluster's cluster.env.
def Vk8s.setting_sh(+dir: String, +key: String) -> String:
  "$(sed -n 's/^" ++ key ++ "=//p' " ++ Vk8s.q(dir ++ "/cluster.env") ++ " 2>/dev/null)"

# vcluster describe (docker driver): Name, Container ID, Status, Created,
# Image, Ports; vk8s shows the VMM's pid as the container and adds nodes
# and the backing store.
def Vk8s.describe.text(+name: String, +dir: String) -> String:
  "d=" ++ Vk8s.q(dir) ++ "; " ++ Vk8s.state_sh() ++ "c=" ++ Vk8s.setting_sh(dir, "CREATED") ++ "; [ -n \"$c\" ] || c=$(stat -f %B \"$d\"); "
    ++ "printf '%-15s%s\\n' 'Name:' " ++ Vk8s.q(name) ++ " 'Container ID:' \"vmm-$(cat \"$d/vmm.pid\" 2>/dev/null)\" 'Status:' \"$s\" "
    ++ "'Created:' \"$(LC_ALL=C date -r \"$c\" '+%a, %d %b %Y %H:%M:%S %z')\" 'Image:' \"vk8s/guest:" ++ Vk8s.setting_sh(dir, "KUBERNETES") ++ "\" "
    ++ "'Ports:' \"127.0.0.1:$(cat \"$d/port\")->6443/tcp\" 'Nodes:' \"$((1 + " ++ Vk8s.setting_sh(dir, "NODES") ++ "0 / 10))\" "
    ++ "'Backing store:' \"" ++ Vk8s.setting_sh(dir, "STORE") ++ "\""

def Vk8s.describe.json(+name: String, +dir: String) -> String:
  "d=" ++ Vk8s.q(dir) ++ "; " ++ Vk8s.state_sh() ++ "c=" ++ Vk8s.setting_sh(dir, "CREATED") ++ "; [ -n \"$c\" ] || c=$(stat -f %B \"$d\"); "
    ++ "printf '{\\n  \"name\": \"%s\",\\n  \"containerId\": \"vmm-%s\",\\n  \"status\": \"%s\",\\n  \"created\": \"%s\",\\n  \"image\": \"vk8s/guest:%s\",\\n  \"ports\": \"127.0.0.1:%s->6443/tcp\"\\n}\\n' "
    ++ Vk8s.q(name) ++ " \"$(cat \"$d/vmm.pid\" 2>/dev/null)\" \"$s\" \"$(date -u -r \"$c\" +%Y-%m-%dT%H:%M:%SZ)\" \"" ++ Vk8s.setting_sh(dir, "KUBERNETES") ++ "\" \"$(cat \"$d/port\")\""

def Vk8s.describe.pick(co: Bool, json: Bool, +name: String, +dir: String) -> String:
  match co json:
    case True{} _:
      "cat " ++ Vk8s.q(dir ++ "/vcluster.yaml") ++ " 2>/dev/null || { echo 'failed to load vcluster config (no vcluster.yaml given at create)' >&2; exit 1; }"
    case False{} True{}:
      Vk8s.describe.json(name, dir)
    case False{} False{}:
      Vk8s.describe.text(name, dir)

def Vk8s.report.go(ok: Bool, out: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.write(out)
    case False{}:
      Vk8s.die(String.trim(out))

def Vk8s.report(r: Sh) -> IO(Unit):
  match r:
    case Sh{ok, out}:
      Vk8s.report.go(ok, out)

def Vk8s.describe(+name: String, co: Bool, json: Bool) -> IO(Unit):
  do IO<Unit>:
    +dir : String <- Vk8s.exists(name)
    r : Sh <- Vk8s.sh(Vk8s.describe.pick(co, json, name, dir))
    Vk8s.report(r)

# `logs NAME`: the logs there are; `logs NAME COMPONENT`: one of them
# (console is the VM's console; NODE/COMPONENT reads a worker's).
def Vk8s.logs.sh(+dir: String, +comp: String) -> String:
  "cd " ++ Vk8s.q(dir) ++ " && c=" ++ Vk8s.q(comp) ++ "; case \"$c\" in '') { echo console; ls share/logs 2>/dev/null | sed 's/\\.log$//'; "
    ++ "for n in nodes/*/; do [ -d \"$n\" ] || continue; b=$(basename \"$n\"); echo \"$b/console\"; ls \"$n/share/logs\" 2>/dev/null | sed \"s|^|$b/|; s/\\.log$//\"; done; } ;; "
    ++ "*..*) echo 'invalid component' >&2; exit 1 ;; console) cat console.log ;; */console) cat \"nodes/${c%/console}/console.log\" ;; "
    ++ "*/*) cat \"nodes/${c%%/*}/share/logs/${c#*/}.log\" ;; *) cat \"share/logs/$c.log\" ;; esac"

def Vk8s.logs(+name: String, +comp: String) -> IO(Unit):
  do IO<Unit>:
    +dir : String <- Vk8s.exists(name)
    r : Sh <- Vk8s.sh(Vk8s.logs.sh(dir, comp))
    Vk8s.report(r)

def Exec.run(prog: String, args: List<String>, key: String, value: String) -> IO(U32):
  import "./effs/exec.c"
  import "./effs/exec.js"

def Vk8s.cache.state(running: Bool) -> String:
  match running:
    case True{}:
      "running on 127.0.0.1:15001-15004"
    case False{}:
      "stopped"

def Vk8s.cache.go(start: Bool, stop: Bool, +home: String, +dir: String) -> IO(Unit):
  match start stop:
    case True{} _:
      do IO<Unit>:
        +assets : String <- Vk8s.assets(home)
        +ok : Bool <- Vk8s.cache_start(home, assets)
        Vk8s.when(ok, Vk8s.say("image cache running"))
        Vk8s.unless(ok, Vk8s.die("the image cache did not start; see " ++ dir ++ "/console.log"))
    case False{} True{}:
      do IO<Unit>:
        _ : Bool <- Vk8s.sh_ok(Vk8s.stop_vms(dir))
        Vk8s.say("image cache stopped (its blobs stay in " ++ dir ++ "/data.img)")
    case False{} False{}:
      do IO<Unit>:
        running : Bool <- Vk8s.cache_running(dir)
        used : String <- Vk8s.sh_out("du -h " ++ Vk8s.q(dir ++ "/data.img") ++ " 2>/dev/null | cut -f1")
        Vk8s.say("image cache: " ++ Vk8s.cache.state(running) ++ ", " ++ String.trim(used) ++ " cached")

def Vk8s.cache(+action: String) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +dir : String = Vk8s.cache_dir(home)
    Vk8s.cache.go(String.eq(action, "start"), String.eq(action, "stop"), home, dir)

def Vk8s.or_name(empty: Bool, +g: String, +name: String) -> String:
  match empty:
    case True{}:
      name
    case False{}:
      g

def Vk8s.setting(+dir: String, +key: String) -> IO(String):
  do IO<String>:
    out : String <- Vk8s.sh_out("printf %s \"" ++ Vk8s.setting_sh(dir, key) ++ "\"")
    return String.trim(out)

def Vk8s.u32(+s: String, +d: U32) -> U32:
  C.Cli.num(U32.read(s), d)

# --upgrade without --nodes keeps the cluster's workers; --nodes N makes
# them 1..N.
def Vk8s.keep_ws(keep: Bool, +old: List<&2, U32>, +n: U32) -> List<&2, U32>:
  match keep:
    case True{}:
      old
    case False{}:
      C.Cli.workers_upto(n)

def Vk8s.worker_list.go(empty: Bool, +w: String, +n: U32) -> List<&2, U32>:
  match empty:
    case True{}:
      C.Cli.workers_upto(n)
    case False{}:
      C.Cli.workers_of(w)

# The cluster's worker indices (cluster.env WORKERS; NODES for clusters
# made before WORKERS existed).
def Vk8s.worker_list(+dir: String) -> IO(List<&2, U32>):
  do IO<List<&2, U32>>:
    +w : String <- Vk8s.setting(dir, "WORKERS")
    n : String <- Vk8s.setting(dir, "NODES")
    return Vk8s.worker_list.go(String.is_empty(w), w, Vk8s.u32(n, 0))

def Vk8s.set_workers(+dir: String, ws: List<&2, U32>) -> IO(Bool):
  +shown : String = C.Cli.workers_show(ws)
  +count : U32 = U32.from_nat(List.length(&2, U32, C.Cli.workers_of(shown)))
  Vk8s.sh_ok("f=" ++ Vk8s.q(dir ++ "/cluster.env") ++ "; grep -v '^WORKERS=\\|^NODES=' \"$f\" > \"$f.new\"; printf 'NODES=%s\\nWORKERS=%s\\n' "
    ++ U32.show(count) ++ " " ++ Vk8s.q(shown) ++ " >> \"$f.new\" && mv \"$f.new\" \"$f\"")

def Vk8s.upgrade.go(+name: String, +home: String, +dir: String, +port0: U32, +cpus: U32, +mem: U32, +etcd: Bool, +nodes0: U32) -> IO(Unit):
  do IO<Unit>:
    +assets : String <- Vk8s.assets(home)
    Vk8s.say("vCluster " ++ name ++ " already exists, recreating it...")
    _ : Bool <- Vk8s.sh_ok(Vk8s.stop_vms(dir))
    +guest0 : String <- Vk8s.setting(dir, "GUEST")
    +guest : String = Vk8s.or_name(String.is_empty(guest0), guest0, name)
    ps : String <- Vk8s.setting(dir, "PORT")
    +port : U32 = Vk8s.pick_port(U32.is_eq(port0, 0), port0, Vk8s.u32(ps, 0))
    created : String <- Vk8s.setting(dir, "CREATED")
    +old : List<&2, U32> <- Vk8s.worker_list(dir)
    +keep : Bool = U32.is_eq(nodes0, 0)
    +ws : List<&2, U32> = Vk8s.keep_ws(keep, old, nodes0)
    +nodes : U32 = U32.from_nat(List.length(&2, U32, ws))
    wrote : Bool <- Vk8s.sh_ok("rm -rf " ++ Vk8s.q(dir ++ "/nodes") ++ " " ++ Vk8s.q(dir ++ "/lan") ++ " && echo " ++ U32.show(port) ++ " > " ++ Vk8s.q(dir ++ "/port")
      ++ " && printf %s " ++ Vk8s.q(Vk8s.env_file(name, guest, port, cpus, mem, etcd, nodes)) ++ " > " ++ Vk8s.q(dir ++ "/cluster.env")
      ++ " && echo CREATED=" ++ Vk8s.q(created) ++ " >> " ++ Vk8s.q(dir ++ "/cluster.env"))
    Vk8s.unless(wrote, Vk8s.die("could not update " ++ dir))
    _ : Bool <- Vk8s.set_workers(dir, ws)
    Vk8s.boot_ws(name, guest, dir, assets, port, cpus, mem, etcd, ws)
    _ : Bool <- Vk8s.sh_ok("keep=\" \"" ++ Vk8s.q(C.Cli.workers_show(ws)) ++ "\" \"; kubectl --kubeconfig " ++ Vk8s.q(dir ++ "/kubeconfig.yaml")
      ++ " get nodes -o name | sed -n 's|^node/" ++ guest ++ "-worker-||p' | while read i; do case \"$keep\" in *\" $i \"*) ;; *) kubectl --kubeconfig "
      ++ Vk8s.q(dir ++ "/kubeconfig.yaml") ++ " delete node " ++ Vk8s.q(guest ++ "-worker-") ++ "$i >/dev/null 2>&1 ;; esac; done; true")
    Vk8s.say("Successfully upgraded virtual cluster " ++ name ++ ". ")
    Vk8s.created_msg(name, dir)

# vcluster create --upgrade (docker driver: stop and recreate the
# container, keeping its volumes): stop the VMs gracefully, keep the control
# plane's data disk and port, and boot on this binary's assets with the new
# settings. Workers join afresh.
def Vk8s.upgrade(+name: String, +port0: U32, +cpus: U32, +mem: U32, +etcd: Bool, +nodes: U32) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +dir : String = C.Cli.dir(home, name)
    +exists : Bool <- Vk8s.sh_ok("test -f " ++ Vk8s.q(dir ++ "/data.img"))
    Vk8s.unless(exists, Vk8s.create(name, port0, cpus, mem, etcd, nodes))
    Vk8s.when(exists, Vk8s.upgrade.go(name, home, dir, port0, cpus, mem, etcd, nodes))

# vk8s node add NAME [--count N]: more worker VMs, joining with the
# control plane's token (vind adds node containers the same way).
def Vk8s.node_add(+name: String, +count: U32) -> IO(Unit):
  do IO<Unit>:
    +dir : String <- Vk8s.exists(name)
    +home : String <- Vk8s.home()
    +assets : String <- Vk8s.assets(home)
    running : Bool <- Vk8s.sh_ok("printf 'status json\\n' | nc -U -w 2 " ++ Vk8s.q(dir ++ "/ctl.sock") ++ " 2>/dev/null | grep -q running")
    Vk8s.unless(running, Vk8s.die("vCluster " ++ name ++ " is not running"))
    +guest : String <- Vk8s.setting(dir, "GUEST")
    +ws : List<&2, U32> <- Vk8s.worker_list(dir)
    +fresh : List<&2, U32> = C.Cli.workers_next(ws, count)
    +token : String <- Vk8s.join_token(dir)
    +self : String <- Vk8s.self()
    Vk8s.workers(fresh, self, dir, assets, Vk8s.or_name(String.is_empty(guest), guest, name), token)
    joined : Bool <- Vk8s.wait_workers(fresh, dir)
    _ : Bool <- Vk8s.set_workers(dir, List.append(&2, U32, ws, fresh))
    Vk8s.unless(joined, Vk8s.die("a new node of " ++ name ++ " did not join; see " ++ dir ++ "/nodes/*/console.log"))
    Vk8s.say("Successfully added " ++ U32.show(count) ++ " node(s) to vCluster " ++ name)

# Stop one VM gracefully (its power button, then quit, then kill).
def Vk8s.stop_vm(+vdir: String) -> String:
  "d=" ++ Vk8s.q(vdir) ++ "; [ -S \"$d/ctl.sock\" ] && printf 'powerdown\\n' | nc -U -w 2 \"$d/ctl.sock\" >/dev/null 2>&1; "
    ++ "pid=$(cat \"$d/vmm.pid\" 2>/dev/null); [ -n \"$pid\" ] || exit 0; i=0; while kill -0 $pid 2>/dev/null && [ $i -lt 120 ]; do sleep 0.5; i=$((i+1)); done; "
    ++ "kill -0 $pid 2>/dev/null && printf 'quit\\n' | nc -U -w 2 \"$d/ctl.sock\" >/dev/null 2>&1; sleep 1; kill -9 $pid 2>/dev/null; true"

# vcluster's drain.Helper: Force, IgnoreAllDaemonSets, DeleteEmptyDirData,
# a 30 s grace period and a 30 min timeout.
def Vk8s.node_drain(found: Bool, drain: Bool, +k: String, +node: String) -> String:
  match found drain:
    case True{} True{}:
      k ++ "drain " ++ Vk8s.q(node) ++ " --force --ignore-daemonsets --delete-emptydir-data --grace-period=30 --timeout=30m 2>&1"
    case _ _:
      "true"

def Vk8s.node_delete.idx(m: Maybe<&2, U32>, +name: String, +node: String, +dir: String, +drain: Bool) -> IO(Unit):
  match m:
    case None{}:
      Vk8s.die("node " ++ node ++ " is not a worker of vCluster " ++ name ++ " (its control plane node cannot be deleted)")
    case Some{+i}:
      do IO<Unit>:
        +k : String = "kubectl --kubeconfig " ++ Vk8s.q(dir ++ "/kubeconfig.yaml") ++ " "
        Vk8s.say("Cordoning node " ++ node ++ "...")
        +c : Bool <- Vk8s.sh_ok(k ++ "cordon " ++ Vk8s.q(node))
        Vk8s.unless(c, Vk8s.say("Node " ++ node ++ " not found"))
        Vk8s.when(Bool.and(c, drain), Vk8s.say("Draining node " ++ node ++ "..."))
        +d : Sh <- Vk8s.sh(Vk8s.node_drain(c, drain, k, node))
        Vk8s.unless(Vk8s.sh_ok.of(d), Vk8s.die("failed to drain node: " ++ String.trim(Vk8s.raw.out(d))))
        Vk8s.say("Deleting node " ++ node ++ "...")
        _ : Bool <- Vk8s.sh_ok(k ++ "delete node " ++ Vk8s.q(node) ++ " --ignore-not-found")
        _ : Bool <- Vk8s.sh_ok(Vk8s.stop_vm(C.Cli.node_dir(dir, i)) ++ "; rm -rf " ++ Vk8s.q(C.Cli.node_dir(dir, i)))
        +ws : List<&2, U32> <- Vk8s.worker_list(dir)
        _ : Bool <- Vk8s.set_workers(dir, C.Cli.workers_drop(ws, i))
        Vk8s.say("Successfully deleted node " ++ node)

# vk8s node delete NAME NODE [--drain=false] (vcluster node delete).
def Vk8s.node_delete(+name: String, +node: String, drain: Bool) -> IO(Unit):
  do IO<Unit>:
    +dir : String <- Vk8s.exists(name)
    +guest0 : String <- Vk8s.setting(dir, "GUEST")
    +guest : String = Vk8s.or_name(String.is_empty(guest0), guest0, name)
    Vk8s.node_delete.idx(C.Cli.worker_index(guest, node), name, node, dir, drain)

def Vk8s.lin(xs: +List<String>) -> List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      Con{x, Vk8s.lin(t)}

def Vk8s.exec.go(cmd: +List<String>, +kc: String) -> IO(Unit):
  match cmd:
    case Nil{}:
      Vk8s.die("vk8s connect: -- needs a command")
    case Con{+prog, args}:
      do IO<Unit>:
        e : U32 <- Exec.run(prog, Vk8s.lin(args), "KUBECONFIG", kc)
        Vk8s.die("could not run " ++ prog ++ " (errno " ++ U32.show(e) ++ ")")

# `connect NAME -- COMMAND`: run COMMAND with KUBECONFIG at the cluster
# (vcluster connect runs it against a temporary kubeconfig).
def Vk8s.exec(+name: String, cmd: +List<String>) -> IO(Unit):
  do IO<Unit>:
    +dir : String <- Vk8s.exists(name)
    Vk8s.exec.go(cmd, dir ++ "/kubeconfig.yaml")

# vcluster snapshot (docker driver): pause the cluster for a consistent
# copy, then resume it; the archive is a tar.gz whose first entry is
# metadata.json. vk8s copies the control plane's data disk (a copy-on-write
# clone, so the pause is short; holes stay holes in the archive). Workers
# keep no state of their own: they join afresh on restore.
def Vk8s.snapshot(+name: String, +path: String) -> IO(Unit):
  do IO<Unit>:
    +dir : String <- Vk8s.exists(name)
    Vk8s.say("Pausing vCluster " ++ name ++ " for consistent snapshot...")
    Vk8s.pause(name, "pause", "paused")
    st : String <- Vk8s.sh_out("mktemp -d")
    +stage : String = String.trim(st)
    copied : Bool <- Vk8s.sh_ok("cp -c " ++ Vk8s.q(dir ++ "/data.img") ++ " " ++ Vk8s.q(stage ++ "/data.img") ++ " && cp "
      ++ Vk8s.q(dir ++ "/cluster.env") ++ " " ++ Vk8s.q(stage ++ "/cluster.env"))
    Vk8s.say("Resuming vCluster " ++ name ++ "...")
    Vk8s.pause(name, "resume", "resumed")
    Vk8s.unless(copied, Vk8s.die("could not copy the data disk of " ++ name))
    made : Bool <- Vk8s.sh_ok("cd " ++ Vk8s.q(stage) ++ " && printf '{\"name\":\"%s\",\"guest\":\"%s\",\"kubernetesVersion\":\"%s\",\"backingStore\":\"%s\",\"nodes\":%s,\"vk8s\":\"0.1.0\"}\\n' "
      ++ Vk8s.q(name) ++ " \"" ++ Vk8s.setting_sh(dir, "GUEST") ++ "\" \"" ++ Vk8s.setting_sh(dir, "KUBERNETES") ++ "\" \"" ++ Vk8s.setting_sh(dir, "STORE")
      ++ "\" \"" ++ Vk8s.setting_sh(dir, "NODES") ++ "\" > metadata.json && (umask 077; tar -czSf " ++ Vk8s.q(path) ++ " metadata.json cluster.env data.img); r=$?; cd / && rm -rf "
      ++ Vk8s.q(stage) ++ "; exit $r")
    Vk8s.unless(made, Vk8s.die("could not write the snapshot " ++ path))
    Vk8s.say("Successfully created snapshot at " ++ path)

# Unpack a snapshot safely (security review F2, F3): the archive must hold
# exactly metadata.json (first), cluster.env and data.img, all regular
# files; they are unpacked into a private staging directory, the disk must
# be raw (no qcow2 header, which could name host files as backing), and
# only then do they move into the new cluster's directory.
def Vk8s.restore_sh(+dir: String, +path: String) -> String:
  "umask 077; p=" ++ Vk8s.q(path) ++ "; d=" ++ Vk8s.q(dir) ++ "; l=$(tar -tvzf \"$p\" 2>/dev/null) || { echo \"cannot read the snapshot $p\"; exit 1; }; "
    ++ "names=$(printf '%s\\n' \"$l\" | awk '{print $NF}' | tr '\\n' ' '); [ \"$names\" = 'metadata.json cluster.env data.img ' ] || { "
    ++ "first=$(printf '%s\\n' \"$l\" | head -1 | awk '{print $NF}'); [ \"$first\" = metadata.json ] || { echo \"expected metadata.json as first entry, got $first\"; exit 1; }; "
    ++ "echo 'the snapshot must hold exactly metadata.json, cluster.env and data.img'; exit 1; }; "
    ++ "printf '%s\\n' \"$l\" | grep -qv '^-' && { echo 'the snapshot holds a member that is not a regular file'; exit 1; }; "
    ++ "mkdir -p \"$(dirname \"$d\")\" && t=$(mktemp -d \"$(dirname \"$d\")/.restore.XXXXXX\") || exit 1; "
    ++ "tar -xzSf \"$p\" -C \"$t\" metadata.json cluster.env data.img || { rm -rf \"$t\"; echo 'could not unpack the snapshot'; exit 1; }; "
    ++ "for f in metadata.json cluster.env data.img; do { [ -f \"$t/$f\" ] && [ ! -L \"$t/$f\" ]; } || { rm -rf \"$t\"; echo \"bad member $f\"; exit 1; }; done; "
    ++ "[ \"$(head -c 4 \"$t/data.img\" | od -An -tx1 | tr -d ' ')\" = 514649fb ] && { rm -rf \"$t\"; echo 'the snapshot disk is not raw (qcow2)'; exit 1; }; "
    ++ "mkdir -p \"$d/share\" && chmod 700 \"$d\" && mv \"$t/data.img\" \"$t/cluster.env\" \"$d/\" && rm -rf \"$t\""

# vcluster restore (docker driver): a new cluster from a snapshot; the
# name must be free. The control plane boots on the snapshot's data disk.
def Vk8s.restore(+name: String, +path: String) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +assets : String <- Vk8s.assets(home)
    +dir : String = C.Cli.dir(home, name)
    exists : Bool <- Vk8s.sh_ok("test -e " ++ Vk8s.q(dir))
    Vk8s.when(exists, Vk8s.die("vCluster \"" ++ name ++ "\" already exists; delete it first or use a different name"))
    Vk8s.unless(C.Cli.paths_fit(dir), Vk8s.die("the cluster directory " ++ dir ++ " is too long for its sockets (macOS allows 103 bytes); use a shorter name"))
    Vk8s.say("Restoring vCluster " ++ name ++ " from snapshot " ++ path ++ "...")
    +chk : Sh <- Vk8s.sh(Vk8s.restore_sh(dir, path))
    Vk8s.unless(Vk8s.sh_ok.of(chk), Vk8s.die(String.trim(Vk8s.raw.out(chk))))
    made : Bool = True{}
    Vk8s.unless(made, Vk8s.die("could not unpack the snapshot " ++ path))
    +guest : String <- Vk8s.setting(dir, "GUEST")
    Vk8s.unless(C.Cli.valid_name(guest), Vk8s.die("the snapshot names an invalid cluster"))
    +store : String <- Vk8s.setting(dir, "STORE")
    cs : String <- Vk8s.setting(dir, "CPUS")
    ms : String <- Vk8s.setting(dir, "MEMORY")
    ns : String <- Vk8s.setting(dir, "NODES")
    now : Nat <- IO.now()
    +port : U32 = C.Cli.port_from(U32.from_nat(now))
    +etcd : Bool = String.eq(store, "etcd")
    +c : U32 = Vk8s.u32(cs, 2)
    +m : U32 = Vk8s.u32(ms, 2048)
    +n : U32 = Vk8s.u32(ns, 0)
    wrote : Bool <- Vk8s.sh_ok("echo " ++ U32.show(port) ++ " > " ++ Vk8s.q(dir ++ "/port") ++ " && printf %s " ++ Vk8s.q(Vk8s.env_file(name, guest, port, c, m, etcd, n))
      ++ " > " ++ Vk8s.q(dir ++ "/cluster.env") ++ " && echo CREATED=$(date +%s) >> " ++ Vk8s.q(dir ++ "/cluster.env"))
    Vk8s.unless(wrote, Vk8s.die("could not set up " ++ dir))
    Vk8s.boot(name, guest, dir, assets, port, c, m, etcd, n)
    Vk8s.say("Successfully restored vCluster " ++ name ++ " from snapshot")
    Vk8s.created_msg(name, dir)

@unsafe def Vk8s.run(c: C.Cmd) -> IO(Unit):
  match c:
    case C.Create{name, port, cpus, mem, etcd, nodes}:
      Vk8s.create(name, port, cpus, mem, etcd, nodes)
    case C.Delete{name, ctx}:
      Vk8s.delete(name, ctx)
    case C.List{}:
      Vk8s.list(False{})
    case C.ListJson{}:
      Vk8s.list(True{})
    case C.Describe{name, co, json}:
      Vk8s.describe(name, co, json)
    case C.Logs{name, comp}:
      Vk8s.logs(name, comp)
    case C.Snapshot{name, path}:
      Vk8s.snapshot(name, path)
    case C.Restore{name, path}:
      Vk8s.restore(name, path)
    case C.Exec{name, cmd}:
      Vk8s.exec(name, cmd)
    case C.Cache{action}:
      Vk8s.cache(action)
    case C.Upgrade{name, port, cpus, mem, etcd, nodes}:
      Vk8s.upgrade(name, port, cpus, mem, etcd, nodes)
    case C.NodeAdd{name, count}:
      Vk8s.node_add(name, count)
    case C.NodeDelete{name, node, drain}:
      Vk8s.node_delete(name, node, drain)
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
