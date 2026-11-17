import Base
import ../host/oci/blob.bend as B
import ../host/tls_server.bend as S

# The OCI blob effects' test program. tests/oci_blob.sh builds it and runs
#
#   oci_blob_echo PORT DIR SRC CERT KEY HI LO OFF_HI OFF_LO LEN_HI LEN_LO
#
# which serves, until killed, one listener per job on 127.0.0.1:
# - PORT: plain TCP. Fetches a blob of HI * 2^32 + LO bytes into
#   DIR/plain.blob: the first chunk TCP.recv_bytes gives is the head, as an
#   HTTP parser leaves it, and OciBlob.fetch reads the rest. Then
#   OciBlob.commit, and the hex SHA-256 goes back as one line ("error
#   ..." on a failure) before the socket closes.
# - PORT+1: the same over TLS (TlsSrv.handshake), into DIR/tls.blob.
# - PORT+2: plain TCP. Sends the whole file SRC (OciBlob.open, then
#   OciBlob.send of its size), then closes.
# - PORT+3: the same over TLS.
# - PORT+4: plain TCP. Sends LEN_HI * 2^32 + LEN_LO bytes of SRC from
#   OFF_HI * 2^32 + OFF_LO.
# CERT and KEY are the TLS server's PEM files. "ready" on stdout means
# all listen; each finished job prints a line ("fetched HEX", "sent", or
# why not). Each connection runs in its own computation.
#
# Run with no arguments (scripts/check.sh runs it so, through `bend` on
# the JavaScript lane) it only opens a missing file: the lane's stand-in
# must fail with ENOSYS (38), a native build with ENOENT (2).

def Res(-A: Type) -> Type:
  Result<&1, &1, U32 & String, A>

type Job is Data:
  JFetch{path: String, hi: U32, lo: U32}
  JSend{src: String, off_hi: U32, off_lo: U32, len_hi: U32, len_lo: U32, whole: Bool}

def Main.forever() -> Nat:
  U32.to_nat(4294967295)

# 64-bit sizes
# ------------

def Bytes.count(xs: List<&2, U32>, +n: U32) -> U32:
  match xs:
    case Nil{}:
      n
    case Con{h, t}:
      Bytes.count(t, (n + 1 : U32))

def Big.sub.go(borrow: Bool, +hi: U32, +lo: U32, +k: U32) -> U32 & U32:
  match borrow:
    case True{}:
      ((hi - 1 : U32), (lo - k : U32))
    case False{}:
      (hi, (lo - k : U32))

# hi * 2^32 + lo, less k.
def Big.sub(+hi: U32, +lo: U32, +k: U32) -> U32 & U32:
  Big.sub.go(U32.is_lt(lo, k), hi, lo, k)

# Connections
# -----------

def Conn.close(tls: Bool, s: Socket) -> IO(Unit):
  match tls:
    case True{}:
      S.TlsSrv.close(s)
    case False{}:
      Socket.close(s)

def Conn.end_tls(q: Socket & Res(Unit)) -> IO(Unit):
  match q:
    case (s, r):
      S.TlsSrv.close(s)

def Conn.end_tcp(q: Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>) -> IO(Unit):
  match q:
    case (s, r):
      Socket.close(s)

# Sends a line, then closes.
def Conn.say(tls: Bool, s: Socket, text: String) -> IO(Unit):
  match tls:
    case True{}:
      do IO<Unit>:
        q : Socket & Res(Unit) <- S.TlsSrv.send(s, text, 10000)
        Conn.end_tls(q)
    case False{}:
      do IO<Unit>:
        q : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send(s, text)
        Conn.end_tcp(q)

def Conn.recv(tls: Bool, s: Socket) -> IO(Socket & Res(Maybe<&1, List<&2, U32>>)):
  match tls:
    case True{}:
      S.TlsSrv.recv(s, 65536, 30000)
    case False{}:
      TCP.recv_bytes(s, 65536)

# Fetch
# -----

# Prints why a fetch failed, and answers it on the socket.
def Fetch.bad(tls: Bool, s: Socket, +why: String) -> IO(Unit):
  do IO<Unit>:
    IO.print(why)
    Conn.say(tls, s, "error " ++ why ++ "\n")

def Fetch.answer(r: Res(Unit), d: Res(String), tls: Bool, s: Socket) -> IO(Unit):
  match r d:
    case Done{u} Done{+hex}:
      do IO<Unit>:
        IO.print("fetched " ++ hex)
        Conn.say(tls, s, hex ++ "\n")
    case Fail{(c, m)} _:
      Fetch.bad(tls, s, "fetch failed: " ++ m ++ " (errno " ++ U32.show(c) ++ ")")
    case Done{u} Fail{(c, m)}:
      Fetch.bad(tls, s, "commit failed: " ++ m ++ " (errno " ++ U32.show(c) ++ ")")

