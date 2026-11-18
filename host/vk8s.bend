import Base
import 0x37f031982dbba38edaaee15fcde6c33d/main.bend as V
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
import ./snapshot_open.bend as O
import ../src/cli/ctr.bend as R
import ../src/cli/backend.bend as B
import ../src/guest/container.bend as CN
import ./init.bend as I
import ./join_server.bend as JS
import ../src/standalone/native.bend as N
import ../src/standalone/native_host.bend as NH
import ../src/cli/nodehost.bend as HN
import ./bin_file.bend as BF
import ../src/lib/sha256.bend as SH
import ../src/cli/idle.bend as ID
import ./idle_proxy.bend as IP
import ../src/cli/lan_wire.bend as LW
import ./layers/fill.bend as LF
import ../src/guest/netpol.bend as NP

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

# n tries of a wait, times VK8S_WAIT_SCALE (C.Cli.wait_tries): an emulated
# KVM host runs the guests tens of times slower.
def Vk8s.scaled(n: Nat) -> IO(Nat):
  do IO<Nat>:
    +s : String <- Vk8s.getenv("VK8S_WAIT_SCALE", "")
    return C.Cli.wait_tries(n, s)

# Wait for file `rel` of a VM's directory while its VMM runs (n tries,
# 500 ms apart, scaled by VK8S_WAIT_SCALE): False once the VMM has been
# seen gone three times in a row (one failed check under load is not a
# dead VMM).
def Vk8s.wait_vm(n: Nat, +vdir: String, +rel: String) -> IO(Bool):
  do IO<Bool>:
    m : Nat <- Vk8s.scaled(n)
    Vk8s.wait_vm.loop(m, vdir, rel, 0)

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

# An argument list as Process.run takes it.
def Vk8s.argv(xs: +List<String>) -> List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      Con{x, Vk8s.argv(t)}

# Run a program (looked up in PATH) with an argument list, no shell; True
# when it exits 0.
def Vk8s.run_ok(+prog: String, args: +List<String>) -> IO(Bool):
  do IO<Bool>:
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run(prog, Vk8s.argv(args), "", 65536, 600000)
    return Vk8s.sh_ok.of(Vk8s.sh.got(r))

# One copy-on-write copy of a disk image or archive (D3 a): GNU cp first,
# then BSD cp's APFS clone (C.Cli.clone_gnu, C.Cli.clone_bsd).
def Vk8s.clone(+src: String, +dst: String) -> IO(Bool):
  do IO<Bool>:
    gnu : Bool <- Vk8s.run_ok("cp", C.Cli.clone_gnu(src, dst))
    Vk8s.or_retry(gnu, Vk8s.run_ok("cp", C.Cli.clone_bsd(src, dst)))

# Vk8s.clone once ok holds; False otherwise.
def Vk8s.clone_if(ok: Bool, +src: String, +dst: String) -> IO(Bool):
  match ok:
    case True{}:
      Vk8s.clone(src, dst)
    case False{}:
      IO.pure(Bool, False{})

# Host writes into a guest's share (review pr-47 P1). The guest may plant
# a symbolic link at any name in its share, and a write through one would
# overwrite a file of the user (or of root, in container mode). So the
# bytes go first to tmp, a path in a host-owned directory on the share's
# file system, and BinFile.place moves them to root/rel/name: root is the
# share's own directory (host-made), rel ("" or "a/b") is walked without
# following a link, and a link at name is replaced, never followed.

def Vk8s.share_put.ok(r: BF.BinFile.Res(Unit)) -> Bool:
  match r:
    case Done{u}:
      True{}
    case Fail{e}:
      False{}

# BinFile.place once ok holds; then tmp is removed (it is gone after a
# rename, and left over after a failure).
def Vk8s.share_place(ok: Bool, +tmp: String, +root: String, +rel: String, +name: String) -> IO(Bool):
  match ok:
    case False{}:
      do IO<Bool>:
        _ : U32 <- V.Fs.remove(tmp)
        return False{}
    case True{}:
      do IO<Bool>:
        r : BF.BinFile.Res(Unit) <- BF.BinFile.place(tmp, root, rel, name)
        _ : U32 <- V.Fs.remove(tmp)
        return Vk8s.share_put.ok(r)

# Write text as root/rel/name; tmp is made 0600.
def Vk8s.share_put(+tmp: String, +root: String, +rel: String, +name: String, +text: String) -> IO(Bool):
  do IO<Bool>:
    w : BF.BinFile.Res(Unit) <- BF.BinFile.write(tmp, SH.Sha256.utf8(text))
    Vk8s.share_place(Vk8s.share_put.ok(w), tmp, root, rel, name)

# Copy the host file src to root/rel/name (copy-on-write when it can,
# Vk8s.clone).
def Vk8s.share_copy(+src: String, +tmp: String, +root: String, +rel: String, +name: String) -> IO(Bool):
  do IO<Bool>:
    c : Bool <- Vk8s.clone(src, tmp)
    Vk8s.share_place(c, tmp, root, rel, name)

# Vk8s.share_copy once ok holds; False otherwise.
def Vk8s.share_copy_if(ok: Bool, +src: String, +tmp: String, +root: String, +rel: String, +name: String) -> IO(Bool):
  match ok:
    case True{}:
      Vk8s.share_copy(src, tmp, root, rel, name)
    case False{}:
      IO.pure(Bool, False{})

# A program's trimmed output (stdout, then stderr), run with an argument
# list and no shell; on a failure to start, the error.
def Vk8s.run_out(+prog: String, args: +List<String>) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run(prog, Vk8s.argv(args), "", 65536, 60000)
    return Vk8s.sh_out.of(Vk8s.sh.got(r))

# This host's machine name (`uname -m`: arm64 on macOS, aarch64 or x86_64
# on Linux).
def Vk8s.uname() -> IO(String):
  Vk8s.run_out("uname", ["-m"])

# This host's asset arch (M.Manifest.arch: arm64, amd64, or "").
def Vk8s.arch() -> IO(String):
  do IO<String>:
    u : String <- Vk8s.uname()
    return M.Manifest.arch(u)

def Vk8s.can_open.got(r: Result<&1, &1, U32 & String, File>) -> IO(Bool):
  match r:
    case Fail{e}:
      IO.pure(Bool, False{})
    case Done{f}:
      do IO<Bool>:
        File.close(f)
        return True{}

# Whether this user may open path with mode ("r" reads, "r+" reads and
# writes), through Base's File effects.
def Vk8s.can_open(+path: String, +mode: String) -> IO(Bool):
  do IO<Bool>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, mode)
    Vk8s.can_open.got(r)

def Vk8s.slurp.close(p: File & Result<&1, &1, U32 & String, String>) -> IO(String):
  match p:
    case (f, Done{s}):
      do IO<String>:
        File.close(f)
        return s
    case (f, Fail{e}):
      do IO<String>:
        File.close(f)
        return ""

def Vk8s.slurp.go(r: Result<&1, &1, U32 & String, File>) -> IO(String):
  match r:
    case Fail{e}:
      IO.pure(String, "")
    case Done{f}:
      do IO<String>:
        p : File & Result<&1, &1, U32 & String, String> <- File.read(f, 4096)
        Vk8s.slurp.close(p)

# A small file's text, "" when it cannot be read.
def Vk8s.slurp(+path: String) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    Vk8s.slurp.go(r)

# Whether any candidate path of a tool opens (C.Cli.path_candidates).
def Vk8s.on_path(cs: +List<String>) -> IO(Bool):
  match cs:
    case Nil{}:
      IO.pure(Bool, False{})
    case Con{c, t}:
      do IO<Bool>:
        ok : Bool <- Vk8s.can_open(c, "r")
        Vk8s.or_retry(ok, Vk8s.on_path(t))

def Vk8s.missing.add(have: Bool, +t: String, +rest: +List<String>) -> +List<String>:
  match have:
    case True{}:
      rest
    case False{}:
      Con{t, rest}

# The tools of ts that no PATH entry holds, in order.
def Vk8s.missing(+path: String, ts: +List<String>) -> IO(List<&2, String>):
  match ts:
    case Nil{}:
      IO.pure(List<&2, String>, Nil{})
    case Con{+t, rest}:
      do IO<List<&2, String>>:
        have : Bool <- Vk8s.on_path(C.Cli.path_candidates(path, t))
        +more : List<&2, String> <- Vk8s.missing(path, rest)
        return Vk8s.missing.add(have, t, more)

# ["/dev/kvm"] when it is needed and does not open for reading and
# writing; [] otherwise.
def Vk8s.kvm_missing(need: Bool) -> IO(List<&2, String>):
  match need:
    case False{}:
      IO.pure(List<&2, String>, Nil{})
    case True{}:
      do IO<List<&2, String>>:
        ok : Bool <- Vk8s.can_open("/dev/kvm", "r+")
        return Vk8s.missing.add(ok, "/dev/kvm", Nil{})

def Vk8s.home() -> IO(String):
  Vk8s.getenv("HOME", "/tmp")

def Vk8s.raw.out(r: Sh) -> String:
  match r:
    case Sh{ok, out}:
      out

def Vk8s.and_then(ok: Bool, next: IO(Bool)) -> IO(Bool):
  match ok:
    case True{}:
      next
    case False{}:
      IO.pure(Bool, False{})

# Whether every one of these files opens for reading (Base's File effects).
def Vk8s.have_all(ps: +List<String>) -> IO(Bool):
  match ps:
    case Nil{}:
      IO.pure(Bool, True{})
    case Con{+p, t}:
      do IO<Bool>:
        ok : Bool <- Vk8s.can_open(p, "r")
        Vk8s.and_then(ok, Vk8s.have_all(t))

def Vk8s.assets.fetch(have: Bool, +dir: String, +ver: String, files: List<&2, A.AssetFile>) -> IO(String):
  match have:
    case True{}:
      IO.pure(String, dir)
    case False{}:
      do IO<String>:
        Vk8s.say("Downloading vk8s guest assets " ++ ver ++ " (once) into " ++ dir ++ "...")
        +base : String <- Vk8s.getenv("VK8S_ASSETS_URL", A.Assets.default_base())
        +r : Sh <- Vk8s.sh(A.Assets.fetch_sh(dir, base, ver, files))
        Vk8s.unless(Vk8s.sh_ok.of(r), Vk8s.die("could not fetch the guest assets: " ++ String.trim(Vk8s.raw.out(r))))
        return dir

def Vk8s.assets.pinned.go(none: Bool, +arch: String, +ver: String, files: List<&2, A.AssetFile>, +uname: String, +home: String) -> IO(String):
  match none:
    case True{}:
      do IO<String>:
        Vk8s.die("this vk8s pins no guest assets for " ++ String.trim(uname) ++ C.Cli.pick_str(String.is_empty(arch), "", " (" ++ arch ++ ")")
          ++ "; set VK8S_ASSETS to a local build (scripts/guest/build.sh)")
        return ""
    case False{}:
      do IO<String>:
        +dir : String = A.Assets.dir(home, ver)
        have : Bool <- Vk8s.have_all(A.Assets.file_paths(dir, M.Manifest.files_for(arch)))
        Vk8s.assets.fetch(have, dir, ver, files)

# The release this binary pins for the host's arch (M.Manifest.for_arch),
# fetched and verified on first use. An arch with no pinned set (amd64
# until its first release) needs a local build in VK8S_ASSETS.
def Vk8s.assets.pinned(p: M.Pinned, +uname: String, +home: String) -> IO(String):
  match p:
    case M.Pinned{+arch, +ver, files}:
      Vk8s.assets.pinned.go(String.is_empty(ver), arch, ver, files, uname, home)

def Vk8s.assets.pick(local: Bool, +env: String, +home: String) -> IO(String):
  match local:
    case True{}:
      IO.pure(String, env)
    case False{}:
      do IO<String>:
        +u : String <- Vk8s.uname()
        Vk8s.assets.pinned(M.Manifest.for_arch(u), u, home)

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

def Vk8s.cache_dir(+home: String) -> String:
  home ++ "/.vk8s/cache"

# The cache runs when its VM runs and a registry answers: a VM whose boot
# failed keeps running with no registry, and every pull then waits on the
# fallback to the upstream.
def Vk8s.cache_running(+dir: String) -> IO(Bool):
  Vk8s.sh_ok("printf 'status json\\n' | nc -U -w 2 " ++ Vk8s.q(dir ++ "/ctl.sock") ++ " 2>/dev/null | grep -q running"
    ++ " && curl -s -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:15002/v2/ | grep -q 200")

# A role's sets (docs/ref/footprint-decisions.md D1) that the assets dir
# of the release pinned for this host's arch lacks are fetched into it,
# once; a local VK8S_ASSETS dir must hold them already.
def Vk8s.sets_fetch(have: Bool, release: Bool, +arch: String, +assets: String, +sets: +List<String>) -> IO(Unit):
  match have release:
    case True{} _:
      IO.pure(Unit, Unit{})
    case False{} True{}:
      do IO<Unit>:
        Vk8s.say("Downloading vk8s guest asset sets (" ++ String.join(sets, ", ") ++ ") of " ++ M.Manifest.version_for(arch) ++ " into " ++ assets ++ ", once...")
        +base : String <- Vk8s.getenv("VK8S_ASSETS_URL", A.Assets.default_base())
        +r : Sh <- Vk8s.sh(A.Assets.fetch_into_sh(assets, base, M.Manifest.version_for(arch), A.Assets.set_files(sets, M.Manifest.sets_for(arch))))
        Vk8s.unless(Vk8s.sh_ok.of(r), Vk8s.die("could not fetch the guest asset sets: " ++ String.trim(Vk8s.raw.out(r))))
    case False{} False{}:
      IO.pure(Unit, Unit{})

def Vk8s.sets_ensure(+home: String, +assets: String, +sets: +List<String>) -> IO(Unit):
  do IO<Unit>:
    +arch : String <- Vk8s.arch()
    have : Bool <- Vk8s.have_all(A.Assets.set_paths(assets, sets))
    Vk8s.sets_fetch(have, String.eq(assets, A.Assets.dir(home, M.Manifest.version_for(arch))), arch, assets, sets)
    ok : Bool <- Vk8s.have_all(A.Assets.set_paths(assets, sets))
    Vk8s.unless(ok, Vk8s.die("the vk8s assets in " ++ assets ++ " lack a set of " ++ String.join(sets, ", ")
      ++ " (<set>.img; scripts/guest/build.sh makes them)"))

# Whether each of these files opens for reading, in order.
def Vk8s.have_each(ps: +List<String>) -> IO(+List<Bool>):
  match ps:
    case Nil{}:
      IO.pure(+List<Bool>, Nil{})
    case Con{+p, t}:
      do IO<+List<Bool>>:
        ok : Bool <- Vk8s.can_open(p, "r")
        +rest : +List<Bool> <- Vk8s.have_each(t)
        return ok <> rest

def Vk8s.sets_warn(+assets: String, +skip: +List<String>) -> IO(Unit):
  Vk8s.unless(List.is_empty(&2, String, skip), Vk8s.say("warning: the vk8s assets in " ++ assets ++ " have no "
    ++ String.join(skip, ", ") ++ " set (optional; <set>.img); going on without it, so images come from the registries"))

# Vk8s.sets_ensure, v2 (docs/ref/review-bend-vk8s-pr-48.md #3): fetches
# the sets the dir lacks and the release pins, then stops vk8s only when a
# required set is still absent; an absent optional set (images, cache;
# A.Assets.optional) is dropped with a warning. Returns the sets the VM
# attaches.
def Vk8s.sets_ensure.v2(+home: String, +assets: String, +sets: +List<String>) -> IO(+List<String>):
  do IO<+List<String>>:
    +arch : String <- Vk8s.arch()
    got0 : +List<Bool> <- Vk8s.have_each(A.Assets.set_paths(assets, sets))
    +miss : +List<String> = A.Assets.absent(sets, got0)
    nopin : Bool = List.is_empty(&2, A.AssetFile, A.Assets.set_files(miss, M.Manifest.sets_for(arch)))
    Vk8s.sets_fetch(nopin, String.eq(assets, A.Assets.dir(home, M.Manifest.version_for(arch))), arch, assets, miss)
    +got : +List<Bool> <- Vk8s.have_each(A.Assets.set_paths(assets, sets))
    +need : +List<String> = A.Assets.missing_required(sets, got)
    Vk8s.unless(List.is_empty(&2, String, need), Vk8s.die("the vk8s assets in " ++ assets ++ " lack a set of " ++ String.join(need, ", ")
      ++ " (<set>.img; scripts/guest/build.sh makes them)"))
    Vk8s.sets_warn(assets, A.Assets.missing_optional(sets, got))
    return A.Assets.present(sets, got)

def Vk8s.sets_ensure.when_per(per: Bool, +home: String, +assets: String, +sets: +List<String>) -> IO(+List<String>):
  match per:
    case True{}:
      Vk8s.sets_ensure.v2(home, assets, sets)
    case False{}:
      IO.pure(+List<String>, sets)

# A VM's bend-vmm flags with its role's asset sets: an assets dir with
# base.img is per-role, and the VM boots base.img, its data disk and one
# disk per set (images only when the image cache does not run, so the
# add-ons are pulled through the cache; footprint-decisions A3; an
# optional set the dir lacks is left out, Vk8s.sets_ensure.v2). Without
# base.img (a single assets.img) the flags stay as they are.
#
# With VK8S_LAYERS=1 (opt-in until the Mac measurements are in; docs/GOAL.md
# section 10), a node VM also gets the shared layer store, ~/.vk8s/layers,
# as a read-only meta share tagged layers (C.Cli.with_layers).
def Vk8s.layers_dir.go(on: Bool, +dir: String) -> IO(Unit):
  match on:
    case True{}:
      do IO<Unit>:
        ok : Bool <- Vk8s.run_ok("mkdir", ["-p", dir])
        Vk8s.unless(ok, Vk8s.die("could not make " ++ dir))
    case False{}:
      IO.pure(Unit, Unit{})

def Vk8s.role_flags(+assets: String, +data: String, +role: String, +flags: +List<String>) -> IO(+List<String>):
  do IO<+List<String>>:
    +per : Bool <- Vk8s.can_open(assets ++ "/base.img", "r")
    +home : String <- Vk8s.home()
    cached : Bool <- Vk8s.cache_running(Vk8s.cache_dir(home))
    +sets : +List<String> <- Vk8s.sets_ensure.when_per(per, home, assets, A.Assets.role_sets(role, cached))
    lay : String <- Vk8s.getenv("VK8S_LAYERS", "")
    +on : Bool = C.Cli.layers_on(lay, role)
    Vk8s.layers_dir.go(on, C.Cli.layers_dir(home ++ "/.vk8s"))
    return C.Cli.with_layers(on, C.Cli.layers_dir(home ++ "/.vk8s"), C.Cli.role_flags(per, flags, assets, data, sets))

def Vk8s.share_values.go(has: Bool, +dir: String, +nd: String) -> IO(Bool):
  match has:
    case True{}:
      Vk8s.share_copy(dir ++ "/vcluster.yaml", nd ++ "/vcluster.yaml.tmp", nd ++ "/share", "", "vcluster.yaml")
    case False{}:
      IO.pure(Bool, True{})

# The cluster's vcluster.yaml (create -f), when it has one, on a worker
# node's share: the node's PID 1 sets its sysctls from it
# (VL.Values.with_node).
def Vk8s.share_values(+dir: String, +nd: String) -> IO(Bool):
  do IO<Bool>:
    has : Bool <- Vk8s.can_open(dir ++ "/vcluster.yaml", "r")
    Vk8s.share_values.go(has, dir, nd)
# Whether the image cache can boot from this assets dir: a per-role dir
# (with base.img) must hold cache.img, the optional cache set; a single
# assets.img holds the registry.
def Vk8s.cache_have(+assets: String) -> IO(Bool):
  do IO<Bool>:
    per : Bool <- Vk8s.can_open(assets ++ "/base.img", "r")
    cset : Bool <- Vk8s.can_open(assets ++ "/cache.img", "r")
    return Bool.not(per) || cset

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
        prep : Bool <- Vk8s.sh_ok("mkdir -p " ++ Vk8s.q(ndir ++ "/share") ++ " && rm -f " ++ Vk8s.q(ndir ++ "/data.img") ++ " " ++ Vk8s.q(ndir ++ "/share/joined"))
        disc : Bool <- Vk8s.share_copy_if(prep, dir ++ "/discovery.conf", ndir ++ "/discovery.conf.tmp", ndir ++ "/share", "", "discovery.conf")
        vy : Bool <- Vk8s.and_then(disc, Vk8s.share_values(dir, ndir))
        made : Bool <- Vk8s.clone_if(vy, assets ++ "/data.img", ndir ++ "/data.img")
        Vk8s.unless(made, Vk8s.die("could not set up " ++ ndir))
        +arch : String <- Vk8s.arch()
        +sc : String <- Vk8s.getenv("VK8S_WAIT_SCALE", "")
        +flags : +List<String> <- Vk8s.role_flags(assets, ndir ++ "/data.img", "worker", C.Cli.arch_flags(arch, C.Cli.scale_flags(sc, C.Cli.worker_flags(dir, ndir, assets, node, i, token, 2, 2048))))
        started : Bool <- Vk8s.sh_ok("cd " ++ Vk8s.q(ndir) ++ " && { nohup " ++ Vk8s.q(self) ++ " vmm"
          ++ P.Plan.sh_words(flags) ++ " </dev/null >vmm.log 2>&1 & } && echo $! > vmm.pid")
        Vk8s.unless(started, Vk8s.die("could not start " ++ node))
        Vk8s.workers(rest, self, dir, assets, name, token)

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

def Vk8s.cache_boot(+dir: String, +assets: String) -> IO(Bool):
  do IO<Bool>:
    +self : String <- Vk8s.self()
    +arch : String <- Vk8s.arch()
    +prep : Bool <- Vk8s.sh_ok("mkdir -p " ++ Vk8s.q(dir ++ "/share") ++ " && chmod 700 " ++ Vk8s.q(dir))
    have : Bool <- Vk8s.can_open(dir ++ "/data.img", "r")
    img : Bool <- Vk8s.or_retry(have, Vk8s.clone_if(prep, assets ++ "/data.img", dir ++ "/data.img"))
    +sc : String <- Vk8s.getenv("VK8S_WAIT_SCALE", "")
    +flags : +List<String> <- Vk8s.role_flags(assets, dir ++ "/data.img", "cache", C.Cli.arch_flags(arch, C.Cli.scale_flags(sc, C.Cli.cache_flags(dir, assets))))
    cset : Bool <- Vk8s.cache_have(assets)
    started : Bool <- Vk8s.and_then(prep && img && cset, Vk8s.sh_ok("cd " ++ Vk8s.q(dir) ++ " && rm -f share/ready && { nohup " ++ Vk8s.q(self) ++ " vmm"
      ++ P.Plan.sh_words(flags) ++ " </dev/null >vmm.log 2>&1 & } && echo $! > vmm.pid"))
    Vk8s.and_then(started, Vk8s.wait_vm(120n, dir, "/share/ready"))

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

