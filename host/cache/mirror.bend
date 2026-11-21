import Base
import 0x002839320e5a033b05bcedb51711713f/main.bend as V
import 0x002839320e5a033b05bcedb51711713f/host/hvf.bend as HV
import ../../src/oci/route.bend as R
import ../../src/oci/fill.bend as F
import ../../src/oci/store.bend as S
import ../../src/oci/size.bend as N
import ../../src/oci/grammar.bend as G
import ../../src/oci/serve.bend as SV
import ../../src/oci/upstream.bend as OU
import ../../src/layers/pull.bend as P
import ../../src/layers/meta.bend as M
import ../../src/guest/plan.bend as PL
import ../oci/blob.bend as B
import ../oci/upstream.bend as UP
import ../tls_server.bend as TS
import ../layers/unpack.bend as U
import ../layers/fill.bend as LF

# `vk8s cache serve`: the image cache, on the host
# ===============================================
#
# A pull-through, pull-only OCI mirror per registry, on
# 127.0.0.1:15001-15004 (src/guest/plan.bend Plan.mirrors), which every
# VM node's containerd tries first (certs.d hosts.toml, `pull` only, the
# upstream as fallback) and reaches as 10.0.2.2. It replaces the image
# cache VM (CNCF distribution's proxy in a bend-vmm VM): the host itself
# dials the registries (host/oci/upstream.bend), so no VM, no cache.img
# and no registry traffic through a VM's NAT.
#
# Every decision is src/oci's: routes and responses (route.bend), the
# store's layout, sidecars and expiry (store.bend), single-flight fills
# that every client follows as they grow (fill.bend), the upstream's
# token auth and redirects (auth.bend, upstream.bend), and the HTTP side
# (serve.bend). This file reads, fetches, writes and sends.
#
# - The store is ~/.vk8s/cache/store (S.Store layout:
#   <registry>/blobs/sha256/<ab>/<hex> and its .meta sidecar; tmp/ for
#   fills). A hit records its last use; an hourly sweep removes what has
#   not been used for 72 h (Store.ttl). `vk8s cache prune` empties it.
# - One port per registry, each with its own main loop: it accepts, owns
#   the fill machine's state (Fill.step), starts each fill's fetch, and
#   tells each waiting connection what to do. A connection reads one
#   request (Connection: close), serves a hit from the store at once
#   (OciBlob.send: sendfile on Linux), or asks its main loop.
# - A fill: the upstream's answer head goes to every waiting client as
#   soon as it arrives (containerd gives a mirror 30 s); its body lands in
#   tmp/<hex>.<n> while OciBlob.fetch hashes it; each follower streams
#   that file as it grows and holds back the last byte until the fill is
#   committed (renamed into the store), so a fill whose digest does not
#   match cuts every follower off and the client's own check fails.
# - A Range request for a blob the store lacks, a HEAD of a missing
#   object, and anything the machine passes are answered 404, so
#   containerd pulls those from the upstream itself.

type MCfg is Data:
  MCfg{root: String, reg: String, port: U32}

# What a main loop tells a waiting connection.
type MMsg is Data:
  # the object is in the store now: serve it from there
  MCache{}
  # not through the mirror: 404, the client goes upstream
  MPass{}
  # the upstream's 200 is in: stream the fill file tmp as it grows
  MSend{len: String, tmp: String, media: String}
  # an error status and OCI code ("": no body)
  MReply{status: U32, code: String}

# What connections and fetches tell their main loop.
type MEv is Data:
  MGet{conn: U32, digest: String, blob: Bool, ranged: Bool, repo: String, back: Chan(MMsg)}
  MHead{digest: String, status: U32, len: String, media: String}
  MEnded{digest: String, got: String}
  MBroke{digest: String}
  MGone{conn: U32}

# A fill in progress, as the host knows it: its file, the upstream's
# Content-Type and Content-Length (once its head is in).
type MFill is Data:
  MFill{digest: String, tmp: String, media: String, len: String}

# How much of a fill is on disk, and whether it is committed.
type MHave is Data:
  MHave{size: N.Size, committed: Bool}

type MBack is Data:
  MBack{conn: U32, back: Chan(MMsg)}

# A main loop's state: the fill machine's fills, the waiting
# connections, the host's fills, the next connection id (also the fill
# file's nonce), and when the store was last swept.
type MSt is Data:
  MSt{es: List<&2, F.Entry>, backs: List<&2, MBack>, fills: List<&2, MFill>, next: U32, swept: U32}

def Mir.hi(s: N.Size) -> U32:
  match s:
    case N.Size{h, l}:
      h

def Mir.lo(s: N.Size) -> U32:
  match s:
    case N.Size{h, l}:
      l

def Mir.forever() -> Nat:
  U32.to_nat(4294967295)

def Mir.say(+c: MCfg, +s: String) -> IO(Unit):
  match c:
    case MCfg{r, g, p}:
      IO.print("vk8s cache serve: " ++ g ++ ": " ++ s)

def MCfg.root(c: MCfg) -> String:
  match c:
    case MCfg{r, g, p}:
      r

def MCfg.reg(c: MCfg) -> String:
  match c:
    case MCfg{r, g, p}:
      g

def MCfg.port(c: MCfg) -> U32:
  match c:
    case MCfg{r, g, p}:
      p

# The image cache's store under ~/.vk8s.
def Mir.root(+vk8s: String) -> String:
  vk8s ++ "/cache/store"

# The ports, one per registry (Plan.mirrors).
def Mir.cfgs(ms: List<&2, P.Mirror>, +root: String) -> List<&2, MCfg>:
  match ms:
    case Nil{}:
      Nil{}
    case Con{P.Mirror{r, p}, t}:
      Con{MCfg{root, r, p}, Mir.cfgs(t, root)}

# The store
# ---------

def Mir.blob_path(+c: MCfg, +d: String) -> String:
  Maybe.default(&2, String, S.Store.blob_path(MCfg.root(c), MCfg.reg(c), d), "")

def Mir.meta_path(+c: MCfg, +d: String) -> String:
  Maybe.default(&2, String, S.Store.meta_path(MCfg.root(c), MCfg.reg(c), d), "")

def Mir.tmp_path.of(m: Maybe<&2, S.Paths>) -> String:
  match m:
    case Some{S.Paths{b, mp, t}}:
      t
    case None{}:
      ""

def Mir.tmp_path(+c: MCfg, +d: String, +n: U32) -> String:
  Mir.tmp_path.of(S.Store.paths(MCfg.root(c), MCfg.reg(c), d, n))

