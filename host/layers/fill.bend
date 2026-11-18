import Base
import 0x37f031982dbba38edaaee15fcde6c33d/main.bend as V
import bend-kube-runtime@0.10.0.0/src/sys.bend as SY
import ../../src/layers/pull.bend as P
import ../../src/layers/fill.bend as F
import ../../src/layers/store.bend as Y
import ../../src/layers/tar.bend as T
import ../../src/layers/meta.bend as M
import ../../src/oci/store.bend as S
import ../../src/oci/size.bend as N
import ../../src/guest/plan.bend as PL
import ../oci/blob.bend as B
import ../bin_file.bend as BF
import ./unpack.bend as U
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
#      one the image cache serves (Plan.mirrors: docker.io,
#      registry.k8s.io, ghcr.io, quay.io);
#   2. the manifest comes from the image cache on 127.0.0.1 (plain
#      HTTP/1.1; the cache VM does the upstream's TLS and token auth), by
#      digest when the reference has one (checked); an index gives the
#      linux/<arch> manifest, fetched by its digest (checked);
#   3. the config, by digest (checked), gives the diffIDs, and with the
#      manifest's layers the chain IDs (Pull.fills);
#   4. each layer whose record and directory are both there
#      (Fill.present) is only used again (its record touched); each other
#      one's blob comes from the OCI blob cache at
#      ~/.vk8s/oci (src/oci/store.bend), or is fetched into it with
#      OciBlob.fetch, which hashes the bytes as they land (digest and
#      size checked, then renamed into place with its sidecar), and is
#      unpacked and published (host/layers/unpack.bend).
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
# fill and gc each hold ~/.vk8s/layers.lock while they run (Fill.lock: an
# O_EXCL create; a lock an hour old is taken over), so gc never removes a
# layer that a fill is about to use or publish. A second fill or gc
# meanwhile fails and says so.
#
# The image cache must run (`vk8s cache start`); `vk8s create` starts it.

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

# The image cache
# ---------------

def Lf.head.more(big: Bool, s: Socket, again: Socket -> IO(Socket & Lf.R(P.Got))) -> IO(Socket & Lf.R(P.Got)):
  match big:
    case True{}:
      IO.pure(Socket & Lf.R(P.Got), (s, Fail{"the image cache's response head passes 64 KiB"}))
    case False{}:
      again(s)

def Lf.head.next(g: P.Got, s: Socket, +n: U32, again: Socket -> IO(Socket & Lf.R(P.Got))) -> IO(Socket & Lf.R(P.Got)):
  match g:
    case P.GMore{}:
      Lf.head.more(U32.is_gt(n, P.Pull.head_max()), s, again)
    case P.GBad{w}:
      IO.pure(Socket & Lf.R(P.Got), (s, Fail{w}))
    case P.GHead{st, l, b}:
      IO.pure(Socket & Lf.R(P.Got), (s, Done{P.GHead{st, l, b}}))

def Lf.head.step(s: Socket, +all: +List<U32>, again: Socket -> List<&2, U32> -> IO(Socket & Lf.R(P.Got))) -> IO(Socket & Lf.R(P.Got)):
  Lf.head.next(P.Pull.got(all), s, F.Fill.count(all, 0), s2 => again(s2, all))

def Lf.head.recv(p: Socket & Result<&1, &1, U32 & String, Maybe<&1, List<&2, U32>>>, +acc: +List<U32>,
  again: Socket -> List<&2, U32> -> IO(Socket & Lf.R(P.Got))) -> IO(Socket & Lf.R(P.Got)):
  match p:
    case (s, Fail{e}):
      IO.pure(Socket & Lf.R(P.Got), (s, Fail{U.Lu.why("reading from the image cache", e)}))
    case (s, Done{None{}}):
      IO.pure(Socket & Lf.R(P.Got), (s, Fail{"the image cache closed the connection before its response"}))
    case (s, Done{Some{bs}}):
      again(s, List.append(&2, U32, acc, bs))

# Reads a response until its head ends: the status, the Content-Length
# and the body bytes that came with the head.
def Lf.head(fuel: Nat, s: Socket, +acc: +List<U32>) -> IO(Socket & Lf.R(P.Got)):
  match fuel:
    case 0n:
      IO.pure(Socket & Lf.R(P.Got), (s, Fail{"the image cache's response head did not end"}))
    case 1n+k:
      do IO<Socket & Lf.R(P.Got)>:
        p : Socket & Result<&1, &1, U32 & String, Maybe<&1, List<&2, U32>>> <- TCP.recv_bytes(s, 65536)
        Lf.head.recv(p, acc, s2 => all => Lf.head.step(s2, all, s3 => a3 => Lf.head(k, s3, a3)))

