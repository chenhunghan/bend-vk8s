import Base
import 0x09bd79c7faef22310b6d041f523d5cb2/main.bend as V
import ../src/cli/cli.bend as C
import ../src/cli/kubeconfig.bend as K
import ../src/cli/assets.bend as A
import ../src/cli/manifest.bend as M
import ../src/cli/token.bend as TK
import ../src/net/cidr.bend as CI
import ../src/config/vcluster.bend as CF
import ../src/guest/values.bend as VL
import ../src/standalone/join.bend as JN
import bend-kube-runtime@0.2.0.0/src/json.bend as J
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

def Vk8s.deads(dead: Bool, +d: U32) -> U32:
  match dead:
    case True{}:
      (d + 1 : U32)
    case False{}:
      0

def Vk8s.wait_vm.loop(n: Nat, +vdir: String, +rel: String, +deads: U32) -> IO(Bool):
  match n:
    case 0n:
      IO.pure(Bool, False{})
    case 1n+p:
      do IO<Bool>:
        r : String <- Vk8s.sh_out("d=" ++ Vk8s.q(vdir) ++ "; if test -s \"$d" ++ rel ++ "\"; then echo up; elif kill -0 \"$(cat \"$d/vmm.pid\" 2>/dev/null)\" 2>/dev/null; then echo wait; else echo dead; fi")
        +st : String = String.trim(r)
        +d2 : U32 = Vk8s.deads(String.eq(st, "dead"), deads)
        Vk8s.wait_vm.go(String.eq(st, "up"), U32.is_ge(d2, 3), Vk8s.sleep_then(Vk8s.wait_vm.loop(p, vdir, rel, d2)))

# Wait for file `rel` of a VM's directory while its VMM runs (n tries,
# 500 ms apart): False once the VMM has been seen gone three times in a
# row (one failed check under load is not a dead VMM).
def Vk8s.wait_vm(n: Nat, +vdir: String, +rel: String) -> IO(Bool):
  Vk8s.wait_vm.loop(n, vdir, rel, 0)

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
          ++ P.Plan.sh_words(flags) ++ " </dev/null >vmm.log 2>&1 & } && echo $! > vmm.pid")
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
      ++ P.Plan.sh_words(C.Cli.cache_flags(dir, assets)) ++ " </dev/null >vmm.log 2>&1 & } && echo $! > vmm.pid")
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

# The join token, when there are workers to join (a classic-mode control
# plane, which has no nodes, publishes none).
def Vk8s.join_token_if(none: Bool, +dir: String) -> IO(String):
  match none:
    case True{}:
      IO.pure(String, "")
    case False{}:
      Vk8s.join_token(dir)

def Vk8s.boot_ws(+name: String, +guest: String, +dir: String, +assets: String, +port: U32, +cpus: U32, +mem: U32, +etcd: Bool,
  +ws: List<&2, U32>, +extra: String) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    Vk8s.cache_ensure(home, assets)
    +self : String <- Vk8s.self()
    +flags : +List<String> = C.Cli.vmm_flags_x(dir, assets, guest, port, cpus, mem, etcd, extra)
    started : Bool <- Vk8s.sh_ok("cd " ++ Vk8s.q(dir) ++ " && rm -f share/kubeconfig.yaml share/join-token && { nohup " ++ Vk8s.q(self) ++ " vmm"
      ++ P.Plan.sh_words(flags) ++ " </dev/null >vmm.log 2>&1 & } && echo $! > vmm.pid")
    Vk8s.unless(started, Vk8s.die("could not start the VM"))
    up : Bool <- Vk8s.wait_vm(360n, dir, "/share/kubeconfig.yaml")
    Vk8s.unless(up, Vk8s.die("vCluster " ++ name ++ " did not come up; see " ++ dir ++ "/console.log"))
    Vk8s.own_kubeconfig(name, dir, port)
    +token : String <- Vk8s.join_token_if(List.is_empty(&2, U32, ws), dir)
    _ : Unit <- Vk8s.workers(ws, self, dir, assets, guest, token)
    joined : Bool <- Vk8s.wait_workers(ws, dir)
    Vk8s.unless(joined, Vk8s.die("a worker node of " ++ name ++ " did not join; see " ++ dir ++ "/nodes/*/console.log"))

def Vk8s.line(ls: List<&2, String>, n: Nat) -> String:
  match ls n:
    case Nil{} _:
      ""
    case Con{l, t} 0n:
      l
    case Con{l, t} 1n+p:
      Vk8s.line(t, p)