def Vk8s.cache_start.go(running: Bool, +dir: String, +assets: String) -> IO(Bool):
  match running:
    case True{}:
      IO.pure(Bool, True{})
    case False{}:
      do IO<Bool>:
        Vk8s.say("Starting the image cache (pull-through registries on 127.0.0.1:15001-15004)...")
        _ : Bool <- Vk8s.sh_ok("printf 'status json\\n' | nc -U -w 2 " ++ Vk8s.q(dir ++ "/ctl.sock") ++ " 2>/dev/null | grep -q running && { "
          ++ Vk8s.stop_vms(dir) ++ "; }")
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

# Sleep when idle (docs/GOAL.md section 10; src/cli/idle.bend decides,
# host/idle_proxy.bend relays). With a limit above 0, `vk8s idle-proxy`
# holds the cluster's port on 127.0.0.1 and relays to the API (a VM
# forwards its 6443 to the private ID.Idle.inner_port instead); it pauses
# the cluster after the limit with no connection, and resumes it on the
# next one. Its pid is idle.pid and its log idle.log in the cluster dir.

def Vk8s.file.close(p: File & Result<&1, &1, U32 & String, Unit>) -> IO(Bool):
  match p:
    case (f, Done{u}):
      do IO<Bool>:
        File.close(f)
        return True{}
    case (f, Fail{e}):
      do IO<Bool>:
        File.close(f)
        return False{}

def Vk8s.file.go(r: Result<&1, &1, U32 & String, File>, +text: String) -> IO(Bool):
  match r:
    case Fail{e}:
      IO.pure(Bool, False{})
    case Done{f}:
      do IO<Bool>:
        p : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, text)
        Vk8s.file.close(p)

# Write ("w") or append ("a") text through Base's File effects.
def Vk8s.file_put(+path: String, +mode: String, +text: String) -> IO(Bool):
  do IO<Bool>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, mode)
    Vk8s.file.go(r, text)

def Vk8s.idle.setting(m: Maybe<&2, U32>) -> IO(U32):
  match m:
    case Some{+v}:
      IO.pure(U32, v)
    case None{}:
      do IO<U32>:
        Vk8s.die("VK8S_IDLE_SLEEP and --idle-sleep take minutes or a duration such as 90s or 1h30m (0: never sleep)")
        return 0

def Vk8s.idle.limit.pick(none: Bool, +rec: String, +dir: String) -> IO(U32):
  match none:
    case False{}:
      IO.pure(U32, ID.Idle.secs(rec, "", ""))
    case True{}:
      do IO<U32>:
        +v : String <- Vk8s.getenv(ID.Idle.env_name(), "")
        +secs : U32 <- Vk8s.idle.setting(ID.Idle.setting("", v))
        _ : Bool <- Vk8s.file_put(dir ++ "/cluster.env", "a", ID.Idle.env_line(secs))
        return secs

# The cluster's idle limit in seconds (0: never): IDLE_SLEEP in its
# cluster.env, else the setting (--idle-sleep, which main turns into
# VK8S_IDLE_SLEEP; else 15 minutes), which is then recorded there.
def Vk8s.idle.limit(+dir: String) -> IO(U32):
  do IO<U32>:
    +env : String <- Vk8s.slurp(dir ++ "/cluster.env")
    +rec : String = R.Ctr.setting(env, "IDLE_SLEEP")
    Vk8s.idle.limit.pick(String.is_empty(rec), rec, dir)

def Vk8s.idle.pid(r: Result<&1, &1, U32 & String, U32>) -> U32:
  match r:
    case Fail{e}:
      0
    case Done{pid}:
      pid

def Vk8s.idle.kill(none: Bool, +pid: U32) -> IO(Unit):
  match none:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        _ : U32 <- I.Proc.signal(pid, 15)
        return Unit{}

# Stop the cluster's idle proxy, if one runs.
def Vk8s.idle.stop(+dir: String) -> IO(Unit):
  do IO<Unit>:
    +t : String <- Vk8s.slurp(dir ++ "/idle.pid")
    +pid : U32 = Maybe.default(&2, U32, U32.read(String.trim(t)), 0)
    Vk8s.idle.kill(U32.is_eq(pid, 0), pid)
    _ : Bool <- Vk8s.run_ok("rm", ["-f", dir ++ "/idle.pid"])
    return Unit{}

def Vk8s.idle.up.go(r: Result<&1, &1, U32 & String, Socket>, again: IO(Bool)) -> IO(Bool):
  match r:
    case Done{s}:
      do IO<Bool>:
        Socket.close(s)
        return True{}
    case Fail{e}:
      again

# Whether something listens on 127.0.0.1:port (n tries, 250 ms apart).
def Vk8s.idle.up(n: Nat, +port: U32) -> IO(Bool):
  match n:
    case 0n:
      IO.pure(Bool, False{})
    case 1n+p:
      do IO<Bool>:
        r : Result<&1, &1, U32 & String, Socket> <- TCP.connect("127.0.0.1", port)
        Vk8s.idle.up.go(r, IO.bind(Unit, Bool, IO.sleep(250), u => Vk8s.idle.up(p, port)))

def Vk8s.idle.start.go(off: Bool, +name: String, +dir: String, +port: U32, +host: String, +up: U32, +limit: U32) -> IO(Unit):
  match off:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        +self : String <- Vk8s.self()
        r : Result<&1, &1, U32 & String, U32> <- I.Proc.start(self, Vk8s.argv(["idle-proxy", name, U32.show(port), host, U32.show(up),
          U32.show(limit)]), dir ++ "/idle.log")
        +pid : U32 = Vk8s.idle.pid(r)
        Vk8s.when(U32.is_eq(pid, 0), Vk8s.die("could not start the API forward of " ++ name ++ "; see " ++ dir ++ "/idle.log"))
        _ : Bool <- Vk8s.file_put(dir ++ "/idle.pid", "w", U32.show(pid) ++ "\n")
        ok : Bool <- Vk8s.idle.up(120n, port)
        Vk8s.unless(ok, Vk8s.die("the API forward of " ++ name ++ " did not listen on 127.0.0.1:" ++ U32.show(port) ++ "; see "
          ++ dir ++ "/idle.log"))

# Start the cluster's idle proxy on 127.0.0.1:port, relaying to host:up
# (none when the limit is 0); one that runs stops first.
def Vk8s.idle.start(+name: String, +dir: String, +port: U32, +host: String, +up: U32, +limit: U32) -> IO(Unit):
  do IO<Unit>:
    Vk8s.idle.stop(dir)
    Vk8s.idle.start.go(U32.is_eq(limit, 0), name, dir, port, host, up, limit)

# A VM's bend-vmm flags: with sleep on, the API goes to the private port.
def Vk8s.idle.flags(off: Bool, flags: +List<String>, classic: Bool, +port: U32) -> +List<String>:
  match off:
    case True{}:
      flags
    case False{}:
      ID.Idle.with_forward(flags, ID.Idle.forwards(classic, port, ID.Idle.inner_port(port)))

def Vk8s.boot_ws(+name: String, +guest: String, +dir: String, +assets: String, +port: U32, +cpus: U32, +mem: U32, +etcd: Bool,
  +ws: List<&2, U32>, +extra: String) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    Vk8s.cache_ensure(home, assets)
    +self : String <- Vk8s.self()
    +arch : String <- Vk8s.arch()
    +sc : String <- Vk8s.getenv("VK8S_WAIT_SCALE", "")
    +limit : U32 <- Vk8s.idle.limit(dir)
    +classic : Bool = String.contains(extra, " VK8S_MODE=classic")
    +flags0 : +List<String> <- Vk8s.role_flags(assets, dir ++ "/data.img", C.Cli.cp_role(extra), C.Cli.arch_flags(arch, C.Cli.scale_flags(sc, C.Cli.vmm_flags_x(dir, assets, guest, port, cpus, mem, etcd, extra))))
    +flags : +List<String> = Vk8s.idle.flags(U32.is_eq(limit, 0), flags0, classic, port)
    started : Bool <- Vk8s.sh_ok("cd " ++ Vk8s.q(dir) ++ " && rm -f share/kubeconfig.yaml share/join-token && { nohup " ++ Vk8s.q(self) ++ " vmm"
      ++ P.Plan.sh_words(flags) ++ " </dev/null >vmm.log 2>&1 & } && echo $! > vmm.pid")
    Vk8s.unless(started, Vk8s.die("could not start the VM"))
    Vk8s.idle.start(name, dir, port, "127.0.0.1", ID.Idle.inner_port(port), limit)
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

def Vk8s.epoch() -> IO(U32):
  do IO<U32>:
    out : String <- Vk8s.sh_out("date +%s")
    return C.Cli.num(U32.read(String.trim(out)), 0)

# --- Host ports: vcluster's RandomPort (pkg/util/clihelper/clihelper.go
# RandomPort, checkPort), through Bend's TCP and file effects instead of
# a shell with grep and nc (docs/ref/review-direct-commits-main.md F5-F7).

# A port is in use on 127.0.0.1, where bend-vmm binds its forwards:
# something accepts a connection there, or it cannot be bound (which also
# sees a port that is bound but not listening; vcluster's checkPort
# binds). An IPv6-only listener does not block bend-vmm's IPv4 bind.
def Vk8s.port_busy.bound(r: Result<&1, &1, U32 & String, Listener>) -> IO(Bool):
  match r:
    case Fail{e}:
      IO.pure(Bool, True{})
    case Done{l}:
      do IO<Bool>:
        Listener.close(l)
        return False{}

def Vk8s.port_busy.connected(r: Result<&1, &1, U32 & String, Socket>, +p: U32) -> IO(Bool):
  match r:
    case Done{sk}:
      do IO<Bool>:
        Socket.close(sk)
        return True{}
    case Fail{e}:
      do IO<Bool>:
        l : Result<&1, &1, U32 & String, Listener> <- TCP.listen("127.0.0.1", p)
        Vk8s.port_busy.bound(l)

def Vk8s.port_busy(+p: U32) -> IO(Bool):
  do IO<Bool>:
    r : Result<&1, &1, U32 & String, Socket> <- TCP.connect("127.0.0.1", p)
    Vk8s.port_busy.connected(r, p)

def Vk8s.any_busy(ps: List<&2, U32>) -> IO(Bool):
  match ps:
    case Nil{}:
      IO.pure(Bool, False{})
    case Con{+p, t}:
      do IO<Bool>:
        b : Bool <- Vk8s.port_busy(p)
        Vk8s.or_retry(b, Vk8s.any_busy(t))

# Another cluster records port p (a stopped cluster keeps its port): grep
# runs without a shell, and self, this cluster's own port file ("" before
# it has one), does not count (C.Cli.recorded_elsewhere).
def Vk8s.port_recorded(+home: String, +self: String, +p: U32) -> IO(Bool):
  do IO<Bool>:
    out : String <- Vk8s.run_out("grep", ["-rsHx", "--include=port", "-e", U32.show(p), home ++ "/.vk8s/clusters"])
    return C.Cli.recorded_elsewhere(out, self)

# A port is taken when another cluster records it, or when any host port
# a cluster on it forwards (C.Cli.host_ports: the API port and the
# derived konnectivity, kubelet and join ports) is in use (review F6).
def Vk8s.port_taken.v2(+home: String, +self: String, +p: U32) -> IO(Bool):
  do IO<Bool>:
    rec : Bool <- Vk8s.port_recorded(home, self, p)
    Vk8s.or_retry(rec, Vk8s.any_busy(C.Cli.host_ports(p)))

# The seed of try i: the OS's random number, or, when it gives none, the
# clock spread by i (C.Cli.fallback_seed), said once (review F7).
def Vk8s.seed.v2(r: Result<&1, &1, U32 & String, U32>, +i: U32) -> IO(U32):
  match r:
    case Done{x}:
      IO.pure(U32, x)
    case Fail{(code, msg)}:
      do IO<U32>:
        Vk8s.when(U32.is_eq(i, 0), IO.print_err("vk8s: no random number from the OS (" ++ msg ++ "); picking ports from the clock"))
        +now : U32 <- Vk8s.epoch()
        return C.Cli.fallback_seed(now, i)

def Vk8s.random_pick(+i: U32) -> IO(U32):
  do IO<U32>:
    r : Result<&1, &1, U32 & String, U32> <- IO.random_u32()
    +seed : U32 <- Vk8s.seed.v2(r, i)
    return C.Cli.port_from(seed)

def Vk8s.random_port.go(taken: Bool, +p: U32, again: IO(U32)) -> IO(U32):
  match taken:
    case False{}:
      IO.pure(U32, p)
    case True{}:
      again

# vcluster's RandomPort (clihelper.go:172-182): up to 10 random ports in
# 10000..12999, the first free one, else one more random port, unchecked.
# Random, not clock-seeded: two creates in the same second must not share
# a port.
def Vk8s.random_port.v2(n: Nat, +i: U32, +home: String, +self: String) -> IO(U32):
  match n:
    case 0n:
      Vk8s.random_pick(i)
    case 1n+k:
      do IO<U32>:
        +p : U32 <- Vk8s.random_pick(i)
        t : Bool <- Vk8s.port_taken.v2(home, self, p)
        Vk8s.random_port.go(t, p, Vk8s.random_port.v2(k, U32.add(i, 1), home, self))

def Vk8s.free_port.v2(auto: Bool, +home: String, +p: U32) -> IO(U32):
  match auto:
    case True{}:
      Vk8s.random_port.v2(10n, 0, home, "")
    case False{}:
      IO.pure(U32, p)

# The port file of the cluster in dir, written with Bend's file effects.
def Vk8s.record_port(+dir: String, +p: U32) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, File> <- File.open(dir ++ "/port", "w")
    ok : Bool <- I.Init.write.go(r, U32.show(p) ++ "\n")
    Vk8s.unless(ok, Vk8s.die("could not write " ++ dir ++ "/port"))

def Vk8s.claim.next(dup: Bool, +p: U32, again: IO(U32)) -> IO(U32):
  match dup:
    case True{}:
      again
    case False{}:
      IO.pure(U32, p)

# A free port, recorded in dir/port at once (dir exists), then checked
# again: when another cluster records the same port, because two creates
# picked it together, pick again (up to n more times). Each sees the
# other's file, and the next pick skips it.
def Vk8s.claim(n: Nat, +home: String, +dir: String) -> IO(U32):
  match n:
    case 0n:
      do IO<U32>:
        +p : U32 <- Vk8s.random_port.v2(10n, 0, home, dir ++ "/port")
        Vk8s.record_port(dir, p)
        return p
    case 1n+k:
      do IO<U32>:
        +p : U32 <- Vk8s.random_port.v2(10n, 0, home, dir ++ "/port")
        Vk8s.record_port(dir, p)
        dup : Bool <- Vk8s.port_recorded(home, dir ++ "/port", p)
        Vk8s.claim.next(dup, p, Vk8s.claim(k, home, dir))

# The cluster's port, recorded in dir/port: the one the user asked for
# (--port, as before: not probed), else a claimed random one.
def Vk8s.claim_port(auto: Bool, +home: String, +dir: String, +port0: U32) -> IO(U32):
  match auto:
    case True{}:
      Vk8s.claim(3n, home, dir)
    case False{}:
      do IO<U32>:
        Vk8s.record_port(dir, port0)
        return port0

# Reserve the cluster's name and port before any slow step (review F5):
# one mkdir makes the cluster's directory and fails when another create
# made it first, and the port goes into it at once (Vk8s.claim_port).
# Before that, the checks that change nothing: the name is free, the
# paths fit, the assets are there.
def Vk8s.reserve(+name: String, +home: String, +assets: String, +port0: U32) -> IO(U32):
  do IO<U32>:
    +dir : String = C.Cli.dir(home, name)
    exists : Bool <- Vk8s.run_ok("test", ["-e", dir])
    Vk8s.when(exists, Vk8s.die("vCluster " ++ name ++ " already exists, use --upgrade to upgrade it"))
    Vk8s.unless(C.Cli.paths_fit(dir), Vk8s.die("the cluster directory " ++ dir ++ " is too long for its sockets (macOS allows 103 bytes); use a shorter name"))
    have : Bool <- Vk8s.run_ok("test", ["-f", assets ++ "/vk8s.cpio", "-a", "-f", assets ++ "/data.img"])
    Vk8s.unless(have, Vk8s.die("vk8s assets not found in " ++ assets ++ " (set VK8S_ASSETS)"))
    parent : Bool <- Vk8s.run_ok("mkdir", ["-p", home ++ "/.vk8s/clusters"])
    made : Bool <- Vk8s.run_ok("mkdir", ["-m", "700", dir])
    Vk8s.unless(made, Vk8s.die("vCluster " ++ name ++ " already exists, use --upgrade to upgrade it"))
    Vk8s.claim_port(U32.is_eq(port0, 0), home, dir, port0)

def Vk8s.reserve.if(reserved: Bool, +name: String, +home: String, +assets: String, +port0: U32) -> IO(U32):
  match reserved:
    case True{}:
      IO.pure(U32, port0)
    case False{}:
      Vk8s.reserve(name, home, assets, port0)

# A reserved cluster directory goes again when create stops before it
# holds anything but its port, so the name stays free.
def Vk8s.unreserve_die(+dir: String, +msg: String) -> IO(Unit):
  do IO<Unit>:
    gone : Bool <- Vk8s.run_ok("rm", ["-rf", dir])
    Vk8s.die(msg)

# A new bootstrap token valid for one hour, made through the API with the
# host-owned kubeconfig (vk8s node add; needs kubectl, as node delete does).
def Vk8s.fresh_token(+dir: String) -> IO(String):
  do IO<String>:
    ids : String <- Vk8s.sh_out("LC_ALL=C tr -dc a-z0-9 </dev/urandom | head -c 22")
    +now : U32 <- Vk8s.epoch()
    +raw : String = String.trim(ids)
    +exp : String = C.Cli.rfc3339_in_one_hour(now)
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
    ++ "\nKUBERNETES=v1.36.6\n" ++ LW.LanWire.env_line(LW.LanWire.current())

def Vk8s.created_msg(+name: String, +dir: String) -> IO(Unit):
  do IO<Unit>:
    Vk8s.say("- Use 'vk8s connect " ++ name ++ "' to access the virtual cluster")
    Vk8s.say("- Use `vk8s connect " ++ name ++ " -- kubectl get ns` to run a command directly within the vcluster")

# Stop before any change when a host tool vk8s runs is missing (nc, curl,
# kubectl, tar; /dev/kvm for the VM backend on Linux), naming each. Bend
# file effects do the lookup; no shell runs.
def Vk8s.preflight() -> IO(Unit):
  do IO<Unit>:
    +path : String <- Vk8s.getenv("PATH", "/usr/bin:/bin")
    +tools : List<&2, String> <- Vk8s.missing(path, C.Cli.preflight_tools())
    +os : String <- Vk8s.slurp("/proc/sys/kernel/ostype")
    +kvm : List<&2, String> <- Vk8s.kvm_missing(C.Cli.kvm_needed(True{}, os))
    +msg : String = C.Cli.preflight(List.append(&2, String, tools, kvm))
    Vk8s.unless(String.is_empty(msg), Vk8s.die(String.trim(msg)))

# create: the name and the port are reserved first (Vk8s.reserve), unless
# the caller reserved them (classic mode, before its host Service).
def Vk8s.create_x.v2(reserved: Bool, +name: String, +port0: U32, +cpus: U32, +mem: U32, +etcd: Bool, +nodes: U32, +extra: String, +hostkc: String, +values: String) -> IO(Unit):
  do IO<Unit>:
    Vk8s.preflight()
    +home : String <- Vk8s.home()
    +assets : String <- Vk8s.assets(home)
    +dir : String = C.Cli.dir(home, name)
    +port : U32 <- Vk8s.reserve.if(reserved, name, home, assets, port0)
    Vk8s.say("Creating vCluster " ++ name ++ " (API on 127.0.0.1:" ++ U32.show(port) ++ ")...")
    prep : Bool <- Vk8s.sh_ok("mkdir -p " ++ Vk8s.q(dir ++ "/share") ++ " && chmod 700 " ++ Vk8s.q(dir))
    img : Bool <- Vk8s.clone_if(prep, assets ++ "/data.img", dir ++ "/data.img")
    made : Bool <- Vk8s.and_then(img, Vk8s.sh_ok("printf %s " ++ Vk8s.q(Vk8s.env_file(name, name, port, cpus, mem, etcd, nodes)) ++ " > " ++ Vk8s.q(dir ++ "/cluster.env")
      ++ " && echo CREATED=$(date +%s) >> " ++ Vk8s.q(dir ++ "/cluster.env")))
    Vk8s.unless(made, Vk8s.die("could not set up " ++ dir))
    hk : Bool <- Vk8s.sh_ok("[ -z " ++ Vk8s.q(hostkc) ++ " ] || { umask 077; printf %s " ++ Vk8s.q(hostkc) ++ " > " ++ Vk8s.q(dir ++ "/share/host-kubeconfig") ++ "; }")
    vy : Bool <- Vk8s.sh_ok("[ -z " ++ Vk8s.q(values) ++ " ] || { printf %s " ++ Vk8s.q(values) ++ " > " ++ Vk8s.q(dir ++ "/vcluster.yaml") ++ " && cp "
      ++ Vk8s.q(dir ++ "/vcluster.yaml") ++ " " ++ Vk8s.q(dir ++ "/share/vcluster.yaml") ++ "; }")
    Vk8s.unless(vy, Vk8s.die("could not write the vcluster.yaml of " ++ name))
    Vk8s.unless(hk, Vk8s.die("could not write the host kubeconfig for " ++ name))
    Vk8s.boot_ws(name, name, dir, assets, port, cpus, mem, etcd, C.Cli.workers_upto(nodes), extra)
    Vk8s.say("Successfully created virtual cluster " ++ name ++ ". ")
    Vk8s.created_msg(name, dir)