def Lf.ask.sent(p: Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>) -> IO(Socket & Lf.R(P.Got)):
  match p:
    case (s, Fail{(e, rest)}):
      IO.pure(Socket & Lf.R(P.Got), (s, Fail{U.Lu.why("sending to the image cache", e)}))
    case (s, Done{u}):
      Lf.head(U.Lu.forever(), s, Nil{})

def Lf.ask.end(q: Socket & Lf.R(P.Got)) -> IO(Lf.R(Socket & P.Got)):
  match q:
    case (s, Fail{e}):
      do IO<Lf.R(Socket & P.Got)>:
        Socket.close(s)
        return Fail{e}
    case (s, Done{g}):
      IO.pure(Lf.R(Socket & P.Got), Done{(s, g)})

def Lf.ask.conn(r: Result<&1, &1, U32 & String, Socket>, +port: U32, req: String) -> IO(Lf.R(Socket & P.Got)):
  match r:
    case Fail{e}:
      IO.pure(Lf.R(Socket & P.Got), Fail{U.Lu.why("connecting to the image cache on 127.0.0.1:" ++ U32.show(port) ++ " (is it running? `vk8s cache start`)", e)})
    case Done{s}:
      do IO<Lf.R(Socket & P.Got)>:
        p : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send(s, req)
        q : Socket & Lf.R(P.Got) <- Lf.ask.sent(p)
        Lf.ask.end(q)

# Sends req to the image cache on port: the connection and the
# response's head (the caller closes the connection).
def Lf.ask(+port: U32, req: String) -> IO(Lf.R(Socket & P.Got)):
  do IO<Lf.R(Socket & P.Got)>:
    r : Result<&1, &1, U32 & String, Socket> <- TCP.connect("127.0.0.1", port)
    Lf.ask.conn(r, port, req)

def Lf.ok200.len(m: Maybe<&2, N.Size>, +what: String) -> Lf.R(N.Size):
  match m:
    case None{}:
      Fail{what ++ ": the image cache sent no Content-Length"}
    case Some{n}:
      Done{n}

# A 200 with a Content-Length: the length; anything else: why not.
def Lf.ok200(+st: U32, l: Maybe<&2, N.Size>, +what: String) -> Lf.R(N.Size):
  Bool.pick(Lf.R(N.Size), U32.is_eq(st, 200), Lf.ok200.len(l, what), Fail{what ++ ": the image cache answered HTTP " ++ U32.show(st)})

def Lf.closed(-A: Type, s: Socket, +e: String) -> IO(Lf.R(A)):
  do IO<Lf.R(A)>:
    Socket.close(s)
    return Fail{e}

# Manifests and configs
# ---------------------

def Lf.body.done(have: Bool, s: Socket, +acc: +List<U32>, more: Socket -> IO(Socket & Lf.R(List<&2, U32>))) -> IO(Socket & Lf.R(List<&2, U32>)):
  match have:
    case True{}:
      IO.pure(Socket & Lf.R(List<&2, U32>), (s, Done{acc}))
    case False{}:
      more(s)

def Lf.body.recv(p: Socket & Result<&1, &1, U32 & String, Maybe<&1, List<&2, U32>>>, +acc: +List<U32>,
  again: Socket -> List<&2, U32> -> IO(Socket & Lf.R(List<&2, U32>))) -> IO(Socket & Lf.R(List<&2, U32>)):
  match p:
    case (s, Fail{e}):
      IO.pure(Socket & Lf.R(List<&2, U32>), (s, Fail{U.Lu.why("reading from the image cache", e)}))
    case (s, Done{None{}}):
      IO.pure(Socket & Lf.R(List<&2, U32>), (s, Fail{"the image cache closed the connection before the body's end"}))
    case (s, Done{Some{bs}}):
      again(s, List.append(&2, U32, acc, bs))

# Reads until acc holds want bytes (or more).
def Lf.body(fuel: Nat, s: Socket, +acc: +List<U32>, +want: U32) -> IO(Socket & Lf.R(List<&2, U32>)):
  match fuel:
    case 0n:
      IO.pure(Socket & Lf.R(List<&2, U32>), (s, Fail{"the image cache's body did not end"}))
    case 1n+k:
      Lf.body.done(U32.is_ge(F.Fill.count(acc, 0), want), s, acc,
        s2 => IO.bind(Socket & Result<&1, &1, U32 & String, Maybe<&1, List<&2, U32>>>, Socket & Lf.R(List<&2, U32>), TCP.recv_bytes(s2, 65536),
          p => Lf.body.recv(p, acc, s3 => a3 => Lf.body(k, s3, a3, want))))

