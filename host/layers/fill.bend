import Base
import 0x2cb44898b57f05c48f38583063e077bf/main.bend as V
import 0x2cb44898b57f05c48f38583063e077bf/src/vmm/hostfiles.bend as HF
import bend-kube-runtime@0.12.0.0/src/sys.bend as SY
import ../../src/layers/pull.bend as P
import ../../src/layers/fill.bend as F
import ../../src/layers/store.bend as Y
import ../../src/layers/tar.bend as T
import ../../src/layers/meta.bend as M
import ../../src/layers/serve.bend as SV
import ../../src/oci/store.bend as S
import ../../src/oci/size.bend as N
import ../../src/guest/plan.bend as PL
import ../../src/oci/upstream.bend as OU
import ../../src/oci/auth.bend as OA
import ../oci/blob.bend as B
import ../oci/upstream.bend as UP
import ../oci/plain.bend as PC
import ../tls_server.bend as TS
import ../bin_file.bend as BF
import ./unpack.bend as U
import ./image.bend as LI
import ./fs.bend as L

# `vk8s layers fill IMAGE` and `vk8s layers gc`
# =============================================
#
# Hidden subcommands of the shared read-only layer store (docs/GOAL.md
# section 10), so a host can be tested before the guest snapshotter uses
# the store. Every decision is src/layers/'s; this file connects, reads,
# writes and prints.
#
# fill: the image's layers become ~/.vk8s/layers/<hex>, one directory
# per chain ID (src/layers/store.bend):
#   1. the reference is normalized (Pull.ref) and its registry must be
#      one vk8s pulls from (Plan.mirrors: docker.io, registry.k8s.io,
#      ghcr.io, quay.io);
#   2. the manifest comes from the registry itself (host/oci/upstream.bend:
#      TLS against the system's roots, an anonymous token for the
#      repository's pull scope, redirects; src/oci/upstream.bend decides),
#      by digest when the reference has one (checked); an index gives the
#      linux/<arch> manifest, fetched by its digest (checked);
#   3. the config, by digest (checked), gives the diffIDs, and with the
#      manifest's layers the chain IDs (Pull.fills);
#   4. under the layer's own lock, each layer whose record and directory
#      are both there (Fill.present.v2: lstat of the directory) is only
#      used again (its record touched); each other
#      one's blob comes from the OCI blob cache at
#      ~/.vk8s/oci (src/oci/store.bend), or is fetched into it with
#      OciBlob.fetch, which hashes the bytes as they land (digest and
#      size checked, then renamed into place with its sidecar), and is
#      unpacked and published (host/layers/unpack.bend; its tar is read
#      once: the diffID is hashed while the blob is decompressed).
#
# gc: removes the layers Lay.gc.drop says (no holder, 72 h since the
# last use; a layer without a readable record counts as unused), tmp
# entries a day old (Fill.stale.name) in ~/.vk8s/tmp and ~/.vk8s/oci/tmp,
# and the blob cache's expired blobs (Store.sweep, 72 h). A layer that a
# node holds is never removed: gc first reads every node's
# share/layers.held under ~/.vk8s/clusters (<cluster>/share and
# <cluster>/nodes/<worker>/share; the guest writes it, so BinFile.read_all
# reads it with O_NOFOLLOW and a 4 MiB limit, and Fill.held.parse keeps
# only well-formed chain IDs), and those layers count as held
# (Fill.hold). A stopped cluster's nodes keep holding theirs until the
# cluster is deleted.
#
# Locks (v2, below: Lf.fill.v2, Lf.gc.v2): each layer has its own lock,
# ~/.vk8s/layer-locks/<hex> (Fill.llock.path.v2: an O_EXCL create; a lock
# an hour old is taken over). A fill holds the lock of the layer it uses
# or publishes and waits while another fill holds it; gc tries the lock
# of each layer it would remove and skips a held one, so gc never removes
# a layer that a fill is about to use or publish, and neither fails on
# the other. The layers of one image are filled at once from one queue
# (Lf.layers.queue.v5: at most F.Fill.lanes.v5 lanes, biggest first).
# The store-wide ~/.vk8s/layers.lock of the first version (Lf.locked,
# Lf.fill, Lf.gc) is no longer taken.
#
# The image cache (`vk8s cache serve`): a fill asks it first when it
# answers (v4, below: Lf.fill.port.v4), so the filler and the nodes share
# one registry fetch per object; it needs only the registries when the
# cache does not run, so any host that runs vk8s can fill the store.

def Lf.R(-A: Type) -> Type:
  U.Lu.R(A)

def Lf.say(+s: String) -> IO(Unit):
  IO.print("vk8s layers: " ++ s)

def Lf.die(+s: String) -> IO(Unit):
  do IO<Unit>:
    IO.print_err("vk8s layers: " ++ s)
    IO.exit(1)

def Lf.said(+s: String) -> IO(Lf.R(Unit)):
  do IO<Lf.R(Unit)>:
    Lf.say(s)
    return Done{Unit{}}

def Lf.hi(s: N.Size) -> U32:
  U.Lu.hi(s)

def Lf.lo(s: N.Size) -> U32:
  U.Lu.lo(s)

def Lf.now.of(w: U32 & (U32 & U32)) -> U32:
  match w:
    case (d, (s, us)):
      ((d * 86400 : U32) + s : U32)

# The wall clock, in seconds since 1970.
def Lf.now() -> IO(U32):
  do IO<U32>:
    w : U32 & (U32 & U32) <- SY.Sys.wall()
    return Lf.now.of(w)

def Lf.code(+c: U32, +what: String) -> Lf.R(Unit):
  Bool.pick(Lf.R(Unit), U32.is_zero(c), Done{Unit{}}, Fail{what ++ " (errno " ++ U32.show(c) ++ ")"})

# A V.Fs call (0 or an errno) as a step.
def Lf.vfs(io: IO(U32), +what: String) -> IO(Lf.R(Unit)):
  IO.bind(U32, Lf.R(Unit), io, c => IO.pure(Lf.R(Unit), Lf.code(c, what)))

def Lf.mirrors(ms: +List<PL.Mirror>) -> List<&2, P.Mirror>:
  match ms:
    case Nil{}:
      Nil{}
    case Con{PL.Mirror{r, u, p}, t}:
      Con{P.Mirror{r, p}, Lf.mirrors(t)}

# The lock
# --------

def Lf.lock.held(+root: String) -> String:
  "another `vk8s layers fill` or `vk8s layers gc` holds " ++ F.Fill.lock.path(root) ++ "; retry when it ends (remove it if none runs; a lock "
    ++ U32.show((F.Fill.lock.ttl() / 60 : U32)) ++ " minutes old is taken over)"

def Lf.lock.old(stale: Bool, +root: String, retry: IO(Lf.R(Unit))) -> IO(Lf.R(Unit)):
  match stale:
    case False{}:
      IO.pure(Lf.R(Unit), Fail{Lf.lock.held(root)})
    case True{}:
      do IO<Lf.R(Unit)>:
        _ : U32 <- V.Fs.remove(F.Fill.lock.path(root))
        retry

def Lf.lock.busy(taken: Bool, e: U32 & String, +root: String, +now: U32, retry: IO(Lf.R(Unit))) -> IO(Lf.R(Unit)):
  match taken:
    case False{}:
      IO.pure(Lf.R(Unit), Fail{U.Lu.why("making " ++ F.Fill.lock.path(root), e)})
    case True{}:
      do IO<Lf.R(Unit)>:
        m : Maybe<&2, String> <- U.Lu.read(F.Fill.lock.path(root))
        Lf.lock.old(F.Fill.lock.stale.of(m, now), root, retry)

def Lf.lock.made(r: L.LayerFs.Res(Unit), +root: String, +now: U32, retry: IO(Lf.R(Unit))) -> IO(Lf.R(Unit)):
  match r:
    case Done{u}:
      IO.pure(Lf.R(Unit), Done{Unit{}})
    case Fail{e}:
      match e:
        case (+c, +m):
          Lf.lock.busy(U32.is_eq(c, L.LayerFs.eexist()), (c, m), root, now, retry)

# Takes <root>/layers.lock (Fill.lock): made with O_EXCL (LayerFs.make
# never makes a file over anything), or taken over when stale (left
# tries).
def Lf.lock(left: Nat, +root: String, +now: U32) -> IO(Lf.R(Unit)):
  match left:
    case 0n:
      IO.pure(Lf.R(Unit), Fail{Lf.lock.held(root)})
    case 1n+k:
      do IO<Lf.R(Unit)>:
        r : L.LayerFs.Res(Unit) <- L.LayerFs.make(L.LayerFs.file(), F.Fill.lock.path(root), T.Tar.b(F.Fill.lock.text(now)))
        Lf.lock.made(r, root, now, Lf.lock(k, root, now))

def Lf.unlock(+root: String) -> IO(Unit):
  IO.bind(U32, Unit, V.Fs.remove(F.Fill.lock.path(root)), c => IO.pure(Unit, Unit{}))

def Lf.locked.go(-A: Type, r: Lf.R(Unit), +root: String, io: IO(Lf.R(A))) -> IO(Lf.R(A)):
  match r:
    case Fail{e}:
      IO.pure(Lf.R(A), Fail{e})
    case Done{u}:
      do IO<Lf.R(A)>:
        x : Lf.R(A) <- io
        Lf.unlock(root)
        return x

# io with the store's lock held (the store's directories made first);
# the lock goes when io ends, failed or not.
def Lf.locked(-A: Type, +root: String, +now: U32, io: IO(Lf.R(A))) -> IO(Lf.R(A)):
  IO.bind(Lf.R(Unit), Lf.R(A), U.Lu.then(Unit, Unit, U.Lu.base(root), u => Lf.lock(3n, root, now)),
    r => Lf.locked.go(A, r, root, io))

# The registry
# ------------
#
# Every request goes to the registry itself (host/oci/upstream.bend:
# TLS, anonymous token auth, redirects). A fill pulls one repository: a
# Lup carries the registry's base URL and the Authorization the pull
# sends with each request (a token for the repository's pull scope, got
# once before the manifest; a request that still gets a 401 fetches a
# new one itself).

type Lup is Data:
  Lup{base: String, auth: String}

def Lf.closed(-A: Type, s: Socket, +e: String) -> IO(Lf.R(A)):
  do IO<Lf.R(A)>:
    TS.TlsSrv.close(s)
    return Fail{e}

def Lf.ok200.len(m: Maybe<&2, N.Size>, +what: String) -> Lf.R(N.Size):
  match m:
    case None{}:
      Fail{what ++ ": the registry sent no Content-Length"}
    case Some{n}:
      Done{n}

# A 200 with a Content-Length: the length; anything else: why not.
def Lf.ok200(+st: U32, l: Maybe<&2, N.Size>, +what: String) -> Lf.R(N.Size):
  Bool.pick(Lf.R(N.Size), U32.is_eq(st, 200), Lf.ok200.len(l, what), Fail{what ++ ": the registry answered HTTP " ++ U32.show(st)})

def Lf.token.got(r: UP.Upc.R(String), +base: String) -> IO(Lup):
  match r:
    case Done{a}:
      IO.pure(Lup, Lup{base, a})
    case Fail{e}:
      do IO<Lup>:
        Lf.say("no token before the pull (" ++ e ++ "); each request asks for its own")
        return Lup{base, ""}

def Lf.token.of(m: Maybe<&2, OA.Bearer>, +base: String, +repo: String) -> IO(Lup):
  match m:
    case None{}:
      IO.pure(Lup, Lup{base, ""})
    case Some{b}:
      IO.bind(UP.Upc.R(String), Lup, UP.Upc.token(OU.Up.repo_scoped(b, repo)), r => Lf.token.got(r, base))

def Lf.token.ping(r: UP.Upc.R(Socket & UP.Resp), +base: String, +repo: String) -> IO(Lup):
  match r:
    case Fail{e}:
      IO.pure(Lup, Lup{base, ""})
    case Done{(s, x)}:
      do IO<Lup>:
        TS.TlsSrv.close(s)
        Lf.token.of(UP.Upc.challenge(x, base), base, repo)

# Where a pull of repo from reg goes: the base URL, and a token for the
# repository's pull scope when the registry's /v2/ asks for one (a
# registry that needs none answers 200).
def Lf.up(+reg: String, +repo: String) -> IO(Lup):
  do IO<Lup>:
    +base : String <- UP.Upc.base(reg)
    r : UP.Upc.R(Socket & UP.Resp) <- UP.Upc.open(base ++ "/v2/", "*/*", "")
    Lf.token.ping(r, base, repo)

def Lf.url(up: Lup, +repo: String, +kind: String, +ref: String) -> String:
  match up:
    case Lup{b, a}:
      OU.Up.url(b, repo, kind, ref)

def Lf.auth(up: Lup) -> String:
  match up:
    case Lup{b, a}:
      a

# Manifests and configs
# ---------------------

def Lf.doc.verify(+digest: String, +bs: +List<U32>, +what: String) -> Lf.R(List<&2, U32>):
  Bool.pick(Lf.R(List<&2, U32>), String.is_empty(digest) || P.Pull.verified(digest, bs), Done{bs},
    Fail{what ++ ": the content is not " ++ digest})