def Vk8s.create_x(+name: String, +port0: U32, +cpus: U32, +mem: U32, +etcd: Bool, +nodes: U32, +extra: String, +hostkc: String, +values: String) -> IO(Unit):
  Vk8s.create_x.v2(False{}, name, port0, cpus, mem, etcd, nodes, extra, hostkc, values)

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
    # a namespace an earlier delete left terminating is waited out (2 min)
    _ : Bool <- Vk8s.sh_ok("for i in $(seq 60); do [ \"$(kubectl --kubeconfig " ++ Vk8s.q(kc) ++ " get namespace " ++ Vk8s.q(ns)
      ++ " -o jsonpath='{.status.phase}' 2>/dev/null)\" = Terminating ] || break; sleep 2; done")
    _ : Bool <- Vk8s.sh_ok("kubectl --kubeconfig " ++ Vk8s.q(kc) ++ " get namespace " ++ Vk8s.q(ns) ++ " >/dev/null 2>&1 || { kubectl --kubeconfig " ++ Vk8s.q(kc)
      ++ " create namespace " ++ Vk8s.q(ns) ++ " >/dev/null && kubectl --kubeconfig " ++ Vk8s.q(kc) ++ " annotate namespace " ++ Vk8s.q(ns) ++ " vcluster.loft.sh/created=true >/dev/null; }")
    ip : String <- Vk8s.sh_out(k ++ "create service clusterip vk8s-cidr-probe --tcp=80 -o jsonpath='{.spec.clusterIP}' 2>/dev/null; " ++ k ++ "delete service vk8s-cidr-probe --ignore-not-found >/dev/null 2>&1")
    Vk8s.host_cidr.go(CI.Cidr.parse_ip(String.trim(ip)), k)

# The vcluster's Service in the host namespace (Cli.host_service): its
# cluster IP joins the API server's SANs, and the syncer mirrors it into
# the virtual default/kubernetes (specialservices).
def Vk8s.host_service(+kc: String, +name: String, +ns: String, +port: U32, +dir: String) -> IO(String):
  do IO<String>:
    +k : String = "kubectl --kubeconfig " ++ Vk8s.q(kc) ++ " "
    ip : String <- Vk8s.sh_out("printf %s " ++ Vk8s.q(C.Cli.host_service(name, ns, port)) ++ " | " ++ k ++ "apply -f - >/dev/null 2>&1 && printf %s "
      ++ Vk8s.q(C.Cli.host_endpoints(name, ns, port)) ++ " | " ++ k ++ "apply -f - >/dev/null 2>&1 && " ++ k ++ "-n " ++ Vk8s.q(ns) ++ " get service " ++ Vk8s.q(name)
      ++ " -o jsonpath='{.spec.clusterIP}' 2>/dev/null")
    +san : String = String.trim(ip)
    Vk8s.when(String.is_empty(san), Vk8s.unreserve_die(dir, "could not create the vCluster service in the host namespace " ++ ns))
    kip : String <- Vk8s.sh_out("printf %s " ++ Vk8s.q(C.Cli.konn_service(name, ns)) ++ " | " ++ k ++ "apply -f - >/dev/null 2>&1 && printf %s "
      ++ Vk8s.q(C.Cli.konn_endpoints(name, ns, port)) ++ " | " ++ k ++ "apply -f - >/dev/null 2>&1 && " ++ k ++ "-n " ++ Vk8s.q(ns) ++ " get service " ++ Vk8s.q(C.Cli.konn_name(name))
      ++ " -o jsonpath='{.spec.clusterIP}' 2>/dev/null")
    +ksan : String = String.trim(kip)
    Vk8s.when(String.is_empty(ksan), Vk8s.unreserve_die(dir, "could not create the konnectivity service in the host namespace " ++ ns))
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
        Vk8s.preflight()
        +home : String <- Vk8s.home()
        +assets : String <- Vk8s.assets(home)
        +port : U32 <- Vk8s.reserve(name, home, assets, port0)
        +san : String <- Vk8s.host_service(kc, name, ns, port, C.Cli.dir(home, name))
        Vk8s.create_x.v2(True{}, name, port, cpus, mem, etcd, nodes, C.Cli.classic_cmdline_full(ns, cidr, san), text, values)
        Vk8s.host_record(name, kc, ns)

# Deleting a classic cluster removes what it made on the host, as vcluster
# delete does (helm uninstall, then the namespace if vcluster created it and
# no other vcluster is left in it): its Services, the objects the syncer
# made (label vcluster.loft.sh/managed-by), its Lease. After the VMs stop,
# so the syncer cannot make them again.
def Vk8s.host_cleanup(+name: String, +dir: String) -> String:
  "if [ -f " ++ Vk8s.q(dir ++ "/host-namespace") ++ " ]; then hk=$(cat " ++ Vk8s.q(dir ++ "/host-kubeconfig-path") ++ "); ns=$(cat " ++ Vk8s.q(dir ++ "/host-namespace") ++ "); "
    ++ "k=\"kubectl --kubeconfig $hk --request-timeout=20s\"; n=" ++ Vk8s.q(name) ++ "; "
    ++ "$k -n \"$ns\" delete service \"$n\" \"$n-konnectivity\" \"$n-kubelet\" --ignore-not-found --wait=false >/dev/null 2>&1; "
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

def Vk8s.delete(+name: String, ctx: Bool) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +dir : String = C.Cli.dir(home, name)
    exists : Bool <- Vk8s.sh_ok("test -d " ++ Vk8s.q(dir))
    Vk8s.unless(exists, Vk8s.die("vCluster " ++ name ++ " not found"))
    Vk8s.idle.stop(dir)
    _ : Bool <- Vk8s.sh_ok(Vk8s.stop_vms(dir))
    _ : Bool <- Vk8s.sh_ok(Vk8s.host_cleanup(name, dir))
    Vk8s.when(ctx, Vk8s.forget(name, home))
    gone : Bool <- Vk8s.sh_ok("rm -rf " ++ Vk8s.q(dir) ++ "; ! test -e " ++ Vk8s.q(dir))
    Vk8s.unless(gone, Vk8s.die("could not remove " ++ dir ++ " (is a VM of " ++ name ++ " still running? see its vmm.pid)"))
    Vk8s.say("Successfully deleted virtual cluster " ++ name)

def Vk8s.entry.of(fs: List<&2, String>) -> List<&2, C.Entry>:
  match fs:
    case Con{n, Con{st, Con{+c, Con{+z, Con{+con, Nil{}}}}}}:
      [C.Entry{n, st, C.Cli.num(U32.read(c), 0), C.Cli.rfc3339_in(C.Cli.num(U32.read(c), 0), z), String.eq(con, "1")}]
    case _:
      Nil{}

def Vk8s.entries.of(ls: List<&2, String>) -> List<&2, C.Entry>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{l, t}:
      List.append(&2, C.Entry, Vk8s.entry.of(String.split(l, '\t')), Vk8s.entries.of(t))

# The VM state of the cluster in "$d" (bend-vmm `status json`), or stopped.
# A native cluster's state is its unit's (systemctl is-active).
def Vk8s.state_sh() -> String:
  "s=; if grep -qsx BACKEND=native \"$d/cluster.env\"; then if systemctl is-active --quiet \"vk8s-${d##*/}.service\"; then s=running; fi; "
    ++ "else s=$(printf 'status json\\n' | nc -U -w 2 \"$d/ctl.sock\" 2>/dev/null | sed -n 's/.*\"state\":\"\\([a-z]*\\)\".*/\\1/p'); fi; s=${s:-stopped}; "

# Every cluster: name, state, created (Unix s and RFC 3339), connected.
def Vk8s.entries(+home: String) -> IO(List<&2, C.Entry>):
  do IO<List<&2, C.Entry>>:
    out : String <- Vk8s.sh_out("cur=$(kubectl config current-context 2>/dev/null); z=$(date +%z); for d in " ++ Vk8s.q(home ++ "/.vk8s/clusters")
      ++ "/*/; do [ -d \"$d\" ] || continue; d=${d%/}; n=$(basename \"$d\"); " ++ Vk8s.state_sh()
      ++ "c=$(sed -n 's/^CREATED=//p' \"$d/cluster.env\" 2>/dev/null); " ++ C.Cli.created_sh() ++ "at=$z; "
      ++ "con=0; [ \"$cur\" = \"vk8s_$n\" ] && con=1; printf '%s\\t%s\\t%s\\t%s\\t%s\\n' \"$n\" \"$s\" \"$c\" \"$at\" \"$con\"; done")
    return Vk8s.entries.of(String.lines(out))

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

# The bend-vmm LAN wire guard (src/cli/lan_wire.bend): a command that
# starts a VM beside the cluster's running ones stops when the cluster
# records another LAN wire version than this binary's.
def Vk8s.lan_wire_guard(+name: String, +dir: String) -> IO(Unit):
  do IO<Unit>:
    +env : String <- Vk8s.slurp(dir ++ "/cluster.env")
    +msg : String = LW.LanWire.check(False{}, name, env)
    Vk8s.unless(String.is_empty(msg), Vk8s.die(msg))

# A setting of the cluster's cluster.env.
def Vk8s.setting_sh(+dir: String, +key: String) -> String:
  "$(sed -n 's/^" ++ key ++ "=//p' " ++ Vk8s.q(dir ++ "/cluster.env") ++ " 2>/dev/null)"

# vcluster describe (docker driver): Name, Container ID, Status, Created,
# Image, Ports; vk8s shows the VMM's pid as the container and adds nodes
# and the backing store.
def Vk8s.describe.text(+name: String, +dir: String, +created: String) -> String:
  "d=" ++ Vk8s.q(dir) ++ "; " ++ Vk8s.state_sh()
    ++ "printf '%-15s%s\\n' 'Name:' " ++ Vk8s.q(name) ++ " 'Container ID:' \"vmm-$(cat \"$d/vmm.pid\" 2>/dev/null)\" 'Status:' \"$s\" "
    ++ "'Created:' " ++ Vk8s.q(created) ++ " 'Image:' \"vk8s/guest:" ++ Vk8s.setting_sh(dir, "KUBERNETES") ++ "\" "
    ++ "'Ports:' \"127.0.0.1:$(cat \"$d/port\")->6443/tcp\" 'Nodes:' \"$((1 + " ++ Vk8s.setting_sh(dir, "NODES") ++ "0 / 10))\" "
    ++ "'Backing store:' \"" ++ Vk8s.setting_sh(dir, "STORE") ++ "\""

def Vk8s.describe.json(+name: String, +dir: String, +created: String) -> String:
  "d=" ++ Vk8s.q(dir) ++ "; " ++ Vk8s.state_sh()
    ++ "printf '{\\n  \"name\": \"%s\",\\n  \"containerId\": \"vmm-%s\",\\n  \"status\": \"%s\",\\n  \"created\": \"%s\",\\n  \"image\": \"vk8s/guest:%s\",\\n  \"ports\": \"127.0.0.1:%s->6443/tcp\"\\n}\\n' "
    ++ Vk8s.q(name) ++ " \"$(cat \"$d/vmm.pid\" 2>/dev/null)\" \"$s\" " ++ Vk8s.q(created) ++ " \"" ++ Vk8s.setting_sh(dir, "KUBERNETES") ++ "\" \"$(cat \"$d/port\")\""

def Vk8s.describe.pick(co: Bool, json: Bool, +name: String, +dir: String, +secs: U32, +zone: String) -> String:
  match co json:
    case True{} _:
      "cat " ++ Vk8s.q(dir ++ "/vcluster.yaml") ++ " 2>/dev/null || { echo 'failed to load vcluster config (no vcluster.yaml given at create)' >&2; exit 1; }"
    case False{} True{}:
      Vk8s.describe.json(name, dir, C.Cli.rfc3339_in(secs, "+0000"))
    case False{} False{}:
      Vk8s.describe.text(name, dir, C.Cli.rfc1123z(secs, zone))

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
    # the creation time and the local zone; Bend renders the date
    cz : String <- Vk8s.sh_out("d=" ++ Vk8s.q(dir) ++ "; c=" ++ Vk8s.setting_sh(dir, "CREATED") ++ "; " ++ C.Cli.created_sh() ++ "echo \"$c\"; date +%z")
    +ls : List<&2, String> = String.lines(cz)
    +secs : U32 = C.Cli.num(U32.read(String.trim(Vk8s.line(ls, 0n))), 0)
    +zone : String = String.trim(Vk8s.line(ls, 1n))
    r : Sh <- Vk8s.sh(Vk8s.describe.pick(co, json, name, dir, secs, zone))
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

# vk8s assets prune [--dry-run] (vk8s design; vcluster has no equivalent):
# remove the release versions in ~/.vk8s/assets that this binary does not
# pin, VK8S_ASSETS does not name, and no running VM boots from
# (C.Cli.assets_prune decides). A running VM's assets dir is one that a
# process's arguments name (bend-vmm's --kernel DIR/Image, for control
# planes, workers and the image cache), as written or resolved.
def Vk8s.assets_root(+home: String) -> String:
  home ++ "/.vk8s/assets"

def Vk8s.assets_names_sh(+root: String) -> String:
  "for d in " ++ Vk8s.q(root) ++ "/*/; do [ -d \"$d\" ] || continue; d=${d%/}; printf '%s\\n' \"${d##*/}\"; done; true"

def Vk8s.assets_used_sh(+root: String) -> String:
  "a=$(ps axww -o args=) || exit 1; r=$(printf '%s\\n' \"$a\" | awk '{ for (i = 1; i < NF; i++) if ($i == \"--kernel\") print $(i+1) }'"
    ++ " | while IFS= read -r k; do (cd \"${k%/*}\" 2>/dev/null && pwd -P); done); "
    ++ "for d in " ++ Vk8s.q(root) ++ "/*/; do [ -d \"$d\" ] || continue; d=${d%/}; n=${d##*/}; "
    ++ "case \"$a\" in *\"$d/\"*) printf '%s\\n' \"$n\"; continue ;; esac; "
    ++ "p=$(cd \"$d\" && pwd -P) && printf '%s\\n' \"$r\" | grep -qxF -- \"$p\" && printf '%s\\n' \"$n\"; done; true"

def Vk8s.assets_override_sh(+root: String, +env: String) -> String:
  "[ -n " ++ Vk8s.q(env) ++ " ] || exit 0; o=$(cd " ++ Vk8s.q(env) ++ " 2>/dev/null && pwd -P) || exit 0; for d in " ++ Vk8s.q(root)
    ++ "/*/; do [ -d \"$d\" ] || continue; d=${d%/}; [ \"$(cd \"$d\" && pwd -P)\" = \"$o\" ] && { printf '%s\\n' \"${d##*/}\"; break; }; done; true"

def Vk8s.assets_prune.one(+dry: Bool, +root: String, +n: String) -> IO(Unit):
  match dry:
    case True{}:
      do IO<Unit>:
        size : String <- Vk8s.sh_out("du -sh " ++ Vk8s.q(root ++ "/" ++ n) ++ " 2>/dev/null | cut -f1")
        Vk8s.say("would remove " ++ root ++ "/" ++ n ++ " (" ++ size ++ ")")
    case False{}:
      do IO<Unit>:
        size : String <- Vk8s.sh_out("du -sh " ++ Vk8s.q(root ++ "/" ++ n) ++ " 2>/dev/null | cut -f1")
        +ok : Bool <- Vk8s.sh_ok("rm -rf " ++ Vk8s.q(root ++ "/" ++ n) ++ "; ! test -e " ++ Vk8s.q(root ++ "/" ++ n))
        Vk8s.when(ok, Vk8s.say("removed " ++ root ++ "/" ++ n ++ " (" ++ size ++ ")"))
        Vk8s.unless(ok, Vk8s.say("could not remove " ++ root ++ "/" ++ n))

def Vk8s.assets_prune.all(ns: +List<String>, +dry: Bool, +root: String) -> IO(Unit):
  match ns:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+n, t}:
      do IO<Unit>:
        Vk8s.assets_prune.one(dry, root, n)
        Vk8s.assets_prune.all(t, dry, root)

def Vk8s.assets_prune.none(none: Bool, +root: String, +ver: String) -> IO(Unit):
  match none:
    case True{}:
      Vk8s.say("no superseded asset versions in " ++ root ++ " (this vk8s uses " ++ ver ++ ")")
    case False{}:
      IO.pure(Unit, Unit{})

def Vk8s.assets_prune(+dry: Bool) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +root : String = Vk8s.assets_root(home)
    +env : String <- Vk8s.getenv("VK8S_ASSETS", "")
    names : String <- Vk8s.sh_out(Vk8s.assets_names_sh(root))
    +used : Sh <- Vk8s.sh(Vk8s.assets_used_sh(root))
    Vk8s.unless(Vk8s.sh_ok.of(used), Vk8s.die("could not list the running VMs (ps); nothing removed"))
    +over : String <- Vk8s.sh_out(Vk8s.assets_override_sh(root, env))
    +arch : String <- Vk8s.arch()
    +ver : String = M.Manifest.version_for(arch)
    +gone : +List<String> = C.Cli.assets_prune(String.lines(names), ver, over, String.lines(Vk8s.raw.out(used)))
    Vk8s.assets_prune.none(List.is_empty(&2, String, gone), root, ver)
    Vk8s.assets_prune.all(gone, dry, root)

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
    +env0 : String <- Vk8s.slurp(dir ++ "/cluster.env")
    +note : String = LW.LanWire.check(True{}, name, env0)
    Vk8s.unless(String.is_empty(note), Vk8s.say(note))
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
    Vk8s.preflight()
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
    Vk8s.lan_wire_guard(name, dir)
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

# Publish "ID ACTION" as share/requests/request through the cluster's own
# directory (host-owned, 0700). An old answer needs no removal: the ID is
# new, so it never matches.
def Vk8s.request.put(+dir: String, +id: String, +action: String) -> IO(Bool):
  Vk8s.share_put(dir ++ "/request." ++ id ++ ".tmp", dir ++ "/share", "requests", "request", id ++ " " ++ action ++ "\n")

# Send a request and do not wait for its answer.
def Vk8s.request.send(+dir: String, +action: String) -> IO(Unit):
  do IO<Unit>:
    idr : String <- Vk8s.sh_out("LC_ALL=C tr -dc a-z0-9 </dev/urandom | head -c 8")
    put : Bool <- Vk8s.request.put(dir, String.trim(idr), action)
    Vk8s.unless(put, Vk8s.die("could not send the request to the cluster"))

# Vk8s.request with n tries of the answer, 500 ms apart.
def Vk8s.request.n(n: Nat, +dir: String, +action: String) -> IO(Bool):
  do IO<Bool>:
    idr : String <- Vk8s.sh_out("LC_ALL=C tr -dc a-z0-9 </dev/urandom | head -c 8")
    +id : String = String.trim(idr)
    put : Bool <- Vk8s.request.put(dir, id, action)
    Vk8s.unless(put, Vk8s.die("could not send the request to the cluster"))
    m : Nat <- Vk8s.scaled(n)
    Vk8s.request.wait(m, dir, id)

# Ask the cluster's PID 1 to run an action (P.Plan.request) and wait for
# its answer: share/requests/request holds "ID ACTION", the guest writes
# "ID done|failed" to share/requests/response.
def Vk8s.request(+dir: String, +action: String) -> IO(Bool):
  Vk8s.request.n(600n, dir, action)

# data.img's allocated size on the host, in KiB (du counts the blocks the
# file holds, not its 16 GiB sparse length).
def Vk8s.cache_img_kib(+dir: String) -> IO(U32):
  do IO<U32>:
    k : String <- Vk8s.sh_out("du -k " ++ Vk8s.q(dir ++ "/data.img") ++ " 2>/dev/null | cut -f1")
    return Vk8s.u32(k, 0)

# Ask a running cache VM to measure each registry (P.Plan.cache_usage);
# it writes share/usage.
def Vk8s.cache_measure(running: Bool, +dir: String) -> IO(Bool):
  match running:
    case True{}:
      Vk8s.request.n(60n, dir, "cache-usage")
    case False{}:
      IO.pure(Bool, False{})

def Vk8s.cache_usage(+dir: String) -> IO(String):
  Vk8s.share_read(dir ++ "/share/usage", 4096)

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
        +running : Bool <- Vk8s.cache_running(dir)
        fresh : Bool <- Vk8s.cache_measure(running, dir)
        +text : String <- Vk8s.cache_usage(dir)
        img : U32 <- Vk8s.cache_img_kib(dir)
        IO.write(C.Cli.cache_status(running, fresh, text, img, dir ++ "/data.img"))

def Vk8s.cache(+action: String) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +dir : String = Vk8s.cache_dir(home)
    Vk8s.cache.go(String.eq(action, "start"), String.eq(action, "stop"), home, dir)

def Vk8s.cache_prune.restop(+dir: String) -> IO(Unit):
  do IO<Unit>:
    _ : Bool <- Vk8s.sh_ok(Vk8s.stop_vms(dir))
    Vk8s.say("image cache stopped again, as it was before the prune")

# vk8s cache prune [REGISTRY] (vk8s design): the cache VM's PID 1 stops
# those registries, removes their storage and runs fstrim
# (P.Plan.cache_prune); the supervisor starts them again, empty, 5 s
# later, and clusters pull from the upstream meanwhile. A stopped cache
# is started for the prune and stopped again after it.
def Vk8s.cache_prune(+regs: +List<String>) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +dir : String = Vk8s.cache_dir(home)
    was : Bool <- Vk8s.cache_running(dir)
    +assets : String <- Vk8s.assets(home)
    up : Bool <- Vk8s.cache_start(home, assets)
    Vk8s.unless(up, Vk8s.die("the image cache did not start, so nothing was pruned; see " ++ dir ++ "/console.log"))
    _ : Bool <- Vk8s.request.n(60n, dir, "cache-usage")
    +before : String <- Vk8s.cache_usage(dir)
    img0 : U32 <- Vk8s.cache_img_kib(dir)
    Vk8s.say("Pruning the image cache (" ++ String.join(regs, ", ") ++ "); clusters pull from the upstream until it is done...")
    ok : Bool <- Vk8s.request(dir, C.Cli.cache_prune_action(regs))
    Vk8s.unless(ok, Vk8s.die("the prune failed; see " ++ dir ++ "/console.log"))
    img1 : U32 <- Vk8s.cache_img_kib(dir)
    Vk8s.say(String.trim(C.Cli.cache_pruned(regs, before, img0, img1)))
    Vk8s.unless(was, Vk8s.cache_prune.restop(dir))

