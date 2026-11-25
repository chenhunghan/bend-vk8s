// AF_VSOCK for the node's host-socket proxy (host/host_socket.bend): the
// guest's connection to a host port, which bend-vmm hands to a Unix
// socket of the host, and the write-side shutdown that carries a client's
// half-close across. Everything else (the Unix listener, the byte pumps)
// is Bend, on Base's TCP effects and bend-kube's Sys.unix_listen.

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#ifdef __linux__
#include <linux/vm_sockets.h>
#endif

#ifdef CID(VSock.connect)
// The connect has finished (the socket is writable) or failed at once:
// the socket's error decides.
static Term vsock_connect_more(Env e, IoWork* w) {
  int fd = (int)w->made;
  int err = (int)w->code;
  socklen_t len = sizeof err;
  if (err == EINPROGRESS && getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len) != 0) {
    err = errno;
  }
  if (err != 0 && fd >= 0) {
    close(fd);
  }
  return err != 0 ? io_fail(e, (u32)err, NULL) : io_done(e, io_hand(fd));
}

// VSock.connect(cid, port): a non-blocking stream socket connected to
// port of the context cid (2: the host), for Base's TCP.send_bytes and
// TCP.recv_bytes. The wildcard cid and port (VMADDR_CID_ANY,
// VMADDR_PORT_ANY: 0xFFFFFFFF) are refused with EINVAL. A connect in
// progress parks until the socket is writable (the kernel gives up after
// its own timeout, 2 s). ENOSYS off Linux.
Term vsock_connect_run(Env e, Term* f, IoWork* w) {
  u32 cid = (u32)f[0];
  u32 port = (u32)f[1];
  w->made = -1;
#ifdef __linux__
  if (cid == VMADDR_CID_ANY || port == VMADDR_PORT_ANY) {
    w->code = EINVAL;
    return vsock_connect_more(e, w);
  }
  int fd = socket(AF_VSOCK, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
  w->made = fd;
  if (fd < 0) {
    w->code = (u32)errno;
    return vsock_connect_more(e, w);
  }
  struct sockaddr_vm at;
  memset(&at, 0, sizeof at);
  at.svm_family = AF_VSOCK;
  at.svm_cid = cid;
  at.svm_port = port;
  int r = connect(fd, (struct sockaddr*)&at, sizeof at);
  w->code = r == 0 ? 0 : (u32)errno;
  if (w->code == EINTR) {
    w->code = EINPROGRESS;
  }
  return w->code == EINPROGRESS
    ? io_wait_on(w, fd, POLLOUT, 0, vsock_connect_more) : vsock_connect_more(e, w);
#else
  (void)cid; (void)port;
  w->code = ENOSYS;
  return vsock_connect_more(e, w);
#endif
}

static void __attribute__((constructor)) vsock_connect_use(void) {
  io_eff(CID(VSock.connect), vsock_connect_run);
}
#endif

#ifdef CID(VSock.shut_wr)
// VSock.shut_wr(sock): shutdown(2) of the write side only, on any stream
// socket: the peer reads end-of-file and may still answer. The handle
// stays open until closed.
Term vsock_shut_wr_run(Env e, Term* f, IoWork* w) {
  int fd = (int)io_hand_v(f[0]);
  shutdown(fd, SHUT_WR);
  return io_hand(fd);
}

static void __attribute__((constructor)) vsock_shut_wr_use(void) {
  io_eff(CID(VSock.shut_wr), vsock_shut_wr_run);
}
#endif