# [there, mode, size hi, size lo, ...] (Hvf.path_facts): a regular
# file's size.
def Mir.size.of(ws: List<&2, U32>) -> Maybe<&2, N.Size>:
  match ws:
    case Con{+there, Con{+mode, Con{hi, Con{lo, rest}}}}:
      Bool.pick(Maybe<&2, N.Size>, Bool.not(U32.is_zero(there)) && U32.is_eq(U32.and(mode, 61440), 32768), Some{N.Size{hi, lo}}, None{})
    case _:
      None{}

# The size of the regular file at path, when there is one.
def Mir.size(+path: String) -> IO(Maybe<&2, N.Size>):
  IO.bind(+List<U32>, Maybe<&2, N.Size>, HV.Hvf.path_facts(path), ws => IO.pure(Maybe<&2, N.Size>, Mir.size.of(ws)))

def Mir.meta.got(m: Maybe<&2, String>, +now: U32) -> Maybe<&2, S.Meta>:
  match m:
    case None{}:
      None{}
    case Some{s}:
      S.Store.hit(s, now)

def Mir.hit.there(there: Maybe<&2, N.Size>, m: Maybe<&2, S.Meta>) -> Maybe<&2, S.Meta>:
  match there:
    case None{}:
      None{}
    case Some{z}:
      m

def Mir.hit.write(m: Maybe<&2, S.Meta>, +c: MCfg, +d: String, +n: U32) -> IO(Maybe<&2, S.Meta>):
  match m:
    case None{}:
      IO.pure(Maybe<&2, S.Meta>, None{})
    case Some{+x}:
      do IO<Maybe<&2, S.Meta>>:
        +t : String = Mir.tmp_path(c, d, n) ++ ".meta"
        _ : U.Lu.R(Unit) <- U.Lu.write(t, S.Store.meta.render(x))
        _ : U32 <- V.Fs.rename(t, Mir.meta_path(c, d))
        return Some{x}

# The store's object d, when it has it: its sidecar, with this use
# recorded (written through tmp and a rename).
def Mir.hit(+c: MCfg, +d: String, +n: U32) -> IO(Maybe<&2, S.Meta>):
  do IO<Maybe<&2, S.Meta>>:
    +now : U32 <- U.Lu.now()
    side : Maybe<&2, String> <- U.Lu.read(Mir.meta_path(c, d))
    there : Maybe<&2, N.Size> <- Mir.size(Mir.blob_path(c, d))
    Mir.hit.write(Mir.hit.there(there, Mir.meta.got(side, now)), c, d, n)

# Fetching (one fill)
# -------------------

def Mir.tell(+inbox: Chan(MEv), ev: MEv) -> IO(Unit):
  do IO<Unit>:
    _ : Result<&1, &1, MEv, Unit> <- Chan.send(MEv, inbox, ev)
    return Unit{}

def Mir.fetch.ended(r: B.OciBlob.Res(Unit), h: B.OciBlob.Res(String), +d: String, +c: MCfg, +inbox: Chan(MEv)) -> IO(Unit):
  match r h:
    case Done{u} Done{hex}:
      Mir.tell(inbox, MEnded{d, "sha256:" ++ hex})
    case Fail{(e, m)} _:
      do IO<Unit>:
        Mir.say(c, d ++ ": the upstream body broke off: " ++ m)
        Mir.tell(inbox, MBroke{d})
    case Done{u} Fail{(e, m)}:
      do IO<Unit>:
        Mir.say(c, d ++ ": " ++ m)
        Mir.tell(inbox, MBroke{d})

def Mir.fetch.body(q: File & (Socket & B.OciBlob.Res(Unit)), +d: String, +c: MCfg, +inbox: Chan(MEv)) -> IO(Unit):
  match q:
    case (f, (s, r)):
      do IO<Unit>:
        TS.TlsSrv.close(s)
        h : B.OciBlob.Res(String) <- B.OciBlob.commit(f)
        Mir.fetch.ended(r, h, d, c, inbox)

def Mir.fetch.created(r: B.OciBlob.Res(File), s: Socket, +len: N.Size, +b: List<&2, U32>, +media: String, +d: String, +c: MCfg,
  +inbox: Chan(MEv)) -> IO(Unit):
  match r:
    case Fail{(e, m)}:
      do IO<Unit>:
        TS.TlsSrv.close(s)
        Mir.say(c, d ++ ": cannot create its fill file: " ++ m)
        Mir.tell(inbox, MHead{d, 0, "", ""})
    case Done{f}:
      do IO<Unit>:
        Mir.tell(inbox, MHead{d, 200, N.Size.show(len), media})
        q : File & (Socket & B.OciBlob.Res(Unit)) <- B.OciBlob.fetch(f, s, b,
          Mir.hi(N.Size.sub(len, N.Size.of(UP.Upc.count(b, 0)))), Mir.lo(N.Size.sub(len, N.Size.of(UP.Upc.count(b, 0)))), 60000)
        Mir.fetch.body(q, d, c, inbox)

def Mir.fetch.ok(ok: Bool, s: Socket, +st: U32, +len: N.Size, +b: List<&2, U32>, +media: String, +tmp: String, +d: String, +c: MCfg,
  +inbox: Chan(MEv)) -> IO(Unit):
  match ok:
    case False{}:
      do IO<Unit>:
        TS.TlsSrv.close(s)
        Mir.tell(inbox, MHead{d, st, "", ""})
    case True{}:
      do IO<Unit>:
        _ : U32 <- V.Fs.mkdir_p(MCfg.root(c) ++ "/tmp", 493)
        r : B.OciBlob.Res(File) <- B.OciBlob.create(tmp)
        Mir.fetch.created(r, s, len, b, media, d, c, inbox)

def Mir.fetch.lb(+st: U32, lb: Maybe<&2, N.Size> & List<&2, U32>, s: Socket, +media: String, +tmp: String, +d: String, +c: MCfg,
  +inbox: Chan(MEv)) -> IO(Unit):
  match lb:
    case (Some{+len}, +b):
      Mir.fetch.ok(U32.is_eq(st, 200) && Bool.not(N.Size.is_lt(len, N.Size.of(UP.Upc.count(b, 0)))), s, st, len, b, media, tmp, d, c, inbox)
    case (None{}, b):
      Mir.fetch.ok(False{}, s, Bool.pick(U32, U32.is_eq(st, 200), 0, st), N.Size.zero(), [], media, tmp, d, c, inbox)

def Mir.fetch.parts(p: U32 & (Maybe<&2, N.Size> & List<&2, U32>), s: Socket, +media: String, +tmp: String, +d: String, +c: MCfg,
  +inbox: Chan(MEv)) -> IO(Unit):
  match p:
    case (st, lb):
      Mir.fetch.lb(st, lb, s, media, tmp, d, c, inbox)