def Lf.doc.got(r: UP.Upc.R(String & List<&2, U32>), +digest: String, +what: String) -> Lf.R(List<&2, U32>):
  match r:
    case Fail{e}:
      Fail{what ++ ": " ++ e}
    case Done{(a, bs)}:
      Lf.doc.verify(digest, bs, what)

# A manifest or a config (kind "manifests" or "blobs", at most 4 MiB) of
# repo, checked against digest unless digest is "".
def Lf.doc(+up: Lup, +repo: String, +kind: String, +ref: String, +accept: String, +digest: String, +what: String) -> IO(Lf.R(List<&2, U32>)):
  IO.bind(UP.Upc.R(String & List<&2, U32>), Lf.R(List<&2, U32>),
    UP.Upc.doc(Lf.url(up, repo, kind, ref), accept, Lf.auth(up), repo, P.Pull.doc_max()),
    r => IO.pure(Lf.R(List<&2, U32>), Lf.doc.got(r, digest, what)))

# A reference's digest, or "" for a tag.
def Lf.digest_of(+ref: String) -> String:
  Bool.pick(String, String.starts_with(ref, "sha256:"), ref, "")

def Lf.man.second(m: P.Man) -> Lf.R(P.Man):
  match m:
    case P.MIndex{d}:
      Fail{"the image index names another index: " ++ d}
    case P.MBad{w}:
      Fail{w}
    case P.MImage{c, ls}:
      Done{P.MImage{c, ls}}

def Lf.man.first(m: P.Man, +port: Lup, +repo: String, +arch: String) -> IO(Lf.R(P.Man)):
  match m:
    case P.MIndex{+d}:
      U.Lu.then(List<&2, U32>, P.Man, Lf.doc(port, repo, "manifests", d, P.Pull.accept(), d, "the manifest " ++ d),
        bs => IO.pure(Lf.R(P.Man), Lf.man.second(P.Pull.manifest(arch, T.Tar.s(bs)))))
    case P.MBad{w}:
      IO.pure(Lf.R(P.Man), Fail{w})
    case P.MImage{c, ls}:
      IO.pure(Lf.R(P.Man), Done{P.MImage{c, ls}})

# The image manifest of ref (a tag or a digest) for linux/arch.
def Lf.manifest(+port: Lup, +repo: String, +arch: String, +ref: String) -> IO(Lf.R(P.Man)):
  U.Lu.then(List<&2, U32>, P.Man, Lf.doc(port, repo, "manifests", ref, P.Pull.accept(), Lf.digest_of(ref), "the manifest " ++ ref),
    bs => Lf.man.first(P.Pull.manifest(arch, T.Tar.s(bs)), port, repo, arch))

def Lf.config.of(m: Maybe<&2, List<&2, String>>) -> Lf.R(List<&2, String>):
  match m:
    case None{}:
      Fail{"the image config has no layers rootfs with valid diffIDs"}
    case Some{ds}:
      Done{ds}

# The diffIDs of the config c.
def Lf.config(+port: Lup, +repo: String, c: P.Desc) -> IO(Lf.R(List<&2, String>)):
  match c:
    case P.Desc{m, +d, s}:
      U.Lu.then(List<&2, U32>, List<&2, String>, Lf.doc(port, repo, "blobs", d, "*/*", d, "the config " ++ d),
        bs => IO.pure(Lf.R(List<&2, String>), Lf.config.of(P.Pull.config(T.Tar.s(bs)))))

# Blobs
# -----

def Lf.blob.done(r: B.OciBlob.Res(Unit), d: B.OciBlob.Res(String), len: N.Size, +what: String) -> Lf.R(String & N.Size):
  match r d:
    case Fail{e} _:
      Fail{U.Lu.why(what, e)}
    case Done{u} Fail{e}:
      Fail{U.Lu.why(what, e)}
    case Done{u} Done{hex}:
      Done{(hex, len)}

def Lf.blob.commit(q: File & (Socket & B.OciBlob.Res(Unit)), len: N.Size, +what: String) -> IO(Lf.R(String & N.Size)):
  match q:
    case (f, (s, r)):
      do IO<Lf.R(String & N.Size)>:
        TS.TlsSrv.close(s)
        d : B.OciBlob.Res(String) <- B.OciBlob.commit(f)
        return Lf.blob.done(r, d, len, what)

def Lf.blob.created(c: B.OciBlob.Res(File), s: Socket, +b: +List<U32>, +len: N.Size, +t: String, +what: String) -> IO(Lf.R(String & N.Size)):
  match c:
    case Fail{e}:
      Lf.closed(String & N.Size, s, U.Lu.why("creating " ++ t, e))
    case Done{f}:
      do IO<Lf.R(String & N.Size)>:
        q : File & (Socket & B.OciBlob.Res(Unit)) <- B.OciBlob.fetch(f, s, b,
          Lf.hi(N.Size.sub(len, N.Size.of(F.Fill.count(b, 0)))), Lf.lo(N.Size.sub(len, N.Size.of(F.Fill.count(b, 0)))), 60000)
        Lf.blob.commit(q, len, what)

def Lf.blob.fits(over: Bool, +len: N.Size, s: Socket, +b: +List<U32>, +t: String, +what: String) -> IO(Lf.R(String & N.Size)):
  match over:
    case True{}:
      Lf.closed(String & N.Size, s, what ++ ": the registry sent more than its Content-Length")
    case False{}:
      do IO<Lf.R(String & N.Size)>:
        c : B.OciBlob.Res(File) <- B.OciBlob.create(t)
        Lf.blob.created(c, s, b, len, t, what)

def Lf.blob.sized(r: Lf.R(N.Size), s: Socket, +b: +List<U32>, +t: String, +what: String) -> IO(Lf.R(String & N.Size)):
  match r:
    case Fail{e}:
      Lf.closed(String & N.Size, s, e)
    case Done{+len}:
      Lf.blob.fits(N.Size.is_lt(len, N.Size.of(F.Fill.count(b, 0))), len, s, b, t, what)

def Lf.blob.head.lb(+st: U32, lb: Maybe<&2, N.Size> & List<&2, U32>, s: Socket, +t: String, +what: String) -> IO(Lf.R(String & N.Size)):
  match lb:
    case (l, +b):
      Lf.blob.sized(Lf.ok200(st, l, what), s, b, t, what)

def Lf.blob.head(h: U32 & (Maybe<&2, N.Size> & List<&2, U32>), s: Socket, +t: String, +what: String) -> IO(Lf.R(String & N.Size)):
  match h:
    case (st, lb):
      Lf.blob.head.lb(st, lb, s, t, what)

def Lf.blob.asked(r: UP.Upc.R(Socket & UP.Resp), +t: String, +what: String) -> IO(Lf.R(String & N.Size)):
  match r:
    case Fail{e}:
      IO.pure(Lf.R(String & N.Size), Fail{what ++ ": " ++ e})
    case Done{(s, x)}:
      Lf.blob.head(UP.Upc.parts(x), s, t, what)

# Fetches blob digest of repo from the registry into the file t: the hex
# SHA-256 of what came and its length.
def Lf.blob.get(+port: Lup, +repo: String, +digest: String, +t: String) -> IO(Lf.R(String & N.Size)):
  IO.bind(UP.Upc.R(Socket & UP.Resp), Lf.R(String & N.Size), UP.Upc.fetch(Lf.url(port, repo, "blobs", digest), "*/*", Lf.auth(port), repo),
    r => Lf.blob.asked(r, t, "the blob " ++ digest))

# Writes a blob's sidecar through tmp ++ ".meta" and a rename.
def Lf.side.put(+mp: String, +t: String, x: S.Meta) -> IO(Lf.R(Unit)):
  U.Lu.then(Unit, Unit, U.Lu.write(t ++ ".meta", S.Store.meta.render(x)),
    u => Lf.vfs(V.Fs.rename(t ++ ".meta", mp), "renaming the blob's sidecar to " ++ mp))

def Lf.blob.verified(ok: Bool, +now: U32, d: P.Desc, +b: String, +mp: String, +t: String) -> IO(Lf.R(String)):
  match ok d:
    case False{} P.Desc{m, dg, sz}:
      do IO<Lf.R(String)>:
        _ : U32 <- V.Fs.remove(t)
        return Fail{"the blob " ++ dg ++ " does not match its digest or size"}
    case True{} P.Desc{m, dg, sz}:
      U.Lu.then(Unit, String, Lf.vfs(V.Fs.mkdir_p(M.Meta.dir(b), 493), "making " ++ M.Meta.dir(b)),
        u => U.Lu.then(Unit, String, Lf.vfs(V.Fs.rename(t, b), "renaming the blob to " ++ b),
          v => U.Lu.then(Unit, String, Lf.side.put(mp, t, S.Store.meta.new(m, sz, now)),
            w => IO.pure(Lf.R(String), Done{b}))))

def Lf.blob.got(p: String & N.Size, +now: U32, +d: P.Desc, +b: String, +mp: String, +t: String) -> IO(Lf.R(String)):
  match p:
    case (hex, len):
      Lf.blob.verified(S.Store.verified(P.Desc.digest(d), hex, Some{P.Desc.size(d)}, len), now, d, b, mp, t)

def Lf.blob.clean(r: Lf.R(String), +t: String) -> IO(Lf.R(String)):
  match r:
    case Done{x}:
      IO.pure(Lf.R(String), Done{x})
    case Fail{e}:
      do IO<Lf.R(String)>:
        _ : U32 <- V.Fs.remove(t)
        return Fail{e}

def Lf.blob.fetch(+port: Lup, +repo: String, +root: String, +now: U32, +d: P.Desc, +b: String, +mp: String, +t: String) -> IO(Lf.R(String)):
  IO.bind(Lf.R(String), Lf.R(String),
    U.Lu.then(Unit, String, Lf.vfs(V.Fs.mkdir_p(root ++ "/oci/tmp", 493), "making " ++ root ++ "/oci/tmp"),
      u => U.Lu.then(String & N.Size, String, Lf.blob.get(port, repo, P.Desc.digest(d), t),
        p => Lf.blob.got(p, now, d, b, mp, t))),
    r => Lf.blob.clean(r, t))

def Lf.blob.meta(m: Maybe<&2, String>, +now: U32) -> Maybe<&2, S.Meta>:
  match m:
    case None{}:
      None{}
    case Some{s}:
      S.Store.hit(s, now)

def Lf.blob.file(f: HF.Facts) -> Bool:
  match f:
    case HF.Facts{k, z, m}:
      U32.is_eq(k, 2)

# The image cache's copy (`vk8s cache`, src/oci/store.bend at
# <root>/cache/store, the same layout): a blob it holds, fresh and on
# disk, is used where it lies (its digest was checked when the cache
# stored it, and Lf.blob.drop removes only <root>/oci paths), so a fill
# with the cache warm reads no registry. Else the registry, as before.
def Lf.blob.cached.got(m: Maybe<&2, S.Meta>, on_disk: Bool, +cb: String, +port: Lup, +repo: String, +root: String, +now: U32, +d: P.Desc,
  +b: String, +mp: String, +t: String) -> IO(Lf.R(String)):
  match m:
    case Some{x}:
      Bool.pick(IO(Lf.R(String)), on_disk, IO.pure(Lf.R(String), Done{cb}), Lf.blob.fetch(port, repo, root, now, d, b, mp, t))
    case None{}:
      Lf.blob.fetch(port, repo, root, now, d, b, mp, t)

def Lf.blob.cached(c: Maybe<&2, S.Paths>, +port: Lup, +repo: String, +root: String, +now: U32, +d: P.Desc, +b: String, +mp: String, +t: String) ->
  IO(Lf.R(String)):
  match c:
    case None{}:
      Lf.blob.fetch(port, repo, root, now, d, b, mp, t)
    case Some{S.Paths{+cb, +cmp, +ct}}:
      do IO<Lf.R(String)>:
        side : Maybe<&2, String> <- U.Lu.read(cmp)
        f : HF.Facts <- V.Fs.facts(cb)
        Lf.blob.cached.got(Lf.blob.meta(side, now), Lf.blob.file(f), cb, port, repo, root, now, d, b, mp, t)

def Lf.blob.hit(m: Maybe<&2, S.Meta>, +port: Lup, +reg: String, +repo: String, +root: String, +now: U32, +d: P.Desc, +b: String, +mp: String, +t: String) ->
  IO(Lf.R(String)):
  match m:
    case Some{x}:
      U.Lu.then(Unit, String, Lf.side.put(mp, t, x), u => IO.pure(Lf.R(String), Done{b}))
    case None{}:
      Lf.blob.cached(S.Store.paths(root ++ "/cache/store", reg, P.Desc.digest(d), now), port, repo, root, now, d, b, mp, t)

def Lf.blob.paths(m: Maybe<&2, S.Paths>, +port: Lup, +reg: String, +repo: String, +root: String, +now: U32, +d: P.Desc) -> IO(Lf.R(String)):
  match m:
    case None{}:
      IO.pure(Lf.R(String), Fail{"no blob cache path for " ++ P.Desc.digest(d)})
    case Some{S.Paths{+b, +mp, +t}}:
      do IO<Lf.R(String)>:
        side : Maybe<&2, String> <- U.Lu.read(mp)
        Lf.blob.hit(Lf.blob.meta(side, now), port, reg, repo, root, now, d, b, mp, t)