def Lf.doc.exact(r: Lf.R(List<&2, U32>), +n: U32, +what: String) -> Lf.R(List<&2, U32>):
  match r:
    case Fail{e}:
      Fail{what ++ ": " ++ e}
    case Done{+bs}:
      Bool.pick(Lf.R(List<&2, U32>), U32.is_eq(F.Fill.count(bs, 0), n), Done{bs}, Fail{what ++ ": the image cache sent more than its Content-Length"})

def Lf.doc.end(q: Socket & Lf.R(List<&2, U32>), +n: U32, +what: String) -> IO(Lf.R(List<&2, U32>)):
  match q:
    case (s, r):
      do IO<Lf.R(List<&2, U32>)>:
        Socket.close(s)
        return Lf.doc.exact(r, n, what)

def Lf.doc.small(ok: Bool, +n: U32, s: Socket, +b: +List<U32>, +what: String) -> IO(Lf.R(List<&2, U32>)):
  match ok:
    case False{}:
      Lf.closed(List<&2, U32>, s, what ++ ": larger than 4 MiB")
    case True{}:
      do IO<Lf.R(List<&2, U32>)>:
        q : Socket & Lf.R(List<&2, U32>) <- Lf.body(U.Lu.forever(), s, b, n)
        Lf.doc.end(q, n, what)

def Lf.doc.sized(r: Lf.R(N.Size), s: Socket, +b: +List<U32>, +what: String) -> IO(Lf.R(List<&2, U32>)):
  match r:
    case Fail{e}:
      Lf.closed(List<&2, U32>, s, e)
    case Done{N.Size{+h, +l}}:
      Lf.doc.small(U32.is_zero(h) && U32.is_le(l, P.Pull.doc_max()), l, s, b, what)

def Lf.doc.head(g: P.Got, s: Socket, +what: String) -> IO(Lf.R(List<&2, U32>)):
  match g:
    case P.GHead{+st, l, +b}:
      Lf.doc.sized(Lf.ok200(st, l, what), s, b, what)
    case _:
      Lf.closed(List<&2, U32>, s, what ++ ": no response head")

def Lf.doc.asked(r: Lf.R(Socket & P.Got), +what: String) -> IO(Lf.R(List<&2, U32>)):
  match r:
    case Fail{e}:
      IO.pure(Lf.R(List<&2, U32>), Fail{what ++ ": " ++ e})
    case Done{(s, g)}:
      Lf.doc.head(g, s, what)

def Lf.doc.verify(+digest: String, +bs: +List<U32>, +what: String) -> Lf.R(List<&2, U32>):
  Bool.pick(Lf.R(List<&2, U32>), String.is_empty(digest) || P.Pull.verified(digest, bs), Done{bs},
    Fail{what ++ ": the content is not " ++ digest})

# A manifest or a config (at most 4 MiB) for req, checked against digest
# unless digest is "".
def Lf.doc(+port: U32, req: String, +digest: String, +what: String) -> IO(Lf.R(List<&2, U32>)):
  U.Lu.then(List<&2, U32>, List<&2, U32>,
    IO.bind(Lf.R(Socket & P.Got), Lf.R(List<&2, U32>), Lf.ask(port, req), r => Lf.doc.asked(r, what)),
    bs => IO.pure(Lf.R(List<&2, U32>), Lf.doc.verify(digest, bs, what)))

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

def Lf.man.first(m: P.Man, +port: U32, +repo: String, +arch: String) -> IO(Lf.R(P.Man)):
  match m:
    case P.MIndex{+d}:
      U.Lu.then(List<&2, U32>, P.Man, Lf.doc(port, P.Pull.get.manifest(port, repo, d), d, "the manifest " ++ d),
        bs => IO.pure(Lf.R(P.Man), Lf.man.second(P.Pull.manifest(arch, T.Tar.s(bs)))))
    case P.MBad{w}:
      IO.pure(Lf.R(P.Man), Fail{w})
    case P.MImage{c, ls}:
      IO.pure(Lf.R(P.Man), Done{P.MImage{c, ls}})

# The image manifest of ref (a tag or a digest) for linux/arch.
def Lf.manifest(+port: U32, +repo: String, +arch: String, +ref: String) -> IO(Lf.R(P.Man)):
  U.Lu.then(List<&2, U32>, P.Man, Lf.doc(port, P.Pull.get.manifest(port, repo, ref), Lf.digest_of(ref), "the manifest " ++ ref),
    bs => Lf.man.first(P.Pull.manifest(arch, T.Tar.s(bs)), port, repo, arch))