# A new bootstrap token valid for one hour, made through the API with the
# host-owned kubeconfig (vk8s node add; needs kubectl, as node delete does).
def Vk8s.fresh_token(+dir: String) -> IO(String):
  do IO<String>:
    ids : String <- Vk8s.sh_out("LC_ALL=C tr -dc a-z0-9 </dev/urandom | head -c 22; echo; date -u -v+1H +%Y-%m-%dT%H:%M:%SZ")
    +ls : List<&2, String> = String.lines(ids)
    +raw : String = String.trim(Vk8s.line(ls, 0n))
    +exp : String = String.trim(Vk8s.line(ls, 1n))
    +id : String = String.take(raw, 6n)
    +sec : String = String.drop(raw, 6n)
    ok : Bool <- Vk8s.sh_ok("printf %s " ++ Vk8s.q(C.Cli.token_secret(id, sec, exp)) ++ " | kubectl --kubeconfig " ++ Vk8s.q(dir ++ "/kubeconfig.yaml") ++ " apply -f - >/dev/null")
    Vk8s.unless(Bool.and(ok, C.Cli.token_ok(id ++ "." ++ sec)), Vk8s.die("could not create a join token (is kubectl installed?)"))
    return id ++ "." ++ sec

# Boot a cluster whose directory holds its data disk: the control plane VM,
# then the workers once it publishes its kubeconfig. `guest` names the
# node inside the VMs (the cluster's original name after a restore).
def Vk8s.boot(+name: String, +guest: String, +dir: String, +assets: String, +port: U32, +cpus: U32, +mem: U32, +etcd: Bool,
  +nodes: U32) -> IO(Unit):
  Vk8s.boot_ws(name, guest, dir, assets, port, cpus, mem, etcd, C.Cli.workers_upto(nodes), "")

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

def Vk8s.create_x(+name: String, +port0: U32, +cpus: U32, +mem: U32, +etcd: Bool, +nodes: U32, +extra: String, +hostkc: String, +values: String) -> IO(Unit):
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
    hk : Bool <- Vk8s.sh_ok("[ -z " ++ Vk8s.q(hostkc) ++ " ] || { umask 077; printf %s " ++ Vk8s.q(hostkc) ++ " > " ++ Vk8s.q(dir ++ "/share/host-kubeconfig") ++ "; }")
    vy : Bool <- Vk8s.sh_ok("[ -z " ++ Vk8s.q(values) ++ " ] || { printf %s " ++ Vk8s.q(values) ++ " > " ++ Vk8s.q(dir ++ "/vcluster.yaml") ++ " && cp "
      ++ Vk8s.q(dir ++ "/vcluster.yaml") ++ " " ++ Vk8s.q(dir ++ "/share/vcluster.yaml") ++ "; }")
    Vk8s.unless(vy, Vk8s.die("could not write the vcluster.yaml of " ++ name))
    Vk8s.unless(hk, Vk8s.die("could not write the host kubeconfig for " ++ name))
    Vk8s.boot_ws(name, name, dir, assets, port, cpus, mem, etcd, C.Cli.workers_upto(nodes), extra)
    Vk8s.say("Successfully created virtual cluster " ++ name ++ ". ")
    Vk8s.created_msg(name, dir)

def Vk8s.create(+name: String, +port0: U32, +cpus: U32, +mem: U32, +etcd: Bool, +nodes: U32) -> IO(Unit):
  Vk8s.create_x(name, port0, cpus, mem, etcd, nodes, "", "", "")

# Whether the host accepts a Service at this cluster IP (vcluster isInRange).
def Vk8s.in_range(+k: String, +ip: U32) -> IO(Bool):
  Vk8s.sh_ok("out=$(printf '%s' " ++ Vk8s.q("{\"apiVersion\":\"v1\",\"kind\":\"Service\",\"metadata\":{\"generateName\":\"test-service-delete-me-\"},\"spec\":{\"ports\":[{\"port\":80}],\"ipFamilyPolicy\":\"SingleStack\",\"ipFamilies\":[\"IPv4\"],\"clusterIP\":\"" ++ CI.Cidr.show_ip(ip) ++ "\"}}")
    ++ " | " ++ k ++ "create -f - -o name 2>&1); r=$?; if [ $r = 0 ]; then " ++ k ++ "delete $out --ignore-not-found >/dev/null 2>&1; exit 0; fi; "
    ++ "case \"$out\" in *'is already allocated'*|*'allocator not ready'*) exit 0;; *) exit 1;; esac")

# The prefix search, one probe (two test Services) per round.
def Vk8s.cidr_loop(fuel: Nat, p: CI.Probe, +s: CI.Search, +a: U32, +k: String) -> IO(String):
  match fuel p:
    case _ CI.Found{x}:
      IO.pure(String, CI.Cidr.show(a, x))
    case 0n CI.Probe{m, l, h}:
      IO.pure(String, "10.96.0.0/12")
    case 1n+f CI.Probe{+mid, +lo, +hi}:
      do IO<String>:
        ok_l : Bool <- Vk8s.in_range(k, lo)
        ok_h : Bool <- Vk8s.in_range(k, hi)
        +s2 : CI.Search = CI.Cidr.answer(s, mid, Bool.and(ok_l, ok_h))
        Vk8s.cidr_loop(f, CI.Cidr.probe(s2), s2, a, k)