# The path of layer blob d in the OCI blob cache (<root>/oci): there
# already (its last use recorded), or fetched into it.
def Lf.blob(+port: Lup, +reg: String, +repo: String, +root: String, +now: U32, +d: P.Desc) -> IO(Lf.R(String)):
  Lf.blob.paths(S.Store.paths(root ++ "/oci", reg, P.Desc.digest(d), now), port, reg, repo, root, now, d)

# Layers
# ------

def Lf.chains.put(m: Maybe<&2, String>, rest: List<&2, String>) -> List<&2, String>:
  match m:
    case None{}:
      rest
    case Some{c}:
      Con{c, rest}

# The chain IDs of a directory's names that the store makes.
def Lf.chains(ns: List<String>) -> List<&2, String>:
  match ns:
    case Nil{}:
      Nil{}
    case Con{+n, t}:
      Lf.chains.put(F.Fill.chain_of(n), Lf.chains(t))

def Lf.fill.chain(f: P.Fill) -> String:
  match f:
    case P.Fill{c, d, p, b, k}:
      c

def Lf.fill.desc(f: P.Fill) -> P.Desc:
  match f:
    case P.Fill{c, d, p, b, k}:
      b

def Lf.layer.unpack(+root: String, +now: U32, +fl: P.Fill, +blob: String) -> IO(Lf.R(Unit)):
  U.Lu.then(String, Unit, U.Lu.publish(root, now, fl, blob), how => Lf.said(Lf.fill.chain(fl) ++ " " ++ how))

def Lf.layer.have(m: Maybe<&2, Y.Layer>, +port: Lup, +reg: String, +repo: String, +root: String, +now: U32, +fl: P.Fill) -> IO(Lf.R(Unit)):
  match m:
    case Some{l}:
      U.Lu.then(Unit, Unit, U.Lu.rec.use(root, now, l), u => Lf.said(Lf.fill.chain(fl) ++ " present"))
    case None{}:
      U.Lu.then(String, Unit, Lf.blob(port, reg, repo, root, now, Lf.fill.desc(fl)), blob => Lf.layer.unpack(root, now, fl, blob))

# One layer: used again when the store has it (its record and its
# directory), else filled. The lock's time is written again first, so a
# long fill never holds a lock that looks stale.
def Lf.layer(+port: Lup, +reg: String, +repo: String, +root: String, +now: U32, +fl: P.Fill) -> IO(Lf.R(Unit)):
  do IO<Lf.R(Unit)>:
    t : U32 <- Lf.now()
    _ : Lf.R(Unit) <- U.Lu.write(F.Fill.lock.path(root), F.Fill.lock.text(t))
    m : Maybe<&2, Y.Layer> <- U.Lu.rec.get(root, Lf.fill.chain(fl))
    ns : List<String> <- V.Fs.ls(root ++ "/layers")
    Lf.layer.have(F.Fill.present(m, Y.Lay.holds(Lf.chains(ns), Lf.fill.chain(fl))), port, reg, repo, root, now, fl)

# Each layer in order (a layer's parent is filled before it); how many.
def Lf.layers(fs: List<&2, P.Fill>, +port: Lup, +reg: String, +repo: String, +root: String, +now: U32, +n: U32) -> IO(Lf.R(U32)):
  match fs:
    case Nil{}:
      IO.pure(Lf.R(U32), Done{n})
    case Con{fl, t}:
      U.Lu.then(Unit, U32, Lf.layer(port, reg, repo, root, now, fl), u => Lf.layers(t, port, reg, repo, root, now, (n + 1 : U32)))

def Lf.fills.of(m: Maybe<&2, List<&2, P.Fill>>) -> Lf.R(List<&2, P.Fill>):
  match m:
    case None{}:
      Fail{"the image config's diffIDs and the manifest's layers differ in number"}
    case Some{fs}:
      Done{fs}

def Lf.image.man(m: P.Man, +port: Lup, +reg: String, +repo: String, +root: String, +now: U32) -> IO(Lf.R(U32)):
  match m:
    case P.MImage{c, ls}:
      U.Lu.then(List<&2, String>, U32, Lf.config(port, repo, c),
        ds => U.Lu.then(List<&2, P.Fill>, U32, IO.pure(Lf.R(List<&2, P.Fill>), Lf.fills.of(P.Pull.fills(ds, ls))),
          fs => Lf.layers(fs, port, reg, repo, root, now, 0)))
    case _:
      IO.pure(Lf.R(U32), Fail{"not an image manifest"})

def Lf.image(+port: Lup, +reg: String, +repo: String, +ref: String, +arch: String, +root: String, +now: U32) -> IO(Lf.R(U32)):
  U.Lu.then(P.Man, U32, Lf.manifest(port, repo, arch, ref), m => Lf.image.man(m, port, reg, repo, root, now))

def Lf.fill.port(m: Maybe<&2, U32>, +reg: String, +repo: String, +ref: String, +arch: String, +root: String, +now: U32) -> IO(Lf.R(U32)):
  match m:
    case None{}:
      IO.pure(Lf.R(U32), Fail{reg ++ " is not a registry vk8s pulls from (docker.io, registry.k8s.io, ghcr.io, quay.io)"})
    case Some{p}:
      IO.bind(Lup, Lf.R(U32), Lf.up(reg, repo), up => Lf.image(up, reg, repo, ref, arch, root, now))

def Lf.fill.ref(m: Maybe<&2, P.Img>, +image: String, +arch: String, +root: String, +now: U32) -> IO(Lf.R(U32)):
  match m:
    case None{}:
      IO.pure(Lf.R(U32), Fail{"not a valid image reference: " ++ image})
    case Some{P.Img{+reg, repo, ref, dig}}:
      Lf.fill.port(P.Pull.port(Lf.mirrors(PL.Plan.mirrors()), reg), reg, repo, ref, arch, root, now)

def Lf.fill.end(r: Lf.R(U32), +image: String, +root: String) -> IO(Unit):
  match r:
    case Fail{e}:
      Lf.die(image ++ ": " ++ e)
    case Done{n}:
      Lf.say(image ++ ": " ++ U32.show(n) ++ " layers in " ++ root ++ "/layers")

def Lf.fill.arch(known: Bool, +image: String, +arch: String, +root: String) -> IO(Unit):
  match known:
    case False{}:
      Lf.die("this host's architecture is not arm64 or amd64")
    case True{}:
      do IO<Unit>:
        +now : U32 <- Lf.now()
        r : Lf.R(U32) <- Lf.locked(U32, root, now, Lf.fill.ref(P.Pull.ref(image), image, arch, root, now))
        Lf.fill.end(r, image, root)

# `vk8s layers fill IMAGE` with the store at root, for linux/arch.
def Lf.fill(+image: String, +arch: String, +root: String) -> IO(Unit):
  Lf.fill.arch(String.eq(arch, "arm64") || String.eq(arch, "amd64"), image, arch, root)

# Garbage collection
# ------------------

def Lf.more.put(held: Bool, +r: String, rest: List<&2, String>) -> List<&2, String>:
  match held:
    case True{}:
      rest
    case False{}:
      Con{r, rest}

# rs's chain IDs that ds does not hold, then ds (one recursion a step).
def Lf.more(rs: List<&2, String>, +ds: List<&2, String>) -> List<&2, String>:
  match rs:
    case Nil{}:
      ds
    case Con{+r, t}:
      Lf.more.put(Y.Lay.holds(ds, r), r, Lf.more(t, ds))

# What the store knows of each chain ID (Fill.or.v2).
def Lf.gc.read(cs: List<&2, String>, +root: String) -> IO(List<&2, Y.Layer>):
  match cs:
    case Nil{}:
      IO.pure(List<&2, Y.Layer>, Nil{})
    case Con{+c, t}:
      do IO<List<&2, Y.Layer>>:
        m : Maybe<&2, String> <- U.Lu.read(Maybe.default(&2, String, F.Fill.rec.path(root, c), ""))
        ys : List<&2, Y.Layer> <- Lf.gc.read(t, root)
        return Con{F.Fill.or.v2(c, m), ys}

def Lf.gc.drop.one(+c: String, +root: String, rest: IO(U32)) -> IO(U32):
  do IO<U32>:
    U.Lu.drop(Maybe.default(&2, String, Y.Lay.dir(root, c), ""))
    U.Lu.drop(Maybe.default(&2, String, Y.Lay.img.v3(root, c), ""))
    U.Lu.drop(Maybe.default(&2, String, F.Fill.rec.path(root, c), ""))
    U.Lu.drop(Maybe.default(&2, String, F.Fill.rec.share(root, c), ""))
    Lf.say("removed " ++ c)
    k : U32 <- rest
    return (k + 1 : U32)

# Removes each layer, its directory first, then its record and the
# nodes' copy of it: how many.
def Lf.gc.drop(ls: List<&2, Y.Layer>, +root: String) -> IO(U32):
  match ls:
    case Nil{}:
      IO.pure(U32, 0)
    case Con{l, t}:
      Lf.gc.drop.one(Y.Layer.chain(l), root, Lf.gc.drop(t, root))

def Lf.gc.tmp.one(stale: Bool, +path: String, rest: IO(U32)) -> IO(U32):
  match stale:
    case False{}:
      rest
    case True{}:
      do IO<U32>:
        U.Lu.drop(path)
        k : U32 <- rest
        return (k + 1 : U32)

# Removes the stale entries of a tmp directory: how many.
def Lf.gc.tmp(ns: List<String>, +dir: String, +now: U32) -> IO(U32):
  match ns:
    case Nil{}:
      IO.pure(U32, 0)
    case Con{+x, t}:
      Lf.gc.tmp.one(F.Fill.stale.name(x, now), dir ++ "/" ++ x, Lf.gc.tmp(t, dir, now))

def Lf.items.one(skip: Bool, +n: String, +reg: String, +dir: String, rest: IO(List<&2, S.Item>)) -> IO(List<&2, S.Item>):
  match skip:
    case True{}:
      rest
    case False{}:
      do IO<List<&2, S.Item>>:
        m : Maybe<&2, String> <- U.Lu.read(dir ++ "/" ++ n ++ ".meta")
        xs : List<&2, S.Item> <- rest
        return Con{S.Item{reg, "sha256:" ++ n, m}, xs}

# The blobs of one <ab> directory of the blob cache, with their sidecars.
def Lf.items.ab(ns: List<String>, +reg: String, +dir: String) -> IO(List<&2, S.Item>):
  match ns:
    case Nil{}:
      IO.pure(List<&2, S.Item>, Nil{})
    case Con{+n, t}:
      Lf.items.one(String.ends_with(n, ".meta"), n, reg, dir, Lf.items.ab(t, reg, dir))

def Lf.items.abs(ns: List<String>, +reg: String, +dir: String) -> IO(List<&2, S.Item>):
  match ns:
    case Nil{}:
      IO.pure(List<&2, S.Item>, Nil{})
    case Con{+n, t}:
      do IO<List<&2, S.Item>>:
        fs : List<String> <- V.Fs.ls(dir ++ "/" ++ n)
        xs : List<&2, S.Item> <- Lf.items.ab(fs, reg, dir ++ "/" ++ n)
        ys : List<&2, S.Item> <- Lf.items.abs(t, reg, dir)
        return List.append(&2, S.Item, xs, ys)

# Every blob of the blob cache at oci, by registry.
def Lf.items.regs(ns: List<String>, +oci: String) -> IO(List<&2, S.Item>):
  match ns:
    case Nil{}:
      IO.pure(List<&2, S.Item>, Nil{})
    case Con{+n, t}:
      do IO<List<&2, S.Item>>:
        subs : List<String> <- V.Fs.ls(oci ++ "/" ++ n ++ "/blobs/sha256")
        xs : List<&2, S.Item> <- Lf.items.abs(subs, n, oci ++ "/" ++ n ++ "/blobs/sha256")
        ys : List<&2, S.Item> <- Lf.items.regs(t, oci)
        return List.append(&2, S.Item, xs, ys)

def Lf.rm.files(ps: List<&2, String>, +n: U32) -> IO(U32):
  match ps:
    case Nil{}:
      IO.pure(U32, n)
    case Con{+p, t}:
      do IO<U32>:
        c : U32 <- V.Fs.remove(p)
        Lf.rm.files(t, (n + Bool.to_u32(U32.is_zero(c)) : U32))

def Lf.held.got(r: BF.BinFile.Res(List<&2, U32>)) -> List<&2, String>:
  match r:
    case Fail{e}:
      Nil{}
    case Done{bs}:
      F.Fill.held.parse(T.Tar.s(bs))

# The chain IDs one node's layers.held names: the guest wrote it, so it
# is read without following a symlink, at most Fill.held.max() bytes, and
# parsed strictly. A missing, unreadable or oversized file names none.
def Lf.held.read(+path: String) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    r : BF.BinFile.Res(List<&2, U32>) <- BF.BinFile.read_all(path, F.Fill.held.max())
    return Lf.held.got(r)

# The held layers of a cluster's workers (dir: <cluster>/nodes).
def Lf.held.nodes(ws: List<String>, +dir: String) -> IO(List<&2, String>):
  match ws:
    case Nil{}:
      IO.pure(List<&2, String>, Nil{})
    case Con{+w, t}:
      do IO<List<&2, String>>:
        a : List<&2, String> <- Lf.held.read(dir ++ "/" ++ w ++ "/share/layers.held")
        b : List<&2, String> <- Lf.held.nodes(t, dir)
        return List.append(&2, String, a, b)