def Mir.fetch.resp(+x: UP.Resp, s: Socket, +tmp: String, +d: String, +c: MCfg, +inbox: Chan(MEv)) -> IO(Unit):
  Mir.fetch.parts(UP.Upc.parts(x), s, UP.Upc.media(x), tmp, d, c, inbox)

def Mir.fetch.got(r: UP.Upc.R(Socket & UP.Resp), +tmp: String, +d: String, +c: MCfg, +inbox: Chan(MEv)) -> IO(Unit):
  match r:
    case Fail{e}:
      do IO<Unit>:
        Mir.say(c, d ++ ": " ++ e)
        Mir.tell(inbox, MHead{d, 0, "", ""})
    case Done{(s, x)}:
      Mir.fetch.resp(x, s, tmp, d, c, inbox)

# The upstream fetch of fill d (a blob, or a manifest by digest) of repo
# into tmp: its head, then its end, told to the main loop.
def Mir.fetch(+c: MCfg, +inbox: Chan(MEv), +d: String, +blob: Bool, +repo: String, +tmp: String) -> IO(Unit):
  do IO<Unit>:
    +base : String <- UP.Upc.base(MCfg.reg(c))
    +kind : String = Bool.pick(String, blob, "blobs", "manifests")
    r : UP.Upc.R(Socket & UP.Resp) <- UP.Upc.fetch(OU.Up.url(base, repo, kind, d), Bool.pick(String, blob, "*/*", OU.Up.manifest_accept()), "", repo)
    Mir.fetch.got(r, tmp, d, c, inbox)

# Answering a connection
# ----------------------

def Mir.sent(q: Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>) -> IO(Socket & Bool):
  match q:
    case (s, Done{u}):
      IO.pure(Socket & Bool, (s, True{}))
    case (s, Fail{e}):
      IO.pure(Socket & Bool, (s, False{}))

def Mir.send(s: Socket, +text: String) -> IO(Socket & Bool):
  IO.bind(Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>, Socket & Bool, TCP.send(s, text), q => Mir.sent(q))

def Mir.close(p: Socket & Bool) -> IO(Unit):
  match p:
    case (s, ok):
      Socket.close(s)

# A response with no body from the store (or a JSON one), then the
# connection closed.
def Mir.answer(s: Socket, +r: R.Resp) -> IO(Unit):
  do IO<Unit>:
    p : Socket & Bool <- Mir.send(s, SV.Serve.render(r))
    Mir.close(p)

def Mir.stream.end(q: Socket & (File & B.OciBlob.Res(Unit))) -> IO(Unit):
  match q:
    case (s, (f, r)):
      do IO<Unit>:
        File.close(f)
        Socket.close(s)

def Mir.stream.opened(r: Result<&1, &1, U32 & String, File>, s: Socket, +first: N.Size, +len: N.Size) -> IO(Unit):
  match r:
    case Fail{e}:
      Socket.close(s)
    case Done{f}:
      IO.bind(Socket & (File & B.OciBlob.Res(Unit)), Unit,
        B.OciBlob.send(s, f, Mir.hi(first), Mir.lo(first), Mir.hi(len), Mir.lo(len), 60000), q => Mir.stream.end(q))

def Mir.stream.head(p: Socket & Bool, +path: String, +first: N.Size, +len: N.Size) -> IO(Unit):
  match p:
    case (s, False{}):
      Socket.close(s)
    case (s, True{}):
      IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open(path, "r"), r => Mir.stream.opened(r, s, first, len))

def Mir.serve.body(b: R.Body, s: Socket, +text: String, +path: String) -> IO(Unit):
  match b:
    case R.Stream{+first, +len}:
      IO.bind(Socket & Bool, Unit, Mir.send(s, text), p => Mir.stream.head(p, path, first, len))
    case _:
      IO.bind(Socket & Bool, Unit, Mir.send(s, text), p => Mir.close(p))

# The answer for an object of the store: Route.found (Range applies to
# blobs), the body sent from the file at path.
def Mir.serve(s: Socket, +r: R.Resp, +path: String) -> IO(Unit):
  match r:
    case R.Resp{st, hs, +b}:
      Mir.serve.body(b, s, SV.Serve.render(R.Resp{st, hs, b}), path)

def Mir.found(m: Maybe<&2, S.Meta>, s: Socket, +q: R.Req, +rq: SV.Rq, +c: MCfg) -> IO(Unit):
  match m q:
    case Some{S.Meta{md, sz, u}} R.Fetch{h, o, n, d}:
      Mir.serve(s, R.Route.found(o, h, d, md, sz, SV.Serve.get(rq, "range"), SV.Serve.get(rq, "if-range")), Mir.blob_path(c, G.Gram.digest.show(d)))
    case _ R.Fetch{h, o, n, d}:
      Mir.answer(s, R.Route.missing(o, h))
    case _ _:
      Mir.answer(s, R.Route.unknown(False{}))

# Following a fill
# ----------------

def Mir.follow.facts(t: Maybe<&2, N.Size>, f: Maybe<&2, N.Size>) -> Maybe<&2, MHave>:
  match t f:
    case Some{z} _:
      Some{MHave{z, False{}}}
    case None{} Some{z}:
      Some{MHave{z, True{}}}
    case None{} None{}:
      None{}

# How much of the fill the store has now, and whether it is committed:
# the fill file tmp while it grows, the blob at path once renamed; None
# once discarded.
def Mir.follow.have(+tmp: String, +path: String) -> IO(Maybe<&2, MHave>):
  do IO<Maybe<&2, MHave>>:
    t : Maybe<&2, N.Size> <- Mir.size(tmp)
    f : Maybe<&2, N.Size> <- Mir.size(path)
    return Mir.follow.facts(t, f)

def Mir.follow.sent(q: Socket & (File & B.OciBlob.Res(Unit)), +upto: N.Size, again: Socket -> File -> N.Size -> IO(Unit)) -> IO(Unit):
  match q:
    case (s, (f, Done{u})):
      again(s, f, upto)
    case (s, (f, Fail{e})):
      do IO<Unit>:
        File.close(f)
        Socket.close(s)

def Mir.follow.wait(late: Bool, s: Socket, f: File, +sent: N.Size, +idle: U32, again: Socket -> File -> N.Size -> U32 -> IO(Unit)) -> IO(Unit):
  match late:
    case True{}:
      do IO<Unit>:
        File.close(f)
        Socket.close(s)
    case False{}:
      do IO<Unit>:
        IO.sleep(20)
        again(s, f, sent, (idle + 1 : U32))