def Lf.config.of(m: Maybe<&2, List<&2, String>>) -> Lf.R(List<&2, String>):
  match m:
    case None{}:
      Fail{"the image config has no layers rootfs with valid diffIDs"}
    case Some{ds}:
      Done{ds}

# The diffIDs of the config c.
def Lf.config(+port: U32, +repo: String, c: P.Desc) -> IO(Lf.R(List<&2, String>)):
  match c:
    case P.Desc{m, +d, s}:
      U.Lu.then(List<&2, U32>, List<&2, String>, Lf.doc(port, P.Pull.get.blob(port, repo, d), d, "the config " ++ d),
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
        Socket.close(s)
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
      Lf.closed(String & N.Size, s, what ++ ": the image cache sent more than its Content-Length")
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

def Lf.blob.head(g: P.Got, s: Socket, +t: String, +what: String) -> IO(Lf.R(String & N.Size)):
  match g:
    case P.GHead{+st, l, +b}:
      Lf.blob.sized(Lf.ok200(st, l, what), s, b, t, what)
    case _:
      Lf.closed(String & N.Size, s, what ++ ": no response head")

def Lf.blob.asked(r: Lf.R(Socket & P.Got), +t: String, +what: String) -> IO(Lf.R(String & N.Size)):
  match r:
    case Fail{e}:
      IO.pure(Lf.R(String & N.Size), Fail{what ++ ": " ++ e})
    case Done{(s, g)}:
      Lf.blob.head(g, s, t, what)

# Fetches blob digest of repo from the cache on port into the file t:
# the hex SHA-256 of what came and its length.
def Lf.blob.get(+port: U32, repo: String, +digest: String, +t: String) -> IO(Lf.R(String & N.Size)):
  IO.bind(Lf.R(Socket & P.Got), Lf.R(String & N.Size), Lf.ask(port, P.Pull.get.blob(port, repo, digest)),
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

def Lf.blob.fetch(+port: U32, +repo: String, +root: String, +now: U32, +d: P.Desc, +b: String, +mp: String, +t: String) -> IO(Lf.R(String)):
  IO.bind(Lf.R(String), Lf.R(String),
    U.Lu.then(Unit, String, Lf.vfs(V.Fs.mkdir_p(root ++ "/oci/tmp", 493), "making " ++ root ++ "/oci/tmp"),
      u => U.Lu.then(String & N.Size, String, Lf.blob.get(port, repo, P.Desc.digest(d), t),
        p => Lf.blob.got(p, now, d, b, mp, t))),
    r => Lf.blob.clean(r, t))

def Lf.blob.hit(m: Maybe<&2, S.Meta>, +port: U32, +repo: String, +root: String, +now: U32, +d: P.Desc, +b: String, +mp: String, +t: String) ->
  IO(Lf.R(String)):
  match m:
    case Some{x}:
      U.Lu.then(Unit, String, Lf.side.put(mp, t, x), u => IO.pure(Lf.R(String), Done{b}))
    case None{}:
      Lf.blob.fetch(port, repo, root, now, d, b, mp, t)

def Lf.blob.meta(m: Maybe<&2, String>, +now: U32) -> Maybe<&2, S.Meta>:
  match m:
    case None{}:
      None{}
    case Some{s}:
      S.Store.hit(s, now)

def Lf.blob.paths(m: Maybe<&2, S.Paths>, +port: U32, +repo: String, +root: String, +now: U32, +d: P.Desc) -> IO(Lf.R(String)):
  match m:
    case None{}:
      IO.pure(Lf.R(String), Fail{"no blob cache path for " ++ P.Desc.digest(d)})
    case Some{S.Paths{+b, +mp, +t}}:
      do IO<Lf.R(String)>:
        side : Maybe<&2, String> <- U.Lu.read(mp)
        Lf.blob.hit(Lf.blob.meta(side, now), port, repo, root, now, d, b, mp, t)

# The path of layer blob d in the OCI blob cache (<root>/oci): there
# already (its last use recorded), or fetched into it.
def Lf.blob(+port: U32, +reg: String, +repo: String, +root: String, +now: U32, +d: P.Desc) -> IO(Lf.R(String)):
  Lf.blob.paths(S.Store.paths(root ++ "/oci", reg, P.Desc.digest(d), now), port, repo, root, now, d)

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

def Lf.layer.have(m: Maybe<&2, Y.Layer>, +port: U32, +reg: String, +repo: String, +root: String, +now: U32, +fl: P.Fill) -> IO(Lf.R(Unit)):
  match m:
    case Some{l}:
      U.Lu.then(Unit, Unit, U.Lu.rec.use(root, now, l), u => Lf.said(Lf.fill.chain(fl) ++ " present"))
    case None{}:
      U.Lu.then(String, Unit, Lf.blob(port, reg, repo, root, now, Lf.fill.desc(fl)), blob => Lf.layer.unpack(root, now, fl, blob))

# One layer: used again when the store has it (its record and its
# directory), else filled. The lock's time is written again first, so a
# long fill never holds a lock that looks stale.
def Lf.layer(+port: U32, +reg: String, +repo: String, +root: String, +now: U32, +fl: P.Fill) -> IO(Lf.R(Unit)):
  do IO<Lf.R(Unit)>:
    t : U32 <- Lf.now()
    _ : Lf.R(Unit) <- U.Lu.write(F.Fill.lock.path(root), F.Fill.lock.text(t))
    m : Maybe<&2, Y.Layer> <- U.Lu.rec.get(root, Lf.fill.chain(fl))
    ns : List<String> <- V.Fs.ls(root ++ "/layers")
    Lf.layer.have(F.Fill.present(m, Y.Lay.holds(Lf.chains(ns), Lf.fill.chain(fl))), port, reg, repo, root, now, fl)

# Each layer in order (a layer's parent is filled before it); how many.
def Lf.layers(fs: List<&2, P.Fill>, +port: U32, +reg: String, +repo: String, +root: String, +now: U32, +n: U32) -> IO(Lf.R(U32)):
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

def Lf.image.man(m: P.Man, +port: U32, +reg: String, +repo: String, +root: String, +now: U32) -> IO(Lf.R(U32)):
  match m:
    case P.MImage{c, ls}:
      U.Lu.then(List<&2, String>, U32, Lf.config(port, repo, c),
        ds => U.Lu.then(List<&2, P.Fill>, U32, IO.pure(Lf.R(List<&2, P.Fill>), Lf.fills.of(P.Pull.fills(ds, ls))),
          fs => Lf.layers(fs, port, reg, repo, root, now, 0)))
    case _:
      IO.pure(Lf.R(U32), Fail{"not an image manifest"})

def Lf.image(+port: U32, +reg: String, +repo: String, +ref: String, +arch: String, +root: String, +now: U32) -> IO(Lf.R(U32)):
  U.Lu.then(P.Man, U32, Lf.manifest(port, repo, arch, ref), m => Lf.image.man(m, port, reg, repo, root, now))

def Lf.fill.port(m: Maybe<&2, U32>, +reg: String, +repo: String, +ref: String, +arch: String, +root: String, +now: U32) -> IO(Lf.R(U32)):
  match m:
    case None{}:
      IO.pure(Lf.R(U32), Fail{reg ++ " is not a registry the image cache serves (docker.io, registry.k8s.io, ghcr.io, quay.io)"})
    case Some{port}:
      Lf.image(port, reg, repo, ref, arch, root, now)

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

# What the store knows of each chain ID (Fill.or).
def Lf.gc.read(cs: List<&2, String>, +root: String) -> IO(List<&2, Y.Layer>):
  match cs:
    case Nil{}:
      IO.pure(List<&2, Y.Layer>, Nil{})
    case Con{+c, t}:
      do IO<List<&2, Y.Layer>>:
        m : Maybe<&2, String> <- U.Lu.read(Maybe.default(&2, String, F.Fill.rec.path(root, c), ""))
        ys : List<&2, Y.Layer> <- Lf.gc.read(t, root)
        return Con{F.Fill.or(c, m), ys}

def Lf.gc.drop.one(+c: String, +root: String, rest: IO(U32)) -> IO(U32):
  do IO<U32>:
    U.Lu.drop(Maybe.default(&2, String, Y.Lay.dir(root, c), ""))
    U.Lu.drop(Maybe.default(&2, String, F.Fill.rec.path(root, c), ""))
    Lf.say("removed " ++ c)
    k : U32 <- rest
    return (k + 1 : U32)

# Removes each layer, its directory first, then its record: how many.
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

# The command line
# ----------------

def Layers.usage() -> String:
  "usage: vk8s layers fill IMAGE | vk8s layers gc"

def Layers.main.fill(ok: Bool, +image: String, +arch: String, +root: String) -> IO(Unit):
  match ok:
    case True{}:
      Lf.fill(image, arch, root)
    case False{}:
      Lf.die(Layers.usage())

def Layers.main.gc(ok: Bool, +root: String) -> IO(Unit):
  match ok:
    case True{}:
      Lf.gc(root)
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