# The held layers of every node of every cluster under dir
# (~/.vk8s/clusters): <cluster>/share/layers.held for the control plane,
# <cluster>/nodes/<worker>/share/layers.held for each worker (Cli.dir,
# Cli.node_dir). Only host-made directories are listed; nothing inside a
# share is walked.
def Lf.held(cs: List<String>, +dir: String) -> IO(List<&2, String>):
  match cs:
    case Nil{}:
      IO.pure(List<&2, String>, Nil{})
    case Con{+c, t}:
      do IO<List<&2, String>>:
        a : List<&2, String> <- Lf.held.read(dir ++ "/" ++ c ++ "/share/layers.held")
        ws : List<String> <- V.Fs.ls(dir ++ "/" ++ c ++ "/nodes")
        b : List<&2, String> <- Lf.held.nodes(ws, dir ++ "/" ++ c ++ "/nodes")
        r : List<&2, String> <- Lf.held(t, dir)
        return List.append(&2, String, a, List.append(&2, String, b, r))

def Lf.gc.end(r: Lf.R(Unit)) -> IO(Unit):
  match r:
    case Fail{e}:
      Lf.die("gc: " ++ e)
    case Done{u}:
      IO.pure(Unit, Unit{})

# `vk8s layers gc` with the store at root, the lock held.
def Lf.gc.run(+root: String, +now: U32) -> IO(Lf.R(Unit)):
  do IO<Lf.R(Unit)>:
    cs : List<String> <- V.Fs.ls(root ++ "/clusters")
    hs : List<&2, String> <- Lf.held(cs, root ++ "/clusters")
    ds : List<String> <- V.Fs.ls(root ++ "/layers")
    rs : List<String> <- V.Fs.ls(root ++ "/layer-refs")
    ls : List<&2, Y.Layer> <- Lf.gc.read(Lf.more(Lf.chains(rs), Lf.chains(ds)), root)
    n : U32 <- Lf.gc.drop(Y.Lay.gc.drop(F.Fill.hold(ls, hs), now), root)
    ts : List<String> <- V.Fs.ls(root ++ "/tmp")
    k : U32 <- Lf.gc.tmp(ts, root ++ "/tmp", now)
    os : List<String> <- V.Fs.ls(root ++ "/oci/tmp")
    j : U32 <- Lf.gc.tmp(os, root ++ "/oci/tmp", now)
    regs : List<String> <- V.Fs.ls(root ++ "/oci")
    items : List<&2, S.Item> <- Lf.items.regs(regs, root ++ "/oci")
    b : U32 <- Lf.rm.files(S.Store.sweep(root ++ "/oci", now, items), 0)
    Lf.say("gc removed " ++ U32.show(n) ++ " layers, " ++ U32.show((k + j : U32)) ++ " tmp entries and " ++ U32.show(b) ++ " blob cache files")
    return Done{Unit{}}

# `vk8s layers gc` with the store at root.
def Lf.gc(+root: String) -> IO(Unit):
  do IO<Unit>:
    +now : U32 <- Lf.now()
    r : Lf.R(Unit) <- Lf.locked(Unit, root, now, Lf.gc.run(root, now))
    Lf.gc.end(r)

# Fill and gc with per-layer locks (v2)
# -------------------------------------
#
# `vk8s layers fill` and `vk8s layers gc` run these (W4 of
# docs/ref/explore-layers-autofill.md). Neither takes <root>/layers.lock
# any more, so a stale one blocks nothing.
#
# fill: each layer is filled under its own lock (U.Lu.layer.v2: it waits
# while another fill holds the lock, then checks present again with
# lstat), so three fills of one layer publish it once and the others find
# it present. The blob is fetched only under the lock and only when the
# layer is not there. The layers of an image go in two halves at once
# (Fill.split.v2 of their chain IDs; IO.fork), the lower layers in one,
# the upper in the other, each half in order. Parent before child is not
# needed across the halves (nor across v5's lanes, below: one queue,
# biggest layer first, that a few lanes share): a layer's directory is
# its own diff, named by its chain ID, which already names every layer under it, and nothing
# in the unpack reads the parent's directory. A node stacks the
# directories itself (containerd prepares parents first, and a parent
# the store lacks is unpacked on the node), so a child published before
# its parent, or without it when the parent's fill failed, is still that
# exact layer. An automatic fill (auto) removes the layer's blob from
# <root>/oci once it published the layer (Fill.blob.drop.v2), and lapses
# the image cache's copy of it (Lf.blob.lapse: gone 10 minutes later
# unless a node asks the cache for it), so an image is not kept twice,
# compressed in the cache and as layers in the store; the CLI's fill
# does neither.
#
# gc: the plan without locks (Fill.gc.plan.v2), then for each layer it
# would remove: its lock tried once (U.Lu.llock.try; a lock 60 minutes
# old is taken over), and a layer whose lock another process holds is
# skipped this time; under the lock, the layer's record and every node's
# layers.held are read again and the layer goes only when the plan still
# says so (Fill.gc.recheck.v2).

def Lf.blob.drop.paths(m: Maybe<&2, S.Paths>) -> IO(Unit):
  match m:
    case None{}:
      IO.pure(Unit, Unit{})
    case Some{S.Paths{+b, +mp, +t}}:
      do IO<Unit>:
        _ : U32 <- V.Fs.remove(mp)
        _ : U32 <- V.Fs.remove(b)
        return Unit{}

# Removes blob digest of reg from the blob cache: its sidecar first, so
# no fill takes a sidecar without its blob for a hit.
def Lf.blob.drop(+root: String, +reg: String, +digest: String, +now: U32) -> IO(Unit):
  Lf.blob.drop.paths(S.Store.paths(root ++ "/oci", reg, digest, now))

def Lf.blob.lapse.text(side: Maybe<&2, String>, +now: U32) -> Maybe<&2, String>:
  match side:
    case None{}:
      None{}
    case Some{s}:
      S.Store.lapse.sidecar(s, now)

# Writes the sidecar text at mp through the filler's tmp file t ++ ".meta"
# and a rename: whether it is there now.
def Lf.blob.lapse.put(m: Maybe<&2, String>, +mp: String, +t: String) -> IO(Bool):
  match m:
    case None{}:
      IO.pure(Bool, False{})
    case Some{text}:
      do IO<Bool>:
        _ : U.Lu.R(Unit) <- U.Lu.write(t ++ ".meta", text)
        +e : U32 <- V.Fs.rename(t ++ ".meta", mp)
        _ : U32 <- V.Fs.remove(t ++ ".meta")
        return U32.is_zero(e)

def Lf.blob.lapse.paths(c: Maybe<&2, S.Paths>, o: Maybe<&2, S.Paths>, +now: U32) -> IO(Bool):
  match c o:
    case Some{S.Paths{cb, +cmp, ct}} Some{S.Paths{b, mp, +t}}:
      do IO<Bool>:
        side : Maybe<&2, String> <- U.Lu.read(cmp)
        Lf.blob.lapse.put(Lf.blob.lapse.text(side, now), cmp, t)
    case _ _:
      IO.pure(Bool, False{})

# The image cache's copy of blob digest of reg (<root>/cache/store), once
# the layer store holds its layer: not kept twice for 72 h. Its sidecar's
# last use is set back (Store.lapse), so the cache's hourly sweep removes
# the blob Store.lapse.grace() from now, unless a node asks the cache for
# it first (a hit records its use and keeps it 72 h, as always). Nodes on
# the layer store never do: the snapshotter says the layer is there, and
# containerd fetches no blob for it (docs/ref/layers-compress.md). The
# blob itself is not touched, so a request the cache is serving, or one
# that comes before the sweep, gets it whole; after the sweep the cache
# fetches it from the registry again, as for any blob that expired.
# Whether a sidecar was written (none: the cache does not hold the blob).
def Lf.blob.lapse(+root: String, +reg: String, +digest: String) -> IO(Bool):
  do IO<Bool>:
    +now : U32 <- Lf.now()
    Lf.blob.lapse.paths(S.Store.paths(root ++ "/cache/store", reg, digest, now), S.Store.paths(root ++ "/oci", reg, digest, now), now)

def Lf.layer.v2.end(drop: Bool, +how: String, +root: String, +reg: String, +now: U32, +fl: P.Fill) -> IO(Lf.R(Unit)):
  match drop:
    case True{}:
      do IO<Lf.R(Unit)>:
        Lf.blob.drop(root, reg, P.Desc.digest(Lf.fill.desc(fl)), now)
        lapsed : Bool <- Lf.blob.lapse(root, reg, P.Desc.digest(Lf.fill.desc(fl)))
        Lf.said(Lf.fill.chain(fl) ++ " " ++ how ++ " (its blob removed from " ++ root ++ "/oci"
          ++ Bool.pick(String, lapsed, "; the image cache's copy goes in " ++ U32.show(U32.div(S.Store.lapse.grace(), 60)) ++ " min unless a node asks for it", "") ++ ")")
    case False{}:
      Lf.said(Lf.fill.chain(fl) ++ " " ++ how)

def Lf.layer.v2.how(+how: String, +auto: Bool, +root: String, +reg: String, +now: U32, +fl: P.Fill) -> IO(Lf.R(Unit)):
  Lf.layer.v2.end(F.Fill.blob.drop.v2(auto, how), how, root, reg, now, fl)

# Per-phase times (work item W7)
# ------------------------------
#
# A v2 fill times each layer it unpacks, in wall-clock ms
# (SV.Srv.ms.v2 of two Sys.wall readings), and logs one line a layer
# (SV.Srv.phases.line.v2) and one an image, the phases summed over its
# layers (SV.Srv.fill.line.v2; the serve daemon logs it, the CLI prints
# the sum). The phases:
#   fetch       the blob from the blob cache, or fetched into it (Lf.blob);
#   decompress  the blob to a tar, hashed as it is written
#               (U.Lu.tar.sniffed), and the tar's diffID check
#               (U.Lu.diff.have: no read of a decompressed tar; its own
#               log line, SV.Srv.diff.line);
#   unpack      the tar's entries (U.Lu.loop) and each directory's
#               .bend-meta (Fill.sides), the tar closed;
#   fsync       every directory of the layer (Fill.syncs, U.Lu.syncs);
#   rename      the records, the rename into place and the fsync of
#               <root>/layers (U.Lu.publish.place).
# Lf.pub is Lu.publish of host/layers/unpack.bend, the same steps in the
# same order, with a clock read around each phase. A layer found present
# under its lock has no phases (it counts as zero in the image's sum).

# io, and the wall-clock ms it took.
def Lf.timed(-A: Type, io: IO(A)) -> IO(A & U32):
  do IO<A & U32>:
    a : U32 & (U32 & U32) <- SY.Sys.wall()
    x : A <- io
    b : U32 & (U32 & U32) <- SY.Sys.wall()
    return (x, SV.Srv.ms.v2(a, b))

def Lf.step.go(-A: Type, -B: Type, p: Lf.R(A) & U32, k: A -> U32 -> IO(Lf.R(B))) -> IO(Lf.R(B)):
  match p:
    case (Fail{e}, ms):
      IO.pure(Lf.R(B), Fail{e})
    case (Done{x}, ms):
      k(x, ms)

# A timed step: io, then k with its value and its ms; a failure skips k.
def Lf.step(-A: Type, -B: Type, io: IO(Lf.R(A)), k: A -> U32 -> IO(Lf.R(B))) -> IO(Lf.R(B)):
  IO.bind(Lf.R(A) & U32, Lf.R(B), Lf.timed(Lf.R(A), io), p => Lf.step.go(A, B, p, k))

def Lf.pub.ents(r: Lf.R(Unit), es: List<&2, T.Ent>) -> Lf.R(List<&2, T.Ent>):
  match r:
    case Done{u}:
      Done{es}
    case Fail{e}:
      Fail{e}

def Lf.pub.closed(q: File & Lf.R(Unit), es: List<&2, T.Ent>) -> IO(Lf.R(List<&2, T.Ent>)):
  match q:
    case (f, r):
      do IO<Lf.R(List<&2, T.Ent>)>:
        File.close(f)
        return Lf.pub.ents(r, es)

def Lf.pub.sides(q: File & Lf.R(List<&2, List<&2, T.Ent>>), +dir: String, +chain: String) -> IO(Lf.R(List<&2, T.Ent>)):
  match q:
    case (f, Fail{e}):
      do IO<Lf.R(List<&2, T.Ent>)>:
        File.close(f)
        return Fail{e}
    case (f, Done{acc}):
      do IO<Lf.R(List<&2, T.Ent>)>:
        +es : List<&2, T.Ent> = List.concat(&2, T.Ent, List.reverse(&2, List<&2, T.Ent>, acc))
        q2 : File & Lf.R(Unit) <- U.Lu.ops(F.Fill.sides(dir, chain, es), f)
        Lf.pub.closed(q2, es)

