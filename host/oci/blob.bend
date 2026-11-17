import Base

# OCI blob transfer
# =================
#
# The IO under the OCI pull-through mirror's blob store: a blob moves from
# a socket into a file while its SHA-256 is computed, and from a file to a
# socket, in 64-bit sizes, with no byte entering the Bend heap. Every
# decision (HTTP framing, what to fetch, which digest to expect, where a
# blob lives, retries) is the caller's, in Bend. This module and its effect
# files (effs/oci_blob.c, effs/oci_blob.js) import nothing of vk8s, so
# the OCI library can move to its own repository as one directory.
#
# Why C: pure-Bend SHA-256 runs at about 0.38 MiB/s, a layer can pass
# 4 GiB while Base's and BinFile's offsets are U32, and a byte in the heap
# costs a list cell. effs/oci_blob.c says more. effs/oci_blob.js stands in
# on the JavaScript lane, where every effect fails with ENOSYS (38).
#
# Sizes and offsets are 64-bit, as a pair of U32: hi * 2^32 + lo.
#
# Sockets: a plain TCP socket (TCP.accept, TCP.connect) or a TLS session
# whose provider sets the C hooks oci_tls_* (vk8s's TlsSrv sessions do).
# ms bounds the time with no progress (0: none), not the whole transfer,
# so a slow 5 GiB layer still lands; past it the effect fails with
# ETIMEDOUT. Every wait parks on the event loop.
#
# A pull: OciBlob.create a temporary file; OciBlob.fetch the body (head is
# what the HTTP parser already read past the headers; call fetch again
# for each chunk of a chunked body); OciBlob.commit for the hex digest;
# compare it with the descriptor's, then rename the file into place (or
# remove it). A serve: OciBlob.open, OciBlob.send the range, File.close.
#
# File operations around the store (rename, remove, list, mkdir -p) are
# not here and need no new C: bend-vmm has them as Hvf.rename, Hvf.remove,
# Hvf.ls and Hvf.mkdir (host/hvf.bend).
# TODO(bend-vmm): wrap them here once bend-vmm exports them from its
# main.bend. Last use (mtime) and free space wait for the same export.

def OciBlob.Res(-A: Type) -> Type:
  Result<&1, &1, U32 & String, A>

# Effects
# -------

# A new blob: the file at path, created or truncated, mode 0600 whatever
# the umask, and an empty SHA-256. A symbolic link as the last component
# fails (ELOOP), anything but a regular file with EINVAL, a libcrypto that
# cannot be loaded with ENOTSUP. End it with OciBlob.commit.
def OciBlob.create(path: String) -> IO(OciBlob.Res(File)):
  import "./effs/oci_blob.c"
  import "./effs/oci_blob.js"

# Appends head (bytes 0..255), then exactly hi * 2^32 + lo bytes read from
# sock, to the blob and its hash. The socket ending first fails with
# ECONNRESET; ms as above. A failure may leave a prefix written: commit
# the blob and throw it away.
def OciBlob.fetch(blob: File, sock: Socket, head: List<&2, U32>, hi: U32, lo: U32, ms: U32) ->
  IO(File & (Socket & OciBlob.Res(Unit))):
  import "./effs/oci_blob.c"
  import "./effs/oci_blob.js"

# Flushes the blob to disk (fsync), closes it, and answers the SHA-256 of
# every byte it got, as 64 lowercase hex digits (an OCI digest is
# "sha256:" ++ these).
def OciBlob.commit(blob: File) -> IO(OciBlob.Res(String)):
  import "./effs/oci_blob.c"
  import "./effs/oci_blob.js"

# Opens the regular file at path to serve, with its size (hi, lo). Refuses
# links and non-regular files as OciBlob.create does. End it with
# File.close.
def OciBlob.open(path: String) -> IO(OciBlob.Res(File & (U32 & U32))):
  import "./effs/oci_blob.c"
  import "./effs/oci_blob.js"

# Sends exactly len_hi * 2^32 + len_lo bytes of the file, from offset
# off_hi * 2^32 + off_lo, to sock: sendfile(2) on a plain socket on
# Linux. The file ending first fails with EIO; ms as above.
def OciBlob.send(sock: Socket, file: File, off_hi: U32, off_lo: U32, len_hi: U32, len_lo: U32,
  ms: U32) -> IO(Socket & (File & OciBlob.Res(Unit))):
  import "./effs/oci_blob.c"
  import "./effs/oci_blob.js"