def Vk8s.host_cidr.go(m: Maybe<&2, U32>, +k: String) -> IO(String):
  match m:
    case None{}:
      do IO<String>:
        Vk8s.die("could not create a probe Service in the host cluster (is kubectl installed and the host kubeconfig valid?)")
        return ""
    case Some{+a}:
      Vk8s.cidr_loop(8n, CI.Cidr.probe(CI.Cidr.start(a)), CI.Cidr.start(a), a, k)

# vcluster's service CIDR detection (pkg/util/servicecidr), against the host
# cluster: a Service gives an address inside the range, then test Services
# at chosen cluster IPs (accepted, or "already allocated", means in range)
# narrow the prefix (src/net/cidr.bend). Every test Service is removed.
def Vk8s.host_cidr(+kc: String, +ns: String) -> IO(String):
  do IO<String>:
    +k : String = "kubectl --kubeconfig " ++ Vk8s.q(kc) ++ " -n " ++ Vk8s.q(ns) ++ " "
    # a namespace vk8s makes carries vcluster's created annotation, so
    # delete removes it (pkg/cli: CreatedByVClusterAnnotation)
    _ : Bool <- Vk8s.sh_ok("kubectl --kubeconfig " ++ Vk8s.q(kc) ++ " get namespace " ++ Vk8s.q(ns) ++ " >/dev/null 2>&1 || { kubectl --kubeconfig " ++ Vk8s.q(kc)
      ++ " create namespace " ++ Vk8s.q(ns) ++ " >/dev/null && kubectl --kubeconfig " ++ Vk8s.q(kc) ++ " annotate namespace " ++ Vk8s.q(ns) ++ " vcluster.loft.sh/created=true >/dev/null; }")
    ip : String <- Vk8s.sh_out(k ++ "create service clusterip vk8s-cidr-probe --tcp=80 -o jsonpath='{.spec.clusterIP}' 2>/dev/null; " ++ k ++ "delete service vk8s-cidr-probe --ignore-not-found >/dev/null 2>&1")
    Vk8s.host_cidr.go(CI.Cidr.parse_ip(String.trim(ip)), k)

# The vcluster's Service in the host namespace (Cli.host_service): its
# cluster IP joins the API server's SANs, and the syncer mirrors it into
# the virtual default/kubernetes (specialservices).
def Vk8s.host_service(+kc: String, +name: String, +ns: String, +port: U32) -> IO(String):
  do IO<String>:
    +k : String = "kubectl --kubeconfig " ++ Vk8s.q(kc) ++ " "
    ip : String <- Vk8s.sh_out("printf %s " ++ Vk8s.q(C.Cli.host_service(name, ns, port)) ++ " | " ++ k ++ "apply -f - >/dev/null 2>&1 && printf %s "
      ++ Vk8s.q(C.Cli.host_endpoints(name, ns, port)) ++ " | " ++ k ++ "apply -f - >/dev/null 2>&1 && " ++ k ++ "-n " ++ Vk8s.q(ns) ++ " get service " ++ Vk8s.q(name)
      ++ " -o jsonpath='{.spec.clusterIP}' 2>/dev/null")
    +san : String = String.trim(ip)
    Vk8s.when(String.is_empty(san), Vk8s.die("could not create the vCluster service in the host namespace " ++ ns))
    kip : String <- Vk8s.sh_out("printf %s " ++ Vk8s.q(C.Cli.konn_service(name, ns)) ++ " | " ++ k ++ "apply -f - >/dev/null 2>&1 && printf %s "
      ++ Vk8s.q(C.Cli.konn_endpoints(name, ns, port)) ++ " | " ++ k ++ "apply -f - >/dev/null 2>&1 && " ++ k ++ "-n " ++ Vk8s.q(ns) ++ " get service " ++ Vk8s.q(C.Cli.konn_name(name))
      ++ " -o jsonpath='{.spec.clusterIP}' 2>/dev/null")
    +ksan : String = String.trim(kip)
    Vk8s.when(String.is_empty(ksan), Vk8s.die("could not create the konnectivity service in the host namespace " ++ ns))
    Vk8s.say("Host service " ++ ns ++ "/" ++ name ++ " at " ++ san ++ ", konnectivity at " ++ ksan)
    return san ++ "," ++ ksan

# Where a classic cluster's host objects live, for delete: the host
# kubeconfig's absolute path and the host namespace.
def Vk8s.host_record(+name: String, +kc: String, +ns: String) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +dir : String = C.Cli.dir(home, name)
    _ : Bool <- Vk8s.sh_ok("f=" ++ Vk8s.q(kc) ++ "; printf '%s/%s' \"$(cd \"$(dirname \"$f\")\" && pwd)\" \"$(basename \"$f\")\" > " ++ Vk8s.q(dir ++ "/host-kubeconfig-path")
      ++ " && printf %s " ++ Vk8s.q(ns) ++ " > " ++ Vk8s.q(dir ++ "/host-namespace"))
    return Unit{}