def Lf.pub.loop(r: Result<&1, &1, U32 & String, File>, +tar: String, +dir: String, +chain: String) -> IO(Lf.R(List<&2, T.Ent>)):
  match r:
    case Fail{e}:
      IO.pure(Lf.R(List<&2, T.Ent>), Fail{U.Lu.why("opening " ++ tar, e)})
    case Done{f}:
      do IO<Lf.R(List<&2, T.Ent>)>:
        q : File & Lf.R(List<&2, List<&2, T.Ent>>) <- U.Lu.loop(U.Lu.forever(), F.Fill.start(), f, dir, Nil{}, 0)
        Lf.pub.sides(q, dir, chain)

# The unpack phase: the tar's entries into dir and their .bend-meta
# files, the tar closed (Lu.unpack without its fsyncs); the entries.
def Lf.pub.unpack(+tar: String, +dir: String, +chain: String) -> IO(Lf.R(List<&2, T.Ent>)):
  do IO<Lf.R(List<&2, T.Ent>)>:
    r : Result<&1, &1, U32 & String, File> <- File.open(tar, "r")
    Lf.pub.loop(r, tar, dir, chain)

# The fsync and rename phases, after fetch (fm), decompress (zm) and
# unpack (um) ms.
def Lf.pub.sync(+es: List<&2, T.Ent>, +root: String, +now: U32, +chain: String, +diff: String, +parent: String, +tmp: String,
  +fm: U32, +zm: U32, +um: U32) -> IO(Lf.R(String & Maybe<&2, SV.Phases>)):
  Lf.step(Unit, String & Maybe<&2, SV.Phases>, U.Lu.syncs(F.Fill.syncs(tmp, es)),
    u => sm => Lf.step(String, String & Maybe<&2, SV.Phases>, U.Lu.publish.place(root, now, chain, diff, parent, tmp, F.Fill.use.of(es)),
      how => rm => IO.pure(Lf.R(String & Maybe<&2, SV.Phases>), Done{(how, Some{SV.Phases{fm, zm, um, sm, rm}})})))

# v3 (docs/ref/layers-sqfs.md): the unpack phase writes the layer's
# image (LI.Li.of_tar, fsynced there), so there is no fsync phase (0 ms);
# the rename phase moves the image into place (U.Lu.publish.place.v3).
def Lf.pub.img(+tar: String, +root: String, +now: U32, +chain: String, +diff: String, +parent: String, +tmp: String, +fm: U32,
  +zm: U32) -> IO(Lf.R(String & Maybe<&2, SV.Phases>)):
  Lf.step(F.Use, String & Maybe<&2, SV.Phases>, LI.Li.of_tar(tar, F.Fill.tmp.img.v3(tmp)),
    use => um => Lf.step(String, String & Maybe<&2, SV.Phases>,
      U.Lu.publish.place.v3(root, now, chain, diff, parent, F.Fill.tmp.img.v3(tmp), use),
      how => rm => IO.pure(Lf.R(String & Maybe<&2, SV.Phases>), Done{(how, Some{SV.Phases{fm, zm, um, 0, rm}})})))

# The diffID check first (U.Lu.diff.have, with the digest m of the
# decompress pass when there is one), its ms and how it hashed logged
# (SV.Srv.diff.line); a tar that is not the diffID ends the fill here,
# before anything is unpacked.
def Lf.pub.said(+z2: U32, +once: Bool, +tar: String, +root: String, +now: U32, +chain: String, +diff: String, +parent: String, +tmp: String,
  +fm: U32, +z1: U32) -> IO(Lf.R(String & Maybe<&2, SV.Phases>)):
  do IO<Lf.R(String & Maybe<&2, SV.Phases>)>:
    Lf.say(SV.Srv.diff.line(chain, once, z2))
    Lf.pub.img(tar, root, now, chain, diff, parent, tmp, fm, (z1 + z2 : U32))

def Lf.pub.checked(check: IO(Lf.R(Unit)), +once: Bool, +tar: String, +root: String, +now: U32, +chain: String, +diff: String, +parent: String,
  +tmp: String, +fm: U32, +z1: U32) -> IO(Lf.R(String & Maybe<&2, SV.Phases>)):
  Lf.step(Unit, String & Maybe<&2, SV.Phases>, check, u => z2 => Lf.pub.said(z2, once, tar, root, now, chain, diff, parent, tmp, fm, z1))

def Lf.pub.diff(m: Maybe<&2, String>, +tar: String, +root: String, +now: U32, +chain: String, +diff: String, +parent: String, +tmp: String,
  +fm: U32, +z1: U32) -> IO(Lf.R(String & Maybe<&2, SV.Phases>)):
  match m:
    case None{}:
      Lf.pub.checked(U.Lu.diff.have(None{}, tar, diff), F.Fill.diff.once(None{}), tar, root, now, chain, diff, parent, tmp, fm, z1)
    case Some{+hex}:
      Lf.pub.checked(U.Lu.diff.have(Some{hex}, tar, diff), F.Fill.diff.once(Some{hex}), tar, root, now, chain, diff, parent, tmp, fm, z1)

def Lf.pub.tar(p: U.Lu.Tar(), +root: String, +now: U32, +chain: String, +diff: String, +parent: String, +tmp: String, +fm: U32,
  +z1: U32) -> IO(Lf.R(String & Maybe<&2, SV.Phases>)):
  match p:
    case (+tar, (ours, m)):
      Lf.pub.diff(m, tar, root, now, chain, diff, parent, tmp, fm, z1)

def Lf.pub.fail(r: Lf.R(String & Maybe<&2, SV.Phases>), +tmp: String) -> IO(Lf.R(String & Maybe<&2, SV.Phases>)):
  match r:
    case Done{x}:
      IO.pure(Lf.R(String & Maybe<&2, SV.Phases>), Done{x})
    case Fail{e}:
      do IO<Lf.R(String & Maybe<&2, SV.Phases>)>:
        U.Lu.drop(tmp)
        return Fail{e}

def Lf.pub.in(+root: String, +now: U32, +chain: String, +diff: String, +parent: String, +blob: String, comp: P.Comp, +mib: U32,
  +tmp: String, +fm: U32) -> IO(Lf.R(String & Maybe<&2, SV.Phases>)):
  do IO<Lf.R(String & Maybe<&2, SV.Phases>)>:
    r : Lf.R(String & Maybe<&2, SV.Phases>) <- Lf.step(U.Lu.Tar(), String & Maybe<&2, SV.Phases>,
      U.Lu.tar.sniffed(comp, mib, blob, F.Fill.tmp.tar(tmp)), p => z1 => Lf.pub.tar(p, root, now, chain, diff, parent, tmp, fm, z1))
    U.Lu.drop(F.Fill.tmp.tar(tmp))
    U.Lu.drop(tmp)
    Lf.pub.fail(r, F.Fill.tmp.img.v3(tmp))

# Lu.publish, timed: layer fl unpacked from its verified blob (fetched
# in fm ms) into the store at root; how ("published", or "present" when
# another fill published it first) and the phases.
def Lf.pub(+root: String, +now: U32, fl: P.Fill, +blob: String, +fm: U32) -> IO(Lf.R(String & Maybe<&2, SV.Phases>)):
  match fl:
    case P.Fill{+chain, +diff, +parent, desc, comp}:
      U.Lu.then(Unit, String & Maybe<&2, SV.Phases>, U.Lu.base(root),
        u => U.Lu.then(String, String & Maybe<&2, SV.Phases>, U.Lu.tmp(64n, root, chain, now),
          tmp => Lf.pub.in(root, now, chain, diff, parent, blob, comp, F.Fill.unz.mib(P.Desc.size(desc)), tmp, fm)))

def Lf.pub.have(m: Maybe<&2, Y.Layer>, +root: String, +now: U32, +fl: P.Fill, blob: IO(Lf.R(String))) ->
  IO(Lf.R(String & Maybe<&2, SV.Phases>)):
  match m:
    case Some{l}:
      U.Lu.then(Unit, String & Maybe<&2, SV.Phases>, U.Lu.rec.use(root, now, l),
        u => IO.pure(Lf.R(String & Maybe<&2, SV.Phases>), Done{("present", None{})}))
    case None{}:
      Lf.step(String, String & Maybe<&2, SV.Phases>, blob, b => fm => Lf.pub(root, now, fl, b, fm))

# Lu.layer.locked, timed: present again under the lock, else fetched and
# published (Lf.pub).
def Lf.pub.locked(+root: String, +now: U32, +fl: P.Fill, blob: IO(Lf.R(String))) -> IO(Lf.R(String & Maybe<&2, SV.Phases>)):
  do IO<Lf.R(String & Maybe<&2, SV.Phases>)>:
    +c : String = Lf.fill.chain(fl)
    m : Maybe<&2, Y.Layer> <- U.Lu.rec.get(root, c)
    st : F.Stat <- U.Lu.stat(Maybe.default(&2, String, Y.Lay.dir(root, c), ""))
    si : F.Stat <- U.Lu.stat(Maybe.default(&2, String, Y.Lay.img.v3(root, c), ""))
    Lf.pub.have(F.Fill.present.v3(m, st, si), root, now, fl, blob)

# Lu.layer.v2 (fake 0), timed: the layer's lock taken (waiting while
# another process holds it), then Lf.pub.locked; the lock goes either
# way.
def Lf.pub.layer(+root: String, +now: U32, +fl: P.Fill, blob: IO(Lf.R(String))) -> IO(Lf.R(String & Maybe<&2, SV.Phases>)):
  do IO<Lf.R(String & Maybe<&2, SV.Phases>)>:
    +path : String = U.Lu.llock.path(root, Lf.fill.chain(fl))
    U.Lu.then(Unit, String & Maybe<&2, SV.Phases>, U.Lu.base.v2(root),
      u => IO.bind(Lf.R(Unit), Lf.R(String & Maybe<&2, SV.Phases>), U.Lu.llock.wait(U32.to_nat(F.Fill.llock.polls.v2()), path, 0),
        r => U.Lu.llock.with(String & Maybe<&2, SV.Phases>, r, path, Lf.pub.locked(root, now, fl, blob))))

# A layer's phases, zero when it had none (present).
def Lf.phases.of(m: Maybe<&2, SV.Phases>) -> SV.Phases:
  match m:
    case None{}:
      SV.Srv.phases.zero.v2()
    case Some{p}:
      p

def Lf.phases.say(m: Maybe<&2, SV.Phases>, +chain: String, +how: String) -> IO(Unit):
  match m:
    case None{}:
      IO.pure(Unit, Unit{})
    case Some{p}:
      Lf.say(SV.Srv.phases.line.v2(chain, how, p))

def Lf.layer.v2.ended(r: Lf.R(Unit), +p: SV.Phases) -> Lf.R(SV.Phases):
  match r:
    case Done{u}:
      Done{p}
    case Fail{e}:
      Fail{e}

def Lf.layer.v2.timed(q: String & Maybe<&2, SV.Phases>, +auto: Bool, +root: String, +reg: String, +now: U32, +fl: P.Fill) ->
  IO(Lf.R(SV.Phases)):
  match q:
    case (+how, +m):
      do IO<Lf.R(SV.Phases)>:
        Lf.phases.say(m, Lf.fill.chain(fl), how)
        r : Lf.R(Unit) <- Lf.layer.v2.how(how, auto, root, reg, now, fl)
        return Lf.layer.v2.ended(r, Lf.phases.of(m))

# One layer, under its lock (Lf.pub.layer): used again when the store
# has it, else its blob taken from the blob cache or fetched, and the
# layer unpacked and published, each phase timed and logged; with auto,
# the blob then goes. Its phases (zero when present).
def Lf.layer.v2(+port: Lup, +reg: String, +repo: String, +root: String, +now: U32, +auto: Bool, +fl: P.Fill) -> IO(Lf.R(SV.Phases)):
  U.Lu.then(String & Maybe<&2, SV.Phases>, SV.Phases, Lf.pub.layer(root, now, fl, Lf.blob(port, reg, repo, root, now, Lf.fill.desc(fl))),
    q => Lf.layer.v2.timed(q, auto, root, reg, now, fl))

def Lf.layers.v2.next(r: Lf.R(U32 & SV.Phases), +p: SV.Phases) -> Lf.R(U32 & SV.Phases):
  match r:
    case Done{(n, q)}:
      Done{(n, SV.Srv.phases.add.v2(p, q))}
    case Fail{e}:
      Fail{e}

# Each layer of one half in order: how many, and their phases summed.
# The first failure ends the half.
def Lf.layers.v2(fs: List<&2, P.Fill>, +port: Lup, +reg: String, +repo: String, +root: String, +now: U32, +auto: Bool, +n: U32) ->
  IO(Lf.R(U32 & SV.Phases)):
  match fs:
    case Nil{}:
      IO.pure(Lf.R(U32 & SV.Phases), Done{(n, SV.Srv.phases.zero.v2())})
    case Con{fl, t}:
      U.Lu.then(SV.Phases, U32 & SV.Phases, Lf.layer.v2(port, reg, repo, root, now, auto, fl),
        p => IO.bind(Lf.R(U32 & SV.Phases), Lf.R(U32 & SV.Phases), Lf.layers.v2(t, port, reg, repo, root, now, auto, (n + 1 : U32)),
          r => IO.pure(Lf.R(U32 & SV.Phases), Lf.layers.v2.next(r, p))))

def Lf.fills.chains(fs: List<&2, P.Fill>) -> List<&2, String>:
  match fs:
    case Nil{}:
      Nil{}
    case Con{fl, t}:
      Con{Lf.fill.chain(fl), Lf.fills.chains(t)}