def Vk8s.wait_api.loop(n: Nat, +dir: String) -> IO(Bool):
  match n:
    case 0n:
      IO.pure(Bool, False{})
    case 1n+p:
      do IO<Bool>:
        ok : Bool <- Vk8s.sh_ok("curl -sk -o /dev/null --max-time 2 https://127.0.0.1:$(cat " ++ Vk8s.q(dir ++ "/port") ++ ")/livez")
        Vk8s.or_retry(ok, Vk8s.sleep_then(Vk8s.wait_api.loop(p, dir)))

# Wait for the API server to answer again (n tries, 500 ms apart, scaled
# by VK8S_WAIT_SCALE).
def Vk8s.wait_api(n: Nat, +dir: String) -> IO(Bool):
  do IO<Bool>:
    m : Nat <- Vk8s.scaled(n)
    Vk8s.wait_api.loop(m, dir)

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
    Vk8s.lan_wire_guard(name, dir)
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
    there : Bool <- Vk8s.run_ok("test", ["-f", archive])
    cp : Bool <- Vk8s.share_copy_if(there, archive, vdir ++ "/" ++ f ++ ".tmp", vdir ++ "/share", "images", f)
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

# The curl form fetches /node/join from the guest join server
# (host/join_server.bend) at 10.10.0.2:8443, which nodes on the VM LAN
# reach (from this host it is forwarded to 127.0.0.1:C.Cli.join_port);
# --kubeadm joins the API server at 10.10.0.2:6443 directly.
# A native cluster records its own endpoints (the host's address, its
# ports) in cluster.env: JOIN_ENDPOINT and API_ENDPOINT.
def Vk8s.token_print(kubeadm: Bool, +token: String, +dir: String) -> IO(Unit):
  match kubeadm:
    case False{}:
      do IO<Unit>:
        +je : String <- Vk8s.setting(dir, "JOIN_ENDPOINT")
        IO.write(JN.Join.join_command("", NH.NHost.or(je, C.Cli.join_endpoint()), token))
    case True{}:
      do IO<Unit>:
        pem : String <- Vk8s.sh_out("sed -n 's/^ *certificate-authority-data: *//p' " ++ Vk8s.q(dir ++ "/kubeconfig.yaml") ++ " | head -1 | base64 -d")
        +ae : String <- Vk8s.setting(dir, "API_ENDPOINT")
        IO.write(JN.Join.kubeadm_command(NH.NHost.or(ae, C.Cli.api_endpoint()), token, Vk8s.hash_of(JN.Join.ca_hash(pem))))

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
    Vk8s.token_print(kubeadm, id ++ "." ++ sec, dir)

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
# keep no state of their own: they join afresh on restore. The control
# plane first flushes its page cache (P.Plan.request sync): a docker
# volume is the host's file system, but a VM's recent writes (kine's
# SQLite does not fsync each commit) are in guest memory, not on the disk
# the snapshot copies. A guest that does not flush (paused, stopped, too
# old, or its sync failed) gets no snapshot (review pr-47 P1): the disk
# alone could miss writes, and pausing does not flush guest memory.
def Vk8s.snapshot(+name: String, +path: String) -> IO(Unit):
  do IO<Unit>:
    +dir : String <- Vk8s.exists(name)
    synced : Bool <- Vk8s.request.n(60n, dir, "sync")
    Vk8s.unless(synced, Vk8s.die("vCluster " ++ name ++ " did not flush its disk within 30 s, so a snapshot could miss its last writes; "
      ++ "if it is paused, run vk8s resume " ++ name ++ " and try again"))
    Vk8s.say("Pausing vCluster " ++ name ++ " for consistent snapshot...")
    Vk8s.pause(name, "pause", "paused")
    st : String <- Vk8s.sh_out("mktemp -d")
    +stage : String = String.trim(st)
    disk : Bool <- Vk8s.clone(dir ++ "/data.img", stage ++ "/data.img")
    copied : Bool <- Vk8s.and_then(disk, Vk8s.sh_ok("cp " ++ Vk8s.q(dir ++ "/cluster.env") ++ " " ++ Vk8s.q(stage ++ "/cluster.env")))
    Vk8s.say("Resuming vCluster " ++ name ++ "...")
    Vk8s.pause(name, "resume", "resumed")
    Vk8s.unless(copied, Vk8s.die("could not copy the data disk of " ++ name))
    # COPYFILE_DISABLE: macOS tar would add AppleDouble "._" entries for the
    # files' extended attributes (com.apple.provenance), and restore takes
    # the first entry as the snapshot's kind; GNU tar ignores the variable.
    made : Bool <- Vk8s.sh_ok("cd " ++ Vk8s.q(stage) ++ " && printf '{\"name\":\"%s\",\"guest\":\"%s\",\"kubernetesVersion\":\"%s\",\"backingStore\":\"%s\",\"nodes\":%s,\"vk8s\":\"0.1.0\"}\\n' "
      ++ Vk8s.q(name) ++ " \"" ++ Vk8s.setting_sh(dir, "GUEST") ++ "\" \"" ++ Vk8s.setting_sh(dir, "KUBERNETES") ++ "\" \"" ++ Vk8s.setting_sh(dir, "STORE")
      ++ "\" \"" ++ Vk8s.setting_sh(dir, "NODES") ++ "\" > metadata.json && (umask 077; COPYFILE_DISABLE=1 tar -czSf " ++ Vk8s.q(path) ++ " metadata.json cluster.env data.img); r=$?; cd / && rm -rf "
      ++ Vk8s.q(stage) ++ "; exit $r")
    Vk8s.unless(made, Vk8s.die("could not write the snapshot " ++ path))
    Vk8s.say("Successfully created snapshot at " ++ path)

# Unpack a snapshot safely (security review F2, F3): the archive must hold
# exactly metadata.json (first), cluster.env and data.img, all regular
# files; they are unpacked into a private staging directory, the disk must
# be raw (no qcow2 header, which could name host files as backing), and
# only then do they move into the new cluster's directory. AppleDouble
# entries ("._NAME", macOS tar's extended attributes in snapshots made
# before COPYFILE_DISABLE, review F12) are left out of the listing and
# never unpacked: tar extracts the three members by name.
def Vk8s.restore_sh(+dir: String, +path: String) -> String:
  "umask 077; p=" ++ Vk8s.q(path) ++ "; d=" ++ Vk8s.q(dir) ++ "; l=$(tar -tvzf \"$p\" 2>/dev/null) || { echo \"cannot read the snapshot $p\"; exit 1; }; "
    ++ "l=$(printf '%s\\n' \"$l\" | awk '$NF !~ /^(\\.\\/)?\\._/'); "
    ++ "names=$(printf '%s\\n' \"$l\" | awk '{print $NF}' | tr '\\n' ' '); [ \"$names\" = 'metadata.json cluster.env data.img ' ] || { "
    ++ "first=$(printf '%s\\n' \"$l\" | head -1 | awk '{print $NF}'); [ \"$first\" = metadata.json ] || { echo \"expected metadata.json as first entry, got $first\"; exit 1; }; "
    ++ "echo 'the snapshot must hold exactly metadata.json, cluster.env and data.img'; exit 1; }; "
    ++ "printf '%s\\n' \"$l\" | grep -qv '^-' && { echo 'the snapshot holds a member that is not a regular file'; exit 1; }; "
    ++ "mkdir -p \"$(dirname \"$d\")\" && t=$(mktemp -d \"$(dirname \"$d\")/.restore.XXXXXX\") || exit 1; "
    ++ "tar -xzSf \"$p\" -C \"$t\" metadata.json cluster.env data.img || { rm -rf \"$t\"; echo 'could not unpack the snapshot'; exit 1; }; "
    ++ "for f in metadata.json cluster.env data.img; do { [ -f \"$t/$f\" ] && [ ! -L \"$t/$f\" ]; } || { rm -rf \"$t\"; echo \"bad member $f\"; exit 1; }; done; "
    ++ "[ \"$(head -c 4 \"$t/data.img\" | od -An -tx1 | tr -d ' ')\" = 514649fb ] && { rm -rf \"$t\"; echo 'the snapshot disk is not raw (qcow2)'; exit 1; }; "
    ++ "mkdir -p \"$d/share\" && chmod 700 \"$d\" && mv \"$t/data.img\" \"$t/cluster.env\" \"$d/\" && rm -rf \"$t\""

# The VM format: the control plane boots on the snapshot's data disk.
def Vk8s.restore_vm(+name: String, +path: String, +assets: String, +dir: String) -> IO(Unit):
  do IO<Unit>:
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
    +home : String <- Vk8s.home()
    +port : U32 <- Vk8s.claim(3n, home, dir)
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

# The open format (vcluster's archive, --format open)
# ---------------------------------------------------
# docs/ref/snapshot-decisions.md; the archive bytes are host/snapshot_open.bend's.

# A classic-mode cluster (vk8s create --host-kubeconfig) keeps its host
# namespace and the host kubeconfig on its share.
def Vk8s.is_classic(+dir: String) -> IO(Bool):
  Vk8s.sh_ok("test -f " ++ Vk8s.q(dir ++ "/host-namespace") ++ " -o -f " ++ Vk8s.q(dir ++ "/share/host-kubeconfig"))

def Vk8s.snapshot_open.report(r: O.Open.R(Unit), +path: String) -> IO(Unit):
  match r:
    case Fail{m}:
      Vk8s.die("could not write the snapshot " ++ path ++ ": " ++ m)
    case Done{u}:
      Vk8s.say("Successfully created snapshot at " ++ path)

# The share copies of the dump go whatever the outcome.
def Vk8s.snapshot_open.done(r: O.Open.R(Unit), +dir: String, +stage: String, +path: String) -> IO(Unit):
  do IO<Unit>:
    _ : Bool <- Vk8s.sh_ok("rm -rf " ++ Vk8s.q(stage) ++ " " ++ Vk8s.q(dir ++ "/share/snapshot/export") ++ " " ++ Vk8s.q(dir ++ "/share/snapshot/export.tmp"))
    Vk8s.snapshot_open.report(r, path)

def Vk8s.snapshot_open.go(+name: String, +dir: String, +path: String) -> IO(Unit):
  do IO<Unit>:
    +store : String <- Vk8s.setting(dir, "STORE")
    +etcd : Bool = String.eq(store, "etcd")
    Vk8s.say("Exporting the " ++ C.Cli.store_name(etcd) ++ " store of vCluster " ++ name ++ " (it keeps running)...")
    ok : Bool <- Vk8s.request(dir, "snapshot-dump")
    Vk8s.unless(ok, Vk8s.die("vCluster " ++ name ++ " could not export its store (is it running?); see " ++ dir ++ "/console.log"))
    there : Bool <- Vk8s.sh_ok("d=" ++ Vk8s.q(dir ++ "/share/snapshot/export") ++ "; test -d \"$d\" && test ! -L \"$d\"")
    Vk8s.unless(there, Vk8s.die("vCluster " ++ name ++ " answered the export without a dump in " ++ dir ++ "/share/snapshot/export"))
    st : String <- Vk8s.sh_out("mktemp -d")
    +stage : String = String.trim(st)
    Vk8s.unless(Bool.not(String.is_empty(stage)), Vk8s.die("could not make a staging directory"))
    r : O.Open.R(Unit) <- O.Open.export(etcd, dir ++ "/share/snapshot/export", stage, path)
    Vk8s.snapshot_open.done(r, dir, stage, path)

# vk8s snapshot create NAME PATH --format open: vcluster's archive of the
# store, read through the store's API while the cluster runs (no pause,
# D6): the guest dumps it on its share (P.Plan.request snapshot-dump),
# the host writes the archive. Standalone clusters only (D4).
def Vk8s.snapshot_open(+name: String, +path: String) -> IO(Unit):
  do IO<Unit>:
    +dir : String <- Vk8s.exists(name)
    classic : Bool <- Vk8s.is_classic(dir)
    Vk8s.when(classic, Vk8s.die("vk8s snapshot: --format open is not supported for classic-mode clusters (created with --host-kubeconfig); use --format vm"))
    Vk8s.snapshot_open.go(name, dir, path)

def Vk8s.restore.abort(+stage: String, +msg: String) -> IO(Unit):
  do IO<Unit>:
    _ : Bool <- Vk8s.sh_ok("rm -rf " ++ Vk8s.q(stage))
    Vk8s.die(msg)

def Vk8s.kind_name(etcd: Bool) -> String:
  match etcd:
    case True{}:
      "an etcd archive"
    case False{}:
      "a key/value archive"

# The new cluster takes the archive's store: embedded etcd for an etcd
# archive (as --backing-store etcd), kine on SQLite for a key/value one.
# Its share holds the db or puts file and the marker before the first
# boot, so PID 1 boots with P.Plan.boot_restore (D12).
def Vk8s.restore_open.boot(+name: String, +etcd: Bool, +assets: String, +dir: String, +stage: String) -> IO(Unit):
  do IO<Unit>:
    Vk8s.say("The snapshot is " ++ Vk8s.kind_name(etcd) ++ ": vCluster " ++ name ++ " gets the " ++ C.Cli.store_name(etcd) ++ " backing store")
    have : Bool <- Vk8s.sh_ok("test -f " ++ Vk8s.q(assets ++ "/vk8s.cpio") ++ " -a -f " ++ Vk8s.q(assets ++ "/data.img"))
    Vk8s.unless(have, Vk8s.restore.abort(stage, "vk8s assets not found in " ++ assets ++ " (set VK8S_ASSETS)"))
    mk : Bool <- Vk8s.run_ok("mkdir", ["-p", dir])
    Vk8s.unless(mk, Vk8s.restore.abort(stage, "could not set up " ++ dir))
    +home : String <- Vk8s.home()
    +port : U32 <- Vk8s.claim(3n, home, dir)
    prep : Bool <- Vk8s.sh_ok("mkdir -p " ++ Vk8s.q(dir ++ "/share") ++ " && chmod 700 " ++ Vk8s.q(dir))
    img : Bool <- Vk8s.clone_if(prep, assets ++ "/data.img", dir ++ "/data.img")
    made : Bool <- Vk8s.and_then(img, Vk8s.sh_ok("echo " ++ U32.show(port) ++ " > " ++ Vk8s.q(dir ++ "/port")
      ++ " && printf %s " ++ Vk8s.q(Vk8s.env_file(name, name, port, 2, 2048, etcd, 0)) ++ " > " ++ Vk8s.q(dir ++ "/cluster.env")
      ++ " && echo CREATED=$(date +%s) >> " ++ Vk8s.q(dir ++ "/cluster.env")
      ++ " && rm -rf " ++ Vk8s.q(dir ++ "/share/snapshot") ++ " && mv " ++ Vk8s.q(stage ++ "/snapshot") ++ " " ++ Vk8s.q(dir ++ "/share/snapshot")
      ++ " && rm -rf " ++ Vk8s.q(stage)))
    Vk8s.unless(made, Vk8s.restore.abort(stage, "could not set up " ++ dir))
    Vk8s.boot(name, name, dir, assets, port, 2, 2048, etcd, 0)
    Vk8s.say("Successfully restored vCluster " ++ name ++ " from snapshot")
    Vk8s.created_msg(name, dir)

def Vk8s.restore_open.placed(r: O.Open.R(Bool), +name: String, +assets: String, +dir: String, +stage: String) -> IO(Unit):
  match r:
    case Fail{m}:
      Vk8s.restore.abort(stage, "vk8s restore: " ++ m)
    case Done{etcd}:
      Vk8s.restore_open.boot(name, etcd, assets, dir, stage)

# vcluster's archive: unpacked into the staging directory (beside the
# cluster directories), its db or puts file made there (Open.place).
def Vk8s.restore_open(+name: String, +path: String, +assets: String, +dir: String, +stage: String) -> IO(Unit):
  do IO<Unit>:
    un : Bool <- Vk8s.sh_ok("umask 077; gzip -dc " ++ Vk8s.q(path) ++ " > " ++ Vk8s.q(stage ++ "/snapshot.tar"))
    Vk8s.unless(un, Vk8s.restore.abort(stage, "could not unpack the snapshot " ++ path))
    r : O.Open.R(Bool) <- O.Open.place(stage ++ "/snapshot.tar", stage ++ "/snapshot")
    Vk8s.restore_open.placed(r, name, assets, dir, stage)

def Vk8s.restore.pick(f: O.Open.Fmt, +name: String, +path: String, +assets: String, +dir: String, +stage: String) -> IO(Unit):
  match f:
    case O.FmtVm{}:
      do IO<Unit>:
        _ : Bool <- Vk8s.sh_ok("rm -rf " ++ Vk8s.q(stage))
        Vk8s.restore_vm(name, path, assets, dir)
    case O.FmtOpen{}:
      Vk8s.restore_open(name, path, assets, dir, stage)
    case O.FmtBad{m}:
      Vk8s.restore.abort(stage, "vk8s restore: " ++ path ++ ": " ++ m)

# vcluster restore (docker driver): a new cluster from a snapshot; the
# name must be free. The first tar entry tells the format (D2):
# metadata.json is the VM format, a name under "/" vcluster's archive.
def Vk8s.restore(+name: String, +path: String) -> IO(Unit):
  do IO<Unit>:
    Vk8s.preflight()
    +home : String <- Vk8s.home()
    +assets : String <- Vk8s.assets(home)
    +dir : String = C.Cli.dir(home, name)
    exists : Bool <- Vk8s.sh_ok("test -e " ++ Vk8s.q(dir))
    Vk8s.when(exists, Vk8s.die("vCluster \"" ++ name ++ "\" already exists; delete it first or use a different name"))
    Vk8s.unless(C.Cli.paths_fit(dir), Vk8s.die("the cluster directory " ++ dir ++ " is too long for its sockets (macOS allows 103 bytes); use a shorter name"))
    Vk8s.say("Restoring vCluster " ++ name ++ " from snapshot " ++ path ++ "...")
    st : String <- Vk8s.sh_out("d=" ++ Vk8s.q(dir) ++ "; p=$(dirname \"$d\"); mkdir -p \"$p\" && mktemp -d \"$p/.restore.XXXXXX\"")
    +stage : String = String.trim(st)
    Vk8s.unless(Bool.not(String.is_empty(stage)), Vk8s.die("could not make a staging directory beside " ++ dir))
    _ : Bool <- Vk8s.sh_ok("umask 077; gzip -dc " ++ Vk8s.q(path) ++ " 2>/dev/null | head -c 1048576 > " ++ Vk8s.q(stage ++ "/first"))
    f : O.Open.Fmt <- O.Open.fmt_file(stage ++ "/first")
    Vk8s.restore.pick(f, name, path, assets, dir, stage)

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

# The backing store: etcd when the vcluster.yaml enables embedded etcd or
# --backing-store etcd asks for it (flags override values, as vcluster's
# create does).
def Vk8s.run.values.create(c: C.Cmd, +etcd: Bool, +text: String, conn: Bool) -> IO(Unit):
  match c:
    case C.Classic{C.Create{+name, port, cpus, mem, e0, nodes}, kc, ns}:
      Vk8s.then_connect(conn, name, Vk8s.create_classic_v(name, port, cpus, mem, Bool.or(e0, etcd), nodes, kc, ns, text))
    case C.Classic{C.NoConnect{C.Create{name, port, cpus, mem, e0, nodes}}, kc, ns}:
      Vk8s.create_classic_v(name, port, cpus, mem, Bool.or(e0, etcd), nodes, kc, ns, text)
    case C.Create{+name, port, cpus, mem, e0, nodes}:
      Vk8s.then_connect(conn, name, Vk8s.create_x(name, port, cpus, mem, Bool.or(e0, etcd), nodes, "", "", text))
    case C.NoConnect{C.Create{name, port, cpus, mem, e0, nodes}}:
      Vk8s.create_x(name, port, cpus, mem, Bool.or(e0, etcd), nodes, "", "", text)
    case _:
      Vk8s.die("-f applies to create only")

def Vk8s.run.values.go(r: Result<&2, &2, String, J.Json>, +text: String, c: C.Cmd, conn: Bool) -> IO(Unit):
  match r:
    case Fail{e}:
      Vk8s.die(e)
    case Done{+cfg}:
      do IO<Unit>:
        +why : String = VL.Values.unsupported.v2(cfg)
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

# --- Container mode (`--backend container`, docs/ref/explore-linux-hosts.md
# Phase 6 C2). src/cli/ctr.bend decides every name, address, argument
# list and message; this runs them, each program with an argument list
# through Process.run or Proc.start, never through a shell. runc starts
# each node from the config.json R.Ctr.json renders (D9 a): Bend 2.0.40
# has no clone, unshare, pivot_root or netlink effect.

# runc run -d hands its output to the container, which outlives this
# process: it starts through I.Proc.start (host/effs/proc.c, posix_spawn
# in a new session, stdout and stderr appended to a log, as PID 1 starts
# its daemons), and I.Proc.reap collects it.

# A program's output (stdout, then stderr) whatever its exit status.
def Vk8s.run_raw(+prog: String, args: +List<String>) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run(prog, Vk8s.argv(args), "", 4194304, 600000)
    return Vk8s.raw.out(Vk8s.sh.got(r))

# A program's exit status and output (stdout, then stderr), no shell.
def Vk8s.run_sh(+prog: String, args: +List<String>) -> IO(Sh):
  do IO<Sh>:
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run(prog, Vk8s.argv(args), "", 4194304, 600000)
    return Vk8s.sh.got(r)

def Vk8s.ctr.write.close(p: File & Result<&1, &1, U32 & String, Unit>) -> IO(Bool):
  match p:
    case (f, Done{u}):
      do IO<Bool>:
        File.close(f)
        return True{}
    case (f, Fail{e}):
      do IO<Bool>:
        File.close(f)
        return False{}

def Vk8s.ctr.write.go(r: Result<&1, &1, U32 & String, File>, +text: String) -> IO(Bool):
  match r:
    case Fail{e}:
      IO.pure(Bool, False{})
    case Done{f}:
      do IO<Bool>:
        p : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, text)
        Vk8s.ctr.write.close(p)

# Write a file through Base's File effects.
def Vk8s.ctr.write(+path: String, +text: String) -> IO(Bool):
  do IO<Bool>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "w")
    Vk8s.ctr.write.go(r, text)

