import Base
import ../host/tls_server.bend as S
import ../src/net/subject.bend as T

# The TLS server's test program. tests/tls_server.sh builds it and runs
#
#   tls_server_echo PORT CERT KEY CA
#
# which serves, until killed:
# - PORT: TLS. A request that starts with "GET " gets an HTTP answer whose
#   body is the verified client's subject (cn=, one o= per group,
#   subject=), or why there is none; anything else is echoed back until
#   the client closes or a chunk ends with "BYE\n".
# - PORT+1: TLS, spliced (TlsSrv.splice) to the plain backend on PORT+2.
# - PORT+2: plain TCP; echoes each chunk upper-cased, and closes after a
#   chunk that ends with "BYE\n".
# CA "" asks no client certificate. "ready" on stdout means all three
# listen. Each connection runs in its own computation.
#
# Run with no arguments (scripts/check.sh runs it so, through `bend` on
# the JavaScript lane) it only checks TlsSrv.listen: the lane's stand-in
# must fail with ENOSYS; a native build must listen.

def Res(-A: Type) -> Type:
  Result<&1, &1, U32 & String, A>

def Echo.forever() -> Nat:
  U32.to_nat(4294967295)

def Echo.upper.pick(low: Bool, +b: U32) -> U32:
  match low:
    case True{}:
      (b - 32 : U32)
    case False{}:
      b

def Echo.upper.one(+b: U32) -> U32:
  Echo.upper.pick(Bool.and(U32.is_ge(b, 97), U32.is_le(b, 122)), b)

def Echo.upper(bs: List<&2, U32>) -> List<&2, U32>:
  match bs:
    case Nil{}:
      Nil{}
    case Con{b, t}:
      Con{Echo.upper.one(b), Echo.upper(t)}

def Echo.is_get(bs: List<&2, U32>) -> Bool:
  match bs:
    case Con{71, Con{69, Con{84, Con{32, t}}}}:
      True{}
    case _:
      False{}

def Echo.is_bye.rev(rs: List<&2, U32>) -> Bool:
  match rs:
    case Con{10, Con{69, Con{89, Con{66, t}}}}:
      True{}
    case _:
      False{}

# Does a chunk end with "BYE\n"? The client's last words: the echo (or the
# backend) answers them, then closes.
def Echo.is_bye(bs: List<&2, U32>) -> Bool:
  Echo.is_bye.rev(List.reverse(&2, U32, bs))

# The plain backend
# -----------------

def Back.sent.go(bye: Bool, s: Socket, again: Socket -> IO(Unit)) -> IO(Unit):
  match bye:
    case True{}:
      Socket.close(s)
    case False{}:
      again(s)

def Back.sent(q: Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>, bye: Bool,
  again: Socket -> IO(Unit)) -> IO(Unit):
  match q:
    case (s, Done{u}):
      Back.sent.go(bye, s, again)
    case (s, Fail{e}):
      Socket.close(s)

def Back.serve.got(p: Socket & Res(Maybe<&1, List<&2, U32>>), again: Socket -> IO(Unit)) -> IO(Unit):
  match p:
    case (s, Done{Some{+bs}}):
      do IO<Unit>:
        q : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send_bytes(s, Echo.upper(bs))
        Back.sent(q, Echo.is_bye(bs), again)
    case (s, Done{None{}}):
      Socket.close(s)
    case (s, Fail{e}):
      Socket.close(s)

def Back.serve(n: Nat, s: Socket) -> IO(Unit):
  match n:
    case 0n:
      Socket.close(s)
    case 1n+p:
      do IO<Unit>:
        r : Socket & Res(Maybe<&1, List<&2, U32>>) <- TCP.recv_bytes(s, 16384)
        Back.serve.got(r, s2 => Back.serve(p, s2))

def Back.got(r: Listener & Res(Socket), again: Listener -> IO(Unit)) -> IO(Unit):
  match r:
    case (l, Done{s}):
      do IO<Unit>:
        IO.spawn(Unit, Back.serve(Echo.forever(), s))
        again(l)
    case (l, Fail{(c, m)}):
      do IO<Unit>:
        IO.print_err("backend accept: " ++ m)
        again(l)

def Back.loop(n: Nat, l: Listener) -> IO(Unit):
  match n:
    case 0n:
      Listener.close(l)
    case 1n+p:
      do IO<Unit>:
        r : Listener & Res(Socket) <- TCP.accept(l)
        Back.got(r, l2 => Back.loop(p, l2))