def Lf.fills.in.put(keep: Bool, fl: P.Fill, rest: List<&2, P.Fill>) -> List<&2, P.Fill>:
  match keep:
    case True{}:
      Con{fl, rest}
    case False{}:
      rest

# The fills whose chain ID half names, in order.
def Lf.fills.in(fs: List<&2, P.Fill>, +half: List<&2, String>) -> List<&2, P.Fill>:
  match fs:
    case Nil{}:
      Nil{}
    case Con{+fl, t}:
      Lf.fills.in.put(Y.Lay.holds(half, Lf.fill.chain(fl)), fl, Lf.fills.in(t, half))

def Lf.sum.go(a: U32 & SV.Phases, b: U32 & SV.Phases) -> U32 & SV.Phases:
  match a:
    case (x, p):
      match b:
        case (y, q):
          ((x + y : U32), SV.Srv.phases.add.v2(p, q))

# Both halves' counts and phases, or the first failure.
def Lf.sum(a: Lf.R(U32 & SV.Phases), b: Lf.R(U32 & SV.Phases)) -> Lf.R(U32 & SV.Phases):
  match a b:
    case Done{x} Done{y}:
      Done{Lf.sum.go(x, y)}
    case Fail{e} _:
      Fail{e}
    case Done{x} Fail{e}:
      Fail{e}

# The two halves (Fill.split.v2) at once: the first forked, the second
# here; both run to their end.
def Lf.layers.par(p: List<&2, String> & List<&2, String>, +fs: List<&2, P.Fill>, +port: Lup, +reg: String, +repo: String, +root: String,
  +now: U32, +auto: Bool) -> IO(Lf.R(U32 & SV.Phases)):
  match p:
    case (a, b):
      do IO<Lf.R(U32 & SV.Phases)>:
        ch : Chan(Lf.R(U32 & SV.Phases)) <- IO.fork(Lf.R(U32 & SV.Phases), Lf.layers.v2(Lf.fills.in(fs, a), port, reg, repo, root, now, auto, 0))
        y : Lf.R(U32 & SV.Phases) <- Lf.layers.v2(Lf.fills.in(fs, b), port, reg, repo, root, now, auto, 0)
        x : Lf.R(U32 & SV.Phases) <- IO.join(Lf.R(U32 & SV.Phases), ch)
        return Lf.sum(x, y)

# The fills in two halves of their chain IDs (Fill.split.v2), at once.
def Lf.layers.halves(+fs: List<&2, P.Fill>, +port: Lup, +reg: String, +repo: String, +root: String, +now: U32, +auto: Bool) ->
  IO(Lf.R(U32 & SV.Phases)):
  Lf.layers.par(F.Fill.split.v2(Lf.fills.chains(fs)), fs, port, reg, repo, root, now, auto)

def Lf.image.man.v2(m: P.Man, +port: Lup, +reg: String, +repo: String, +root: String, +now: U32, +auto: Bool) -> IO(Lf.R(U32 & SV.Phases)):
  match m:
    case P.MImage{c, ls}:
      U.Lu.then(List<&2, String>, U32 & SV.Phases, Lf.config(port, repo, c),
        ds => U.Lu.then(List<&2, P.Fill>, U32 & SV.Phases, IO.pure(Lf.R(List<&2, P.Fill>), Lf.fills.of(P.Pull.fills(ds, ls))),
          fs => Lf.layers.halves(fs, port, reg, repo, root, now, auto)))
    case _:
      IO.pure(Lf.R(U32 & SV.Phases), Fail{"not an image manifest"})

# The image's layers filled: how many, and their phases summed.
def Lf.fill.port.v2(m: Maybe<&2, U32>, +reg: String, +repo: String, +ref: String, +arch: String, +root: String, +now: U32, +auto: Bool) ->
  IO(Lf.R(U32 & SV.Phases)):
  match m:
    case None{}:
      IO.pure(Lf.R(U32 & SV.Phases), Fail{reg ++ " is not a registry vk8s pulls from (docker.io, registry.k8s.io, ghcr.io, quay.io)"})
    case Some{p}:
      IO.bind(Lup, Lf.R(U32 & SV.Phases), Lf.up(reg, repo),
        +port => U.Lu.then(P.Man, U32 & SV.Phases, Lf.manifest(port, repo, arch, ref), m => Lf.image.man.v2(m, port, reg, repo, root, now, auto)))

def Lf.fill.ref.v2(m: Maybe<&2, P.Img>, +image: String, +arch: String, +root: String, +now: U32, +auto: Bool) -> IO(Lf.R(U32 & SV.Phases)):
  match m:
    case None{}:
      IO.pure(Lf.R(U32 & SV.Phases), Fail{"not a valid image reference: " ++ image})
    case Some{P.Img{+reg, repo, ref, dig}}:
      Lf.fill.port.v2(P.Pull.port(Lf.mirrors(PL.Plan.mirrors()), reg), reg, repo, ref, arch, root, now, auto)

# The end of a v2 fill: the count line, then the phases summed over
# the image's layers.
def Lf.fill.end.v2(r: Lf.R(U32 & SV.Phases), +image: String, +root: String) -> IO(Unit):
  match r:
    case Fail{e}:
      Lf.die(image ++ ": " ++ e)
    case Done{(n, p)}:
      do IO<Unit>:
        Lf.say(image ++ ": " ++ U32.show(n) ++ " layers in " ++ root ++ "/layers")
        Lf.say(image ++ ": summed over its layers: " ++ SV.Srv.phases.render.v2(p))

def Lf.fill.arch.v2(known: Bool, +image: String, +arch: String, +root: String, +auto: Bool) -> IO(Unit):
  match known:
    case False{}:
      Lf.die("this host's architecture is not arm64 or amd64")
    case True{}:
      do IO<Unit>:
        +now : U32 <- Lf.now()
        r : Lf.R(U32 & SV.Phases) <- U.Lu.then(Unit, U32 & SV.Phases, U.Lu.base.v2(root), u => Lf.fill.ref.v2(P.Pull.ref(image), image, arch, root, now, auto))
        Lf.fill.end.v2(r, image, root)

# A fill of IMAGE with the store at root, for linux/arch, with per-layer
# locks; auto (an automatic fill) removes each blob it published from.
# `vk8s layers fill IMAGE` is Lf.fill.v2(IMAGE, arch, root, False).
def Lf.fill.v2(+image: String, +arch: String, +root: String, +auto: Bool) -> IO(Unit):
  Lf.fill.arch.v2(String.eq(arch, "arm64") || String.eq(arch, "amd64"), image, arch, root, auto)

def Lf.gc.check.v2(drop: Bool, +c: String, +root: String) -> IO(U32):
  match drop:
    case True{}:
      do IO<U32>:
        U.Lu.drop(Maybe.default(&2, String, Y.Lay.dir(root, c), ""))
        U.Lu.drop(Maybe.default(&2, String, Y.Lay.img.v3(root, c), ""))
        U.Lu.drop(Maybe.default(&2, String, F.Fill.rec.path(root, c), ""))
        U.Lu.drop(Maybe.default(&2, String, F.Fill.rec.share(root, c), ""))
        Lf.say("removed " ++ c)
        return 1
    case False{}:
      do IO<U32>:
        Lf.say("kept " ++ c ++ ": used or held since gc planned")
        return 0

# Under layer c's lock: its record and every node's layers.held read
# again; the layer goes only when Fill.gc.recheck.v2 still says so.
def Lf.gc.recheck.v2(+c: String, +root: String, +now: U32) -> IO(U32):
  do IO<U32>:
    m : Maybe<&2, String> <- U.Lu.read(Maybe.default(&2, String, F.Fill.rec.path(root, c), ""))
    cs : List<String> <- V.Fs.ls(root ++ "/clusters")
    hs : List<&2, String> <- Lf.held(cs, root ++ "/clusters")
    Lf.gc.check.v2(F.Fill.gc.recheck.v2(c, m, hs, now), c, root)

# After the try of layer c's lock: (removed, skipped).
def Lf.gc.got.v2(r: U.Lu.R(Bool), +c: String, +root: String, +now: U32, +path: String) -> IO(U32 & U32):
  match r:
    case Fail{e}:
      do IO<U32 & U32>:
        IO.print_err("vk8s layers: gc skipped " ++ c ++ ": " ++ e)
        return (0, 1)
    case Done{False{}}:
      do IO<U32 & U32>:
        Lf.say("gc skipped " ++ c ++ ": a fill holds " ++ path)
        return (0, 1)
    case Done{True{}}:
      do IO<U32 & U32>:
        n : U32 <- Lf.gc.recheck.v2(c, root, now)
        U.Lu.llock.drop(path)
        return (n, 0)

def Lf.add2(a: U32 & U32, b: U32 & U32) -> U32 & U32:
  match a:
    case (x, y):
      match b:
        case (z, w):
          ((x + z : U32), (y + w : U32))

# Removes each planned layer that its lock and a second look allow:
# (removed, skipped).
def Lf.gc.drop.v2(ls: List<&2, Y.Layer>, +root: String, +now: U32) -> IO(U32 & U32):
  match ls:
    case Nil{}:
      IO.pure(U32 & U32, (0, 0))
    case Con{l, t}:
      do IO<U32 & U32>:
        +c : String = Y.Layer.chain(l)
        +path : String = U.Lu.llock.path(root, c)
        r : U.Lu.R(Bool) <- U.Lu.llock.try(path, now)
        a : U32 & U32 <- Lf.gc.got.v2(r, c, root, now, path)
        b : U32 & U32 <- Lf.gc.drop.v2(t, root, now)
        return Lf.add2(a, b)

def Lf.gc.said.v2(p: U32 & U32, +k: U32, +b: U32) -> IO(Lf.R(Unit)):
  match p:
    case (n, s):
      Lf.said("gc removed " ++ U32.show(n) ++ " layers (" ++ U32.show(s) ++ " skipped: a fill holds them), " ++ U32.show(k)
        ++ " tmp entries and " ++ U32.show(b) ++ " blob cache files")

# gc of the store at root at now, with per-layer locks.
def Lf.gc.run.v2(+root: String, +now: U32) -> IO(Lf.R(Unit)):
  do IO<Lf.R(Unit)>:
    cs : List<String> <- V.Fs.ls(root ++ "/clusters")
    hs : List<&2, String> <- Lf.held(cs, root ++ "/clusters")
    ds : List<String> <- V.Fs.ls(root ++ "/layers")
    rs : List<String> <- V.Fs.ls(root ++ "/layer-refs")
    ls : List<&2, Y.Layer> <- Lf.gc.read(Lf.more(Lf.chains(rs), Lf.chains(ds)), root)
    p : U32 & U32 <- Lf.gc.drop.v2(F.Fill.gc.plan.v2(ls, hs, [], now), root, now)
    ts : List<String> <- V.Fs.ls(root ++ "/tmp")
    k : U32 <- Lf.gc.tmp(ts, root ++ "/tmp", now)
    os : List<String> <- V.Fs.ls(root ++ "/oci/tmp")
    j : U32 <- Lf.gc.tmp(os, root ++ "/oci/tmp", now)
    regs : List<String> <- V.Fs.ls(root ++ "/oci")
    items : List<&2, S.Item> <- Lf.items.regs(regs, root ++ "/oci")
    b : U32 <- Lf.rm.files(S.Store.sweep(root ++ "/oci", now, items), 0)
    Lf.gc.said.v2(p, (k + j : U32), b)

# gc v2 at now: the store's directories made first.
def Lf.gc.at.v2(+root: String, +now: U32) -> IO(Lf.R(Unit)):
  U.Lu.then(Unit, Unit, U.Lu.base.v2(root), u => Lf.gc.run.v2(root, now))

# `vk8s layers gc` with the store at root.
def Lf.gc.v2(+root: String) -> IO(Unit):
  do IO<Unit>:
    +now : U32 <- Lf.now()
    r : Lf.R(Unit) <- Lf.gc.at.v2(root, now)
    Lf.gc.end(r)

# Through the image cache (v4)
# ----------------------------
#
# `vk8s layers fill` and `vk8s layers serve` run these (feat/fill-via-cache).
# A fill first pings the host's image cache (`vk8s cache serve`,
# host/cache/mirror.bend) on the registry's port (Plan.mirrors: docker.io
# 15001, registry.k8s.io 15002, ghcr.io 15003, quay.io 15004, on
# 127.0.0.1). When it answers (Lf.src), every blob and every manifest by
# digest is asked of it first, over plain HTTP (host/oci/plain.bend; no
# TLS, no token: the cache does the registry's auth, fills each object
# once and lets every client follow a fill in progress), so a cold pull
# is fetched from the registry once for the nodes and the filler, and an
# object the cache holds needs no registry round trip. A manifest by tag
# goes to the registry (the cache refuses tags), and so does any request
# the cache does not answer with a 200 or whose bytes fail their check
# (Up.mirror.asks, Up.via): the registry is then asked as before, with no
# token got ahead (a 401 fetches one). When the cache does not answer,
# the fill is v2's: the registry, with a token got before the manifest.
#
# A layer blob the cache's store already holds (fresh sidecar, regular
# file, at <root>/cache/store in src/oci/store.bend's layout) is not
# streamed: the filler makes a hard link to it at its own tmp path in
# <root>/oci/tmp (one metadata write, no byte copied; the cache checked
# its digest when it stored it) and renames that into <root>/oci with
# its sidecar, as a fetched blob. The filler then reads only its own
# name for the file, so the cache's hourly sweep or `vk8s cache prune`
# removing the cache's name, before or during the unpack, takes nothing
# from the fill; an automatic fill's drop (Lf.blob.drop) removes only
# the filler's link. A link that cannot be made (the blob gone already,
# another file system) falls back to the HTTP fetch.

