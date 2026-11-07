import Base
import ../src/net/subject.bend as T

# TLS server
# ==========
#
# What vcluster serves itself over TLS (the fake kubelet API that
# kube-apiserver dials for logs, exec and port-forward, with the
# apiserver-kubelet-client certificate; the proxy) needs a TLS server.
# bend-kube has only a TLS client, so the server lives here:
# effs/tls_server.c on native builds, OpenSSL 3 (or 1.1.1) loaded with
# dlopen as bend-kube's tls.c does, so the binary has no link-time
# dependency. effs/tls_server.js stands in on the JavaScript lane, where
# every effect fails with ENOSYS (38).
#
# A TLS connection is a Socket handle whose descriptor indexes the C side's
# table of SSL objects. Use it only with the TlsSrv effects, and end it
# with TlsSrv.close (or TlsSrv.splice), never Socket.close, which would
# leave its SSL object behind. Every effect but close and splice hands the
# socket back beside its result, as Base's TCP effects do. Every wait
# (handshake, recv, send, splice) parks on the descriptor, so the event
# loop never blocks.

def TlsSrv.Res(-A: Type) -> Type:
  Result<&1, &1, U32 & String, A>

# Effects
# -------

# A TCP listener on the IPv4 literal host, as TCP.listen. It fails with
# ENOTSUP when OpenSSL cannot be loaded (BEND_KUBE_LIBSSL and
# BEND_KUBE_LIBCRYPTO name the libraries when the search misses them).
def TlsSrv.listen(host: String, port: U32) -> IO(TlsSrv.Res(Listener)):
  import "./effs/tls_server.c"
  import "./effs/tls_server.js"

# The server side of the handshake on a TCP connection (from TCP.accept):
# the certificate chain and key are PEM files, read again when a file
# changes. When ca is not "", the client must present a certificate that
# the PEM bundle ca verifies; otherwise none is asked for. TLS 1.2 or
# later; ALPN answers http/1.1 when the client offers it. ms bounds the
# handshake (0: 30 s). A failure closes the connection: EACCES for a
# client certificate that is missing or rejected, ETIMEDOUT past ms.
def TlsSrv.handshake(sock: Socket, cert: String, key: String, ca: String, ms: U32) ->
  IO(TlsSrv.Res(Socket)):
  import "./effs/tls_server.c"
  import "./effs/tls_server.js"

# The verified client certificate's subject in RFC 4514 form, for
# example "CN=kube-apiserver-kubelet-client,O=system:masters" (read it
# with TlsSrv.subject). ENOENT when the client sent no certificate.
def TlsSrv.peer(sock: Socket) -> IO(Socket & TlsSrv.Res(String)):
  import "./effs/tls_server.c"
  import "./effs/tls_server.js"

# Sends raw bytes (each 0..255); ms bounds the whole send (0: no deadline).
def TlsSrv.send_bytes(sock: Socket, data: List<&2, U32>, ms: U32) ->
  IO(Socket & TlsSrv.Res(Unit)):
  import "./effs/tls_server.c"
  import "./effs/tls_server.js"

# Sends text as UTF-8; ms as in send_bytes.
def TlsSrv.send(sock: Socket, text: String, ms: U32) -> IO(Socket & TlsSrv.Res(Unit)):
  import "./effs/tls_server.c"
  import "./effs/tls_server.js"

# Some{bytes} (at most max, 0: 16 KiB), or None{} once the peer has
# closed. ms bounds the wait (0: none), past which it fails with ETIMEDOUT.
def TlsSrv.recv(sock: Socket, max: U32, ms: U32) ->
  IO(Socket & TlsSrv.Res(Maybe<&1, List<&2, U32>>)):
  import "./effs/tls_server.c"
  import "./effs/tls_server.js"

# Pumps bytes both ways between a and b until either side closes, then
# closes both. Each may be a TLS connection or a plain TCP socket (from
# TCP.connect or TCP.accept): this is the upgraded stream of exec, attach
# and port-forward. It waits on both descriptors at once (epoll on Linux,
# kqueue on macOS), so other computations keep running.
def TlsSrv.splice(a: Socket, b: Socket) -> IO(Unit):
  import "./effs/tls_server.c"
  import "./effs/tls_server.js"

# A best-effort close_notify, then the descriptor closes.
def TlsSrv.close(sock: Socket) -> IO(Unit):
  import "./effs/tls_server.c"
  import "./effs/tls_server.js"

# Composed
# --------

def TlsSrv.accept.go(r: Listener & TlsSrv.Res(Socket), +cert: String, +key: String, +ca: String,
  +ms: U32) -> IO(Listener & TlsSrv.Res(Socket)):
  match r:
    case (l, Fail{e}):
      IO.pure(Listener & TlsSrv.Res(Socket), (l, Fail{e}))
    case (l, Done{s}):
      do IO<Listener & TlsSrv.Res(Socket)>:
        h : TlsSrv.Res(Socket) <- TlsSrv.handshake(s, cert, key, ca, ms)
        return (l, h)

# The next connection on l, handshaken as TlsSrv.handshake does. The
# listener waits while the handshake runs: a server with many clients
# calls TCP.accept and runs each TlsSrv.handshake in its own computation.
def TlsSrv.accept(l: Listener, +cert: String, +key: String, +ca: String, +ms: U32) ->
  IO(Listener & TlsSrv.Res(Socket)):
  do IO<Listener & TlsSrv.Res(Socket)>:
    r : Listener & TlsSrv.Res(Socket) <- TCP.accept(l)
    TlsSrv.accept.go(r, cert, key, ca, ms)

def TlsSrv.subject.go(p: Socket & TlsSrv.Res(String)) -> Socket & TlsSrv.Res(T.Subject):
  match p:
    case (s, Fail{e}):
      (s, Fail{e})
    case (s, Done{text}):
      (s, Done{T.Subject.parse(text)})

# The verified client's user (CN) and groups (O), as kube-apiserver reads
# them.
def TlsSrv.subject(sock: Socket) -> IO(Socket & TlsSrv.Res(T.Subject)):
  do IO<Socket & TlsSrv.Res(T.Subject)>:
    p : Socket & TlsSrv.Res(String) <- TlsSrv.peer(sock)
    return TlsSrv.subject.go(p)
