# TLS on a macOS host

## The problem

Every TLS connection a vk8s host makes goes through OpenSSL 3 (or 1.1.1),
loaded with dlopen at run time, never linked:

| Loader | Used by on the host |
|---|---|
| bend-kube-runtime 0.10.0.0 `src/effs/tls.c` (`tls_load_now`) | the Kubernetes client: `vk8s token create/list/delete`, `node add` (join token), `certs rotate` and `rotate-ca` (/livez wait), classic-mode create (host namespace, service CIDR probe, host Services), `create --upgrade` (stale worker Nodes) |
| `host/effs/tls_server.c` (`tsv_load_now`) | `TlsSrv.secure`: the image cache (`vk8s cache serve`) and the layer filler (`vk8s layers serve`/`fill`) reaching registries |
| `host/oci/effs/oci_blob.c` (`ocb_load_now`, libcrypto only) | the SHA-256 of every blob the cache and the filler fetch or check |

All three search `libssl.so.3`, `libssl.so.1.1`, `libssl.so`,
`/opt/homebrew/opt/openssl@3/lib/libssl.3.dylib`,
`/usr/local/opt/openssl@3/lib/libssl.3.dylib`, `libssl.3.dylib` (and the
same for libcrypto), unless `BEND_KUBE_LIBSSL` / `BEND_KUBE_LIBCRYPTO` is
set and not empty: then only that path is tried (so
`BEND_KUBE_LIBCRYPTO=/nonexistent` simulates a host without OpenSSL). Each
loader reads them once, at its first TLS call, and remembers a failure for
the life of the process.

macOS ships no OpenSSL 3: only LibreSSL as private, versioned dylibs in the
shared cache (`/usr/lib/libssl.48.dylib`, `libssl.46.dylib`,
`libcrypto.46.dylib` on macOS 27). So a Mac without Homebrew's `openssl@3`
has no TLS on the host.

## Never silent (done)

The host probes once (`Vk8s.tls.probe`: `TlsSrv.listen("127.0.0.1", 0)`
loads OpenSSL before it binds; the ephemeral listener is closed at once).
`C.Cli.tls_absent` tells a loader failure ("TLS: ...") from a socket error.

- Degrade with one warning (`C.Cli.tls_degraded`): every cluster boot
  (create, upgrade, restore) when the image cache or the layer store is
  on, `vk8s cache start`, and the `cache serve` / `layers serve` processes
  (in their logs).
- Stop before any change (`C.Cli.tls_needed`): `token create/list/delete`,
  `node add`, `certs rotate`, `certs rotate-ca`, classic-mode create.

## Options for "a Mac needs only vk8s"

**(a) Ship OpenSSL 3 as a hash-pinned darwin host asset.** Chosen.
- The asset download needs no TLS of ours: `Assets.fetch_one_strict` runs
  the system's `/usr/bin/curl` and `shasum`, so there is no bootstrap
  problem.
- `scripts/host-openssl.sh` makes `libssl.3.dylib.tgz` and
  `libcrypto.3.dylib.tgz` from Homebrew's bottle: ids become
  `@loader_path/<name>`, libssl's absolute Cellar reference to libcrypto
  becomes `@loader_path/libcrypto.3.dylib`, both are re-signed ad hoc.
  vk8s is signed ad hoc without the hardened runtime, so library
  validation does not apply. Each archive holds one file, as the strict
  fetch requires.
- Their OPENSSLDIR stays `/opt/homebrew/etc/openssl@3`, so a clean Mac
  has no default CA bundle: a handshake to registry.k8s.io with the
  relocated libraries fails with "unable to get local issuer certificate"
  until `SSL_CERT_FILE=/etc/ssl/cert.pem` (macOS's own bundle) is set;
  then it succeeds (TLSv1.3), loading only the relocated copies
  (`DYLD_PRINT_LIBRARIES`).
- No re-exec is needed: the loaders read the variables lazily, and the
  host's `Sys.setenv` effect (host/effs/sys.c) sets them for the process
  and every process it starts. `Vk8s.tls.env` does so at the start of
  every host command, and again right after the first asset fetch.
  `C.Cli.tls_env` decides: only with both files in `host/` of the assets
  dir (`A.Assets.host_dir`: VK8S_ASSETS's, else the pinned release's), only
  when the user set neither loader variable, and `SSL_CERT_FILE` only when
  neither `SSL_CERT_FILE` nor `SSL_CERT_DIR` is set. The shipped copy wins
  over Homebrew's when both exist: it is the pinned, tested one.
- `M.Manifest.host_darwin` pins the two archives; it is `[]` until a
  release carries them, and then nothing changes (a Mac still needs
  Homebrew). OpenSSL is Apache-2.0: the release carries its license.
- Cost: about 2.6 MB of downloads, once; OpenSSL security updates mean a
  new pin (a vk8s release).

**(b) A change in bend-kube-runtime.** Not chosen as the fix.
- Static OpenSSL: Bend compiles each effect's C file into the program
  with its plain clang line; it has no way to name a static library to
  link, and vendoring OpenSSL's sources is out of scale.
- Network.framework owns its connections (nw_connection), while every TLS
  session here is an fd that the event loop polls and that OciBlob's hooks
  read and write; it does not fit.
- SecureTransport (Security.framework, dlopen-able) does fit the fd model
  with IO callbacks, but it is deprecated since macOS 10.15, has no
  TLS 1.3, and would have to be written three times (bend-kube's tls.c,
  host/effs/tls_server.c, and CommonCrypto for oci_blob.c's SHA-256).
- System LibreSSL (option c below) fails in bend-kube's loader only
  because it requires `SSL_CTX_set_options`, a macro in LibreSSL.

**(c) The system's LibreSSL.** Not chosen. `/usr/lib/libssl.48.dylib`
and `/usr/lib/libcrypto.46.dylib` load and export what tls_server.c and
oci_blob.c need (tls_server.c already treats `SSL_CTX_set_options` as
optional and falls back to `SSL_get_peer_certificate`), but Apple calls
them private with no stable ABI, the version numbers change between macOS
releases (libssl.46 lacks `SSL_set1_host`), and bend-kube's loader refuses
them.

## What bend-kube-runtime should still do (request)

Small changes that make (a) sturdier, for `src/effs/tls.c`:

1. A probe effect, `Tls.available() -> IO(Result<&1, &1, U32 & String,
   Unit>)`: `tls_load()`, then `Done{Unit}` or `Fail{(ENOTSUP, tls_why)}`.
   vk8s now probes through its own `TlsSrv.listen`, which only stands for
   bend-kube's loader because both search the same names.
2. Do not remember a failure (`tls_ready = -1`) forever: retry
   `tls_load_now` when it is -1, so a variable set after a failed first
   call takes effect.
3. Treat `SSL_CTX_set_options` as optional (fall back to
   `SSL_CTX_ctrl(ctx, 32 /* SSL_CTRL_OPTIONS */, op, NULL)`), as vk8s's
   tls_server.c does; also accept `SSL_get_peer_certificate`.
4. Tests (`tests/`): with `BEND_KUBE_LIBCRYPTO=/nonexistent`,
   `Tls.available()` fails with the "OpenSSL not found" text; with a valid
   pair it succeeds; after a failure, setting the variable and calling
   again succeeds.