# A fill's sources: the image cache's mirror of the registry ("" when it
# does not answer), and the registry itself.
type Lsrc is Data:
  Lsrc{cache: String, up: Lup}

def Lsrc.cache(s: Lsrc) -> String:
  match s:
    case Lsrc{c, u}:
      c

def Lsrc.up(s: Lsrc) -> Lup:
  match s:
    case Lsrc{c, u}:
      u

def Lf.src.of(up: Bool, +cache: String, +reg: String, +repo: String) -> IO(Lsrc):
  match up:
    case True{}:
      do IO<Lsrc>:
        +base : String <- UP.Upc.base(reg)
        Lf.say(reg ++ "/" ++ repo ++ ": via the image cache at " ++ cache ++ " (the registry for what it does not answer)")
        return Lsrc{cache, Lup{base, ""}}
    case False{}:
      IO.bind(Lup, Lsrc, Lf.up(reg, repo), u => IO.pure(Lsrc, Lsrc{"", u}))

# Where a fill of repo from reg goes: the image cache on port when it
# answers its ping, and the registry (with a token got ahead only when
# the cache does not answer).
def Lf.src(+port: U32, +reg: String, +repo: String) -> IO(Lsrc):
  do IO<Lsrc>:
    +cache : String = OU.Up.mirror(port)
    up : Bool <- PC.Plc.ping(cache)
    Lf.src.of(up, cache, reg, repo)

# Whether a request (kind, ref) goes to the image cache first.
def Lf.via(+src: Lsrc, +kind: String, +ref: String) -> Bool:
  Bool.not(String.is_empty(Lsrc.cache(src))) && OU.Up.mirror.asks(kind, ref)

# The cache's result, or, when it failed, the registry's (again).
def Lf.around(-A: Type, r: Lf.R(A), +what: String, again: IO(Lf.R(A))) -> IO(Lf.R(A)):
  match r:
    case Done{x}:
      IO.pure(Lf.R(A), Done{x})
    case Fail{e}:
      do IO<Lf.R(A)>:
        Lf.say(what ++ ": from the registry (" ++ e ++ ")")
        again

def Lf.doc.cached(r: PC.Plc.R(List<&2, U32>), +digest: String, +what: String) -> Lf.R(List<&2, U32>):
  match r:
    case Fail{e}:
      Fail{e}
    case Done{bs}:
      Lf.doc.verify(digest, bs, what)

def Lf.doc.via(ask: Bool, +src: Lsrc, +repo: String, +kind: String, +ref: String, +accept: String, +digest: String, +what: String) ->
  IO(Lf.R(List<&2, U32>)):
  match ask:
    case False{}:
      Lf.doc(Lsrc.up(src), repo, kind, ref, accept, digest, what)
    case True{}:
      IO.bind(PC.Plc.R(List<&2, U32>), Lf.R(List<&2, U32>), PC.Plc.doc(OU.Up.url(Lsrc.cache(src), repo, kind, ref), accept, P.Pull.doc_max()),
        r => Lf.around(List<&2, U32>, Lf.doc.cached(r, digest, what), what, Lf.doc(Lsrc.up(src), repo, kind, ref, accept, digest, what)))

# Lf.doc through the image cache first (Lf.via).
def Lf.doc.v4(+src: Lsrc, +repo: String, +kind: String, +ref: String, +accept: String, +digest: String, +what: String) -> IO(Lf.R(List<&2, U32>)):
  Lf.doc.via(Lf.via(src, kind, ref), src, repo, kind, ref, accept, digest, what)

def Lf.man.first.v4(m: P.Man, +src: Lsrc, +repo: String, +arch: String) -> IO(Lf.R(P.Man)):
  match m:
    case P.MIndex{+d}:
      U.Lu.then(List<&2, U32>, P.Man, Lf.doc.v4(src, repo, "manifests", d, P.Pull.accept(), d, "the manifest " ++ d),
        bs => IO.pure(Lf.R(P.Man), Lf.man.second(P.Pull.manifest(arch, T.Tar.s(bs)))))
    case P.MBad{w}:
      IO.pure(Lf.R(P.Man), Fail{w})
    case P.MImage{c, ls}:
      IO.pure(Lf.R(P.Man), Done{P.MImage{c, ls}})

# Lf.manifest through the image cache first.
def Lf.manifest.v4(+src: Lsrc, +repo: String, +arch: String, +ref: String) -> IO(Lf.R(P.Man)):
  U.Lu.then(List<&2, U32>, P.Man, Lf.doc.v4(src, repo, "manifests", ref, P.Pull.accept(), Lf.digest_of(ref), "the manifest " ++ ref),
    bs => Lf.man.first.v4(P.Pull.manifest(arch, T.Tar.s(bs)), src, repo, arch))

# Lf.config through the image cache first.
def Lf.config.v4(+src: Lsrc, +repo: String, c: P.Desc) -> IO(Lf.R(List<&2, String>)):
  match c:
    case P.Desc{m, +d, s}:
      U.Lu.then(List<&2, U32>, List<&2, String>, Lf.doc.v4(src, repo, "blobs", d, "*/*", d, "the config " ++ d),
        bs => IO.pure(Lf.R(List<&2, String>), Lf.config.of(P.Pull.config(T.Tar.s(bs)))))

# Fetches blob digest of repo from the image cache at cache into the
# file t (Lf.blob.asked: OciBlob.fetch hashes it as it lands).
def Lf.blob.cget(+cache: String, +repo: String, +digest: String, +t: String) -> IO(Lf.R(String & N.Size)):
  IO.bind(PC.Plc.R(Socket & UP.Resp), Lf.R(String & N.Size), PC.Plc.fetch(OU.Up.url(cache, repo, "blobs", digest), "*/*"),
    r => Lf.blob.asked(r, t, "the blob " ++ digest ++ " from the image cache"))

# A fetch into t, then its check and its move into place (Lf.blob.got).
def Lf.blob.from(get: IO(Lf.R(String & N.Size)), +now: U32, +d: P.Desc, +b: String, +mp: String, +t: String) -> IO(Lf.R(String)):
  U.Lu.then(String & N.Size, String, get, p => Lf.blob.got(p, now, d, b, mp, t))

def Lf.blob.fetch.via(ask: Bool, +src: Lsrc, +repo: String, +now: U32, +d: P.Desc, +b: String, +mp: String, +t: String) -> IO(Lf.R(String)):
  match ask:
    case False{}:
      Lf.blob.from(Lf.blob.get(Lsrc.up(src), repo, P.Desc.digest(d), t), now, d, b, mp, t)
    case True{}:
      IO.bind(Lf.R(String), Lf.R(String), Lf.blob.from(Lf.blob.cget(Lsrc.cache(src), repo, P.Desc.digest(d), t), now, d, b, mp, t),
        r => Lf.around(String, r, "the blob " ++ P.Desc.digest(d), Lf.blob.from(Lf.blob.get(Lsrc.up(src), repo, P.Desc.digest(d), t), now, d, b, mp, t)))

# Lf.blob.fetch through the image cache first. Nothing is left at t
# first: the fetch truncates the file at t (OciBlob.create), and the file
# at a stale t could be a link to the cache's copy (Lf.blob.link).
def Lf.blob.fetch.v4(+src: Lsrc, +repo: String, +root: String, +now: U32, +d: P.Desc, +b: String, +mp: String, +t: String) -> IO(Lf.R(String)):
  IO.bind(Lf.R(String), Lf.R(String),
    U.Lu.then(Unit, String, Lf.vfs(V.Fs.mkdir_p(root ++ "/oci/tmp", 493), "making " ++ root ++ "/oci/tmp"),
      u => IO.bind(U32, Lf.R(String), V.Fs.remove(t), z => Lf.blob.fetch.via(Lf.via(src, "blobs", P.Desc.digest(d)), src, repo, now, d, b, mp, t))),
    r => Lf.blob.clean(r, t))

def Lf.blob.linked(r: L.LayerFs.Res(Unit), +src: Lsrc, +repo: String, +root: String, +now: U32, +d: P.Desc, +b: String, +mp: String, +t: String) ->
  IO(Lf.R(String)):
  match r:
    case Done{u}:
      IO.bind(Lf.R(String), Lf.R(String), Lf.blob.verified(True{}, now, d, b, mp, t), x => Lf.blob.clean(x, t))
    case Fail{e}:
      Lf.blob.fetch.v4(src, repo, root, now, d, b, mp, t)

# The image cache's copy at cb, linked at t (the filler's own name for
# it), then moved into <root>/oci with its sidecar; else fetched
# (Lf.blob.fetch.v4). A file at a stale t goes first.
def Lf.blob.link(+cb: String, +src: Lsrc, +repo: String, +root: String, +now: U32, +d: P.Desc, +b: String, +mp: String, +t: String) ->
  IO(Lf.R(String)):
  do IO<Lf.R(String)>:
    _ : U32 <- V.Fs.mkdir_p(root ++ "/oci/tmp", 493)
    _ : U32 <- V.Fs.remove(t)
    r : L.LayerFs.Res(Unit) <- L.LayerFs.make(L.LayerFs.link(), t, T.Tar.b(cb))
    Lf.blob.linked(r, src, repo, root, now, d, b, mp, t)

def Lf.blob.cached.v4.at(on_disk: Bool, +cb: String, +src: Lsrc, +repo: String, +root: String, +now: U32, +d: P.Desc, +b: String, +mp: String,
  +t: String) -> IO(Lf.R(String)):
  match on_disk:
    case True{}:
      Lf.blob.link(cb, src, repo, root, now, d, b, mp, t)
    case False{}:
      Lf.blob.fetch.v4(src, repo, root, now, d, b, mp, t)

def Lf.blob.cached.v4.got(m: Maybe<&2, S.Meta>, on_disk: Bool, +cb: String, +src: Lsrc, +repo: String, +root: String, +now: U32, +d: P.Desc,
  +b: String, +mp: String, +t: String) -> IO(Lf.R(String)):
  match m:
    case Some{x}:
      Lf.blob.cached.v4.at(on_disk, cb, src, repo, root, now, d, b, mp, t)
    case None{}:
      Lf.blob.fetch.v4(src, repo, root, now, d, b, mp, t)

def Lf.blob.cached.v4(c: Maybe<&2, S.Paths>, +src: Lsrc, +repo: String, +root: String, +now: U32, +d: P.Desc, +b: String, +mp: String, +t: String) ->
  IO(Lf.R(String)):
  match c:
    case None{}:
      Lf.blob.fetch.v4(src, repo, root, now, d, b, mp, t)
    case Some{S.Paths{+cb, +cmp, +ct}}:
      do IO<Lf.R(String)>:
        side : Maybe<&2, String> <- U.Lu.read(cmp)
        f : HF.Facts <- V.Fs.facts(cb)
        Lf.blob.cached.v4.got(Lf.blob.meta(side, now), Lf.blob.file(f), cb, src, repo, root, now, d, b, mp, t)

def Lf.blob.hit.v4(m: Maybe<&2, S.Meta>, +src: Lsrc, +reg: String, +repo: String, +root: String, +now: U32, +d: P.Desc, +b: String, +mp: String,
  +t: String) -> IO(Lf.R(String)):
  match m:
    case Some{x}:
      U.Lu.then(Unit, String, Lf.side.put(mp, t, x), u => IO.pure(Lf.R(String), Done{b}))
    case None{}:
      Lf.blob.cached.v4(S.Store.paths(root ++ "/cache/store", reg, P.Desc.digest(d), now), src, repo, root, now, d, b, mp, t)

def Lf.blob.paths.v4(m: Maybe<&2, S.Paths>, +src: Lsrc, +reg: String, +repo: String, +root: String, +now: U32, +d: P.Desc) -> IO(Lf.R(String)):
  match m:
    case None{}:
      IO.pure(Lf.R(String), Fail{"no blob cache path for " ++ P.Desc.digest(d)})
    case Some{S.Paths{+b, +mp, +t}}:
      do IO<Lf.R(String)>:
        side : Maybe<&2, String> <- U.Lu.read(mp)
        Lf.blob.hit.v4(Lf.blob.meta(side, now), src, reg, repo, root, now, d, b, mp, t)

# Lf.blob through the image cache: the path of layer blob d in <root>/oci,
# there already, linked from the cache's store, or fetched (the cache
# first).
def Lf.blob.v4(+src: Lsrc, +reg: String, +repo: String, +root: String, +now: U32, +d: P.Desc) -> IO(Lf.R(String)):
  Lf.blob.paths.v4(S.Store.paths(root ++ "/oci", reg, P.Desc.digest(d), now), src, reg, repo, root, now, d)

