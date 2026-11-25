import Base
import bend-kube-runtime@0.12.0.0/src/sys.bend as Y

# The node's host sockets (vk8s create --host-socket; src/guest/extras.bend
# Extras.sock_steps starts this as the daemon host-sockets):
#
#   vk8s-init host-sockets PATH PORT [PATH PORT ...]
#
# listens on each Unix socket PATH (mode 0666: a pod's non-root user
# connects) and relays every connection to the host's vsock port PORT
# (AF_VSOCK, CID 2), which bend-vmm hands to a Unix socket of the host
# (<--vsock path>_PORT). Each connection is two computations, one per
# direction, each owning a handle of both sockets (Sys.dup). A side that
# ends its writes (end-of-file) has that passed on as a write-side
# shutdown, and the other direction keeps going, so a client that shuts
# down its write side still reads the reply; an error ends both
# directions.

def HSock.Res(-A: Type) -> Type:
  Result<&1, &1, U32 & String, A>

# A stream socket connected to port of the vsock context cid (2: the
# host). Linux only (host/effs/vsock.c).
def VSock.connect(cid: U32, port: U32) -> IO(HSock.Res(Socket)):
  import "./effs/vsock.c"
  import "./effs/vsock.js"

# shutdown(2) of the write side: the peer reads end-of-file and may
# still send.
def VSock.shut_wr(sock: Socket) -> IO(Socket):
  import "./effs/vsock.c"
  import "./effs/vsock.js"

def HSock.forever() -> Nat:
  U32.to_nat(4294967295)

def HSock.say(+s: String) -> IO(Unit):
  IO.print("host-sockets: " ++ s)

# The host's context id (VMADDR_CID_HOST, vsock(7)).
def HSock.host_cid() -> U32:
  2

# One direction ended in an error: both connections end for both
# directions (the other pump's recv ends), then this pump's handles close.
def HSock.abort(a: Socket, b: Socket) -> IO(Unit):
  do IO<Unit>:
    a1 : Socket <- Y.Sys.shutdown(a)
    b1 : Socket <- Y.Sys.shutdown(b)
    Socket.close(a1)
    Socket.close(b1)

# The source ended its writes: the sink's write side ends too, and this
# pump's handles close (the other pump still holds its own).
def HSock.finish(a: Socket, b: Socket) -> IO(Unit):
  do IO<Unit>:
    b1 : Socket <- VSock.shut_wr(b)
    Socket.close(a)
    Socket.close(b1)

def HSock.sent(s: Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>, a: Socket, again: Socket -> Socket -> IO(Unit)) -> IO(Unit):
  match s:
    case (b, Done{u}):
      again(a, b)
    case (b, Fail{e}):
      HSock.abort(a, b)

def HSock.got(r: Socket & HSock.Res(Maybe<&1, List<&2, U32>>), b: Socket, again: Socket -> Socket -> IO(Unit)) -> IO(Unit):
  match r:
    case (a, Done{Some{bs}}):
      do IO<Unit>:
        s : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send_bytes(b, bs)
        HSock.sent(s, a, again)
    case (a, Done{None{}}):
      HSock.finish(a, b)
    case (a, Fail{e}):
      HSock.abort(a, b)

# Bytes from a to b until a ends.
def HSock.pump(n: Nat, a: Socket, b: Socket) -> IO(Unit):
  match n:
    case 0n:
      HSock.abort(a, b)
    case 1n+p:
      do IO<Unit>:
        r : Socket & HSock.Res(Maybe<&1, List<&2, U32>>) <- TCP.recv_bytes(a, 65536)
        HSock.got(r, b, x => y => HSock.pump(p, x, y))

def HSock.relay.go(u: Socket & HSock.Res(Socket), c1: Socket, c2: Socket) -> IO(Unit):
  match u:
    case (u1, Done{u2}):
      do IO<Unit>:
        IO.spawn(Unit, HSock.pump(HSock.forever(), c1, u1))
        HSock.pump(HSock.forever(), u2, c2)
    case (u1, Fail{e}):
      do IO<Unit>:
        HSock.abort(c1, u1)
        Socket.close(c2)