def Vk8s.create_classic.go(r: Result<&2, &2, String, String>, +name: String, +port0: U32, +cpus: U32, +mem: U32, +etcd: Bool, +nodes: U32, +ns: String, +kc: String, +values: String) -> IO(Unit):
  match r:
    case Fail{e}:
      Vk8s.die(e)
    case Done{text}:
      do IO<Unit>:
        +cidr : String <- Vk8s.host_cidr(kc, ns)
        Vk8s.say("Host cluster service CIDR: " ++ cidr)
        now : Nat <- IO.now()
        +port : U32 = Vk8s.pick_port(U32.is_eq(port0, 0), port0, U32.from_nat(now))
        +san : String <- Vk8s.host_service(kc, name, ns, port)
        Vk8s.create_x(name, port, cpus, mem, etcd, nodes, C.Cli.classic_cmdline_full(ns, cidr, san), text, values)
        Vk8s.host_record(name, kc, ns)

# Deleting a classic cluster removes what it made on the host, as vcluster
# delete does (helm uninstall, then the namespace if vcluster created it and
# no other vcluster is left in it): its Services, the objects the syncer
# made (label vcluster.loft.sh/managed-by), its Lease. After the VMs stop,
# so the syncer cannot make them again.
def Vk8s.host_cleanup(+name: String, +dir: String) -> String:
  "if [ -f " ++ Vk8s.q(dir ++ "/host-namespace") ++ " ]; then hk=$(cat " ++ Vk8s.q(dir ++ "/host-kubeconfig-path") ++ "); ns=$(cat " ++ Vk8s.q(dir ++ "/host-namespace") ++ "); "
    ++ "k=\"kubectl --kubeconfig $hk --request-timeout=20s\"; n=" ++ Vk8s.q(name) ++ "; "
    ++ "$k -n \"$ns\" delete service \"$n\" \"$n-konnectivity\" --ignore-not-found --wait=false >/dev/null 2>&1; "
    ++ "$k -n \"$ns\" delete lease \"vcluster-$n-controller\" --ignore-not-found --wait=false >/dev/null 2>&1; "
    ++ "$k -n \"$ns\" delete pods,services,endpoints,configmaps,secrets,serviceaccounts,persistentvolumeclaims -l \"vcluster.loft.sh/managed-by=$n\" --ignore-not-found --wait=false >/dev/null 2>&1; "
    ++ "$k delete persistentvolumes,storageclasses,priorityclasses -l \"vcluster.loft.sh/managed-by=$n\" --ignore-not-found --wait=false >/dev/null 2>&1; "
    ++ "if [ \"$($k get namespace \"$ns\" -o jsonpath='{.metadata.annotations.vcluster\\.loft\\.sh/created}' 2>/dev/null)\" = true ] "
    ++ "&& [ -z \"$($k -n \"$ns\" get services -l app=vcluster -o name 2>/dev/null)\" ]; then "
    ++ "$k delete namespace \"$ns\" --wait=false >/dev/null 2>&1 && echo \"Deleted host namespace $ns\"; fi; fi"

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

# Classic mode with a vcluster.yaml (create -f): the file reaches the share,
# where the syncer reads its sync flags (--config).
def Vk8s.create_classic_v(+name: String, +port0: U32, +cpus: U32, +mem: U32, +etcd: Bool, +nodes: U32, +kc: String, +ns: String, +values: String) -> IO(Unit):
  do IO<Unit>:
    +got : Sh <- Vk8s.read(kc)
    Vk8s.unless(Vk8s.sh_ok.of(got), Vk8s.die("could not read the host kubeconfig " ++ kc))
    Vk8s.create_classic.go(K.Kubeconfig.for_guest(Vk8s.raw.out(got)), name, port0, cpus, mem, etcd, nodes, ns, kc, values)

# Classic mode (vcluster on a host cluster): the host cluster's kubeconfig,
# as the guest's syncer reaches it (Kubeconfig.for_guest), goes on the
# share, and the kernel command line names the mode and host namespace.
def Vk8s.create_classic(+name: String, +port0: U32, +cpus: U32, +mem: U32, +etcd: Bool, +nodes: U32, +kc: String, +ns: String) -> IO(Unit):
  Vk8s.create_classic_v(name, port0, cpus, mem, etcd, nodes, kc, ns, "")

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
    _ : Bool <- Vk8s.sh_ok(Vk8s.host_cleanup(name, dir))
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
    Vk8s.boot_ws(name, guest, dir, assets, port, cpus, mem, etcd, ws, "")
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
    +token : String <- Vk8s.fresh_token(dir)
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