def Vk8s.values_files.go(none: Bool, +values: String, +dir: String) -> IO(Bool):
  match none:
    case True{}:
      IO.pure(Bool, True{})
    case False{}:
      do IO<Bool>:
        a : Bool <- Vk8s.ctr.write(dir ++ "/vcluster.yaml", values)
        Vk8s.and_then(a, Vk8s.ctr.write(dir ++ "/share/vcluster.yaml", values))

# The vcluster.yaml of create -f (values; "" without one) in the cluster's
# directory (workers' shares copy it, Vk8s.share_values) and on the
# control plane's share, where its PID 1 reads it.
def Vk8s.values_files(+values: String, +dir: String) -> IO(Bool):
  Vk8s.values_files.go(String.is_empty(values), values, dir)

# Run prog with each argument list in order; False at the first failure.
def Vk8s.ctr.all(+prog: String, cs: +List<+List<String>>) -> IO(Bool):
  match cs:
    case Nil{}:
      IO.pure(Bool, True{})
    case Con{c, t}:
      do IO<Bool>:
        ok : Bool <- Vk8s.run_ok(prog, c)
        Vk8s.and_then(ok, Vk8s.ctr.all(prog, t))

# Run prog with each argument list, whatever each exits with (cleanup).
def Vk8s.ctr.each(+prog: String, cs: +List<+List<String>>) -> IO(Unit):
  match cs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{c, t}:
      do IO<Unit>:
        _ : Bool <- Vk8s.run_ok(prog, c)
        Vk8s.ctr.each(prog, t)

def Vk8s.ctr.first.go(ok: Bool, +c: String, more: IO(String)) -> IO(String):
  match ok:
    case True{}:
      IO.pure(String, c)
    case False{}:
      more

# The first candidate path that opens ("" when none does).
def Vk8s.ctr.first(cs: +List<String>) -> IO(String):
  match cs:
    case Nil{}:
      IO.pure(String, "")
    case Con{+c, t}:
      do IO<String>:
        ok : Bool <- Vk8s.can_open(c, "r")
        Vk8s.ctr.first.go(ok, c, Vk8s.ctr.first(t))

# runc's absolute path (Proc.start does not search PATH).
def Vk8s.ctr.runc() -> IO(String):
  do IO<String>:
    +path : String <- Vk8s.getenv("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
    Vk8s.ctr.first(C.Cli.path_candidates(path, "runc"))

def Vk8s.ctr.modules(ms: +List<String>) -> IO(List<&2, String>):
  match ms:
    case Nil{}:
      IO.pure(List<&2, String>, Nil{})
    case Con{+m, t}:
      do IO<List<&2, String>>:
        ok : Bool <- Vk8s.run_ok("modprobe", [m])
        +rest : List<&2, String> <- Vk8s.ctr.modules(t)
        return R.Ctr.lacks.add(ok, m, rest)

# Stop before any change when the host cannot run node containers: root,
# the tools, the kernel modules (loaded here, as vcluster's docker driver
# loads them), cgroup v2 and its controllers.
def Vk8s.ctr.preflight() -> IO(Unit):
  do IO<Unit>:
    +path : String <- Vk8s.getenv("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
    +tools : List<&2, String> <- Vk8s.missing(path, R.Ctr.tools())
    +status : String <- Vk8s.slurp("/proc/self/status")
    +mods : List<&2, String> <- Vk8s.ctr.modules(NP.Netpol.ctr_modules())
    +ctl : String <- Vk8s.slurp("/sys/fs/cgroup/cgroup.controllers")
    +msg : String = R.Ctr.preflight_message(R.Ctr.root(status), Bool.not(String.is_empty(String.trim(ctl))), tools, mods,
      R.Ctr.missing_controllers(ctl))
    Vk8s.unless(String.is_empty(msg), Vk8s.die(String.trim(msg)))

def Vk8s.ctr.enable(+file: String, es: +List<String>) -> IO(Unit):
  match es:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{e, t}:
      do IO<Unit>:
        _ : Bool <- Vk8s.ctr.write(file, e)
        Vk8s.ctr.enable(file, t)

# Host cgroup delegation: /sys/fs/cgroup/vk8s/<cluster> exists, and it
# and every cgroup above it enable their controllers for their children,
# one at a time (a controller the host cannot enable is skipped).
def Vk8s.ctr.cgroups(ds: +List<String>) -> IO(Unit):
  match ds:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+d, t}:
      do IO<Unit>:
        _ : Bool <- Vk8s.run_ok("mkdir", ["-p", d])
        +cs : String <- Vk8s.slurp(d ++ "/cgroup.controllers")
        Vk8s.ctr.enable(d ++ "/cgroup.subtree_control", R.Ctr.enables(cs))
        Vk8s.ctr.cgroups(t)

def Vk8s.ctr.exit_pick(hit: Bool, +code: U32, more: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match hit:
    case True{}:
      Some{code}
    case False{}:
      more

def Vk8s.ctr.exit_of(es: List<(U32 & U32)>, +pid: U32) -> Maybe<&2, U32>:
  match es:
    case Nil{}:
      None{}
    case Con{(p, code), rest}:
      Vk8s.ctr.exit_pick(U32.is_eq(p, pid), code, Vk8s.ctr.exit_of(rest, pid))

def Vk8s.ctr.reaped(m: Maybe<&2, U32>, again: IO(Bool)) -> IO(Bool):
  match m:
    case Some{c}:
      IO.pure(Bool, U32.is_eq(c, 0))
    case None{}:
      again

# Wait for child pid to exit (n polls, 100 ms apart): True when it exits 0.
def Vk8s.ctr.wait_pid(n: Nat, +pid: U32) -> IO(Bool):
  match n:
    case 0n:
      IO.pure(Bool, False{})
    case 1n+p:
      do IO<Bool>:
        IO.sleep(100)
        es : List<(U32 & U32)> <- I.Proc.reap()
        Vk8s.ctr.reaped(Vk8s.ctr.exit_of(es, pid), Vk8s.ctr.wait_pid(p, pid))

def Vk8s.ctr.started(r: Result<&1, &1, U32 & String, U32>) -> U32:
  match r:
    case Fail{e}:
      0
    case Done{pid}:
      pid

# runc run -d; the node's PID 1 keeps runc's stdout and stderr, the log.
def Vk8s.ctr.runc_run(+runc: String, +bundle: String, +id: String, +log: String) -> IO(Bool):
  do IO<Bool>:
    r : Result<&1, &1, U32 & String, U32> <- I.Proc.start(runc, Vk8s.argv(R.Ctr.runc_run(bundle, id)), log)
    +pid : U32 = Vk8s.ctr.started(r)
    Vk8s.and_then(Bool.not(U32.is_eq(pid, 0)), Vk8s.ctr.wait_pid(600n, pid))

def Vk8s.ctr.status(+runc: String, +id: String) -> IO(String):
  do IO<String>:
    out : String <- Vk8s.run_raw(runc, R.Ctr.runc(["state", id]))
    return R.Ctr.status(out)

# Wait for a file the node writes on its share while its container runs
# (n tries, 500 ms apart).
def Vk8s.ctr.wait(n: Nat, +runc: String, +id: String, +path: String) -> IO(Bool):
  match n:
    case 0n:
      IO.pure(Bool, False{})
    case 1n+p:
      do IO<Bool>:
        up : Bool <- Vk8s.run_ok("test", ["-s", path])
        +st : String <- Vk8s.ctr.status(runc, id)
        Vk8s.wait_vm.go(up, String.eq(st, "stopped"), Vk8s.sleep_then(Vk8s.ctr.wait(p, runc, id, path)))

def Vk8s.ctr.wait_stopped(n: Nat, +runc: String, +id: String) -> IO(Bool):
  match n:
    case 0n:
      IO.pure(Bool, False{})
    case 1n+p:
      do IO<Bool>:
        +st : String <- Vk8s.ctr.status(runc, id)
        Vk8s.or_retry(String.eq(st, "stopped"), Vk8s.sleep_then(Vk8s.ctr.wait_stopped(p, runc, id)))

# One node: its root filesystem (the initramfs), data dir and share, its
# resolv.conf and config.json, its network namespace on the bridge, then
# runc. The control plane's directory is the cluster's.
def Vk8s.ctr.node(+runc: String, +name: String, +dir: String, +assets: String, +mnt: String, +k: U32, +i: U32,
  env: +List<String>, +resolv: String) -> IO(Bool):
  do IO<Bool>:
    +nd : String = R.Ctr.node_dir(dir, i)
    +bundle : String = nd ++ "/bundle"
    +rootfs : String = bundle ++ "/rootfs"
    +data : String = nd ++ "/data"
    +share : String = nd ++ "/share"
    +arch : String <- Vk8s.arch()
    made : Bool <- Vk8s.run_ok("mkdir", ["-p", rootfs, data, share])
    unpacked : Bool <- Vk8s.and_then(made, Vk8s.run_ok("cpio", R.Ctr.unpack(assets ++ "/vk8s.cpio", rootfs)))
    dns : Bool <- Vk8s.and_then(unpacked, Vk8s.ctr.write(rootfs ++ "/etc/resolv.conf", resolv))
    conf : Bool <- Vk8s.and_then(dns, Vk8s.ctr.write(bundle ++ "/config.json",
      R.Ctr.json(CN.Spec{name, R.Ctr.node(name, i), rootfs, data, share, mnt, R.Ctr.arch_env(arch, env)}, R.Ctr.netns_path(name, i))))
    net : Bool <- Vk8s.and_then(conf, Vk8s.ctr.all("ip", R.Ctr.ip_node(name, k, i)))
    Vk8s.and_then(net, Vk8s.ctr.runc_run(runc, bundle, R.Ctr.id(name, i), nd ++ "/console.log"))

# Worker containers i..: each gets the control plane's discovery kubeconfig
# on its share and the join token in its environment.
def Vk8s.ctr.workers(ws: List<&2, U32>, +runc: String, +name: String, +dir: String, +assets: String, +mnt: String, +k: U32,
  +token: String, +resolv: String) -> IO(Bool):
  match ws:
    case Nil{}:
      IO.pure(Bool, True{})
    case Con{+i, rest}:
      do IO<Bool>:
        +nd : String = R.Ctr.node_dir(dir, i)
        Vk8s.say("Starting node " ++ R.Ctr.node(name, i) ++ " (" ++ R.Ctr.node_ip(k, i) ++ ")...")
        prep : Bool <- Vk8s.run_ok("mkdir", ["-p", nd ++ "/share"])
        disc : Bool <- Vk8s.share_copy_if(prep, dir ++ "/discovery.conf", nd ++ "/discovery.conf.tmp", nd ++ "/share", "", "discovery.conf")
        vy : Bool <- Vk8s.and_then(disc, Vk8s.share_values(dir, nd))
        ok : Bool <- Vk8s.and_then(vy, Vk8s.ctr.node(runc, name, dir, assets, mnt, k, i, R.Ctr.env_worker(name, k, i, token), resolv))
        Vk8s.and_then(ok, Vk8s.ctr.workers(rest, runc, name, dir, assets, mnt, k, token, resolv))

def Vk8s.ctr.wait_workers(ws: List<&2, U32>, +runc: String, +name: String, +dir: String) -> IO(Bool):
  match ws:
    case Nil{}:
      IO.pure(Bool, True{})
    case Con{+i, rest}:
      do IO<Bool>:
        ok : Bool <- Vk8s.ctr.wait(1200n, runc, R.Ctr.id(name, i), R.Ctr.node_dir(dir, i) ++ "/share/joined")
        Vk8s.and_then(ok, Vk8s.ctr.wait_workers(rest, runc, name, dir))

# The host-owned kubeconfig and discovery file: the server is the control
# plane's address on the bridge, which the host routes to.
def Vk8s.ctr.kubeconfig(+name: String, +dir: String, +server: String) -> IO(Unit):
  do IO<Unit>:
    +text : String <- Vk8s.share_read(dir ++ "/share/kubeconfig.yaml", 1048576)
    Vk8s.own_kubeconfig.go(K.Kubeconfig.sanitize(text, server, K.Kubeconfig.context_name(name)), K.Kubeconfig.discovery(text, server), dir)

# With sleep when idle on, the host-owned kubeconfig names the idle
# proxy on 127.0.0.1 (a free port, recorded in the port file) instead of
# the control plane's bridge address; worker nodes keep joining through
# the bridge (join is the discovery file's server).
def Vk8s.ctr.kubeconfig_x(+name: String, +dir: String, +server: String, +join: String) -> IO(Unit):
  do IO<Unit>:
    +text : String <- Vk8s.share_read(dir ++ "/share/kubeconfig.yaml", 1048576)
    Vk8s.own_kubeconfig.go(K.Kubeconfig.sanitize(text, server, K.Kubeconfig.context_name(name)), K.Kubeconfig.discovery(text, join), dir)

def Vk8s.ctr.server(off: Bool, +k: U32, +port: U32) -> String:
  match off:
    case True{}:
      "https://" ++ R.Ctr.node_ip(k, 0) ++ ":6443"
    case False{}:
      "https://127.0.0.1:" ++ U32.show(port)

def Vk8s.ctr.idle_port(off: Bool, +dir: String) -> IO(U32):
  match off:
    case True{}:
      IO.pure(U32, 0)
    case False{}:
      do IO<U32>:
        +home : String <- Vk8s.home()
        +port : U32 <- Vk8s.free_port.v2(True{}, home, 0)
        ok : Bool <- Vk8s.file_put(dir ++ "/port", "w", U32.show(port) ++ "\n")
        Vk8s.unless(ok, Vk8s.die("could not write " ++ dir ++ "/port"))
        return port

def Vk8s.ctr.env_file(+name: String, +k: U32, +etcd: Bool, +nodes: U32, +now: String) -> String:
  Vk8s.env_file(name, name, 6443, 0, 0, etcd, nodes) ++ "BACKEND=container\nSLOT=" ++ U32.show(k) ++ "\nAPI=https://"
    ++ R.Ctr.node_ip(k, 0) ++ ":6443\nCREATED=" ++ String.trim(now) ++ "\n"

# The assets a container cluster needs: per-role (base.img and the
# control plane's sets) or, from an older build, the single assets.img.
def Vk8s.ctr.have(per: Bool, +assets: String) -> IO(Bool):
  match per:
    case True{}:
      Vk8s.run_ok("test", ["-f", assets ++ "/vk8s.cpio", "-a", "-f", assets ++ "/base.img",
        "-a", "-f", assets ++ "/node.img", "-a", "-f", assets ++ "/control-plane.img"])
    case False{}:
      Vk8s.run_ok("test", ["-f", assets ++ "/vk8s.cpio", "-a", "-f", assets ++ "/assets.img"])

def Vk8s.ctr.mount_sets(+assets: String, +dir: String, sets: +List<String>) -> IO(Bool):
  match sets:
    case Nil{}:
      IO.pure(Bool, True{})
    case Con{+s, t}:
      do IO<Bool>:
        ok : Bool <- Vk8s.run_ok("mount", R.Ctr.mount_assets(assets ++ "/" ++ s ++ ".img", R.Ctr.set_dir(dir, s)))
        Vk8s.and_then(ok, Vk8s.ctr.mount_sets(assets, dir, t))

# <dir>/assets as the nodes bind it: base.img and the sets joined by a
# read-only overlay (R.Ctr.lowers), or the single assets.img.
def Vk8s.ctr.mount_assets(per: Bool, +assets: String, +dir: String, +sets: +List<String>) -> IO(Bool):
  match per:
    case True{}:
      do IO<Bool>:
        made : Bool <- Vk8s.run_ok("mkdir", Con{"-p", R.Ctr.lowers(dir, sets)})
        base : Bool <- Vk8s.and_then(made, Vk8s.run_ok("mount", R.Ctr.mount_assets(assets ++ "/base.img", R.Ctr.base_dir(dir))))
        each : Bool <- Vk8s.and_then(base, Vk8s.ctr.mount_sets(assets, dir, sets))
        Vk8s.and_then(each, Vk8s.run_ok("mount", R.Ctr.mount_overlay(R.Ctr.lowers(dir, sets), dir ++ "/assets")))
    case False{}:
      Vk8s.run_ok("mount", R.Ctr.mount_assets(assets ++ "/assets.img", dir ++ "/assets"))

# --- Container mode in the node-host VM (macOS; src/cli/nodehost.bend,
# docs/ref/explore-linux-hosts.md Phase 6 C4 and D11 a). The nodes run
# in one shared bend-vmm VM whose PID 1 (host/init.bend, role node-host)
# runs the container driver's steps; this side starts or reuses the VM,
# asks it for each cluster's containers through the share's request
# channel (Vk8s.request), reads the nodes' shares and owns the kubeconfig
# (server: the cluster's forwarded port on 127.0.0.1).

# Whether --backend container runs in the node host here (macOS, or
# VK8S_NODE_HOST=vm on Linux).
def Vk8s.nh.use() -> IO(Bool):
  do IO<Bool>:
    +os : String <- Vk8s.run_out("uname", ["-s"])
    +env : String <- Vk8s.getenv("VK8S_NODE_HOST", "")
    return HN.Nh.use_vm(String.trim(os), env)

# A line to the VM's control socket (bend-vmm's status, powerdown); its
# answer.
def Vk8s.nh.ctl(+dir: String, +line: String) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("nc", Vk8s.argv(["-U", "-w", "2", dir ++ "/ctl.sock"]), line ++ "\n", 65536, 10000)
    return Vk8s.raw.out(Vk8s.sh.got(r))

# The node host serves requests: its VMM runs and PID 1 said it is ready.
def Vk8s.nh.running(+dir: String) -> IO(Bool):
  do IO<Bool>:
    st : String <- Vk8s.nh.ctl(dir, "status json")
    ready : Bool <- Vk8s.run_ok("test", ["-s", dir ++ "/share/ready"])
    return String.contains(st, "running") && ready

def Vk8s.nh.sets(+assets: String) -> IO(+List<String>):
  do IO<+List<String>>:
    images : Bool <- Vk8s.can_open(assets ++ "/images.img", "r")
    return HN.Nh.sets(images)

# Boot the node host: its data disk (a clone of data.img, kept between
# boots), the initramfs on its share (the nodes' root), and the VMM in
# its own session (Proc.start, no shell), then wait for PID 1's ready.
def Vk8s.nh.boot(+dir: String, +assets: String) -> IO(Bool):
  do IO<Bool>:
    +self : String <- Vk8s.self()
    +arch : String <- Vk8s.arch()
    +home : String <- Vk8s.home()
    +sets : +List<String> <- Vk8s.nh.sets(assets)
    Vk8s.sets_ensure(home, assets, sets)
    +memv : String <- Vk8s.getenv("VK8S_NODE_HOST_MEMORY", "")
    +cpuv : String <- Vk8s.getenv("VK8S_NODE_HOST_CPUS", "")
    +mem : U32 = C.Cli.num(U32.read(memv), HN.Nh.mem())
    +cpus : U32 = C.Cli.num(U32.read(cpuv), HN.Nh.cpus())
    Vk8s.say("Starting the node host VM (" ++ U32.show(cpus) ++ " vCPUs, " ++ U32.show(mem) ++ " MiB; API ports 127.0.0.1:"
      ++ U32.show(HN.Nh.port(1)) ++ "-" ++ U32.show(HN.Nh.port(HN.Nh.max())) ++ ")...")
    made : Bool <- Vk8s.run_ok("mkdir", ["-p", dir ++ "/share/requests"])
    priv : Bool <- Vk8s.and_then(made, Vk8s.run_ok("chmod", ["700", dir]))
    _ : Bool <- Vk8s.run_ok("rm", ["-f", dir ++ "/share/ready", dir ++ "/share/requests/request", dir ++ "/share/requests/response"])
    have : Bool <- Vk8s.can_open(dir ++ "/data.img", "r")
    img : Bool <- Vk8s.or_retry(have, Vk8s.clone_if(priv, assets ++ "/data.img", dir ++ "/data.img"))
    cpio : Bool <- Vk8s.share_copy_if(img, assets ++ "/vk8s.cpio", dir ++ "/vk8s.cpio.tmp", dir ++ "/share", "", "vk8s.cpio")
    +flags : +List<String> = C.Cli.role_flags(True{}, C.Cli.arch_flags(arch, HN.Nh.flags(dir, assets, mem, cpus)), assets, dir ++ "/data.img", sets)
    r : Result<&1, &1, U32 & String, U32> <- I.Proc.start(self, Vk8s.argv(Con{"vmm", flags}), dir ++ "/vmm.log")
    +pid : U32 = Vk8s.ctr.started(r)
    _ : Bool <- Vk8s.ctr.write(dir ++ "/vmm.pid", U32.show(pid) ++ "\n")
    Vk8s.and_then(cpio && Bool.not(U32.is_eq(pid, 0)), Vk8s.wait_vm(360n, dir, "/share/ready"))

def Vk8s.nh.ensure.go(running: Bool, +dir: String, +assets: String) -> IO(Bool):
  match running:
    case True{}:
      IO.pure(Bool, True{})
    case False{}:
      do IO<Bool>:
        # a VMM left from an earlier boot that never got ready
        _ : Bool <- Vk8s.sh_ok(Vk8s.stop_vms(dir))
        Vk8s.nh.boot(dir, assets)

# Start the node host unless it serves requests already.
def Vk8s.nh.ensure(+dir: String, +assets: String) -> IO(Bool):
  do IO<Bool>:
    running : Bool <- Vk8s.nh.running(dir)
    Vk8s.nh.ensure.go(running, dir, assets)

# Power the node host off (PID 1 stops, the VMM exits; then quit, kill).
def Vk8s.nh.stop(+dir: String) -> IO(Unit):
  do IO<Unit>:
    Vk8s.say("Stopping the node host VM (no container cluster is left)...")
    _ : Bool <- Vk8s.sh_ok(Vk8s.stop_vms(dir))
    return Unit{}

# The host-owned kubeconfig (server: the forwarded port) and the workers'
# discovery file (server: the control plane's address on the VM's bridge).
def Vk8s.nh.kubeconfig(+name: String, +dir: String, +cpdir: String, +port: U32, +k: U32) -> IO(Unit):
  do IO<Unit>:
    +text : String <- Vk8s.share_read(cpdir ++ "/share/kubeconfig.yaml", 1048576)
    Vk8s.own_kubeconfig.go(K.Kubeconfig.sanitize(text, "https://127.0.0.1:" ++ U32.show(port), K.Kubeconfig.context_name(name)),
      K.Kubeconfig.discovery(text, "https://" ++ R.Ctr.node_ip(k, 0) ++ ":6443"), dir)

def Vk8s.nh.workers(ws: List<&2, U32>, +nh: String, +name: String, +dir: String, +k: U32, +token: String) -> IO(Bool):
  match ws:
    case Nil{}:
      IO.pure(Bool, True{})
    case Con{+i, rest}:
      do IO<Bool>:
        Vk8s.say("Starting node " ++ R.Ctr.node(name, i) ++ " (" ++ R.Ctr.node_ip(k, i) ++ ")...")
        # The node host VM runs: every directory under its share is the
        # guest's, so the walk makes and checks them (no mkdir -p).
        disc : Bool <- Vk8s.share_copy(dir ++ "/discovery.conf", nh ++ "/discovery." ++ name ++ "." ++ U32.show(i) ++ ".tmp", nh ++ "/share",
          HN.Nh.rel(name, i) ++ "/share", "discovery.conf")
        ok : Bool <- Vk8s.and_then(disc, Vk8s.request(nh, HN.Nh.req_join(name, k, i, token)))
        Vk8s.and_then(ok, Vk8s.nh.workers(rest, nh, name, dir, k, token))

def Vk8s.nh.wait_workers(ws: List<&2, U32>, +nh: String, +name: String) -> IO(Bool):
  match ws:
    case Nil{}:
      IO.pure(Bool, True{})
    case Con{+i, rest}:
      do IO<Bool>:
        ok : Bool <- Vk8s.wait_file(1200n, HN.Nh.share(nh, name, i) ++ "/joined")
        Vk8s.and_then(ok, Vk8s.nh.wait_workers(rest, nh, name))

# vk8s create NAME --backend container on macOS: a slot (1..16), the
# cluster's directory and settings, the node host, the control plane's
# container, its kubeconfig, then the workers' containers.
def Vk8s.nh.create(+name: String, +etcd: Bool, +nodes: U32) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +assets : String <- Vk8s.assets(home)
    +dir : String = C.Cli.dir(home, name)
    +nh : String = HN.Nh.dir(home)
    exists : Bool <- Vk8s.run_ok("test", ["-e", dir])
    Vk8s.when(exists, Vk8s.die("vCluster " ++ name ++ " already exists"))
    have : Bool <- Vk8s.run_ok("test", ["-f", assets ++ "/vk8s.cpio", "-a", "-f", assets ++ "/base.img", "-a", "-f", assets ++ "/Image"])
    Vk8s.unless(have, Vk8s.die("vk8s assets with base.img not found in " ++ assets ++ " (set VK8S_ASSETS)"))
    used : String <- Vk8s.run_raw("grep", ["-rh", "--include=cluster.env", "^SLOT=", home ++ "/.vk8s/clusters"])
    +k : U32 = HN.Nh.slot(R.Ctr.slots(used))
    Vk8s.when(U32.is_eq(k, 0), Vk8s.die(HN.Nh.full_message()))
    +port : U32 = HN.Nh.port(k)
    Vk8s.say("Creating vCluster " ++ name ++ " (containers in the node host VM, API on https://127.0.0.1:" ++ U32.show(port) ++ ")...")
    now : String <- Vk8s.run_raw("date", ["+%s"])
    made : Bool <- Vk8s.run_ok("mkdir", ["-p", dir])
    priv : Bool <- Vk8s.and_then(made, Vk8s.run_ok("chmod", ["700", dir]))
    env : Bool <- Vk8s.and_then(priv, Vk8s.ctr.write(dir ++ "/cluster.env", HN.Nh.env(name, k, etcd, nodes, now)))
    pf : Bool <- Vk8s.and_then(env, Vk8s.ctr.write(dir ++ "/port", U32.show(port) ++ "\n"))
    Vk8s.unless(pf, Vk8s.die("could not set up " ++ dir))
    up : Bool <- Vk8s.nh.ensure(nh, assets)
    Vk8s.unless(up, Vk8s.die("the node host VM did not start; see " ++ nh ++ "/console.log; vk8s delete " ++ name ++ " cleans up"))
    _ : Bool <- Vk8s.run_ok("rm", ["-rf", nh ++ "/share/clusters/" ++ name])
    cp : Bool <- Vk8s.request(nh, HN.Nh.req_up(name, k, etcd))
    Vk8s.unless(cp, Vk8s.die("the node host could not start the control plane of " ++ name ++ "; see " ++ nh ++ "/console.log; vk8s delete "
      ++ name ++ " cleans up"))
    +cpdir : String = HN.Nh.node_dir(nh, name, 0)
    ready : Bool <- Vk8s.wait_file(1800n, cpdir ++ "/share/kubeconfig.yaml")
    Vk8s.unless(ready, Vk8s.die("vCluster " ++ name ++ " did not come up; see " ++ nh ++ "/share/logs/" ++ R.Ctr.id(name, 0) ++ ".log and "
      ++ cpdir ++ "/share/logs"))
    Vk8s.nh.kubeconfig(name, dir, cpdir, port, k)
    +token : String <- Vk8s.join_token_if(U32.is_eq(nodes, 0), cpdir)
    started : Bool <- Vk8s.nh.workers(C.Cli.workers_upto(nodes), nh, name, dir, k, token)
    Vk8s.unless(started, Vk8s.die("the node host could not start a worker node of " ++ name ++ "; see " ++ nh ++ "/console.log"))
    joined : Bool <- Vk8s.nh.wait_workers(C.Cli.workers_upto(nodes), nh, name)
    Vk8s.unless(joined, Vk8s.die("a worker node of " ++ name ++ " did not join; see " ++ nh ++ "/share/clusters/" ++ name ++ "/nodes/*/share/logs"))
    Vk8s.say("Successfully created virtual cluster " ++ name ++ ". ")
    Vk8s.created_msg(name, dir)

# vk8s delete: the node host stops and removes the cluster's containers,
# network, rules and cgroups; then its directories go, and the node host
# stops when no container cluster is left on this host.
def Vk8s.nh.delete(+name: String, ctx: Bool) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +dir : String = C.Cli.dir(home, name)
    +nh : String = HN.Nh.dir(home)
    +env : String <- Vk8s.slurp(dir ++ "/cluster.env")
    +k : U32 = Maybe.default(&2, U32, U32.read(R.Ctr.setting(env, "SLOT")), 0)
    +running : Bool <- Vk8s.nh.running(nh)
    down : Bool <- Vk8s.and_then(running, Vk8s.request.n(2400n, nh, HN.Nh.req_down(name, k, C.Cli.workers_of(R.Ctr.setting(env, "WORKERS")))))
    Vk8s.unless(down || Bool.not(running), Vk8s.say("warning: the node host did not confirm that the containers of " ++ name ++ " are gone"))
    Vk8s.when(ctx, Vk8s.forget(name, home))
    _ : Bool <- Vk8s.run_ok("rm", ["-rf", dir, nh ++ "/share/clusters/" ++ name])
    left : Bool <- Vk8s.run_ok("test", ["-e", dir])
    Vk8s.when(left, Vk8s.die("could not remove " ++ dir))
    rest : String <- Vk8s.run_raw("grep", ["-rh", "--include=cluster.env", "^NODEHOST=", home ++ "/.vk8s/clusters"])
    Vk8s.unless(HN.Nh.left(rest) || Bool.not(running), Vk8s.nh.stop(nh))
    Vk8s.say("Successfully deleted virtual cluster " ++ name)

# vk8s pause / resume: runc pause / resume of every node in the node host.
def Vk8s.nh.pause(+name: String, +verb: String, +done: String) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +env : String <- Vk8s.slurp(C.Cli.dir(home, name) ++ "/cluster.env")
    ok : Bool <- Vk8s.request(HN.Nh.dir(home), HN.Nh.req_freeze(verb, name, C.Cli.workers_of(R.Ctr.setting(env, "WORKERS"))))
    Vk8s.unless(ok, Vk8s.die("the node host could not " ++ verb ++ " " ++ name))
    Vk8s.say("vCluster " ++ name ++ ": " ++ done)

# runc's container list the node host keeps on its share ("" when it is
# not running: every node-host cluster then lists as stopped).
def Vk8s.nh.list_text(running: Bool, +dir: String) -> IO(String):
  match running:
    case True{}:
      Vk8s.slurp(dir ++ "/share/runc-list")
    case False{}:
      IO.pure(String, "")

# Free slot k again (its reservation, R.Ctr.release).
def Vk8s.ctr.release(+k: U32) -> IO(Unit):
  do IO<Unit>:
    _ : Bool <- Vk8s.run_ok("rm", R.Ctr.release(k))
    return Unit{}

def Vk8s.ctr.release_die(+k: U32, +msg: String) -> IO(Unit):
  do IO<Unit>:
    Vk8s.ctr.release(k)
    Vk8s.die(msg)

def Vk8s.ctr.claim.wrote(p: File & Result<&1, &1, U32 & String, Unit>, +k: U32) -> IO(Bool):
  match p:
    case (f, Done{u}):
      do IO<Bool>:
        File.close(f)
        return True{}
    case (f, Fail{e}):
      do IO<Bool>:
        File.close(f)
        Vk8s.ctr.release(k)
        return False{}

def Vk8s.ctr.claim.go(r: Result<&1, &1, U32 & String, File>, +k: U32, +text: String) -> IO(Bool):
  match r:
    case Fail{e}:
      IO.pure(Bool, False{})
    case Done{f}:
      do IO<Bool>:
        p : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, text)
        Vk8s.ctr.claim.wrote(p, k)

# Claim slot k for the cluster in dir: its owner file is created with
# O_CREAT|O_EXCL (File.open's "x"), so the kernel lets one create, from
# any home, have it. The exit status of `mkdir` without -p is not the
# lock: Ubuntu 26.04's coreutils let two creates hold one slot, and both
# then wrote the one owner file. A claim whose owner text cannot be
# written is freed again. True when this create holds the slot.
def Vk8s.ctr.claim(+k: U32, +dir: String) -> IO(Bool):
  do IO<Bool>:
    _ : Bool <- Vk8s.run_ok("mkdir", ["-p", R.Ctr.slot_dir(k)])
    r : Result<&1, &1, U32 & String, File> <- File.open(R.Ctr.slot_owner(k), "x")
    Vk8s.ctr.claim.go(r, k, R.Ctr.owner_text(dir))

def Vk8s.ctr.reserve.keep(busy: Bool, +k: U32, more: IO(U32)) -> IO(U32):
  match busy:
    case True{}:
      do IO<U32>:
        Vk8s.ctr.release(k)
        more
    case False{}:
      IO.pure(U32, k)

def Vk8s.ctr.reserve.got(got: Bool, +k: U32, more: IO(U32)) -> IO(U32):
  match got:
    case False{}:
      more
    case True{}:
      do IO<U32>:
        busy : Bool <- Vk8s.run_ok("ip", R.Ctr.bridge_show(k))
        Vk8s.ctr.reserve.keep(busy, k, more)

# The first slot of ks this create reserves on the host (R.Ctr.slots_dir,
# Vk8s.ctr.claim). A slot whose bridge exists (a cluster from an older
# vk8s) is freed again and skipped. The owner file names the cluster's
# directory. 0: none.
def Vk8s.ctr.reserve(ks: List<&2, U32>, +dir: String) -> IO(U32):
  match ks:
    case Nil{}:
      IO.pure(U32, 0)
    case Con{+k, t}:
      do IO<U32>:
        got : Bool <- Vk8s.ctr.claim(k, dir)
        Vk8s.ctr.reserve.got(got, k, Vk8s.ctr.reserve(t, dir))

# Create on this Linux host: the control plane's sets fetched (or found),
# a slot reserved on the host, the cluster's directory, the assets mount,
# the bridge and its rules (isolated from the other clusters' bridges),
# then the nodes.
def Vk8s.ctr.create(+name: String, +etcd: Bool, +nodes: U32, +values: String) -> IO(Unit):
  do IO<Unit>:
    Vk8s.ctr.preflight()
    +home : String <- Vk8s.home()
    +assets : String <- Vk8s.assets(home)
    +dir : String = C.Cli.dir(home, name)
    exists : Bool <- Vk8s.run_ok("test", ["-e", dir])
    Vk8s.when(exists, Vk8s.die("vCluster " ++ name ++ " already exists"))
    +per : Bool <- Vk8s.can_open(assets ++ "/base.img", "r")
    +arch : String <- Vk8s.arch()
    present : Bool <- Vk8s.can_open(assets ++ "/images.img", "r")
    +images : Bool = R.Ctr.want_images(present, String.eq(assets, A.Assets.dir(home, M.Manifest.version_for(arch))),
      Bool.not(List.is_empty(&2, A.AssetFile, A.Assets.set_files(["images"], M.Manifest.sets_for(arch)))))
    Vk8s.when(per, Vk8s.sets_ensure(home, assets, R.Ctr.sets(images)))
    have : Bool <- Vk8s.ctr.have(per, assets)
    Vk8s.unless(have, Vk8s.die("vk8s assets not found in " ++ assets ++ " (set VK8S_ASSETS)"))
    +runc : String <- Vk8s.ctr.runc()
    used : String <- Vk8s.run_raw("grep", ["-rh", "--include=cluster.env", "^SLOT=", home ++ "/.vk8s/clusters"])
    _ : Bool <- Vk8s.run_ok("mkdir", ["-p", R.Ctr.slots_dir()])
    +k : U32 <- Vk8s.ctr.reserve(R.Ctr.free(R.Ctr.slots(used)), dir)
    Vk8s.when(U32.is_eq(k, 0), Vk8s.die(R.Ctr.no_slot_message()))
    +mnt : String = dir ++ "/assets"
    Vk8s.say("Creating vCluster " ++ name ++ " (containers on " ++ R.Ctr.bridge(k) ++ ", API on https://" ++ R.Ctr.node_ip(k, 0) ++ ":6443)...")
    now : String <- Vk8s.run_raw("date", ["+%s"])
    prep : Bool <- Vk8s.run_ok("mkdir", ["-p", mnt, dir ++ "/share"])
    priv : Bool <- Vk8s.and_then(prep, Vk8s.run_ok("chmod", ["700", dir]))
    env : Bool <- Vk8s.and_then(priv, Vk8s.ctr.write(dir ++ "/cluster.env", Vk8s.ctr.env_file(name, k, etcd, nodes, now)))
    vy : Bool <- Vk8s.and_then(env, Vk8s.values_files(values, dir))
    Vk8s.unless(vy, Vk8s.ctr.release_die(k, "could not set up " ++ dir))
    mounted : Bool <- Vk8s.ctr.mount_assets(per, assets, dir, R.Ctr.sets(images))
    Vk8s.unless(mounted, Vk8s.die("could not set up " ++ dir ++ " and mount the assets of " ++ assets ++ " on it; vk8s delete " ++ name ++ " cleans up"))
    Vk8s.ctr.cgroups(R.Ctr.cgroup_dirs(name))
    fwd : Bool <- Vk8s.ctr.write("/proc/sys/net/ipv4/ip_forward", "1")
    br : Bool <- Vk8s.and_then(fwd, Vk8s.ctr.all("ip", R.Ctr.ip_bridge(k)))
    fw : Bool <- Vk8s.and_then(br, Vk8s.ctr.all("iptables", R.Ctr.rules.v2(name, k)))
    Vk8s.unless(fw, Vk8s.die("could not set up the network of " ++ name ++ " (" ++ R.Ctr.bridge(k) ++ "); vk8s delete " ++ name ++ " cleans up"))
    +a : String <- Vk8s.slurp("/run/systemd/resolve/resolv.conf")
    +b : String <- Vk8s.slurp("/etc/resolv.conf")
    +resolv : String = R.Ctr.resolv(a, b)
    cp : Bool <- Vk8s.ctr.node(runc, name, dir, assets, mnt, k, 0, R.Ctr.env_cp(name, k, 6443, etcd), resolv)
    Vk8s.unless(cp, Vk8s.die("could not start the control plane of " ++ name ++ "; see " ++ dir ++ "/console.log"))
    up : Bool <- Vk8s.ctr.wait(1800n, runc, R.Ctr.id(name, 0), dir ++ "/share/kubeconfig.yaml")
    Vk8s.unless(up, Vk8s.die("vCluster " ++ name ++ " did not come up; see " ++ dir ++ "/console.log and " ++ dir ++ "/share/logs"))
    +limit : U32 <- Vk8s.idle.limit(dir)
    +port : U32 <- Vk8s.ctr.idle_port(U32.is_eq(limit, 0), dir)
    Vk8s.idle.start(name, dir, port, R.Ctr.node_ip(k, 0), 6443, limit)
    Vk8s.ctr.kubeconfig_x(name, dir, Vk8s.ctr.server(U32.is_eq(limit, 0), k, port), "https://" ++ R.Ctr.node_ip(k, 0) ++ ":6443")
    +token : String <- Vk8s.join_token_if(U32.is_eq(nodes, 0), dir)
    started : Bool <- Vk8s.ctr.workers(C.Cli.workers_upto(nodes), runc, name, dir, assets, mnt, k, token, resolv)
    Vk8s.unless(started, Vk8s.die("could not start a worker node of " ++ name ++ "; see " ++ dir ++ "/nodes/*/console.log"))
    joined : Bool <- Vk8s.ctr.wait_workers(C.Cli.workers_upto(nodes), runc, name, dir)
    Vk8s.unless(joined, Vk8s.die("a worker node of " ++ name ++ " did not join; see " ++ dir ++ "/nodes/*/share/logs"))
    Vk8s.say("Successfully created virtual cluster " ++ name ++ ". ")
    Vk8s.created_msg(name, dir)

# Stop node i as vind stops a container: PID 1 reads the stop request on
# its share, stops the daemons last started first and exits (up to 60 s);
# then runc kills what is left and deletes the container, and the node's
# network namespace goes with its veth pair.
def Vk8s.ctr.stop(+runc: String, +name: String, +dir: String, +i: U32) -> IO(Unit):
  do IO<Unit>:
    +id : String = R.Ctr.id(name, i)
    _ : Bool <- Vk8s.run_ok(runc, R.Ctr.runc(["resume", id]))
    +nd : String = R.Ctr.node_dir(dir, i)
    _ : Bool <- Vk8s.share_put(nd ++ "/stop.tmp", nd ++ "/share", "", "stop", "stop\n")
    _ : Bool <- Vk8s.ctr.wait_stopped(120n, runc, id)
    _ : Bool <- Vk8s.run_ok(runc, R.Ctr.runc(["kill", id, "KILL"]))
    _ : Bool <- Vk8s.ctr.wait_stopped(20n, runc, id)
    _ : Bool <- Vk8s.run_ok(runc, R.Ctr.runc(["delete", "-f", id]))
    _ : Bool <- Vk8s.run_ok("ip", R.Ctr.ip_node_del(name, i))
    return Unit{}

def Vk8s.ctr.stop_all(ws: List<&2, U32>, +runc: String, +name: String, +dir: String) -> IO(Unit):
  match ws:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+i, rest}:
      do IO<Unit>:
        Vk8s.ctr.stop(runc, name, dir, i)
        Vk8s.ctr.stop_all(rest, runc, name, dir)