def Mir.follow.step(w: SV.Fw, s: Socket, f: File, +sent: N.Size, +idle: U32, again: Socket -> File -> N.Size -> U32 -> IO(Unit)) -> IO(Unit):
  match w:
    case SV.FwDone{}:
      do IO<Unit>:
        File.close(f)
        Socket.close(s)
    case SV.FwSend{+upto}:
      IO.bind(Socket & (File & B.OciBlob.Res(Unit)), Unit,
        B.OciBlob.send(s, f, Mir.hi(sent), Mir.lo(sent), Mir.hi(N.Size.sub(upto, sent)), Mir.lo(N.Size.sub(upto, sent)), 60000),
        q => Mir.follow.sent(q, upto, s2 => f2 => u2 => again(s2, f2, u2, 0)))
    case SV.FwWait{}:
      Mir.follow.wait(U32.is_gt(idle, 6000), s, f, sent, idle, again)

def Mir.follow.at(h: Maybe<&2, MHave>, s: Socket, f: File, +sent: N.Size, +len: N.Size, +idle: U32,
  again: Socket -> File -> N.Size -> U32 -> IO(Unit)) -> IO(Unit):
  match h:
    case None{}:
      do IO<Unit>:
        File.close(f)
        Socket.close(s)
    case Some{MHave{have, committed}}:
      Mir.follow.step(SV.Serve.follow(sent, have, len, committed), s, f, sent, idle, again)

# Streams the fill file f (opened at tmp; the blob at path once it is
# committed) to s as it grows, up to len bytes, the last one only once
# the fill is committed (Serve.follow). Two minutes with no new byte end
# it.
def Mir.follow(n: Nat, s: Socket, f: File, +tmp: String, +path: String, +sent: N.Size, +len: N.Size, +idle: U32) -> IO(Unit):
  match n:
    case 0n:
      do IO<Unit>:
        File.close(f)
        Socket.close(s)
    case 1n+k:
      do IO<Unit>:
        h : Maybe<&2, MHave> <- Mir.follow.have(tmp, path)
        Mir.follow.at(h, s, f, sent, len, idle, s2 => f2 => u2 => i2 => Mir.follow(k, s2, f2, tmp, path, u2, len, i2))

def Mir.follow.open2(r: Result<&1, &1, U32 & String, File>, s: Socket, +tmp: String, +path: String, +len: N.Size) -> IO(Unit):
  match r:
    case Fail{e}:
      Socket.close(s)
    case Done{f}:
      Mir.follow(Mir.forever(), s, f, tmp, path, N.Size.zero(), len, 0)

def Mir.follow.open(r: Result<&1, &1, U32 & String, File>, s: Socket, +tmp: String, +path: String, +len: N.Size) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open(path, "r"), r2 => Mir.follow.open2(r2, s, tmp, path, len))
    case Done{f}:
      Mir.follow(Mir.forever(), s, f, tmp, path, N.Size.zero(), len, 0)

def Mir.follow.start(p: Socket & Bool, +tmp: String, +path: String, +len: N.Size) -> IO(Unit):
  match p:
    case (s, False{}):
      Socket.close(s)
    case (s, True{}):
      IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open(tmp, "r"), r => Mir.follow.open(r, s, tmp, path, len))

# The answer the main loop gave a connection that waited for a fill.
def Mir.waited(m: Maybe<&1, MMsg>, s: Socket, +q: R.Req, +rq: SV.Rq, +c: MCfg, +id: U32) -> IO(Unit):
  match m q:
    case Some{MCache{}} R.Fetch{h, o, n, +d}:
      IO.bind(Maybe<&2, S.Meta>, Unit, Mir.hit(c, G.Gram.digest.show(d), id), x => Mir.found(x, s, R.Fetch{h, o, n, d}, rq, c))
    case Some{MSend{+len, +tmp, +media}} R.Fetch{h, o, n, +d}:
      IO.bind(Socket & Bool, Unit,
        Mir.send(s, SV.Serve.render(R.Resp{200, R.Route.content(o, d, media, len), R.NoBody{}})),
        p => Mir.follow.start(p, tmp, Mir.blob_path(c, G.Gram.digest.show(d)), Maybe.default(&2, N.Size, N.Size.read(len), N.Size.zero())))
    case Some{MReply{st, code}} R.Fetch{h, o, n, d}:
      Mir.answer(s, SV.Serve.reply(h, st, code))
    case _ R.Fetch{h, o, n, d}:
      Mir.answer(s, R.Route.missing(o, h))
    case _ _:
      Mir.answer(s, R.Route.unknown(False{}))

def Mir.is_blob(o: R.Obj) -> Bool:
  match o:
    case R.Blob{}:
      True{}
    case R.Manifest{}:
      False{}

def Mir.miss.go(get: Bool, s: Socket, +q: R.Req, +rq: SV.Rq, +c: MCfg, +inbox: Chan(MEv), +id: U32) -> IO(Unit):
  match get q:
    case True{} R.Fetch{h, +o, +n, +d}:
      do IO<Unit>:
        +back : Chan(MMsg) <- Chan.new(MMsg, 2)
        Mir.tell(inbox, MGet{id, G.Gram.digest.show(d), Mir.is_blob(o), Maybe.is_some(&2, String, SV.Serve.get(rq, "range")), n, back})
        m : Maybe<&1, MMsg> <- Chan.recv(MMsg, back)
        Mir.waited(m, s, R.Fetch{h, o, n, d}, rq, c, id)
    case False{} R.Fetch{h, o, n, d}:
      Mir.answer(s, R.Route.missing(o, h))
    case _ _:
      Mir.answer(s, R.Route.unknown(False{}))

def Mir.is_head(q: R.Req) -> Bool:
  match q:
    case R.Fetch{h, o, n, d}:
      h
    case _:
      False{}

# An object the store lacks: a GET waits for its fill (Fill.step in the
# main loop); a HEAD is a 404 (containerd then asks the upstream).
def Mir.miss(s: Socket, +q: R.Req, +rq: SV.Rq, +c: MCfg, +inbox: Chan(MEv), +id: U32) -> IO(Unit):
  Mir.miss.go(Bool.not(Mir.is_head(q)), s, q, rq, c, inbox, id)

def Mir.looked(m: Maybe<&2, S.Meta>, s: Socket, +q: R.Req, +rq: SV.Rq, +c: MCfg, +inbox: Chan(MEv), +id: U32) -> IO(Unit):
  match m:
    case Some{x}:
      Mir.found(Some{x}, s, q, rq, c)
    case None{}:
      Mir.miss(s, q, rq, c, inbox, id)