def Vk8s.request.next(done: Bool, failed: Bool, again: IO(Bool)) -> IO(Bool):
  match done failed:
    case True{} _:
      IO.pure(Bool, True{})
    case False{} True{}:
      IO.pure(Bool, False{})
    case False{} False{}:
      again

def Vk8s.request.wait(n: Nat, +dir: String, +id: String) -> IO(Bool):
  match n:
    case 0n:
      IO.pure(Bool, False{})
    case 1n+p:
      do IO<Bool>:
        r : String <- Vk8s.share_read(dir ++ "/share/requests/response", 256)
        +ans : String = String.trim(r)
        Vk8s.request.next(String.eq(ans, id ++ " done"), String.eq(ans, id ++ " failed"), Vk8s.sleep_then(Vk8s.request.wait(p, dir, id)))

# Ask the cluster's PID 1 to run an action (P.Plan.request) and wait for
# its answer: share/requests/request holds "ID ACTION", the guest writes
# "ID done|failed" to share/requests/response.
def Vk8s.request(+dir: String, +action: String) -> IO(Bool):
  do IO<Bool>:
    idr : String <- Vk8s.sh_out("LC_ALL=C tr -dc a-z0-9 </dev/urandom | head -c 8")
    +id : String = String.trim(idr)
    put : Bool <- Vk8s.sh_ok("d=" ++ Vk8s.q(dir ++ "/share/requests") ++ "; mkdir -p \"$d\" && rm -f \"$d/response\" && printf '%s %s\\n' "
      ++ Vk8s.q(id) ++ " " ++ Vk8s.q(action) ++ " > \"$d/request.tmp\" && mv \"$d/request.tmp\" \"$d/request\"")
    Vk8s.unless(put, Vk8s.die("could not send the request to the cluster"))
    Vk8s.request.wait(600n, dir, id)

# Wait for the API server to answer again (n tries, 500 ms apart).
def Vk8s.wait_api(n: Nat, +dir: String) -> IO(Bool):
  match n:
    case 0n:
      IO.pure(Bool, False{})
    case 1n+p:
      do IO<Bool>:
        ok : Bool <- Vk8s.sh_ok("curl -sk -o /dev/null --max-time 2 https://127.0.0.1:$(cat " ++ Vk8s.q(dir ++ "/port") ++ ")/livez")
        Vk8s.or_retry(ok, Vk8s.sleep_then(Vk8s.wait_api(p, dir)))

def Vk8s.certs.go(rotate: Bool, +name: String, +dir: String) -> IO(Unit):
  match rotate:
    case True{}:
      do IO<Unit>:
        Vk8s.say("Rotating the certificates of vCluster " ++ name ++ "...")
        ok : Bool <- Vk8s.request(dir, "certs-rotate")
        Vk8s.unless(ok, Vk8s.die("certificate rotation failed; see " ++ dir ++ "/console.log"))
        ps : String <- Vk8s.setting(dir, "PORT")
        up : Bool <- Vk8s.wait_api(240n, dir)
        Vk8s.own_kubeconfig(name, dir, Vk8s.u32(ps, 0))
        Vk8s.unless(up, Vk8s.die("the API server did not come back after rotation"))
        Vk8s.say("Successfully rotated the certificates of vCluster " ++ name ++ " (run 'vk8s connect " ++ name ++ "' to refresh your kubeconfig)")
    case False{}:
      do IO<Unit>:
        ok : Bool <- Vk8s.request(dir, "certs-check")
        Vk8s.unless(ok, Vk8s.die("the certificate check failed"))
        out : String <- Vk8s.sh_out("ls -t " ++ Vk8s.q(dir ++ "/share/requests") ++ " | grep '\\.out$' | head -1")
        +text : String <- Vk8s.share_read(dir ++ "/share/requests/" ++ String.trim(out), 65536)
        IO.write(text)

def Vk8s.stop_workers(ws: List<&2, U32>, +dir: String) -> IO(Unit):
  match ws:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+i, t}:
      do IO<Unit>:
        _ : Bool <- Vk8s.sh_ok(Vk8s.stop_vm(C.Cli.node_dir(dir, i)))
        Vk8s.stop_workers(t, dir)