def Fetch.fetched(q: File & (Socket & Res(Unit)), tls: Bool) -> IO(Unit):
  match q:
    case (f, (s, r)):
      do IO<Unit>:
        d : Res(String) <- B.OciBlob.commit(f)
        Fetch.answer(r, d, tls, s)

def Fetch.created(r: Res(File), tls: Bool, s: Socket, head: List<&2, U32>, hi: U32, lo: U32) -> IO(Unit):
  match r:
    case Fail{(c, m)}:
      do IO<Unit>:
        IO.print("create failed: " ++ m)
        Conn.close(tls, s)
    case Done{f}:
      do IO<Unit>:
        q : File & (Socket & Res(Unit)) <- B.OciBlob.fetch(f, s, head, hi, lo, 30000)
        Fetch.fetched(q, tls)

def Fetch.blob(n: U32 & U32, tls: Bool, s: Socket, head: List<&2, U32>, path: String) -> IO(Unit):
  match n:
    case (hi, lo):
      do IO<Unit>:
        r : Res(File) <- B.OciBlob.create(path)
        Fetch.created(r, tls, s, head, hi, lo)

def Fetch.first(p: Socket & Res(Maybe<&1, List<&2, U32>>), tls: Bool, path: String, +hi: U32, +lo: U32) ->
  IO(Unit):
  match p:
    case (s, Done{Some{+bs}}):
      Fetch.blob(Big.sub(hi, lo, Bytes.count(bs, 0)), tls, s, bs, path)
    case (s, Done{None{}}):
      Conn.close(tls, s)
    case (s, Fail{e}):
      Conn.close(tls, s)

def Fetch.go(+tls: Bool, s: Socket, path: String, hi: U32, lo: U32) -> IO(Unit):
  do IO<Unit>:
    p : Socket & Res(Maybe<&1, List<&2, U32>>) <- Conn.recv(tls, s)
    Fetch.first(p, tls, path, hi, lo)

# Send
# ----

def Send.said(r: Res(Unit)) -> IO(Unit):
  match r:
    case Done{u}:
      IO.print("sent")
    case Fail{(c, m)}:
      IO.print("send failed: " ++ m ++ " (errno " ++ U32.show(c) ++ ")")

def Send.sent(q: Socket & (File & Res(Unit)), tls: Bool) -> IO(Unit):
  match q:
    case (s, (f, r)):
      do IO<Unit>:
        File.close(f)
        Send.said(r)
        Conn.close(tls, s)

def Send.run(tls: Bool, s: Socket, f: File, off_hi: U32, off_lo: U32, len_hi: U32, len_lo: U32) -> IO(Unit):
  do IO<Unit>:
    q : Socket & (File & Res(Unit)) <- B.OciBlob.send(s, f, off_hi, off_lo, len_hi, len_lo, 30000)
    Send.sent(q, tls)

def Send.range(whole: Bool, tls: Bool, s: Socket, f: File, hi: U32, lo: U32, off_hi: U32, off_lo: U32,
  len_hi: U32, len_lo: U32) -> IO(Unit):
  match whole:
    case True{}:
      Send.run(tls, s, f, 0, 0, hi, lo)
    case False{}:
      Send.run(tls, s, f, off_hi, off_lo, len_hi, len_lo)

def Send.opened(r: Res(File & (U32 & U32)), whole: Bool, tls: Bool, s: Socket, off_hi: U32, off_lo: U32,
  len_hi: U32, len_lo: U32) -> IO(Unit):
  match r:
    case Fail{(c, m)}:
      do IO<Unit>:
        IO.print("open failed: " ++ m)
        Conn.close(tls, s)
    case Done{(f, (hi, lo))}:
      Send.range(whole, tls, s, f, hi, lo, off_hi, off_lo, len_hi, len_lo)

def Send.go(tls: Bool, s: Socket, src: String, whole: Bool, off_hi: U32, off_lo: U32, len_hi: U32,
  len_lo: U32) -> IO(Unit):
  do IO<Unit>:
    r : Res(File & (U32 & U32)) <- B.OciBlob.open(src)
    Send.opened(r, whole, tls, s, off_hi, off_lo, len_hi, len_lo)

# Serving
# -------

def Job.run(j: Job, tls: Bool, s: Socket) -> IO(Unit):
  match j:
    case JFetch{path, hi, lo}:
      Fetch.go(tls, s, path, hi, lo)
    case JSend{src, off_hi, off_lo, len_hi, len_lo, whole}:
      Send.go(tls, s, src, whole, off_hi, off_lo, len_hi, len_lo)

def Srv.start(r: Res(Socket), job: Job) -> IO(Unit):
  match r:
    case Done{s}:
      Job.run(job, True{}, s)
    case Fail{(c, m)}:
      IO.print_err("handshake: " ++ m)