def Vk8s.ctr.umount(ok: Bool, +mnt: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        _ : Bool <- Vk8s.run_ok("umount", ["-l", mnt])
        return Unit{}

def Vk8s.ctr.umount_all(ms: +List<String>) -> IO(Unit):
  match ms:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+m, t}:
      do IO<Unit>:
        un : Bool <- Vk8s.run_ok("umount", [m])
        Vk8s.ctr.umount(un, m)
        Vk8s.ctr.umount_all(t)

# The cluster's nodes, workers first, the control plane (0) last.
def Vk8s.ctr.nodes(+env: String) -> List<&2, U32>:
  List.append(&2, U32, C.Cli.workers_of(R.Ctr.setting(env, "WORKERS")), [0])

# Every rule tagged TAG in each table deleted (iptables -w); True when a
# fresh listing of every table succeeds and holds none of them.
def Vk8s.ctr.unrule.v2(ts: +List<String>, +tag: String) -> IO(Bool):
  match ts:
    case Nil{}:
      IO.pure(Bool, True{})
    case Con{+t, rest}:
      do IO<Bool>:
        out : String <- Vk8s.run_raw("iptables", R.Ctr.list_rules(t))
        Vk8s.ctr.each("iptables", R.Ctr.undo.v2(t, tag, out))
        +r : Sh <- Vk8s.run_sh("iptables", R.Ctr.list_rules(t))
        more : Bool <- Vk8s.ctr.unrule.v2(rest, tag)
        return Vk8s.sh_ok.of(r) && R.Ctr.rules_gone(t, tag, Vk8s.raw.out(r)) && more

# The slot's bridge deleted when the registry gives the slot to this
# cluster; another's (or one no reservation names) stays, with a
# warning. True when no bridge of this cluster is left.
def Vk8s.ctr.unbridge(owned: Bool, +k: U32) -> IO(Bool):
  match owned:
    case True{}:
      do IO<Bool>:
        _ : Bool <- Vk8s.run_ok("ip", R.Ctr.ip_bridge_del(k))
        there : Bool <- Vk8s.run_ok("ip", R.Ctr.bridge_show(k))
        return Bool.not(there)
    case False{}:
      do IO<Bool>:
        there : Bool <- Vk8s.run_ok("ip", R.Ctr.bridge_show(k))
        Vk8s.when(there, Vk8s.say(R.Ctr.unowned_message(k)))
        return True{}

# The cluster's cgroups removed, deepest first (n tries, 500 ms apart: a
# killed process leaves its cgroup a moment later); True when gone.
def Vk8s.ctr.uncgroup(n: Nat, +name: String) -> IO(Bool):
  match n:
    case 0n:
      IO.pure(Bool, False{})
    case 1n+p:
      do IO<Bool>:
        _ : Bool <- Vk8s.run_ok("find", [R.Ctr.cgroup(name), "-depth", "-type", "d", "-delete"])
        left : Bool <- Vk8s.run_ok("test", ["-e", R.Ctr.cgroup(name)])
        Vk8s.or_retry(Bool.not(left), Vk8s.sleep_then(Vk8s.ctr.uncgroup(p, name)))