# vk8s certs rotate-ca NAME (vcluster certs rotate-ca): a new CA and every
# certificate under it; the service account keys stay. The workers rejoin
# under the new CA.
def Vk8s.rotate_ca(+name: String, +dir: String) -> IO(Unit):
  do IO<Unit>:
    Vk8s.say("Rotating the certificate authority of vCluster " ++ name ++ "...")
    ok : Bool <- Vk8s.request(dir, "certs-rotate-ca")
    Vk8s.unless(ok, Vk8s.die("CA rotation failed; see " ++ dir ++ "/console.log (the old PKI is in /var/lib/vcluster/pki.bak)"))
    up : Bool <- Vk8s.wait_api(240n, dir)
    Vk8s.unless(up, Vk8s.die("the API server did not come back after CA rotation"))
    fin : Bool <- Vk8s.request(dir, "certs-ca-finish")
    Vk8s.unless(fin, Vk8s.die("could not refresh the join material after CA rotation"))
    ps : String <- Vk8s.setting(dir, "PORT")
    Vk8s.own_kubeconfig(name, dir, Vk8s.u32(ps, 0))
    +ws : List<&2, U32> <- Vk8s.worker_list(dir)
    Vk8s.stop_workers(ws, dir)
    +guest0 : String <- Vk8s.setting(dir, "GUEST")
    +home : String <- Vk8s.home()
    +assets : String <- Vk8s.assets(home)
    +token : String <- Vk8s.join_token(dir)
    +self : String <- Vk8s.self()
    Vk8s.workers(ws, self, dir, assets, Vk8s.or_name(String.is_empty(guest0), guest0, name), token)
    joined : Bool <- Vk8s.wait_workers(ws, dir)
    Vk8s.unless(joined, Vk8s.die("a worker did not rejoin after CA rotation"))
    Vk8s.say("Successfully rotated the certificate authority of vCluster " ++ name ++ " (run 'vk8s connect " ++ name ++ "' to refresh your kubeconfig)")

def Vk8s.certs.ca(ca: Bool, +action: String, +name: String, +dir: String) -> IO(Unit):
  match ca:
    case True{}:
      Vk8s.rotate_ca(name, dir)
    case False{}:
      Vk8s.certs.go(String.eq(action, "rotate"), name, dir)

# vk8s certs rotate NAME: renew every certificate (the CA is kept), restart
# the control plane on them, and rebuild the host-owned kubeconfig.
# vk8s certs check NAME: kubeadm's expiration table.
def Vk8s.certs(+action: String, +name: String) -> IO(Unit):
  do IO<Unit>:
    +dir : String <- Vk8s.exists(name)
    Vk8s.certs.ca(String.eq(action, "rotate-ca"), action, name, dir)

def Vk8s.node_vdir(m: Maybe<&2, U32>, cp: Bool, +dir: String) -> String:
  match m cp:
    case _ True{}:
      dir
    case Some{i} False{}:
      C.Cli.node_dir(dir, i)
    case None{} False{}:
      ""

def Vk8s.load_name(gz: Bool) -> String:
  match gz:
    case True{}:
      "load.tar.gz"
    case False{}:
      "load.tar"

# vk8s node load-image NAME NODE --archive FILE (vcluster node load-image):
# the archive goes on that node VM's share, and its PID 1 imports it.
def Vk8s.node_load(+name: String, +node: String, +archive: String) -> IO(Unit):
  do IO<Unit>:
    +dir : String <- Vk8s.exists(name)
    +guest0 : String <- Vk8s.setting(dir, "GUEST")
    +guest : String = Vk8s.or_name(String.is_empty(guest0), guest0, name)
    +vdir : String = Vk8s.node_vdir(C.Cli.worker_index(guest, node), String.eq(node, guest), dir)
    Vk8s.when(String.is_empty(vdir), Vk8s.die("node " ++ node ++ " not found in vCluster " ++ name))
    +f : String = Vk8s.load_name(String.ends_with(archive, ".gz"))
    Vk8s.say("Loading " ++ archive ++ " into node " ++ node ++ "...")
    cp : Bool <- Vk8s.sh_ok("test -f " ++ Vk8s.q(archive) ++ " && mkdir -p " ++ Vk8s.q(vdir ++ "/share/images") ++ " && cp -c " ++ Vk8s.q(archive) ++ " " ++ Vk8s.q(vdir ++ "/share/images/" ++ f))
    Vk8s.unless(cp, Vk8s.die("could not read " ++ archive))
    ok : Bool <- Vk8s.request(vdir, "image-load:" ++ f)
    Vk8s.unless(ok, Vk8s.die("the node could not import " ++ archive ++ "; see " ++ vdir ++ "/console.log"))
    Vk8s.say("Successfully loaded " ++ archive ++ " into node " ++ node)

def Vk8s.token_expiry(never: Bool, +d: TK.Dur, +now: U32) -> Maybe<&2, JN.Join.Time>:
  match never d:
    case True{} _:
      None{}
    case False{} TK.Dur{ok, secs, e}:
      Some{JN.Join.expiry(JN.Join.time_of_unix(now), secs)}

def Vk8s.dur_ok(d: TK.Dur) -> Bool:
  match d:
    case TK.Dur{ok, s, e}:
      ok

def Vk8s.dur_err(d: TK.Dur) -> String:
  match d:
    case TK.Dur{ok, s, e}:
      e

def Vk8s.hash_of(h: JN.Join.Hash) -> String:
  match h:
    case JN.HashOk{v}:
      v
    case JN.HashErr{e}:
      ""