def Srv.conn(tls: Bool, s: Socket, cert: String, key: String, job: Job) -> IO(Unit):
  match tls:
    case True{}:
      do IO<Unit>:
        r : Res(Socket) <- S.TlsSrv.handshake(s, cert, key, "", 10000)
        Srv.start(r, job)
    case False{}:
      Job.run(job, False{}, s)

def Srv.got(r: Listener & Res(Socket), +tls: Bool, +cert: String, +key: String, +job: Job,
  again: Listener -> IO(Unit)) -> IO(Unit):
  match r:
    case (l, Done{s}):
      do IO<Unit>:
        IO.spawn(Unit, Srv.conn(tls, s, cert, key, job))
        again(l)
    case (l, Fail{(c, m)}):
      do IO<Unit>:
        IO.print_err("accept: " ++ m)
        again(l)

def Srv.loop(n: Nat, l: Listener, +tls: Bool, +cert: String, +key: String, +job: Job) -> IO(Unit):
  match n:
    case 0n:
      Listener.close(l)
    case 1n+p:
      do IO<Unit>:
        r : Listener & Res(Socket) <- TCP.accept(l)
        Srv.got(r, tls, cert, key, job, l2 => Srv.loop(p, l2, tls, cert, key, job))

# Starting
# --------

def Main.listener(r: Res(Listener)) -> IO(Listener):
  match r:
    case Done{l}:
      IO.pure(Listener, l)
    case Fail{(c, m)}:
      IO.die(Listener, 1, "listen: " ++ m)

def Main.listen(+port: U32, +k: U32) -> IO(Listener):
  do IO<Listener>:
    r : Res(Listener) <- TCP.listen("127.0.0.1", (port + k : U32))
    Main.listener(r)

def Main.serve(+port: U32, +dir: String, +src: String, +cert: String, +key: String, +hi: U32, +lo: U32,
  +off_hi: U32, +off_lo: U32, +len_hi: U32, +len_lo: U32) -> IO(Unit):
  do IO<Unit>:
    l0 : Listener <- Main.listen(port, 0)
    l1 : Listener <- Main.listen(port, 1)
    l2 : Listener <- Main.listen(port, 2)
    l3 : Listener <- Main.listen(port, 3)
    l4 : Listener <- Main.listen(port, 4)
    IO.spawn(Unit, Srv.loop(Main.forever(), l0, False{}, cert, key, JFetch{dir ++ "/plain.blob", hi, lo}))
    IO.spawn(Unit, Srv.loop(Main.forever(), l1, True{}, cert, key, JFetch{dir ++ "/tls.blob", hi, lo}))
    IO.spawn(Unit, Srv.loop(Main.forever(), l2, False{}, cert, key, JSend{src, 0, 0, 0, 0, True{}}))
    IO.spawn(Unit, Srv.loop(Main.forever(), l3, True{}, cert, key, JSend{src, 0, 0, 0, 0, True{}}))
    IO.spawn(Unit, Srv.loop(Main.forever(), l4, False{}, cert, key, JSend{src, off_hi, off_lo, len_hi, len_lo, False{}}))
    IO.print("ready")

def Main.num(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{n}:
      n
    case None{}:
      0

def Main.lane.say(enosys: Bool, enoent: Bool, m: String) -> IO(Unit):
  match enosys enoent:
    case True{} _:
      IO.print("PASS oci_blob_echo: the JavaScript stand-in fails with ENOSYS")
    case False{} True{}:
      IO.print("PASS oci_blob_echo: OciBlob.open answers ENOENT (native lane)")
    case False{} False{}:
      IO.print("FAIL oci_blob_echo: OciBlob.open: " ++ m)

def Main.lane.code(+c: U32, m: String) -> IO(Unit):
  Main.lane.say(U32.is_eq(c, 38), U32.is_eq(c, 2), m)

def Main.lane(r: Res(File & (U32 & U32))) -> IO(Unit):
  match r:
    case Fail{(c, m)}:
      Main.lane.code(c, m)
    case Done{(f, n)}:
      do IO<Unit>:
        File.close(f)
        IO.print("FAIL oci_blob_echo: a missing file opened")

def Main.args(args: List<String>) -> IO(Unit):
  match args:
    case Con{_, Con{port, Con{dir, Con{src, Con{cert, Con{key, Con{hi, Con{lo, Con{off_hi, Con{off_lo, Con{len_hi, Con{len_lo, _}}}}}}}}}}}}:
      Main.serve(Main.num(U32.read(port)), dir, src, cert, key, Main.num(U32.read(hi)),
        Main.num(U32.read(lo)), Main.num(U32.read(off_hi)), Main.num(U32.read(off_lo)),
        Main.num(U32.read(len_hi)), Main.num(U32.read(len_lo)))
    case _:
      do IO<Unit>:
        r : Res(File & (U32 & U32)) <- B.OciBlob.open("/nonexistent-oci-blob/missing")
        Main.lane(r)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    Main.args(args)
