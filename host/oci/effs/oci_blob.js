// The OCI blob effects run only native (oci_blob.c). These stand-ins let
// `bend` check and interpret programs that use them elsewhere: every
// effect fails with ENOSYS (38), so no blob is ever made here. A handle
// handed to an effect comes back beside the failure, and OciBlob.commit,
// which consumes its file, still closes it, so no descriptor leaks.
const OCI_BLOB_ENOSYS = 38;
io_eff(CID(OciBlob.create), function (path) { return io_fail(OCI_BLOB_ENOSYS); });
io_eff(CID(OciBlob.fetch), function (blob, sock, head, hi, lo, ms) {
  return io_tup(blob, io_tup(sock, io_fail(OCI_BLOB_ENOSYS)));
});
io_eff(CID(OciBlob.commit), function (blob) {
  try {
    require("fs").closeSync(blob);
  } catch (e) {
  }
  return io_fail(OCI_BLOB_ENOSYS);
});
io_eff(CID(OciBlob.open), function (path) { return io_fail(OCI_BLOB_ENOSYS); });
io_eff(CID(OciBlob.send), function (sock, file, off_hi, off_lo, len_hi, len_lo, ms) {
  return io_tup(sock, io_tup(file, io_fail(OCI_BLOB_ENOSYS)));
});