def Vk8s.token_print(kubeadm: Bool, +api: String, +token: String, +dir: String) -> IO(Unit):
  match kubeadm:
    case False{}:
      IO.write(JN.Join.join_command("", api, token))
    case True{}:
      do IO<Unit>:
        pem : String <- Vk8s.sh_out("sed -n 's/^ *certificate-authority-data: *//p' " ++ Vk8s.q(dir ++ "/kubeconfig.yaml") ++ " | head -1 | base64 -d")
        IO.write(JN.Join.kubeadm_command(api, token, Vk8s.hash_of(JN.Join.ca_hash(pem))))

# vcluster token create: a bootstrap token Secret with vcluster's labels,
# then the join command (or with --kubeadm the raw kubeadm join).
def Vk8s.token_create(+name: String, +expires: String, +kubeadm: Bool, +cp: Bool) -> IO(Unit):
  do IO<Unit>:
    +dir : String <- Vk8s.exists(name)
    Vk8s.when(Bool.and(kubeadm, cp), Vk8s.die("--kubeadm and --control-plane are mutually exclusive"))
    +never : Bool = String.is_empty(expires)
    +d : TK.Dur = TK.Tok.duration(expires)
    Vk8s.unless(Bool.or(never, Vk8s.dur_ok(d)), Vk8s.die(Vk8s.dur_err(d)))
    +now : U32 <- Vk8s.epoch()
    ids : String <- Vk8s.sh_out("LC_ALL=C tr -dc a-z0-9 </dev/urandom | head -c 22")
    +raw : String = String.trim(ids)
    +id : String = String.take(raw, 6n)
    +sec : String = String.drop(raw, 6n)
    # client-go fills apiVersion and kind for vcluster's typed Secret
    +secret : String = "{\"apiVersion\":\"v1\",\"kind\":\"Secret\"," ++ String.drop(J.Json.show(JN.Join.token_secret(id, sec, cp, Vk8s.token_expiry(never, d, now))), 1n)
    ok : Bool <- Vk8s.sh_ok("printf %s " ++ Vk8s.q(secret) ++ " | kubectl --kubeconfig " ++ Vk8s.q(dir ++ "/kubeconfig.yaml") ++ " apply -f - >/dev/null")
    Vk8s.unless(Bool.and(ok, JN.Join.valid_token(id ++ "." ++ sec)), Vk8s.die("could not create the token (is kubectl installed?)"))
    +api : String = C.Cli.lan_ip(0) ++ ":6443"
    Vk8s.token_print(kubeadm, api, id ++ "." ++ sec, dir)

def Vk8s.tok_entry(fs: List<&2, String>) -> List<&2, C.TokEntry>:
  match fs:
    case Con{i, Con{x, Con{c, Nil{}}}}:
      [C.TokEntry{i, x, c}]
    case _:
      Nil{}

def Vk8s.tok_entries(ls: List<&2, String>) -> List<&2, C.TokEntry>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{l, t}:
      List.append(&2, C.TokEntry, Vk8s.tok_entry(String.split(l, '\t')), Vk8s.tok_entries(t))

def Vk8s.token_list.out(json: Bool, es: List<&2, C.TokEntry>) -> String:
  match json:
    case True{}:
      C.Cli.token_json(es)
    case False{}:
      C.Cli.token_table(es)

# vcluster token list: the Secrets labeled vcluster.loft.sh/token=true.
def Vk8s.token_list(+name: String, json: Bool) -> IO(Unit):
  do IO<Unit>:
    +dir : String <- Vk8s.exists(name)
    out : String <- Vk8s.sh_out("kubectl --kubeconfig " ++ Vk8s.q(dir ++ "/kubeconfig.yaml") ++ " -n kube-system get secrets -l vcluster.loft.sh/token=true "
      ++ "-o jsonpath='{range .items[*]}{.data.token-id}{\" \"}{.data.expiration}{\" \"}{.metadata.creationTimestamp}{\"\\n\"}{end}' | while read i x c; do "
      ++ "[ -n \"$x\" ] && [ \"$c\" ] && x=$(printf %s \"$x\" | base64 -d) || { c=$x; x=never; }; printf '%s\\t%s\\t%s\\n' \"$(printf %s \"$i\" | base64 -d)\" \"$x\" \"$c\"; done")
    IO.write(Vk8s.token_list.out(json, Vk8s.tok_entries(String.lines(out))))

def Vk8s.token_delete(+name: String, +id: String) -> IO(Unit):
  do IO<Unit>:
    +dir : String <- Vk8s.exists(name)
    +r : Sh <- Vk8s.sh("kubectl --kubeconfig " ++ Vk8s.q(dir ++ "/kubeconfig.yaml") ++ " -n kube-system delete secret " ++ Vk8s.q(JN.Join.secret_name(id)) ++ " 2>&1")
    Vk8s.unless(Vk8s.sh_ok.of(r), Vk8s.die(String.trim(Vk8s.raw.out(r))))
    Vk8s.say("Token deleted successfully")

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