def HSock.relay(c: Socket & HSock.Res(Socket), up: Socket) -> IO(Unit):
  match c:
    case (c1, Done{c2}):
      do IO<Unit>:
        u : Socket & HSock.Res(Socket) <- Y.Sys.dup(up)
        HSock.relay.go(u, c1, c2)
    case (c1, Fail{e}):
      do IO<Unit>:
        Socket.close(c1)
        Socket.close(up)

def HSock.serve.up(r: HSock.Res(Socket), client: Socket, +port: U32) -> IO(Unit):
  match r:
    case Fail{(code, msg)}:
      do IO<Unit>:
        HSock.say("port " ++ U32.show(port) ++ ": the host did not accept (errno " ++ U32.show(code) ++ "); is its socket there?")
        Socket.close(client)
    case Done{up}:
      do IO<Unit>:
        c : Socket & HSock.Res(Socket) <- Y.Sys.dup(client)
        HSock.relay(c, up)

# One connection of a node's client: to the host's port, then both ways.
def HSock.serve(client: Socket, +port: U32) -> IO(Unit):
  do IO<Unit>:
    r : HSock.Res(Socket) <- VSock.connect(HSock.host_cid(), port)
    HSock.serve.up(r, client, port)

def HSock.accepted(r: Listener & HSock.Res(Socket), +port: U32, again: Listener -> IO(Unit)) -> IO(Unit):
  match r:
    case (l, Done{s}):
      do IO<Unit>:
        IO.spawn(Unit, HSock.serve(s, port))
        again(l)
    case (l, Fail{(code, msg)}):
      do IO<Unit>:
        HSock.say("port " ++ U32.show(port) ++ ": accept failed: " ++ msg)
        IO.sleep(100)
        again(l)

def HSock.loop(n: Nat, l: Listener, +port: U32) -> IO(Unit):
  match n:
    case 0n:
      Listener.close(l)
    case 1n+p:
      do IO<Unit>:
        r : Listener & HSock.Res(Socket) <- TCP.accept(l)
        HSock.accepted(r, port, x => HSock.loop(p, x, port))

def HSock.listening(r: HSock.Res(Listener), +path: String, +port: U32) -> IO(Unit):
  match r:
    case Fail{(code, msg)}:
      HSock.say("cannot listen on " ++ path ++ ": " ++ msg)
    case Done{l}:
      do IO<Unit>:
        HSock.say("listening on " ++ path ++ " for the host's port " ++ U32.show(port))
        HSock.loop(HSock.forever(), l, port)

# The socket file's mode, 0666.
def HSock.mode() -> U32:
  438

def HSock.listen(+path: String, +port: U32) -> IO(Unit):
  do IO<Unit>:
    r : HSock.Res(Listener) <- Y.Sys.unix_listen(path, HSock.mode())
    HSock.listening(r, path, port)

def HSock.start.one(m: Maybe<&2, U32>, +path: String) -> IO(Unit):
  match m:
    case Some{+port}:
      IO.spawn(Unit, HSock.listen(path, port))
    case None{}:
      HSock.say("not a port for " ++ path)

# A listener per PATH PORT pair, each in its own computation.
def HSock.start(xs: +List<String>) -> IO(Unit):
  match xs:
    case Con{+path, Con{+port, t}}:
      do IO<Unit>:
        HSock.start.one(U32.read(port), path)
        HSock.start(t)
    case _:
      IO.pure(Unit, Unit{})

def HSock.park(n: Nat) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+p:
      do IO<Unit>:
        IO.sleep(3600000)
        HSock.park(p)

# argv: vk8s-init host-sockets PATH PORT [PATH PORT ...]
def HSock.main(+args: +List<String>) -> IO(Unit):
  do IO<Unit>:
    HSock.start(List.drop(&2, String, args, 2n))
    HSock.park(HSock.forever())