# The TLS echo
# ------------

def Echo.lines(os: +List<String>) -> String:
  match os:
    case Nil{}:
      ""
    case Con{o, t}:
      "o=" ++ o ++ "\n" ++ Echo.lines(t)

def Echo.body.of(s: T.Subject, text: String) -> String:
  match s:
    case T.Subject{cn, os}:
      "cn=" ++ cn ++ "\n" ++ Echo.lines(os) ++ "subject=" ++ text ++ "\n"

def Echo.body(r: Res(String)) -> String:
  match r:
    case Fail{(c, m)}:
      "no client certificate: " ++ m ++ " (errno " ++ U32.show(c) ++ ")\n"
    case Done{+text}:
      Echo.body.of(T.Subject.parse(text), text)

def Echo.end(q: Socket & Res(Unit)) -> IO(Unit):
  match q:
    case (s, r):
      S.TlsSrv.close(s)

def Echo.http(p: Socket & Res(String)) -> IO(Unit):
  match p:
    case (s, r):
      do IO<Unit>:
        q : Socket & Res(Unit) <- S.TlsSrv.send(s, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n" ++ Echo.body(r), 10000)
        Echo.end(q)

def Echo.sent.go(bye: Bool, s: Socket, again: Socket -> IO(Unit)) -> IO(Unit):
  match bye:
    case True{}:
      S.TlsSrv.close(s)
    case False{}:
      again(s)

def Echo.sent(q: Socket & Res(Unit), bye: Bool, again: Socket -> IO(Unit)) -> IO(Unit):
  match q:
    case (s, Done{u}):
      Echo.sent.go(bye, s, again)
    case (s, Fail{e}):
      S.TlsSrv.close(s)

def Echo.got(p: Socket & Res(Maybe<&1, List<&2, U32>>), again: Socket -> IO(Unit)) -> IO(Unit):
  match p:
    case (s, Done{Some{+bs}}):
      do IO<Unit>:
        q : Socket & Res(Unit) <- S.TlsSrv.send_bytes(s, bs, 10000)
        Echo.sent(q, Echo.is_bye(bs), again)
    case (s, Done{None{}}):
      S.TlsSrv.close(s)
    case (s, Fail{e}):
      S.TlsSrv.close(s)

def Echo.loop(n: Nat, s: Socket) -> IO(Unit):
  match n:
    case 0n:
      S.TlsSrv.close(s)
    case 1n+p:
      do IO<Unit>:
        r : Socket & Res(Maybe<&1, List<&2, U32>>) <- S.TlsSrv.recv(s, 16384, 0)
        Echo.got(r, s2 => Echo.loop(p, s2))

def Echo.route(get: Bool, s: Socket, +bs: List<&2, U32>) -> IO(Unit):
  match get:
    case True{}:
      do IO<Unit>:
        p : Socket & Res(String) <- S.TlsSrv.peer(s)
        Echo.http(p)
    case False{}:
      do IO<Unit>:
        q : Socket & Res(Unit) <- S.TlsSrv.send_bytes(s, bs, 10000)
        Echo.sent(q, Echo.is_bye(bs), s2 => Echo.loop(Echo.forever(), s2))

def Echo.first(p: Socket & Res(Maybe<&1, List<&2, U32>>)) -> IO(Unit):
  match p:
    case (s, Done{Some{+bs}}):
      Echo.route(Echo.is_get(bs), s, bs)
    case (s, Done{None{}}):
      S.TlsSrv.close(s)
    case (s, Fail{e}):
      S.TlsSrv.close(s)

def Echo.serve(s: Socket) -> IO(Unit):
  do IO<Unit>:
    p : Socket & Res(Maybe<&1, List<&2, U32>>) <- S.TlsSrv.recv(s, 16384, 30000)
    Echo.first(p)

# The spliced front
# -----------------

def Front.joined(s: Socket, r: Res(Socket)) -> IO(Unit):
  match r:
    case Done{b}:
      S.TlsSrv.splice(s, b)
    case Fail{(c, m)}:
      do IO<Unit>:
        IO.print_err("backend connect: " ++ m)
        S.TlsSrv.close(s)

def Front.serve(s: Socket, +back: U32) -> IO(Unit):
  do IO<Unit>:
    r : Res(Socket) <- TCP.connect("127.0.0.1", back)
    Front.joined(s, r)

# Accepting
# ---------

# A connection's handshake and its service run in their own computation,
# so a slow client never holds up the listener.
def Srv.conn.go(r: Res(Socket), splice: Bool, +back: U32) -> IO(Unit):
  match r splice:
    case Fail{(c, m)} _:
      IO.print_err("handshake: " ++ m ++ " (errno " ++ U32.show(c) ++ ")")
    case Done{s} True{}:
      Front.serve(s, back)
    case Done{s} False{}:
      Echo.serve(s)

def Srv.conn(s: Socket, +cert: String, +key: String, +ca: String, +splice: Bool, +back: U32) -> IO(Unit):
  do IO<Unit>:
    r : Res(Socket) <- S.TlsSrv.handshake(s, cert, key, ca, 10000)
    Srv.conn.go(r, splice, back)

def Srv.got(r: Listener & Res(Socket), +cert: String, +key: String, +ca: String, +splice: Bool, +back: U32,
  again: Listener -> IO(Unit)) -> IO(Unit):
  match r:
    case (l, Done{s}):
      do IO<Unit>:
        IO.spawn(Unit, Srv.conn(s, cert, key, ca, splice, back))
        again(l)
    case (l, Fail{(c, m)}):
      do IO<Unit>:
        IO.print_err("accept: " ++ m)
        again(l)

def Srv.loop(n: Nat, l: Listener, +cert: String, +key: String, +ca: String, +splice: Bool, +back: U32) -> IO(Unit):
  match n:
    case 0n:
      Listener.close(l)
    case 1n+p:
      do IO<Unit>:
        r : Listener & Res(Socket) <- TCP.accept(l)
        Srv.got(r, cert, key, ca, splice, back, l2 => Srv.loop(p, l2, cert, key, ca, splice, back))

# Starting
# --------

def Main.listener(r: Res(Listener), +what: String) -> IO(Listener):
  match r:
    case Done{l}:
      IO.pure(Listener, l)
    case Fail{(c, m)}:
      IO.die(Listener, 1, "listen " ++ what ++ ": " ++ m)

def Main.serve(+port: U32, +cert: String, +key: String, +ca: String) -> IO(Unit):
  do IO<Unit>:
    r1 : Res(Listener) <- S.TlsSrv.listen("127.0.0.1", port)
    l1 : Listener <- Main.listener(r1, "echo")
    r2 : Res(Listener) <- S.TlsSrv.listen("127.0.0.1", (port + 1 : U32))
    l2 : Listener <- Main.listener(r2, "splice")
    r3 : Res(Listener) <- TCP.listen("127.0.0.1", (port + 2 : U32))
    l3 : Listener <- Main.listener(r3, "backend")
    IO.spawn(Unit, Back.loop(Echo.forever(), l3))
    IO.spawn(Unit, Srv.loop(Echo.forever(), l2, cert, key, ca, True{}, (port + 2 : U32)))
    IO.spawn(Unit, Srv.loop(Echo.forever(), l1, cert, key, ca, False{}, (port + 2 : U32)))
    IO.print("ready")

def Main.lane.fail(enosys: Bool, m: String) -> IO(Unit):
  match enosys:
    case True{}:
      IO.print("PASS tls_server_echo: the JavaScript stand-in fails with ENOSYS")
    case False{}:
      IO.print("FAIL tls_server_echo: TlsSrv.listen: " ++ m)

def Main.lane(r: Res(Listener)) -> IO(Unit):
  match r:
    case Done{l}:
      do IO<Unit>:
        Listener.close(l)
        IO.print("PASS tls_server_echo: TlsSrv.listen listens (native lane)")
    case Fail{(c, m)}:
      Main.lane.fail(U32.is_eq(c, 38), m)

def Main.port(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{p}:
      p
    case None{}:
      0

def Main.args(args: List<String>) -> IO(Unit):
  match args:
    case Con{_, Con{port, Con{cert, Con{key, Con{ca, _}}}}}:
      Main.serve(Main.port(U32.read(port)), cert, key, ca)
    case _:
      do IO<Unit>:
        r : Res(Listener) <- S.TlsSrv.listen("127.0.0.1", 0)
        Main.lane(r)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    Main.args(args)