# Lf.layer.v2 with the blob through the image cache (Lf.blob.v4).
def Lf.layer.v4(+src: Lsrc, +reg: String, +repo: String, +root: String, +now: U32, +auto: Bool, +fl: P.Fill) -> IO(Lf.R(SV.Phases)):
  U.Lu.then(String & Maybe<&2, SV.Phases>, SV.Phases, Lf.pub.layer(root, now, fl, Lf.blob.v4(src, reg, repo, root, now, Lf.fill.desc(fl))),
    q => Lf.layer.v2.timed(q, auto, root, reg, now, fl))

# Lf.layers.v2 with Lf.layer.v4.
def Lf.layers.v4(fs: List<&2, P.Fill>, +src: Lsrc, +reg: String, +repo: String, +root: String, +now: U32, +auto: Bool, +n: U32) ->
  IO(Lf.R(U32 & SV.Phases)):
  match fs:
    case Nil{}:
      IO.pure(Lf.R(U32 & SV.Phases), Done{(n, SV.Srv.phases.zero.v2())})
    case Con{fl, t}:
      U.Lu.then(SV.Phases, U32 & SV.Phases, Lf.layer.v4(src, reg, repo, root, now, auto, fl),
        p => IO.bind(Lf.R(U32 & SV.Phases), Lf.R(U32 & SV.Phases), Lf.layers.v4(t, src, reg, repo, root, now, auto, (n + 1 : U32)),
          r => IO.pure(Lf.R(U32 & SV.Phases), Lf.layers.v2.next(r, p))))

# Lf.layers.par with Lf.layers.v4: the two halves at once.
def Lf.layers.par.v4(p: List<&2, String> & List<&2, String>, +fs: List<&2, P.Fill>, +src: Lsrc, +reg: String, +repo: String, +root: String,
  +now: U32, +auto: Bool) -> IO(Lf.R(U32 & SV.Phases)):
  match p:
    case (a, b):
      do IO<Lf.R(U32 & SV.Phases)>:
        ch : Chan(Lf.R(U32 & SV.Phases)) <- IO.fork(Lf.R(U32 & SV.Phases), Lf.layers.v4(Lf.fills.in(fs, a), src, reg, repo, root, now, auto, 0))
        y : Lf.R(U32 & SV.Phases) <- Lf.layers.v4(Lf.fills.in(fs, b), src, reg, repo, root, now, auto, 0)
        x : Lf.R(U32 & SV.Phases) <- IO.join(Lf.R(U32 & SV.Phases), ch)
        return Lf.sum(x, y)

# One queue, a few lanes (v5)
# ---------------------------
#
# The layers of an image go in one queue (F.Fill.order.v5: the biggest
# blob first) that F.Fill.lanes.v5 workers share, each taking the next
# layer as soon as it is done with one (Lf.layer.v4 each: the layer's
# lock, the blob through the image cache, the unpack), so every layer of
# a small image is fetched at once and a small layer never waits in a
# lane behind a big one while another lane is free. v4's two halves ran
# each half in order, so a half with both big layers took their sum.

def Lf.forever() -> Nat:
  U32.to_nat(4294967295)

def Lf.count(fs: List<&2, P.Fill>, +n: U32) -> U32:
  match fs:
    case Nil{}:
      n
    case Con{f, t}:
      Lf.count(t, (n + 1 : U32))

def Lf.job(fl: P.Fill) -> F.Job:
  match fl:
    case P.Fill{c, d, p, b, k}:
      F.Job{c, P.Desc.size(b)}

def Lf.jobs(fs: List<&2, P.Fill>) -> List<&2, F.Job>:
  match fs:
    case Nil{}:
      Nil{}
    case Con{+fl, t}:
      Con{Lf.job(fl), Lf.jobs(t)}

def Lf.fills.find(fs: List<&2, P.Fill>, +c: String) -> List<&2, P.Fill>:
  match fs:
    case Nil{}:
      Nil{}
    case Con{+fl, t}:
      Bool.pick(List<&2, P.Fill>, String.eq(Lf.fill.chain(fl), c), [fl], Lf.fills.find(t, c))

# The fills in the order of the chain IDs cs.
def Lf.fills.pick(cs: List<&2, String>, +fs: List<&2, P.Fill>) -> List<&2, P.Fill>:
  match cs:
    case Nil{}:
      Nil{}
    case Con{+c, t}:
      List.append(&2, P.Fill, Lf.fills.find(fs, c), Lf.fills.pick(t, fs))

def Lf.queue.put(fs: List<&2, P.Fill>, +q: Chan(P.Fill)) -> IO(Unit):
  match fs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{fl, t}:
      do IO<Unit>:
        _ : Result<&1, &1, P.Fill, Unit> <- Chan.send(P.Fill, q, fl)
        Lf.queue.put(t, q)

def Lf.worker.add(acc: U32 & SV.Phases, +p: SV.Phases) -> U32 & SV.Phases:
  match acc:
    case (n, q):
      ((n + 1 : U32), SV.Srv.phases.add.v2(q, p))

def Lf.worker.next(x: Lf.R(SV.Phases), acc: U32 & SV.Phases, again: (U32 & SV.Phases) -> IO(Lf.R(U32 & SV.Phases))) -> IO(Lf.R(U32 & SV.Phases)):
  match x:
    case Done{+p}:
      again(Lf.worker.add(acc, p))
    case Fail{e}:
      IO.pure(Lf.R(U32 & SV.Phases), Fail{e})

def Lf.worker.got(r: Poll<&1, &1, Maybe<&1, P.Fill>, Unit>, acc: U32 & SV.Phases, +src: Lsrc, +reg: String, +repo: String, +root: String,
  +now: U32, +auto: Bool, again: (U32 & SV.Phases) -> IO(Lf.R(U32 & SV.Phases))) -> IO(Lf.R(U32 & SV.Phases)):
  match r:
    case Ready{Some{fl}}:
      IO.bind(Lf.R(SV.Phases), Lf.R(U32 & SV.Phases), Lf.layer.v4(src, reg, repo, root, now, auto, fl),
        x => Lf.worker.next(x, acc, again))
    case _:
      IO.pure(Lf.R(U32 & SV.Phases), Done{acc})

# One lane: the next layer of the queue q until it is empty; how many
# and their phases summed. Its first failure ends the lane (the others
# go on with the queue).
def Lf.worker.v5(n: Nat, +q: Chan(P.Fill), +src: Lsrc, +reg: String, +repo: String, +root: String, +now: U32, +auto: Bool,
  acc: U32 & SV.Phases) -> IO(Lf.R(U32 & SV.Phases)):
  match n:
    case 0n:
      IO.pure(Lf.R(U32 & SV.Phases), Done{acc})
    case 1n+k:
      do IO<Lf.R(U32 & SV.Phases)>:
        r : Poll<&1, &1, Maybe<&1, P.Fill>, Unit> <- Chan.try_recv(P.Fill, q, 0)
        Lf.worker.got(r, acc, src, reg, repo, root, now, auto, a2 => Lf.worker.v5(k, q, src, reg, repo, root, now, auto, a2))

# k lanes on q at once: their counts and phases summed, or a failure.
def Lf.lanes.v5(k: Nat, +q: Chan(P.Fill), +src: Lsrc, +reg: String, +repo: String, +root: String, +now: U32, +auto: Bool) ->
  IO(Lf.R(U32 & SV.Phases)):
  match k:
    case 0n:
      IO.pure(Lf.R(U32 & SV.Phases), Done{(0, SV.Srv.phases.zero.v2())})
    case 1n+j:
      do IO<Lf.R(U32 & SV.Phases)>:
        ch : Chan(Lf.R(U32 & SV.Phases)) <- IO.fork(Lf.R(U32 & SV.Phases),
          Lf.worker.v5(Lf.forever(), q, src, reg, repo, root, now, auto, (0, SV.Srv.phases.zero.v2())))
        y : Lf.R(U32 & SV.Phases) <- Lf.lanes.v5(j, q, src, reg, repo, root, now, auto)
        x : Lf.R(U32 & SV.Phases) <- IO.join(Lf.R(U32 & SV.Phases), ch)
        return Lf.sum(x, y)

# The fills fs of one image: queued biggest first, then F.Fill.lanes.v5
# lanes on the queue.
def Lf.layers.queue.v5(+fs: List<&2, P.Fill>, +src: Lsrc, +reg: String, +repo: String, +root: String, +now: U32, +auto: Bool) ->
  IO(Lf.R(U32 & SV.Phases)):
  do IO<Lf.R(U32 & SV.Phases)>:
    +q : Chan(P.Fill) <- Chan.new(P.Fill, (Lf.count(fs, 0) + 1 : U32))
    Lf.queue.put(Lf.fills.pick(F.Fill.order.v5(Lf.jobs(fs)), fs), q)
    Lf.lanes.v5(U32.to_nat(F.Fill.lanes.v5(Lf.count(fs, 0))), q, src, reg, repo, root, now, auto)

def Lf.image.man.v4(m: P.Man, +src: Lsrc, +reg: String, +repo: String, +root: String, +now: U32, +auto: Bool) -> IO(Lf.R(U32 & SV.Phases)):
  match m:
    case P.MImage{c, ls}:
      U.Lu.then(List<&2, String>, U32 & SV.Phases, Lf.config.v4(src, repo, c),
        ds => U.Lu.then(List<&2, P.Fill>, U32 & SV.Phases, IO.pure(Lf.R(List<&2, P.Fill>), Lf.fills.of(P.Pull.fills(ds, ls))),
          fs => Lf.layers.queue.v5(fs, src, reg, repo, root, now, auto)))
    case _:
      IO.pure(Lf.R(U32 & SV.Phases), Fail{"not an image manifest"})

# Lf.fill.port.v2 through the image cache on the registry's port, when
# it answers (Lf.src): the image's layers filled, how many, and their
# phases summed.
def Lf.fill.port.v4(m: Maybe<&2, U32>, +reg: String, +repo: String, +ref: String, +arch: String, +root: String, +now: U32, +auto: Bool) ->
  IO(Lf.R(U32 & SV.Phases)):
  match m:
    case None{}:
      IO.pure(Lf.R(U32 & SV.Phases), Fail{reg ++ " is not a registry vk8s pulls from (docker.io, registry.k8s.io, ghcr.io, quay.io)"})
    case Some{p}:
      IO.bind(Lsrc, Lf.R(U32 & SV.Phases), Lf.src(p, reg, repo),
        +src => U.Lu.then(P.Man, U32 & SV.Phases, Lf.manifest.v4(src, repo, arch, ref), m => Lf.image.man.v4(m, src, reg, repo, root, now, auto)))

def Lf.fill.ref.v4(m: Maybe<&2, P.Img>, +image: String, +arch: String, +root: String, +now: U32, +auto: Bool) -> IO(Lf.R(U32 & SV.Phases)):
  match m:
    case None{}:
      IO.pure(Lf.R(U32 & SV.Phases), Fail{"not a valid image reference: " ++ image})
    case Some{P.Img{+reg, repo, ref, dig}}:
      Lf.fill.port.v4(P.Pull.port(Lf.mirrors(PL.Plan.mirrors()), reg), reg, repo, ref, arch, root, now, auto)

def Lf.fill.arch.v4(known: Bool, +image: String, +arch: String, +root: String, +auto: Bool) -> IO(Unit):
  match known:
    case False{}:
      Lf.die("this host's architecture is not arm64 or amd64")
    case True{}:
      do IO<Unit>:
        +now : U32 <- Lf.now()
        r : Lf.R(U32 & SV.Phases) <- U.Lu.then(Unit, U32 & SV.Phases, U.Lu.base.v2(root), u => Lf.fill.ref.v4(P.Pull.ref(image), image, arch, root, now, auto))
        Lf.fill.end.v2(r, image, root)

# Lf.fill.v2 through the image cache when it answers. `vk8s layers fill
# IMAGE` is Lf.fill.v4(IMAGE, arch, root, False).
def Lf.fill.v4(+image: String, +arch: String, +root: String, +auto: Bool) -> IO(Unit):
  Lf.fill.arch.v4(String.eq(arch, "arm64") || String.eq(arch, "amd64"), image, arch, root, auto)

# The command line
# ----------------

def Layers.usage() -> String:
  "usage: vk8s layers fill IMAGE | vk8s layers gc | vk8s layers serve"

def Layers.main.fill(ok: Bool, +image: String, +arch: String, +root: String) -> IO(Unit):
  match ok:
    case True{}:
      Lf.fill.v4(image, arch, root, False{})
    case False{}:
      Lf.die(Layers.usage())

def Layers.main.gc(ok: Bool, +root: String) -> IO(Unit):
  match ok:
    case True{}:
      Lf.gc.v2(root)
    case False{}:
      Lf.die(Layers.usage())

def Layers.main.args(+args: +List<String>, +arch: String, +root: String) -> IO(Unit):
  match args:
    case Con{+sub, Con{+image, Nil{}}}:
      Layers.main.fill(String.eq(sub, "fill"), image, arch, root)
    case Con{+sub, Nil{}}:
      Layers.main.gc(String.eq(sub, "gc"), root)
    case _:
      Lf.die(Layers.usage())

# argv ["vk8s", "layers", ...]: the store is home/.vk8s, arch the host's
# asset arch (arm64 or amd64).
def Layers.main(+xs: +List<String>, +home: String, +arch: String) -> IO(Unit):
  Layers.main.args(List.drop(&2, String, xs, 2n), arch, home ++ "/.vk8s")