def Mir.routed(q: R.Req, s: Socket, +rq: SV.Rq, +c: MCfg, +inbox: Chan(MEv), +id: U32) -> IO(Unit):
  match q:
    case R.Ping{h}:
      Mir.answer(s, R.Route.ping(h))
    case R.Reply{r}:
      Mir.answer(s, r)
    case R.Fetch{h, +o, +n, +d}:
      IO.bind(Maybe<&2, S.Meta>, Unit, Mir.hit(c, G.Gram.digest.show(d), id), m => Mir.looked(m, s, R.Fetch{h, o, n, d}, rq, c, inbox, id))

def Mir.parsed(m: Maybe<&2, SV.Rq>, s: Socket, +c: MCfg, +inbox: Chan(MEv), +id: U32) -> IO(Unit):
  match m:
    case None{}:
      Mir.answer(s, R.Resp{400, [R.Hdr{"Content-Length", "0"}], R.NoBody{}})
    case Some{+rq}:
      Mir.routed(R.Route.request(SV.Serve.method(rq), SV.Serve.target(rq)), s, rq, c, inbox, id)

def Mir.read.more(big: Bool, s: Socket, h: List<&2, U32>, again: Socket -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match big:
    case True{}:
      Socket.close(s)
    case False{}:
      again(s, h)

def Mir.read.cut(x: OU.Cut, s: Socket, +c: MCfg, +inbox: Chan(MEv), +id: U32, again: Socket -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match x:
    case OU.Cut{h, b, True{}}:
      Mir.parsed(SV.Serve.request(OU.Up.text(h)), s, c, inbox, id)
    case OU.Cut{+h, b, False{}}:
      Mir.read.more(U32.is_gt(UP.Upc.count(h, 0), 16384), s, h, again)

def Mir.read.got(p: Socket & Poll<&1, &1, Result<&1, &1, U32 & String, Maybe<&1, List<&2, U32>>>, Unit>, +acc: List<&2, U32>, +c: MCfg,
  +inbox: Chan(MEv), +id: U32, again: Socket -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match p:
    case (s, Ready{Done{Some{bs}}}):
      Mir.read.cut(OU.Up.cut(List.append(&2, U32, acc, bs)), s, c, inbox, id, again)
    case (s, _):
      Socket.close(s)

# Reads a request head (at most 16 KiB, 30 s a read), then answers it.
def Mir.read(n: Nat, s: Socket, +acc: List<&2, U32>, +c: MCfg, +inbox: Chan(MEv), +id: U32) -> IO(Unit):
  match n:
    case 0n:
      Socket.close(s)
    case 1n+k:
      do IO<Unit>:
        p : Socket & Poll<&1, &1, Result<&1, &1, U32 & String, Maybe<&1, List<&2, U32>>>, Unit> <- TCP.try_recv_bytes(s, 16384, 30000)
        Mir.read.got(p, acc, c, inbox, id, s2 => a2 => Mir.read(k, s2, a2, c, inbox, id))

# One connection: one request answered, then its end told.
def Mir.conn(s: Socket, +c: MCfg, +inbox: Chan(MEv), +id: U32) -> IO(Unit):
  do IO<Unit>:
    Mir.read(64n, s, [], c, inbox, id)
    Mir.tell(inbox, MGone{id})

# The main loop
# -------------

def Mir.backs.take.put(r: Maybe<&1, Chan(MMsg)> & List<&2, MBack>, hit: Bool, b: MBack) -> Maybe<&1, Chan(MMsg)> & List<&2, MBack>:
  match r:
    case (m, rest):
      match hit b:
        case True{} MBack{i, ch}:
          (Some{ch}, rest)
        case False{} MBack{i, ch}:
          (m, Con{MBack{i, ch}, rest})

def Mir.bconn(b: MBack) -> U32 & MBack:
  match b:
    case MBack{+i, ch}:
      (i, MBack{i, ch})

def Mir.backs.take.one(p: U32 & MBack, +conn: U32, r: Maybe<&1, Chan(MMsg)> & List<&2, MBack>) -> Maybe<&1, Chan(MMsg)> & List<&2, MBack>:
  match p:
    case (i, b):
      Mir.backs.take.put(r, U32.is_eq(i, conn), b)

# The channel of connection conn, taken out of the list.
def Mir.backs.take(bs: List<&2, MBack>, +conn: U32) -> Maybe<&1, Chan(MMsg)> & List<&2, MBack>:
  match bs:
    case Nil{}:
      (None{}, Nil{})
    case Con{b, t}:
      Mir.backs.take.one(Mir.bconn(b), conn, Mir.backs.take(t, conn))

def Mir.tell.back(m: Maybe<&1, Chan(MMsg)>, msg: MMsg) -> IO(Unit):
  match m:
    case None{}:
      IO.pure(Unit, Unit{})
    case Some{ch}:
      do IO<Unit>:
        _ : Result<&1, &1, MMsg, Unit> <- Chan.send(MMsg, ch, msg)
        return Unit{}

def Mir.fdig(f: MFill) -> String:
  match f:
    case MFill{d, t, m, l}:
      d

def Mir.fills.find.pick(hit: Bool, f: MFill, rest: Maybe<&2, MFill>) -> Maybe<&2, MFill>:
  match hit:
    case True{}:
      Some{f}
    case False{}:
      rest

def Mir.fills.find(fs: List<&2, MFill>, +d: String) -> Maybe<&2, MFill>:
  match fs:
    case Nil{}:
      None{}
    case Con{+f, t}:
      Mir.fills.find.pick(String.eq(Mir.fdig(f), d), f, Mir.fills.find(t, d))

def Mir.fills.drop.put(hit: Bool, f: MFill, rest: List<&2, MFill>) -> List<&2, MFill>:
  match hit:
    case True{}:
      rest
    case False{}:
      Con{f, rest}

def Mir.fills.drop(fs: List<&2, MFill>, +d: String) -> List<&2, MFill>:
  match fs:
    case Nil{}:
      Nil{}
    case Con{+f, t}:
      Mir.fills.drop.put(String.eq(Mir.fdig(f), d), f, Mir.fills.drop(t, d))

def Mir.fills.head.one(hit: Bool, f: MFill, +len: String, +media: String) -> MFill:
  match hit f:
    case True{} MFill{d, t, m, l}:
      MFill{d, t, media, len}
    case False{} MFill{d, t, m, l}:
      MFill{d, t, m, l}

# The upstream's Content-Length and Content-Type, kept with fill d.
def Mir.fills.head(fs: List<&2, MFill>, +d: String, +len: String, +media: String) -> List<&2, MFill>:
  match fs:
    case Nil{}:
      Nil{}
    case Con{+f, t}:
      Con{Mir.fills.head.one(String.eq(Mir.fdig(f), d), f, len, media), Mir.fills.head(t, d, len, media)}

def Mir.send_msg(m: Maybe<&2, MFill>, +len: String) -> MMsg:
  match m:
    case Some{MFill{d, t, md, l}}:
      MSend{len, t, md}
    case None{}:
      MReply{502, ""}

def Mir.commit.with(m: Maybe<&2, MFill>, +c: MCfg, +d: String, +now: U32) -> IO(Unit):
  match m:
    case None{}:
      IO.pure(Unit, Unit{})
    case Some{MFill{x, +t, md, +l}}:
      do IO<Unit>:
        +mp : String = Mir.meta_path(c, d)
        +b : String = Mir.blob_path(c, d)
        _ : U32 <- V.Fs.mkdir_p(M.Meta.dir(b), 493)
        _ : U.Lu.R(Unit) <- U.Lu.write(t ++ ".meta", S.Store.meta.render(S.Store.meta.new(md, Maybe.default(&2, N.Size, N.Size.read(l), N.Size.zero()), now)))
        _ : U32 <- V.Fs.rename(t ++ ".meta", mp)
        +e : U32 <- V.Fs.rename(t, b)
        Mir.say(c, d ++ Bool.pick(String, U32.is_zero(e), " cached (" ++ l ++ " bytes)", " could not be renamed into the store (errno " ++ U32.show(e) ++ ")"))

def Mir.discard.with(m: Maybe<&2, MFill>, +c: MCfg, +d: String) -> IO(Unit):
  match m:
    case None{}:
      IO.pure(Unit, Unit{})
    case Some{MFill{x, +t, md, l}}:
      do IO<Unit>:
        _ : U32 <- V.Fs.remove(t)
        Mir.say(c, d ++ " not kept (the upstream did not send it whole, or it did not match its digest)")

# The context of an event's actions: the repository and kind of the
# request that may start a fill.
type MCtx is Data:
  MCtx{repo: String, blob: Bool}

def Mir.fetch.start(ctx: MCtx, +d: String, es: List<&2, F.Entry>, bs: List<&2, MBack>, fs: List<&2, MFill>, +n: U32, +sw: U32,
  +c: MCfg, +inbox: Chan(MEv)) -> IO(MSt):
  match ctx:
    case MCtx{+repo, +blob}:
      do IO<MSt>:
        +t : String = Mir.tmp_path(c, d, n)
        IO.spawn(Unit, Mir.fetch(c, inbox, d, blob, repo, t))
        return MSt{es, bs, Con{MFill{d, t, "", ""}, fs}, (n + 1 : U32), sw}

def Mir.told(p: Maybe<&1, Chan(MMsg)> & List<&2, MBack>, msg: MMsg, es: List<&2, F.Entry>, fs: List<&2, MFill>, +n: U32, +sw: U32) -> IO(MSt):
  match p:
    case (m, rest):
      IO.bind(Unit, MSt, Mir.tell.back(m, msg), u => IO.pure(MSt, MSt{es, rest, fs, n, sw}))

def Mir.untold(p: Maybe<&1, Chan(MMsg)> & List<&2, MBack>, es: List<&2, F.Entry>, fs: List<&2, MFill>, +n: U32, +sw: U32) -> MSt:
  match p:
    case (m, rest):
      MSt{es, rest, fs, n, sw}

def Mir.act(a: F.Act, st: MSt, +ctx: MCtx, +c: MCfg, +inbox: Chan(MEv), +now: U32) -> IO(MSt):
  match a st:
    case F.Cache{k} MSt{es, bs, fs, n, sw}:
      Mir.told(Mir.backs.take(bs, k), MCache{}, es, fs, n, sw)
    case F.Pass{k} MSt{es, bs, fs, n, sw}:
      Mir.told(Mir.backs.take(bs, k), MPass{}, es, fs, n, sw)
    case F.Reply{k, s, code} MSt{es, bs, fs, n, sw}:
      Mir.told(Mir.backs.take(bs, k), MReply{s, code}, es, fs, n, sw)
    case F.Send{k, +d, len} MSt{es, bs, +fs, n, sw}:
      Mir.told(Mir.backs.take(bs, k), Mir.send_msg(Mir.fills.find(fs, d), len), es, fs, n, sw)
    case F.Abort{k} MSt{es, bs, fs, n, sw}:
      IO.pure(MSt, Mir.untold(Mir.backs.take(bs, k), es, fs, n, sw))
    case F.Fetch{+d} MSt{es, bs, fs, +n, sw}:
      Mir.fetch.start(ctx, d, es, bs, fs, n, sw, c, inbox)
    case F.Commit{+d} MSt{es, bs, +fs, n, sw}:
      IO.bind(Unit, MSt, Mir.commit.with(Mir.fills.find(fs, d), c, d, now), u => IO.pure(MSt, MSt{es, bs, Mir.fills.drop(fs, d), n, sw}))
    case F.Discard{+d} MSt{es, bs, +fs, n, sw}:
      IO.bind(Unit, MSt, Mir.discard.with(Mir.fills.find(fs, d), c, d), u => IO.pure(MSt, MSt{es, bs, Mir.fills.drop(fs, d), n, sw}))

def Mir.acts(xs: List<&2, F.Act>, st: MSt, +ctx: MCtx, +c: MCfg, +inbox: Chan(MEv), +now: U32) -> IO(MSt):
  match xs:
    case Nil{}:
      IO.pure(MSt, st)
    case Con{a, t}:
      IO.bind(MSt, MSt, Mir.act(a, st, ctx, c, inbox, now), s2 => Mir.acts(t, s2, ctx, c, inbox, now))

def Mir.with_es(st: MSt, es: List<&2, F.Entry>) -> MSt:
  match st:
    case MSt{x, bs, fs, n, sw}:
      MSt{es, bs, fs, n, sw}

def Mir.es(st: MSt) -> List<&2, F.Entry> & MSt:
  match st:
    case MSt{es, bs, fs, n, sw}:
      (es, MSt{[], bs, fs, n, sw})

# One fill-machine event: its new fills, then its actions done in order.
def Mir.step.out(o: F.Out, st: MSt, +ctx: MCtx, +c: MCfg, +inbox: Chan(MEv), +now: U32) -> IO(MSt):
  match o:
    case F.Out{es, acts}:
      Mir.acts(acts, Mir.with_es(st, es), ctx, c, inbox, now)

def Mir.step.go(p: List<&2, F.Entry> & MSt, ev: F.Ev, +ctx: MCtx, +c: MCfg, +inbox: Chan(MEv), +now: U32) -> IO(MSt):
  match p:
    case (es, st):
      Mir.step.out(F.Fill.step(F.Fill.limits(), es, ev), st, ctx, c, inbox, now)

def Mir.step(st: MSt, ev: F.Ev, +ctx: MCtx, +c: MCfg, +inbox: Chan(MEv), +now: U32) -> IO(MSt):
  Mir.step.go(Mir.es(st), ev, ctx, c, inbox, now)

def Mir.add_back(st: MSt, +conn: U32, back: Chan(MMsg)) -> MSt:
  match st:
    case MSt{es, bs, fs, n, sw}:
      MSt{es, Con{MBack{conn, back}, bs}, fs, n, sw}

def Mir.drop_back(st: MSt, +conn: U32) -> MSt:
  match st:
    case MSt{es, bs, fs, n, sw}:
      Mir.untold(Mir.backs.take(bs, conn), es, fs, n, sw)

def Mir.ev(ev: MEv, st: MSt, +c: MCfg, +inbox: Chan(MEv), +now: U32) -> IO(MSt):
  match ev:
    case MGet{+k, +d, +b, r, +repo, back}:
      do IO<MSt>:
        there : Maybe<&2, N.Size> <- Mir.size(Mir.blob_path(c, d))
        Mir.step(Mir.add_back(st, k, back), F.Get{k, d, b, Maybe.is_some(&2, N.Size, there), r, now}, MCtx{repo, b}, c, inbox, now)
    case MHead{+d, s, +len, +media}:
      match st:
        case MSt{es, bs, fs, n, sw}:
          Mir.step(MSt{es, bs, Mir.fills.head(fs, d, len, media), n, sw}, F.Head{d, s, len}, MCtx{"", False{}}, c, inbox, now)
    case MEnded{d, got}:
      Mir.step(st, F.Ended{d, got}, MCtx{"", False{}}, c, inbox, now)
    case MBroke{d}:
      Mir.step(st, F.Broke{d}, MCtx{"", False{}}, c, inbox, now)
    case MGone{+k}:
      Mir.step(Mir.drop_back(st, k), F.Gone{k}, MCtx{"", False{}}, c, inbox, now)

def Mir.drain.go(p: Poll<&1, &1, Maybe<&1, MEv>, Unit>, st: MSt, +c: MCfg, +inbox: Chan(MEv), +now: U32, more: MSt -> IO(MSt)) -> IO(MSt):
  match p:
    case Ready{Some{ev}}:
      IO.bind(MSt, MSt, Mir.ev(ev, st, c, inbox, now), more)
    case _:
      IO.pure(MSt, st)

# The events sent since the last round (at most n).
def Mir.drain(n: Nat, st: MSt, +c: MCfg, +inbox: Chan(MEv), +now: U32) -> IO(MSt):
  match n:
    case 0n:
      IO.pure(MSt, st)
    case 1n+k:
      do IO<MSt>:
        r : Poll<&1, &1, Maybe<&1, MEv>, Unit> <- Chan.try_recv(MEv, inbox, 0)
        Mir.drain.go(r, st, c, inbox, now, s2 => Mir.drain(k, s2, c, inbox, now))

# Sweeping
# --------

def Mir.when(ok: Bool, act: IO(Unit)) -> IO(Unit):
  match ok:
    case True{}:
      act
    case False{}:
      IO.pure(Unit, Unit{})

# Removes the store's objects unused for 72 h (Store.sweep): how many
# files.
def Mir.sweep(+c: MCfg, +now: U32) -> IO(Unit):
  do IO<Unit>:
    +root : String = MCfg.root(c)
    +reg : String = MCfg.reg(c)
    subs : List<String> <- V.Fs.ls(root ++ "/" ++ reg ++ "/blobs/sha256")
    items : List<&2, S.Item> <- LF.Lf.items.abs(subs, reg, root ++ "/" ++ reg ++ "/blobs/sha256")
    +k : U32 <- LF.Lf.rm.files(S.Store.sweep(root, now, items), 0)
    Mir.when(Bool.not(U32.is_zero(k)), Mir.say(c, "swept " ++ U32.show(k) ++ " files unused for 72 h"))

def Mir.sweep.due(due: Bool, st: MSt, +c: MCfg, +now: U32) -> IO(MSt):
  match due st:
    case True{} MSt{es, bs, fs, n, sw}:
      do IO<MSt>:
        IO.spawn(Unit, Mir.sweep(c, now))
        return MSt{es, bs, fs, n, now}
    case False{} s:
      IO.pure(MSt, s)

def Mir.swept(st: MSt) -> U32 & MSt:
  match st:
    case MSt{es, bs, fs, n, +sw}:
      (sw, MSt{es, bs, fs, n, sw})

def Mir.sweep.check(p: U32 & MSt, +c: MCfg, +now: U32) -> IO(MSt):
  match p:
    case (+sw, st):
      Mir.sweep.due(U32.is_ge(now, sw) && U32.is_ge((now - sw : U32), 3600), st, c, now)

def Mir.next(st: MSt) -> U32 & MSt:
  match st:
    case MSt{es, bs, fs, +n, sw}:
      (n, MSt{es, bs, fs, (n + 1 : U32), sw})

def Mir.spawn(p: U32 & MSt, sock: Socket, +c: MCfg, +inbox: Chan(MEv), l: Listener, next: Listener -> MSt -> IO(Unit)) -> IO(Unit):
  match p:
    case (id, st):
      do IO<Unit>:
        IO.spawn(Unit, Mir.conn(sock, c, inbox, id))
        next(l, st)

def Mir.got(r: Listener & Poll<&1, &1, Result<&1, &1, U32 & String, Socket>, Unit>, +c: MCfg, +inbox: Chan(MEv), st: MSt,
  next: Listener -> MSt -> IO(Unit)) -> IO(Unit):
  match r:
    case (l, Ready{Done{sock}}):
      Mir.spawn(Mir.next(st), sock, c, inbox, l, next)
    case (l, Ready{Fail{(code, msg)}}):
      do IO<Unit>:
        Mir.say(c, "accept failed: " ++ msg)
        IO.sleep(100)
        next(l, st)
    case (l, Wait{u}):
      next(l, st)

# Each round: the events drained, the machine's clock ticked (late
# waiters get 504), the hourly sweep, then up to 50 ms for a connection.
def Mir.loop(n: Nat, l: Listener, +c: MCfg, +inbox: Chan(MEv), st: MSt) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+k:
      do IO<Unit>:
        +now : U32 <- U.Lu.now()
        s1 : MSt <- Mir.drain(256n, st, c, inbox, now)
        s2 : MSt <- Mir.step(s1, F.Tick{now}, MCtx{"", False{}}, c, inbox, now)
        s3 : MSt <- Mir.sweep.check(Mir.swept(s2), c, now)
        r : Listener & Poll<&1, &1, Result<&1, &1, U32 & String, Socket>, Unit> <- TCP.try_accept(l, 50)
        Mir.got(r, c, inbox, s3, l2 => s4 => Mir.loop(k, l2, c, inbox, s4))

# Starting
# --------

def Mir.run(l: Listener, +c: MCfg) -> IO(Unit):
  do IO<Unit>:
    +inbox : Chan(MEv) <- Chan.new(MEv, 4096)
    Mir.loop(Mir.forever(), l, c, inbox, MSt{[], [], [], 1, 0})

def Mir.listened(r: Result<&1, &1, U32 & String, Listener>, +c: MCfg) -> IO(Maybe<&1, Listener>):
  match r:
    case Fail{(e, m)}:
      do IO<Maybe<&1, Listener>>:
        Mir.say(c, "cannot listen on 127.0.0.1:" ++ U32.show(MCfg.port(c)) ++ ": " ++ m)
        return None{}
    case Done{l}:
      IO.pure(Maybe<&1, Listener>, Some{l})

def Mir.start.ok(ok: Bool, l: Listener, +c: MCfg) -> IO(Bool):
  match ok:
    case True{}:
      do IO<Bool>:
        Mir.say(c, "mirror on 127.0.0.1:" ++ U32.show(MCfg.port(c)) ++ ", store " ++ MCfg.root(c))
        IO.spawn(Unit, Mir.run(l, c))
        return True{}
    case False{}:
      IO.pure(Bool, False{})

def Mir.start.one(m: Maybe<&1, Listener>, +c: MCfg, rest: IO(Bool)) -> IO(Bool):
  match m:
    case None{}:
      IO.pure(Bool, False{})
    case Some{l}:
      do IO<Bool>:
        ok : Bool <- rest
        Mir.start.ok(ok, l, c)

# Listens on every port first, so a second `vk8s cache serve` fails
# before it touches the store; then each port's loop starts.
def Mir.start(cs: List<&2, MCfg>) -> IO(Bool):
  match cs:
    case Nil{}:
      IO.pure(Bool, True{})
    case Con{+c, t}:
      do IO<Bool>:
        r : Result<&1, &1, U32 & String, Listener> <- TCP.listen("127.0.0.1", MCfg.port(c))
        m : Maybe<&1, Listener> <- Mir.listened(r, c)
        Mir.start.one(m, c, Mir.start(t))

def Mir.stop.go(asked: Bool, +stop: String, again: IO(Unit)) -> IO(Unit):
  match asked:
    case True{}:
      do IO<Unit>:
        _ : U32 <- V.Fs.remove(stop)
        IO.print("vk8s cache serve: stopped (asked through " ++ stop ++ ")")
        IO.exit(0)
    case False{}:
      again

# Every half second: the file stop there asks the mirror to exit (vk8s
# cache stop writes it).
def Mir.stop.watch(n: Nat, +stop: String) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+k:
      do IO<Unit>:
        IO.sleep(500)
        ws : +List<U32> <- HV.Hvf.path_facts(stop)
        Mir.stop.go(Bool.not(U32.is_zero(Maybe.default(&2, U32, List.head(&2, U32, ws), 0))), stop, Mir.stop.watch(k, stop))

def Mir.started(ok: Bool, +root: String, +stop: String) -> IO(Unit):
  match ok:
    case False{}:
      IO.die(Unit, 1, "vk8s cache serve: could not listen on every port (is another image cache running?)")
    case True{}:
      do IO<Unit>:
        U.Lu.drop(root ++ "/tmp")
        _ : U32 <- V.Fs.mkdir_p(root ++ "/tmp", 448)
        Mir.stop.watch(Mir.forever(), stop)

# `vk8s cache serve` with the store at root: the image cache's mirrors,
# until the file stop appears (or a signal). Fill files a killed
# predecessor left in root/tmp are removed once every port listens.
def Mir.main(+root: String, +stop: String) -> IO(Unit):
  do IO<Unit>:
    _ : U32 <- V.Fs.mkdir_p(root, 448)
    ok : Bool <- Mir.start(Mir.cfgs(LF.Lf.mirrors(PL.Plan.mirrors()), root))
    Mir.started(ok, root, stop)

# `vk8s cache status` and `vk8s cache prune`
# ------------------------------------------

def Mir.item.size(it: S.Item, +root: String) -> IO(N.Size):
  match it:
    case S.Item{r, d, m}:
      IO.bind(Maybe<&2, N.Size>, N.Size, Mir.size(Maybe.default(&2, String, S.Store.blob_path(root, r, d), "")),
        z => IO.pure(N.Size, Maybe.default(&2, N.Size, z, N.Size.zero())))

def Mir.items.size(its: List<&2, S.Item>, +root: String, +acc: N.Size) -> IO(N.Size):
  match its:
    case Nil{}:
      IO.pure(N.Size, acc)
    case Con{it, t}:
      IO.bind(N.Size, N.Size, Mir.item.size(it, root), z => Mir.items.size(t, root, N.Size.add(acc, z)))

# The bytes of registry reg's objects in the store at root.
def Mir.reg.size(+root: String, +reg: String) -> IO(N.Size):
  do IO<N.Size>:
    subs : List<String> <- V.Fs.ls(root ++ "/" ++ reg ++ "/blobs/sha256")
    items : List<&2, S.Item> <- LF.Lf.items.abs(subs, reg, root ++ "/" ++ reg ++ "/blobs/sha256")
    Mir.items.size(items, root, N.Size.zero())

# One "KiB<TAB>registry" line per registry (as du -sk prints them, which
# C.Cli.cache_sizes reads).
def Mir.usage(regs: +List<String>, +root: String) -> IO(String):
  match regs:
    case Nil{}:
      IO.pure(String, "")
    case Con{+r, t}:
      do IO<String>:
        z : N.Size <- Mir.reg.size(root, r)
        rest : String <- Mir.usage(t, root)
        return U32.show(SV.Serve.kib(z)) ++ "\t" ++ r ++ "\n" ++ rest

def Mir.prune.paths(ps: List<&2, String>) -> IO(Unit):
  match ps:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+p, t}:
      do IO<Unit>:
        U.Lu.drop(p)
        Mir.prune.paths(t)

# Removes registries' directories from the store (every registry and
# tmp/ when all; Store.prune); a running mirror fills them again.
def Mir.prune(+root: String, +regs: +List<String>, all: Bool) -> IO(Unit):
  Mir.prune.paths(Bool.pick(List<&2, String>, all, S.Store.prune(root, regs), S.Store.prune.dirs(regs, root)))