# vcluster create connects afterwards (--connect, default true): the
# context is added to the kubeconfig and becomes current.
def Vk8s.then_connect(go: Bool, +name: String, act: IO(Unit)) -> IO(Unit):
  match go:
    case True{}:
      do IO<Unit>:
        act
        Vk8s.connect(name, False{}, True{})
    case False{}:
      act

def Vk8s.run.values.create(c: C.Cmd, +etcd: Bool, +text: String, conn: Bool) -> IO(Unit):
  match c:
    case C.Classic{C.Create{+name, port, cpus, mem, e0, nodes}, kc, ns}:
      Vk8s.then_connect(conn, name, Vk8s.create_classic_v(name, port, cpus, mem, etcd, nodes, kc, ns, text))
    case C.Classic{C.NoConnect{C.Create{name, port, cpus, mem, e0, nodes}}, kc, ns}:
      Vk8s.create_classic_v(name, port, cpus, mem, etcd, nodes, kc, ns, text)
    case C.Create{+name, port, cpus, mem, e0, nodes}:
      Vk8s.then_connect(conn, name, Vk8s.create_x(name, port, cpus, mem, etcd, nodes, "", "", text))
    case C.NoConnect{C.Create{name, port, cpus, mem, e0, nodes}}:
      Vk8s.create_x(name, port, cpus, mem, etcd, nodes, "", "", text)
    case _:
      Vk8s.die("-f applies to create only")

def Vk8s.run.values.go(r: Result<&2, &2, String, J.Json>, +text: String, c: C.Cmd, conn: Bool) -> IO(Unit):
  match r:
    case Fail{e}:
      Vk8s.die(e)
    case Done{+cfg}:
      do IO<Unit>:
        +why : String = VL.Values.unsupported(cfg)
        Vk8s.unless(String.is_empty(why), Vk8s.die(why))
        Vk8s.run.values.create(c, VL.Values.etcd(cfg), text, conn)

# vcluster create -f vcluster.yaml: validated as vcluster validates it
# (src/config/vcluster.bend), its backing store chosen, settings vk8s
# cannot honor refused; the guest applies the components' extraArgs.
def Vk8s.run.values(c: C.Cmd, +file: String, conn: Bool) -> IO(Unit):
  do IO<Unit>:
    +got : Sh <- Vk8s.read(file)
    Vk8s.unless(Vk8s.sh_ok.of(got), Vk8s.die("could not read " ++ file))
    +text : String = Vk8s.raw.out(got)
    Vk8s.run.values.go(CF.Config.parse(text), text, c, conn)

def Vk8s.run.classic(c: C.Cmd, +kc: String, +ns: String, conn: Bool) -> IO(Unit):
  match c:
    case C.Create{+name, port, cpus, mem, etcd, nodes}:
      Vk8s.then_connect(conn, name, Vk8s.create_classic(name, port, cpus, mem, etcd, nodes, kc, ns))
    case C.NoConnect{C.Create{name, port, cpus, mem, etcd, nodes}}:
      Vk8s.create_classic(name, port, cpus, mem, etcd, nodes, kc, ns)
    case _:
      Vk8s.die("--host-kubeconfig applies to create only")

@unsafe def Vk8s.run.go(c: C.Cmd, conn: Bool) -> IO(Unit):
  match c:
    case C.NoConnect{inner}:
      Vk8s.run.go(inner, False{})
    case C.Classic{inner, kc, ns}:
      Vk8s.run.classic(inner, kc, ns, conn)
    case C.WithValues{inner, file}:
      Vk8s.run.values(inner, file, conn)
    case C.Create{+name, port, cpus, mem, etcd, nodes}:
      Vk8s.then_connect(conn, name, Vk8s.create(name, port, cpus, mem, etcd, nodes))
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
    case C.Restore{+name, path}:
      Vk8s.then_connect(conn, name, Vk8s.restore(name, path))
    case C.Exec{name, cmd}:
      Vk8s.exec(name, cmd)
    case C.Cache{action}:
      Vk8s.cache(action)
    case C.Certs{action, name}:
      Vk8s.certs(action, name)
    case C.TokenCreate{name, expires, kubeadm, cp}:
      Vk8s.token_create(name, expires, kubeadm, cp)
    case C.TokenList{name, json}:
      Vk8s.token_list(name, json)
    case C.TokenDelete{name, id}:
      Vk8s.token_delete(name, id)
    case C.NodeLoad{name, node, archive}:
      Vk8s.node_load(name, node, archive)
    case C.Upgrade{+name, port, cpus, mem, etcd, nodes}:
      Vk8s.then_connect(conn, name, Vk8s.upgrade(name, port, cpus, mem, etcd, nodes))
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

@unsafe def Vk8s.run(c: C.Cmd) -> IO(Unit):
  Vk8s.run.go(c, True{})

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
