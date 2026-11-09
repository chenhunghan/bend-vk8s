// The TLS server runs only native (effs/tls_server.c). These stand-ins
// let `bend` check and interpret programs that use it elsewhere: every
// effect fails with ENOSYS (38). An effect that consumes a socket still
// closes it, so no descriptor leaks.
const TLS_SRV_ENOSYS = 38;
function tls_srv_drop(sock) {
  if (typeof sock === "number" && sock >= 0) {
    io_sys().close(sock);
  }
}
io_eff(CID(TlsSrv.listen), function (host, port) { return io_fail(TLS_SRV_ENOSYS); });
io_eff(CID(TlsSrv.handshake), function (sock, cert, key, ca, ms) {
  tls_srv_drop(sock);
  return io_fail(TLS_SRV_ENOSYS);
});
io_eff(CID(TlsSrv.connect), function (host, port, name, ca, cert, key, ms) {
  return io_fail(TLS_SRV_ENOSYS);
});
io_eff(CID(TlsSrv.peer), function (sock) { return io_tup(sock, io_fail(TLS_SRV_ENOSYS)); });
io_eff(CID(TlsSrv.send_bytes), function (sock, data, ms) { return io_tup(sock, io_fail(TLS_SRV_ENOSYS)); });
io_eff(CID(TlsSrv.send), function (sock, text, ms) { return io_tup(sock, io_fail(TLS_SRV_ENOSYS)); });
io_eff(CID(TlsSrv.recv), function (sock, max, ms) { return io_tup(sock, io_fail(TLS_SRV_ENOSYS)); });
io_eff(CID(TlsSrv.splice), function (a, b) {
  tls_srv_drop(a);
  tls_srv_drop(b);
  return { $: CID(Unit) };
});
io_eff(CID(TlsSrv.close), function (sock) {
  tls_srv_drop(sock);
  return { $: CID(Unit) };
});