# The nodes' containers (runc's state) and network namespaces still here.
def Vk8s.ctr.nodes_left(ws: List<&2, U32>, +name: String) -> IO(List<&2, String>):
  match ws:
    case Nil{}:
      IO.pure(List<&2, String>, Nil{})
    case Con{+i, rest}:
      do IO<List<&2, String>>:
        c : Bool <- Vk8s.run_ok("test", ["-e", R.Ctr.state_dir(R.Ctr.id(name, i))])
        n : Bool <- Vk8s.run_ok("test", ["-e", R.Ctr.netns_path(name, i)])
        +more : List<&2, String> <- Vk8s.ctr.nodes_left(rest, name)
        return R.Ctr.left_node(c, n, name, i, more)

# The asset mounts still mounted.
def Vk8s.ctr.mounts_left(ms: +List<String>) -> IO(List<&2, String>):
  match ms:
    case Nil{}:
      IO.pure(List<&2, String>, Nil{})
    case Con{+m, t}:
      do IO<List<&2, String>>:
        on : Bool <- Vk8s.run_ok("mountpoint", ["-q", m])
        +more : List<&2, String> <- Vk8s.ctr.mounts_left(t)
        return R.Ctr.left_mount(on, m, more)

# Delete leaves nothing on the host: the containers, the network
# namespaces and veths, the bridge (when the slot registry gives it to
# this cluster), the tagged rules, the cgroups, the assets mount and the
# cluster's directory. It then checks: when anything is left it says
# what, keeps the cluster.env (the only record of SLOT=) and the slot's
# reservation, and exits 1 (docs/ref/review-bend-vk8s-pr-49.md 1, 3).
def Vk8s.ctr.delete.local(+name: String, ctx: Bool) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +dir : String = C.Cli.dir(home, name)
    exists : Bool <- Vk8s.run_ok("test", ["-d", dir])
    Vk8s.unless(exists, Vk8s.die("vCluster " ++ name ++ " not found"))
    Vk8s.idle.stop(dir)
    +env : String <- Vk8s.slurp(dir ++ "/cluster.env")
    +k : U32 = Maybe.default(&2, U32, U32.read(R.Ctr.setting(env, "SLOT")), 0)
    +runc : String <- Vk8s.ctr.runc()
    Vk8s.ctr.stop_all(Vk8s.ctr.nodes(env), runc, name, dir)
    +nl : List<&2, String> <- Vk8s.ctr.nodes_left(Vk8s.ctr.nodes(env), name)
    rules : Bool <- Vk8s.ctr.unrule.v2(R.Ctr.tables(), R.Ctr.tag(name))
    +own : String <- Vk8s.slurp(R.Ctr.slot_owner(k))
    +owned : Bool = R.Ctr.owns(own, dir)
    br : Bool <- Vk8s.ctr.unbridge(owned, k)
    cg : Bool <- Vk8s.ctr.uncgroup(20n, name)
    _ : Bool <- Vk8s.run_ok("rmdir", ["/sys/fs/cgroup/vk8s"])
    Vk8s.ctr.umount_all(R.Ctr.asset_mounts(dir))
    +ml : List<&2, String> <- Vk8s.ctr.mounts_left(R.Ctr.asset_mounts(dir))
    +left : List<&2, String> = R.Ctr.leftovers(name, k, nl, rules, br, cg, ml)
    Vk8s.when(R.Ctr.some(left), Vk8s.die(R.Ctr.delete_failed(name, dir, left)))
    Vk8s.when(owned, Vk8s.ctr.release(k))
    Vk8s.when(ctx, Vk8s.forget(name, home))
    _ : Bool <- Vk8s.run_ok("rm", ["-rf", "--one-file-system", dir])
    left : Bool <- Vk8s.run_ok("test", ["-e", dir])
    Vk8s.when(left, Vk8s.die("could not remove " ++ dir))
    Vk8s.say("Successfully deleted virtual cluster " ++ name)

def Vk8s.ctr.delete.pick(nh: Bool, +name: String, ctx: Bool) -> IO(Unit):
  match nh:
    case True{}:
      Vk8s.nh.delete(name, ctx)
    case False{}:
      Vk8s.ctr.delete.local(name, ctx)

# A container cluster's delete: in the node host (NODEHOST=1 in its
# cluster.env) or on this Linux host.
def Vk8s.ctr.delete(+name: String, ctx: Bool) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +env : String <- Vk8s.slurp(C.Cli.dir(home, name) ++ "/cluster.env")
    Vk8s.ctr.delete.pick(String.eq(R.Ctr.setting(env, "NODEHOST"), "1"), name, ctx)

def Vk8s.ctr.verbs(+verb: String, +name: String, ws: List<&2, U32>) -> +List<+List<String>>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{i, t}:
      Con{R.Ctr.runc([verb, R.Ctr.id(name, i)]), Vk8s.ctr.verbs(verb, name, t)}

# runc pause / resume (the cgroup freezer) of every node, the control
# plane first, as vind pauses the control plane, then the workers.
def Vk8s.ctr.pause.local(+name: String, +verb: String, +done: String) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +env : String <- Vk8s.slurp(C.Cli.dir(home, name) ++ "/cluster.env")
    +runc : String <- Vk8s.ctr.runc()
    Vk8s.ctr.each(runc, Vk8s.ctr.verbs(verb, name, List.reverse(&2, U32, Vk8s.ctr.nodes(env))))
    Vk8s.say("vCluster " ++ name ++ ": " ++ done)

def Vk8s.ctr.pause.pick(nh: Bool, +name: String, +verb: String, +done: String) -> IO(Unit):
  match nh:
    case True{}:
      Vk8s.nh.pause(name, verb, done)
    case False{}:
      Vk8s.ctr.pause.local(name, verb, done)

def Vk8s.ctr.pause(+name: String, +verb: String, +done: String) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +env : String <- Vk8s.slurp(C.Cli.dir(home, name) ++ "/cluster.env")
    Vk8s.ctr.pause.pick(String.eq(R.Ctr.setting(env, "NODEHOST"), "1"), name, verb, done)

# vk8s pause and resume, and the idle proxy's sleep and wake (src/guest/
# plan.bend Plan.idle_sleep, Plan.idle_wake): before the nodes pause, the
# control plane's PID 1 stops kube-controller-manager; after they resume,
# it sets a VM's clock from the RTC and restarts kube-controller-manager,
# so no controller acts on a node lease that went stale while paused. A
# node host cluster and a native one pause as before (no request).
def Vk8s.idle.ask.go(ok: Bool, +action: String) -> IO(Unit):
  Vk8s.unless(ok, Vk8s.say("warning: the control plane did not confirm " ++ action))

# The wake: send idle-wake and do not wait for the answer. PID 1's wake
# (src/guest/plan.bend Plan.idle_wake.v2) waits up to one 10 s kubelet
# renew period for node leases renewed after the thaw. The idle proxy
# holds the client's connection until `vk8s resume` exits, and kubectl
# gives up on its TLS handshake after 10 s (idle_sleep_smoke, "kubectl
# answers through the sleeping cluster's forward"). The API server runs
# as soon as the container or the VM thaws; PID 1 restarts
# kube-controller-manager on its own when the leases are fresh.
def Vk8s.idle.wake(skip: Bool, +dir: String, +action: String) -> IO(Unit):
  match skip:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      Vk8s.request.send(dir, action)

def Vk8s.idle.ask(skip: Bool, +dir: String, +action: String) -> IO(Unit):
  match skip:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        ok : Bool <- Vk8s.request.n(60n, dir, action)
        Vk8s.idle.ask.go(ok, action)

def Vk8s.vm.pause(+name: String) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +dir : String = C.Cli.dir(home, name)
    +b : String <- Vk8s.setting(dir, "BACKEND")
    Vk8s.idle.ask(String.eq(b, "native"), dir, ID.Idle.req_sleep())
    Vk8s.pause(name, "pause", "paused")

def Vk8s.vm.resume(+name: String) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +dir : String = C.Cli.dir(home, name)
    +b : String <- Vk8s.setting(dir, "BACKEND")
    Vk8s.pause(name, "resume", "resumed")
    Vk8s.idle.wake(String.eq(b, "native"), dir, ID.Idle.req_wake(True{}))

def Vk8s.ctr.pause_x(+name: String) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +dir : String = C.Cli.dir(home, name)
    +env : String <- Vk8s.slurp(dir ++ "/cluster.env")
    Vk8s.idle.ask(String.eq(R.Ctr.setting(env, "NODEHOST"), "1"), dir, ID.Idle.req_sleep())
    Vk8s.ctr.pause(name, "pause", "paused")

# Was the control plane container paused before the resume? A node host
# cluster answers True (its PID 1 gets no request anyway). A resume of a
# cluster that runs already (`vk8s resume`, then the idle proxy's wake on
# the next connection, which still counts the cluster as asleep) sends no
# idle-wake: PID 1's wake waits for node leases renewed after it (src/
# guest/plan.bend Plan.idle_wake.v2), up to 10 s on a cluster that never
# slept, while the proxy holds the client's connection, and kubectl gives
# up on its TLS handshake after 10 s.
def Vk8s.ctr.was_paused(nh: Bool, +name: String) -> IO(Bool):
  match nh:
    case True{}:
      IO.pure(Bool, True{})
    case False{}:
      do IO<Bool>:
        +runc : String <- Vk8s.ctr.runc()
        st : String <- Vk8s.ctr.status(runc, R.Ctr.id(name, 0))
        return String.eq(st, "paused")

def Vk8s.ctr.resume_x(+name: String) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +dir : String = C.Cli.dir(home, name)
    +env : String <- Vk8s.slurp(dir ++ "/cluster.env")
    +nh : Bool = String.eq(R.Ctr.setting(env, "NODEHOST"), "1")
    was : Bool <- Vk8s.ctr.was_paused(nh, name)
    Vk8s.ctr.pause(name, "resume", "resumed")
    Vk8s.idle.wake(nh || Bool.not(was), dir, ID.Idle.req_wake(False{}))

def Vk8s.ctr.entry.pick(ctr: Bool, nh: Bool, +runc: String, +nhlist: String, +name: String, status: String, created: U32, at: String, con: Bool) -> IO(C.Entry):
  match ctr nh:
    case True{} True{}:
      IO.pure(C.Entry, C.Entry{name, HN.Nh.status(nhlist, R.Ctr.id(name, 0)), created, at, con})
    case True{} False{}:
      do IO<C.Entry>:
        +st : String <- Vk8s.ctr.status(runc, R.Ctr.id(name, 0))
        return C.Entry{name, st, created, at, con}
    case False{} _:
      IO.pure(C.Entry, C.Entry{name, status, created, at, con})

def Vk8s.ctr.entry(e: C.Entry, +home: String, +runc: String, +nhlist: String) -> IO(C.Entry):
  match e:
    case C.Entry{+name, status, created, at, con}:
      do IO<C.Entry>:
        +env : String <- Vk8s.slurp(C.Cli.dir(home, name) ++ "/cluster.env")
        Vk8s.ctr.entry.pick(String.eq(R.Ctr.setting(env, "BACKEND"), "container"), String.eq(R.Ctr.setting(env, "NODEHOST"), "1"),
          runc, nhlist, name, status, created, at, con)

def Vk8s.ctr.entries(es: List<&2, C.Entry>, +home: String, +runc: String, +nhlist: String) -> IO(List<&2, C.Entry>):
  match es:
    case Nil{}:
      IO.pure(List<&2, C.Entry>, Nil{})
    case Con{e, t}:
      do IO<List<&2, C.Entry>>:
        +x : C.Entry <- Vk8s.ctr.entry(e, home, runc, nhlist)
        +rest : List<&2, C.Entry> <- Vk8s.ctr.entries(t, home, runc, nhlist)
        return Con{x, rest}

# list: a container cluster's state is its control plane's runc state, on
# this host or, in the node host, from the list its PID 1 keeps.
def Vk8s.ctr.list(json: Bool) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +runc : String <- Vk8s.ctr.runc()
    running : Bool <- Vk8s.nh.running(HN.Nh.dir(home))
    +nhlist : String <- Vk8s.nh.list_text(running, HN.Nh.dir(home))
    es0 : List<&2, C.Entry> <- Vk8s.entries(home)
    es : List<&2, C.Entry> <- Vk8s.ctr.entries(es0, home, runc, nhlist)
    +now : U32 <- Vk8s.epoch()
    IO.write(Vk8s.list.out(json, es, now))

def Vk8s.by_backend.go(ctr: Bool, a: IO(Unit), b: IO(Unit)) -> IO(Unit):
  match ctr:
    case True{}:
      a
    case False{}:
      b

# A cluster's command by the backend its cluster.env records.
def Vk8s.by_backend(+name: String, a: IO(Unit), b: IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +env : String <- Vk8s.slurp(C.Cli.dir(home, name) ++ "/cluster.env")
    Vk8s.by_backend.go(String.eq(R.Ctr.setting(env, "BACKEND"), "container"), a, b)

# The node host's nodes (macOS) do not take a vcluster.yaml yet: its
# shares live in the node-host VM (docs/STATUS.md lists the gap).
def Vk8s.ctr.create.pick(vm: Bool, +name: String, +etcd: Bool, +nodes: U32, +values: String) -> IO(Unit):
  match vm:
    case True{}:
      do IO<Unit>:
        Vk8s.unless(String.is_empty(values), Vk8s.die("vk8s: -f with --backend container in the node-host VM (macOS) is not supported yet; use the VM backend"))
        Vk8s.nh.create(name, etcd, nodes)
    case False{}:
      Vk8s.ctr.create(name, etcd, nodes, values)

# create --backend container: in the node-host VM on macOS (or with
# VK8S_NODE_HOST=vm), else on this Linux host as root.
def Vk8s.ctr.create.any(+name: String, +etcd: Bool, +nodes: U32, +values: String) -> IO(Unit):
  do IO<Unit>:
    vm : Bool <- Vk8s.nh.use()
    Vk8s.ctr.create.pick(vm, name, etcd, nodes, values)

def Vk8s.ctr.values.create(c: C.Cmd, +etcd: Bool, +text: String, conn: Bool) -> IO(Unit):
  match c:
    case C.NoConnect{inner}:
      Vk8s.ctr.values.create(inner, etcd, text, False{})
    case C.Create{+name, port, cpus, mem, e0, nodes}:
      Vk8s.then_connect(conn, name, Vk8s.ctr.create.any(name, Bool.or(e0, etcd), nodes, text))
    case _:
      Vk8s.die("vk8s: -f with --backend container applies to create only")

def Vk8s.ctr.values.go(r: Result<&2, &2, String, J.Json>, +text: String, c: C.Cmd, conn: Bool) -> IO(Unit):
  match r:
    case Fail{e}:
      Vk8s.die(e)
    case Done{+cfg}:
      do IO<Unit>:
        +why : String = VL.Values.unsupported.v2(cfg)
        Vk8s.unless(String.is_empty(why), Vk8s.die(why))
        Vk8s.ctr.values.create(c, VL.Values.etcd(cfg), text, conn)

# create -f with --backend container: the vcluster.yaml checked as for a
# VM (Vk8s.run.values), then on the nodes' shares.
def Vk8s.ctr.values(c: C.Cmd, +file: String, conn: Bool) -> IO(Unit):
  do IO<Unit>:
    +got : Sh <- Vk8s.read(file)
    Vk8s.unless(Vk8s.sh_ok.of(got), Vk8s.die("could not read " ++ file))
    +text : String = Vk8s.raw.out(got)
    Vk8s.ctr.values.go(CF.Config.parse(text), text, c, conn)

# The commands --backend container supports: create (control plane and
# --nodes workers), delete, list, pause and resume.
def Vk8s.ctr.run(c: C.Cmd, conn: Bool) -> IO(Unit):
  match c:
    case C.NoConnect{inner}:
      Vk8s.ctr.run(inner, False{})
    case C.Create{+name, port, cpus, mem, etcd, nodes}:
      Vk8s.then_connect(conn, name, Vk8s.ctr.create.any(name, etcd, nodes, ""))
    case C.WithValues{inner, file}:
      Vk8s.ctr.values(inner, file, conn)
    case C.Delete{name, ctx}:
      Vk8s.ctr.delete(name, ctx)
    case C.List{}:
      Vk8s.ctr.list(False{})
    case C.ListJson{}:
      Vk8s.ctr.list(True{})
    case C.Pause{name}:
      Vk8s.ctr.pause_x(name)
    case C.Resume{name}:
      Vk8s.ctr.resume_x(name)
    case C.Help{msg}:
      IO.print_err(msg)
    case _:
      Vk8s.die("vk8s: --backend container supports create, delete, list, pause and resume")

# --- Native mode (`vk8s create NAME --backend native`; docs/ref/native-host.md,
# docs/ref/explore-linux-hosts.md Phase 5, N3 and N4). The control plane
# (and, on the first native cluster of a host, the node) runs on this
# Linux host as the systemd unit vk8s-NAME.service, which runs this binary
# as `vk8s native` (host/init.bend NInit) over /var/lib/vk8s/NAME. vk8s
# runs as the user; each step that needs root runs through sudo, as an
# argument list, printed before it runs. Every decision is in
# src/standalone/native_host.bend (NH.NHost).

def Vk8s.nat.pick(ok: Bool, +out: String, +err: String) -> String:
  match ok:
    case True{}:
      out
    case False{}:
      out ++ err

def Vk8s.nat.got.go(+st: U32, +out: String, +err: String) -> Sh:
  Sh{U32.is_eq(st, 0), Vk8s.nat.pick(U32.is_eq(st, 0), out, err)}

# Whether a command exited 0, and its stdout (with stderr when it failed).
def Vk8s.nat.got(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> Sh:
  match r:
    case Fail{(c, m)}:
      Sh{False{}, m}
    case Done{(st, (out, err))}:
      Vk8s.nat.got.go(st, out, err)

def Vk8s.nat.ok_out.go(ok: Bool, +out: String) -> String:
  match ok:
    case True{}:
      out
    case False{}:
      ""

def Vk8s.nat.ok_out(r: Sh) -> String:
  match r:
    case Sh{ok, out}:
      Vk8s.nat.ok_out.go(ok, out)

# A command's stdout, "" when it failed (not its stderr).
def Vk8s.nat.out_ok(+prog: String, args: +List<String>) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run(prog, Vk8s.argv(args), "", 16777216, 60000)
    return Vk8s.nat.ok_out(Vk8s.nat.got(r))

# Run one argument list (no shell), printed first.
def Vk8s.nat.exec(argv: +List<String>, +input: String) -> IO(Sh):
  match argv:
    case Nil{}:
      IO.pure(Sh, Sh{True{}, ""})
    case Con{+prog, +args}:
      do IO<Sh>:
        Vk8s.say(NH.NHost.show(Con{prog, args}))
        r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run(prog, Vk8s.argv(args), input, 16777216, 600000)
        return Vk8s.nat.got(r)

# A program's stdout, not printed (reads only).
def Vk8s.nat.out(+prog: String, args: +List<String>) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run(prog, Vk8s.argv(args), "", 16777216, 60000)
    return Vk8s.raw.out(Vk8s.nat.got(r))

def Vk8s.nat.must.go(ok: Bool, +out: String, next: IO(Bool)) -> IO(Bool):
  match ok:
    case True{}:
      next
    case False{}:
      do IO<Bool>:
        IO.print_err(String.trim(out))
        return False{}

# The commands in order; the first failure stops them (False).
def Vk8s.nat.must(cmds: List<&2, List<&2, String>>) -> IO(Bool):
  match cmds:
    case Nil{}:
      IO.pure(Bool, True{})
    case Con{c, t}:
      do IO<Bool>:
        +r : Sh <- Vk8s.nat.exec(c, "")
        Vk8s.nat.must.go(Vk8s.sh_ok.of(r), Vk8s.raw.out(r), Vk8s.nat.must(t))

# Every command, a failure only noted (delete goes on).
def Vk8s.nat.try(cmds: List<&2, List<&2, String>>) -> IO(Unit):
  match cmds:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{c, t}:
      do IO<Unit>:
        +r : Sh <- Vk8s.nat.exec(c, "")
        Vk8s.unless(Vk8s.sh_ok.of(r), Vk8s.say("  (failed, going on: " ++ String.trim(Vk8s.raw.out(r)) ++ ")"))
        Vk8s.nat.try(t)

# A file of the user's (no shell, no sudo).
def Vk8s.nat.write(+path: String, +text: String) -> IO(Bool):
  do IO<Bool>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "w")
    I.Init.write.go(r, text)

# The kernel modules of these that are not loaded.
def Vk8s.nat.mods(ms: +List<String>) -> IO(List<&2, String>):
  match ms:
    case Nil{}:
      IO.pure(List<&2, String>, Nil{})
    case Con{+m, rest}:
      do IO<List<&2, String>>:
        have : Bool <- Vk8s.run_ok("test", ["-d", "/sys/module/" ++ m])
        +more : List<&2, String> <- Vk8s.nat.mods(rest)
        return Vk8s.missing.add(have, m, more)

def Vk8s.nat.mods_if(node: Bool) -> IO(List<&2, String>):
  match node:
    case True{}:
      Vk8s.nat.mods(NP.Netpol.native_modules())
    case False{}:
      IO.pure(List<&2, String>, Nil{})

def Vk8s.nat.resolv(resolved: Bool) -> String:
  match resolved:
    case True{}:
      "/run/systemd/resolve/resolv.conf"
    case False{}:
      "/etc/resolv.conf"

# The role sets, with the preloaded images when the assets have them.
def Vk8s.nat.sets(images: Bool) -> +List<String>:
  match images:
    case True{}:
      List.append(&2, String, NH.NHost.sets(), ["images"])
    case False{}:
      NH.NHost.sets()

def Vk8s.nat.node_note(node: Bool) -> String:
  match node:
    case True{}:
      "the control plane is also this host's node"
    case False{}:
      "control plane only: this host's node belongs to another cluster, or another kubelet runs here"

def Vk8s.nat.creating(+name: String, +ip: String, +port: U32, +data: String, node: Bool) -> String:
  "Creating vCluster " ++ name ++ " natively (API on " ++ ip ++ ":" ++ U32.show(port) ++ ", join server on " ++ ip ++ ":"
    ++ U32.show(NH.NHost.join_port(port)) ++ ", data in " ++ data ++ ", "
    ++ Vk8s.nat.node_note(node) ++ ")..."

def Vk8s.nat.failed(+name: String) -> IO(Unit):
  Vk8s.die("could not create vCluster " ++ name ++ "; `vk8s delete " ++ name ++ "` removes what was made")

# flannel's manifest for this host (NH.NHost.flannel), from the initramfs
# into the data dir.
def Vk8s.nat.flannel(+dir: String, +data: String) -> IO(Bool):
  do IO<Bool>:
    +r : Sh <- Vk8s.nat.exec(["sudo", "cat", data ++ "/initramfs/etc/vk8s/flannel.yaml"], "")
    +tmp : String = dir ++ "/flannel.yaml"
    w : Bool <- Vk8s.nat.write(tmp, NH.NHost.flannel(Vk8s.raw.out(r)))
    Vk8s.and_then(Bool.and(Vk8s.sh_ok.of(r), w),
      Vk8s.nat.must([["sudo", "install", "-D", "-m", "0644", tmp, data ++ "/etc/flannel.yaml"], ["sudo", "rm", "-rf", data ++ "/initramfs"],
        ["rm", "-f", tmp]]))

def Vk8s.nat.create(+name: String, +port0: U32, +etcd: Bool, +nodes: U32, +values: String, +parp: Bool) -> IO(Unit):
  do IO<Unit>:
    Vk8s.unless(U32.is_eq(nodes, 0), Vk8s.die(NH.NHost.nodes_msg(name)))
    +home : String <- Vk8s.home()
    +dir : String = C.Cli.dir(home, name)
    +data : String = NH.NHost.data_dir(name)
    exists : Bool <- Vk8s.run_ok("test", ["-e", dir])
    Vk8s.when(exists, Vk8s.die("vCluster " ++ name ++ " already exists"))
    Vk8s.unless(N.Native.env_ok.v2(N.Native.env_of(data, "", dir ++ "/share", "", "", "")),
      Vk8s.die("vk8s: " ++ dir ++ " must be an absolute path with only letters, digits and / . _ - + @ , : = for --backend native"))
    +assets : String <- Vk8s.assets(home)
    Vk8s.sets_ensure(home, assets, NH.NHost.sets())
    +upath : String <- Vk8s.getenv("PATH", "/usr/bin:/bin")
    +path : String = C.Cli.root_path(upath)
    +tools : List<&2, String> <- Vk8s.missing(path, NP.Netpol.native_tools())
    systemd : Bool <- Vk8s.run_ok("test", ["-d", "/run/systemd/system"])
    cg2 : Bool <- Vk8s.run_ok("test", ["-f", "/sys/fs/cgroup/cgroup.controllers"])
    # Another kubelet on the host (k3s, a kubeadm node) shares its
    # iptables chains and cgroups with a native cluster: refuse. Another
    # native cluster's (any user's) runs the host's node: control plane
    # only.
    +kls : String <- Vk8s.nat.out_ok("sudo", ["sh", "-c", NH.NHost.kubelets_script()])
    +foreign : List<&2, String> = NH.NHost.foreign_kubelets(kls)
    Vk8s.unless(List.is_empty(&2, String, foreign), Vk8s.die(NH.NHost.foreign_msg(foreign)))
    mine : Bool <- Vk8s.run_ok("grep", ["-r", "-q", "-x", "--include=cluster.env", "HOST_NODE=1", home ++ "/.vk8s/clusters"])
    +other : Bool = Bool.or(mine, Bool.not(List.is_empty(&2, String, NH.NHost.vk8s_kubelets(kls))))
    pods : Bool <- Vk8s.run_ok("test", ["-e", "/sys/fs/cgroup/kubepods"])
    +node : Bool = Bool.not(Bool.or(other, pods))
    +mods : List<&2, String> <- Vk8s.nat.mods_if(node)
    +fwd : String <- Vk8s.slurp("/proc/sys/net/ipv4/ip_forward")
    +bnf : String <- Vk8s.slurp("/proc/sys/net/bridge/bridge-nf-call-iptables")
    +arp : String <- Vk8s.slurp("/proc/sys/net/ipv4/conf/all/proxy_arp")
    +ndp : String <- Vk8s.slurp("/proc/sys/net/ipv6/conf/all/proxy_ndp")
    +msg : String = NH.NHost.preflight(tools, systemd, cg2, mods,
      List.append(&2, String, NH.NHost.sysctls_needed(node, fwd, bnf), NH.NHost.proxy_sysctls_needed(parp, node, arp, ndp)))
    Vk8s.unless(String.is_empty(msg), Vk8s.die(String.trim(msg)))
    have : Bool <- Vk8s.have_all([assets ++ "/vk8s.cpio", assets ++ "/node.img", assets ++ "/control-plane.img"])
    Vk8s.unless(have, Vk8s.die("vk8s assets not found in " ++ assets ++ " (vk8s.cpio, node.img, control-plane.img; set VK8S_ASSETS)"))
    images : Bool <- Vk8s.can_open(assets ++ "/images.img", "r")
    +route : String <- Vk8s.nat.out("ip", ["-4", "-o", "route", "get", "1.1.1.1"])
    +ip : String = NH.NHost.route_src(route)
    Vk8s.unless(NH.NHost.ip_ok(ip), Vk8s.die("vk8s: could not find this host's IPv4 address (ip -4 -o route get 1.1.1.1)"))
    resolved : Bool <- Vk8s.can_open("/run/systemd/resolve/resolv.conf", "r")
    +port : U32 <- Vk8s.free_port.v2(U32.is_eq(port0, 0), home, port0)
    +self : String <- Vk8s.self()
    +arch : String <- Vk8s.arch()
    +now : U32 <- Vk8s.epoch()
    Vk8s.say(Vk8s.nat.creating(name, ip, port, data, node))
    prep : Bool <- Vk8s.nat.must([["mkdir", "-p", dir ++ "/share"], ["chmod", "700", dir]])
    Vk8s.unless(prep, Vk8s.die("could not set up " ++ dir))
    env : Bool <- Vk8s.nat.write(dir ++ "/cluster.env", NH.NHost.env_text(name, port, etcd, ip, node) ++ NH.NHost.env_cgroup(name)
      ++ "CREATED=" ++ U32.show(now) ++ "\n")
    pf : Bool <- Vk8s.nat.write(dir ++ "/port", U32.show(port) ++ "\n")
    Vk8s.unless(Bool.and(env, pf), Vk8s.die("could not write " ++ dir ++ "/cluster.env"))
    vy : Bool <- Vk8s.values_files(values, dir)
    Vk8s.unless(vy, Vk8s.die("could not write the vcluster.yaml of " ++ name))
    ok1 : Bool <- Vk8s.nat.must(NH.NHost.prepare_cmds(data, assets, self, Vk8s.nat.sets(images)))
    Vk8s.unless(ok1, Vk8s.nat.failed(name))
    ok2 : Bool <- Vk8s.nat.flannel(dir, data)
    Vk8s.unless(ok2, Vk8s.nat.failed(name))
    +unit : String = dir ++ "/" ++ NH.NHost.unit_name(name)
    u : Bool <- Vk8s.nat.write(unit, NH.NHost.unit(NH.Inst{name, data, dir ++ "/share", ip, port, etcd, node, arch, Vk8s.nat.resolv(resolved)}))
    ok3 : Bool <- Vk8s.and_then(u, Vk8s.nat.must(NH.NHost.install_cmds(name, unit)))
    Vk8s.unless(ok3, Vk8s.nat.failed(name))
    up : Bool <- Vk8s.wait_file(1200n, dir ++ "/share/kubeconfig.yaml")
    Vk8s.unless(up, Vk8s.die("vCluster " ++ name ++ " did not come up; see `journalctl -u " ++ NH.NHost.unit_name(name) ++ "` and " ++ dir
      ++ "/share/logs"))
    Vk8s.own_kubeconfig(name, dir, port)
    Vk8s.say("Successfully created virtual cluster " ++ name ++ ". ")
    Vk8s.created_msg(name, dir)

# --- Native delete

def Vk8s.nat.kill_now(there: Bool, +cg: String) -> IO(Unit):
  match there:
    case False{}:
      IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        _ : Sh <- Vk8s.nat.exec(["sudo", "tee", cg ++ "/cgroup.kill"], "1\n")
        IO.sleep(2000)

# The pods' processes: the unit's stop ended its own (the control group);
# the pods run under the kubelet's cgroup root (NH.NHost.kill_dir: the
# cluster's own, or /kubepods for a cluster made before it had one),
# which cgroup.kill ends at once. cg "": none to end.
def Vk8s.nat.kill_pods(act: Bool, +cg: String) -> IO(Unit):
  match act:
    case False{}:
      IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        there : Bool <- Vk8s.run_ok("test", ["-e", cg ++ "/cgroup.kill"])
        Vk8s.nat.kill_now(there, cg)

def Vk8s.nat.cgroups.go(there: Bool, +cg: String, next: IO(Unit)) -> IO(Unit):
  match there:
    case False{}:
      IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        _ : Sh <- Vk8s.nat.exec(["sudo", "find", cg, "-depth", "-type", "d", "-delete"], "")
        IO.sleep(1000)
        next

# The emptied cgroups, removed (n tries: a cgroup goes once its last
# process has exited).
def Vk8s.nat.cgroups(n: Nat, +cg: String) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+p:
      do IO<Unit>:
        there : Bool <- Vk8s.run_ok("test", ["-e", cg])
        Vk8s.nat.cgroups.go(Bool.and(there, Bool.not(String.is_empty(cg))), cg, Vk8s.nat.cgroups(p, cg))

def Vk8s.nat.restore.go(empty: Bool, +stem: String, +text: String) -> IO(Unit):
  match empty:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        +r : Sh <- Vk8s.nat.exec(NH.NHost.ipt_restore_cmd(stem), text)
        Vk8s.unless(Vk8s.sh_ok.of(r), Vk8s.say("  (failed, going on: " ++ String.trim(Vk8s.raw.out(r)) ++ ")"))

def Vk8s.nat.clean_if(ok: Bool, +shared: Bool, +out: String) -> String:
  match ok:
    case True{}:
      NP.Netpol.ipt_clean.v2(shared, out)
    case False{}:
      ""

def Vk8s.nat.table(+shared: Bool, +stem: String) -> IO(Unit):
  do IO<Unit>:
    +r : Sh <- Vk8s.nat.exec(["sudo", stem ++ "-save"], "")
    +text : String = Vk8s.nat.clean_if(Vk8s.sh_ok.of(r), shared, Vk8s.raw.out(r))
    Vk8s.nat.restore.go(String.is_empty(text), stem, text)

# vk8s's chains and the rules that jump to them, by exact name, with
# <stem>-restore --noflush (NP.Netpol.ipt_clean.v2): kube-proxy's,
# flannel's, the CNI plugins' (cbr0), kube-router's and the network
# policy gate; only the gate while another kubelet runs (shared).
def Vk8s.nat.rules(+shared: Bool, ts: +List<String>) -> IO(Unit):
  match ts:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+stem, t}:
      do IO<Unit>:
        Vk8s.nat.table(shared, stem)
        Vk8s.nat.rules(shared, t)

def Vk8s.nat.node_clean(node: Bool, +shared: Bool, +cg: String) -> IO(Unit):
  match node:
    case False{}:
      IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        Vk8s.nat.cgroups(15n, cg)
        Vk8s.nat.rules(shared, NH.NHost.ipt_tools())
        # kube-router's ipsets by exact name, once no rule uses them
        +sets : String <- Vk8s.nat.out("sudo", ["ipset", "list", "-n"])
        Vk8s.nat.try(NP.Netpol.ipset_destroy.v2(shared, sets))

# Whether none of these paths exists.
def Vk8s.nat.gone(ps: +List<String>) -> IO(Bool):
  match ps:
    case Nil{}:
      IO.pure(Bool, True{})
    case Con{+p, t}:
      do IO<Bool>:
        there : Bool <- Vk8s.run_ok("test", ["-e", p])
        Vk8s.and_then(Bool.not(there), Vk8s.nat.gone(t))

# Delete (N3): stop the unit, end the pods, unmount what they left under
# the data dir, remove their cgroups and the iptables rules, then the data
# dir, the unit file, the host node's leftovers and the cluster dir
# (NH.NHost.delete_cmds; laws native.delete_leaves_nothing).
def Vk8s.nat.delete(+name: String, ctx: Bool, +dir: String) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +hn : String <- Vk8s.setting(dir, "HOST_NODE")
    +node : Bool = String.eq(hn, "1")
    +data : String = NH.NHost.data_dir(name)
    Vk8s.say("Deleting native vCluster " ++ name ++ " (" ++ data ++ ")...")
    Vk8s.nat.try(NH.NHost.stop_cmds(name))
    # The unit's own kubelet is gone now: any other one shares the host's
    # chains, ipsets and (for a cluster made before CGROUP) /kubepods.
    +kls : String <- Vk8s.nat.out_ok("sudo", ["sh", "-c", NH.NHost.kubelets_script()])
    +shared : Bool = Bool.not(String.is_empty(String.trim(kls)))
    Vk8s.when(Bool.and(node, shared), Vk8s.say(NH.NHost.shared_note(kls)))
    +cgs : String <- Vk8s.setting(dir, "CGROUP")
    +cg : String = NH.NHost.kill_dir(cgs, shared, name)
    Vk8s.nat.kill_pods(Bool.and(node, Bool.not(String.is_empty(cg))), cg)
    +mi : String <- Vk8s.nat.out("cat", ["/proc/self/mountinfo"])
    Vk8s.nat.try(NH.NHost.umount_cmds(NH.NHost.mounts_under(mi, data)))
    Vk8s.nat.node_clean(node, shared, cg)
    Vk8s.nat.try(NH.NHost.remove_cmds(name, dir, node))
    Vk8s.when(ctx, Vk8s.forget(name, home))
    gone : Bool <- Vk8s.nat.gone([data, NH.NHost.unit_path(name), dir])
    Vk8s.unless(gone, Vk8s.die("could not remove all of vCluster " ++ name ++ "; see the failed commands above"))
    Vk8s.say("Successfully deleted virtual cluster " ++ name)

def Vk8s.delete.pick(native: Bool, +name: String, ctx: Bool, +dir: String) -> IO(Unit):
  match native:
    case True{}:
      Vk8s.nat.delete(name, ctx, dir)
    case False{}:
      Vk8s.delete(name, ctx)

# delete by the backend the cluster's cluster.env records.
def Vk8s.delete.any(+name: String, ctx: Bool) -> IO(Unit):
  do IO<Unit>:
    +home : String <- Vk8s.home()
    +dir : String = C.Cli.dir(home, name)
    +b : String <- Vk8s.setting(dir, "BACKEND")
    Vk8s.delete.pick(String.eq(b, "native"), name, ctx, dir)

# `vk8s vmm`: a VM on a cluster's LAN starts only when the cluster
# records this binary's LAN wire version. This also stops a VM that a
# guest reset starts again from a newer vk8s binary on the same path.
@unsafe def Vk8s.vmm(+flags: +List<String>) -> IO(Unit):
  do IO<Unit>:
    +env : String <- Vk8s.slurp(LW.LanWire.env_path(flags))
    +msg : String = LW.LanWire.vmm_check(env)
    Vk8s.unless(String.is_empty(msg), Vk8s.die(msg))
    V.Vmm.run(["vk8s", "vmm"], Vk8s.lin(flags))

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
    case C.Delete{+name, +ctx}:
      Vk8s.by_backend(name, Vk8s.ctr.delete(name, ctx), Vk8s.delete.any(name, ctx))
    case C.List{}:
      Vk8s.ctr.list(False{})
    case C.ListJson{}:
      Vk8s.ctr.list(True{})
    case C.Describe{name, co, json}:
      Vk8s.describe(name, co, json)
    case C.Logs{name, comp}:
      Vk8s.logs(name, comp)
    case C.Snapshot{name, path}:
      Vk8s.snapshot(name, path)
    case C.SnapshotOpen{name, path}:
      Vk8s.snapshot_open(name, path)
    case C.Restore{+name, path}:
      Vk8s.then_connect(conn, name, Vk8s.restore(name, path))
    case C.Exec{name, cmd}:
      Vk8s.exec(name, cmd)
    case C.Cache{action}:
      Vk8s.cache(action)
    case C.CachePrune{regs}:
      Vk8s.cache_prune(regs)
    case C.AssetsPrune{dry}:
      Vk8s.assets_prune(dry)
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
    case C.Pause{+name}:
      Vk8s.by_backend(name, Vk8s.ctr.pause_x(name), Vk8s.vm.pause(name))
    case C.Resume{+name}:
      Vk8s.by_backend(name, Vk8s.ctr.resume_x(name), Vk8s.vm.resume(name))
    case C.Vmm{flags}:
      Vk8s.vmm(flags)
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

# --backend native: create runs natively; every other verb is the same as
# without the flag (delete, list and connect read the cluster's backend
# from its cluster.env).
def Vk8s.nat.values.create(c: C.Cmd, +etcd: Bool, +parp: Bool, +text: String) -> IO(Unit):
  match c:
    case C.Create{+name, port, cpus, mem, e0, nodes}:
      Vk8s.then_connect(True{}, name, Vk8s.nat.create(name, port, Bool.or(e0, etcd), nodes, text, parp))
    case C.NoConnect{C.Create{name, port, cpus, mem, e0, nodes}}:
      Vk8s.nat.create(name, port, Bool.or(e0, etcd), nodes, text, parp)
    case other:
      Vk8s.run.values.create(other, etcd, text, True{})

def Vk8s.nat.values.go(r: Result<&2, &2, String, J.Json>, +text: String, c: C.Cmd) -> IO(Unit):
  match r:
    case Fail{e}:
      Vk8s.die(e)
    case Done{+cfg}:
      do IO<Unit>:
        +why : String = VL.Values.unsupported.v2(cfg)
        Vk8s.unless(String.is_empty(why), Vk8s.die(why))
        Vk8s.nat.values.create(c, VL.Values.etcd(cfg), VL.Values.proxy_arp(cfg), text)

# create -f with --backend native: the vcluster.yaml checked as for a VM
# (Vk8s.run.values), on the cluster's share for the unit (NInit.values);
# vk8s.nodes.proxyArp joins the preflight's sysctls.
def Vk8s.nat.values(c: C.Cmd, +file: String) -> IO(Unit):
  do IO<Unit>:
    +got : Sh <- Vk8s.read(file)
    Vk8s.unless(Vk8s.sh_ok.of(got), Vk8s.die("could not read " ++ file))
    +text : String = Vk8s.raw.out(got)
    Vk8s.nat.values.go(CF.Config.parse(text), text, c)

@unsafe def Vk8s.nat.run(c: C.Cmd) -> IO(Unit):
  match c:
    case C.Create{+name, port, cpus, mem, etcd, nodes}:
      Vk8s.then_connect(True{}, name, Vk8s.nat.create(name, port, etcd, nodes, "", False{}))
    case C.NoConnect{C.Create{name, port, cpus, mem, etcd, nodes}}:
      Vk8s.nat.create(name, port, etcd, nodes, "", False{})
    case C.WithValues{inner, file}:
      Vk8s.nat.values(inner, file)
    case other:
      Vk8s.run(other)

# --backend vm (the default), container or native (B.Backend.parse; the
# effective default stays vm until the other backends' regression runs
# pass, docs/GOAL.md section 8).
@unsafe def Vk8s.run.pick(container: Bool, native: Bool, c: C.Cmd) -> IO(Unit):
  match container native:
    case True{} _:
      Vk8s.ctr.run(c, True{})
    case False{} True{}:
      Vk8s.nat.run(c)
    case False{} False{}:
      Vk8s.run(c)

@unsafe def Vk8s.run.backend(s: B.Selection) -> IO(Unit):
  match s:
    case B.Selected{+backend, c}:
      Vk8s.run.pick(String.eq(backend, "container"), String.eq(backend, "native"), c)

# argv[1] "native": the native supervisor (host/init.bend NInit), which a
# native cluster's systemd unit runs; "join-server": its /node/join server
# (host/join_server.bend), which that supervisor starts; anything else is
# the CLI.
# --idle-sleep D (src/cli/idle.bend): this program runs again without the
# flag and with VK8S_IDLE_SLEEP=D, so every create path reads one setting.
def Vk8s.main.exec(+xs: +List<String>) -> IO(Unit):
  do IO<Unit>:
    +rest : +List<String> = ID.Idle.drop_flag(xs)
    e : U32 <- Exec.run(Vk8s.self.prog(Vk8s.argv(rest)), Vk8s.argv(List.drop(&2, String, rest, 1n)), ID.Idle.env_name(), ID.Idle.flag(xs))
    Vk8s.die("vk8s: could not run again with " ++ ID.Idle.env_name() ++ " set (errno " ++ U32.show(e) ++ ")")

@unsafe def Vk8s.main.cli.go(flag: Bool, +xs: +List<String>) -> IO(Unit):
  match flag:
    case True{}:
      Vk8s.main.exec(xs)
    case False{}:
      Vk8s.run.backend(B.Backend.parse(List.drop(&2, String, xs, 1n)))

# argv[1] "layers" (hidden): `vk8s layers fill IMAGE` and `vk8s layers gc`,
# the host side of the shared read-only layer store (host/layers/fill.bend),
# so a host can be tested before the guest snapshotter uses it.
def Vk8s.layers(+xs: +List<String>) -> IO(Unit):
  do IO<Unit>:
    home : String <- Vk8s.home()
    arch : String <- Vk8s.arch()
    LF.Layers.main(xs, home, arch)

@unsafe def Vk8s.main.cli(layers: Bool, +xs: +List<String>) -> IO(Unit):
  match layers:
    case True{}:
      Vk8s.layers(xs)
    case False{}:
      Vk8s.main.cli.go(ID.Idle.has_flag(xs), xs)

# argv[1] "idle-proxy": a cluster's API forward (host/idle_proxy.bend),
# which create starts.
@unsafe def Vk8s.main.go(native: Bool, js: Bool, idle: Bool, +xs: +List<String>) -> IO(Unit):
  match native js idle:
    case True{} _ _:
      I.NInit.main(xs)
    case False{} True{} _:
      JS.JoinSrv.serve(JS.JoinSrv.cfg(xs))
    case False{} False{} True{}:
      IP.IdleP.main(xs)
    case False{} False{} False{}:
      Vk8s.main.cli(I.Init.is_mode(xs, "layers"), xs)

@unsafe def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +xs : +List<String> = Vk8s.plus(args)
    Vk8s.main.go(I.Init.is_mode(xs, "native"), I.Init.is_mode(xs, "join-server"), I.Init.is_mode(xs, "idle-proxy"), xs)
