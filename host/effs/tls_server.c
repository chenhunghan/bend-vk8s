// TLS server
// ==========

// The server side of TLS over OpenSSL 3 (or 1.1.1), loaded with dlopen as
// bend-kube's tls.c loads it, so the program builds with Bend's plain
// clang line, needs no OpenSSL headers and has no link-time dependency.
// Every name here starts with tsv_ so that this file and bend-kube's
// tls.c (a TLS client) can share one program.
//
// A TLS connection is a Socket handle whose fd indexes tsv_conn, the
// table of SSL objects; an fd with no entry is a plain TCP socket, which
// TlsSrv.splice also takes. Sockets stay non-blocking: the handshake,
// recv, send and splice park on the loop (io_wait_on) while OpenSSL wants
// the socket, and never block it. Splice waits on two descriptors at
// once through one: an epoll (Linux) or kqueue (macOS) descriptor that
// becomes readable when either socket is ready.
//
// TlsSrv.handshake reads the certificate chain, key and client CA bundle
// from PEM files into an SSL_CTX, kept while the paths and the files'
// size and mtime stay the same (a rotated certificate takes effect on the
// next connection).
//
// BEND_KUBE_LIBSSL and BEND_KUBE_LIBCRYPTO name the libraries when the
// default search misses them, as for bend-kube.

#include <dlfcn.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <sys/stat.h>
#include <netinet/tcp.h>
#ifdef __linux__
#include <sys/epoll.h>
#else
#include <sys/event.h>
#endif

typedef struct {
  int           (*init_ssl)(uint64_t, const void*);
  const void*   (*server_method)(void);
  void*         (*ctx_new)(const void*);
  void          (*ctx_free)(void*);
  long          (*ctx_ctrl)(void*, int, long, void*);
  void          (*ctx_set_verify)(void*, int, void*);
  int           (*ctx_chain_file)(void*, const char*);
  int           (*ctx_key_file)(void*, const char*, int);
  int           (*ctx_check_key)(void*);
  int           (*ctx_verify_locations)(void*, const char*, const char*);
  void*         (*load_client_ca)(const char*);
  void          (*ctx_client_ca_list)(void*, void*);
  int           (*ctx_sid_ctx)(void*, const unsigned char*, unsigned);
  void          (*ctx_alpn_cb)(void*, int (*)(void*, const unsigned char**, unsigned char*,
                  const unsigned char*, unsigned, void*), void*);
  uint64_t      (*ctx_options)(void*, uint64_t);  // optional (1.1: a macro)
  void*         (*ssl_new)(void*);
  void          (*ssl_free)(void*);
  int           (*ssl_set_fd)(void*, int);
  int           (*ssl_accept)(void*);
  int           (*ssl_read)(void*, void*, int);
  int           (*ssl_write)(void*, const void*, int);
  int           (*ssl_get_error)(const void*, int);
  int           (*ssl_shutdown)(void*);
  long          (*ssl_verify_result)(const void*);
  void*         (*ssl_peer_cert)(const void*);
  unsigned long (*version_num)(void);
  const char*   (*verify_text)(long);
  void          (*x509_free)(void*);
  void*         (*x509_subject)(const void*);
  int           (*name_count)(const void*);
  void*         (*name_entry)(const void*, int);
  void*         (*entry_object)(const void*);
  void*         (*entry_data)(const void*);
  int           (*obj_nid)(const void*);
  const char*   (*nid_short)(int);
  int           (*obj_text)(char*, int, const void*, int);
  int           (*asn1_utf8)(unsigned char**, const void*);
  void          (*crypto_free)(void*, const char*, int);
  unsigned long (*err_get)(void);
  void          (*err_text)(unsigned long, char*, size_t);
  void          (*err_clear)(void);
} TsvLib;

static TsvLib          tsv_lib;
static int             tsv_ready;  // 0 untried, 1 loaded, -1 missing
static char            tsv_why[256];
static pthread_mutex_t tsv_gate = PTHREAD_MUTEX_INITIALIZER;

#define TSV_MAX_FD 65536
static void* tsv_conn[TSV_MAX_FD];  // an SSL*, or NULL for a plain socket

#define TSV_CTRL_MODE          33
#define TSV_CTRL_OPTIONS       32
#define TSV_CTRL_MIN_PROTO     123
#define TSV_MODE_PARTIAL_WRITE 1
#define TSV_MODE_MOVING_BUFFER 2
#define TSV_OP_IGNORE_EOF      ((uint64_t)1 << 7)  // OpenSSL 3 only
#define TSV_TLS_1_2            0x0303
#define TSV_FILETYPE_PEM       1
#define TSV_VERIFY_PEER        1
#define TSV_VERIFY_FAIL_NO_CERT 2
#define TSV_WANT_READ          2
#define TSV_WANT_WRITE         3
#define TSV_SYSCALL            5
#define TSV_ZERO_RETURN        6
#define TSV_ALPN_OK            0
#define TSV_ALPN_NOACK         3

static void* tsv_open_lib(const char* env, const char* const* names) {
  const char* own = getenv(env);
  if (own != NULL && *own != 0) {
    return dlopen(own, RTLD_NOW | RTLD_LOCAL);
  }
  for (u32 i = 0; names[i] != NULL; i += 1) {
    void* h = dlopen(names[i], RTLD_NOW | RTLD_LOCAL);
    if (h != NULL) {
      return h;
    }
  }
  return NULL;
}

#define TSV_SYM(h, field, name) \
  if ((*(void**)&tsv_lib.field = dlsym(h, name)) == NULL) { \
    snprintf(tsv_why, sizeof tsv_why, "TLS: %s is missing", name); \
    return -1; \
  }

static int tsv_load_now(void) {
  static const char* const ssl_names[] = {
    "libssl.so.3", "libssl.so.1.1", "libssl.so",
    "/opt/homebrew/opt/openssl@3/lib/libssl.3.dylib",
    "/usr/local/opt/openssl@3/lib/libssl.3.dylib",
    "libssl.3.dylib", NULL };
  static const char* const crypto_names[] = {
    "libcrypto.so.3", "libcrypto.so.1.1", "libcrypto.so",
    "/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib",
    "/usr/local/opt/openssl@3/lib/libcrypto.3.dylib",
    "libcrypto.3.dylib", NULL };
  void* c = tsv_open_lib("BEND_KUBE_LIBCRYPTO", crypto_names);
  void* s = c == NULL ? NULL : tsv_open_lib("BEND_KUBE_LIBSSL", ssl_names);
  if (s == NULL) {
    snprintf(tsv_why, sizeof tsv_why,
      "TLS: OpenSSL not found (set BEND_KUBE_LIBSSL and BEND_KUBE_LIBCRYPTO)");
    return -1;
  }
  TSV_SYM(s, init_ssl, "OPENSSL_init_ssl");
  TSV_SYM(s, server_method, "TLS_server_method");
  TSV_SYM(s, ctx_new, "SSL_CTX_new");
  TSV_SYM(s, ctx_free, "SSL_CTX_free");
  TSV_SYM(s, ctx_ctrl, "SSL_CTX_ctrl");
  TSV_SYM(s, ctx_set_verify, "SSL_CTX_set_verify");
  TSV_SYM(s, ctx_chain_file, "SSL_CTX_use_certificate_chain_file");
  TSV_SYM(s, ctx_key_file, "SSL_CTX_use_PrivateKey_file");
  TSV_SYM(s, ctx_check_key, "SSL_CTX_check_private_key");
  TSV_SYM(s, ctx_verify_locations, "SSL_CTX_load_verify_locations");
  TSV_SYM(s, load_client_ca, "SSL_load_client_CA_file");
  TSV_SYM(s, ctx_client_ca_list, "SSL_CTX_set_client_CA_list");
  TSV_SYM(s, ctx_sid_ctx, "SSL_CTX_set_session_id_context");
  TSV_SYM(s, ctx_alpn_cb, "SSL_CTX_set_alpn_select_cb");
  *(void**)&tsv_lib.ctx_options = dlsym(s, "SSL_CTX_set_options");
  TSV_SYM(s, ssl_new, "SSL_new");
  TSV_SYM(s, ssl_free, "SSL_free");
  TSV_SYM(s, ssl_set_fd, "SSL_set_fd");
  TSV_SYM(s, ssl_accept, "SSL_accept");
  TSV_SYM(s, ssl_read, "SSL_read");
  TSV_SYM(s, ssl_write, "SSL_write");
  TSV_SYM(s, ssl_get_error, "SSL_get_error");
  TSV_SYM(s, ssl_shutdown, "SSL_shutdown");
  TSV_SYM(s, ssl_verify_result, "SSL_get_verify_result");
  // OpenSSL 3 renamed SSL_get_peer_certificate (1.1) to this.
  if ((*(void**)&tsv_lib.ssl_peer_cert = dlsym(s, "SSL_get1_peer_certificate")) == NULL) {
    TSV_SYM(s, ssl_peer_cert, "SSL_get_peer_certificate");
  }
  TSV_SYM(c, version_num, "OpenSSL_version_num");
  TSV_SYM(c, verify_text, "X509_verify_cert_error_string");
  TSV_SYM(c, x509_free, "X509_free");
  TSV_SYM(c, x509_subject, "X509_get_subject_name");
  TSV_SYM(c, name_count, "X509_NAME_entry_count");
  TSV_SYM(c, name_entry, "X509_NAME_get_entry");
  TSV_SYM(c, entry_object, "X509_NAME_ENTRY_get_object");
  TSV_SYM(c, entry_data, "X509_NAME_ENTRY_get_data");
  TSV_SYM(c, obj_nid, "OBJ_obj2nid");
  TSV_SYM(c, nid_short, "OBJ_nid2sn");
  TSV_SYM(c, obj_text, "OBJ_obj2txt");
  TSV_SYM(c, asn1_utf8, "ASN1_STRING_to_UTF8");
  TSV_SYM(c, crypto_free, "CRYPTO_free");
  TSV_SYM(c, err_get, "ERR_get_error");
  TSV_SYM(c, err_text, "ERR_error_string_n");
  TSV_SYM(c, err_clear, "ERR_clear_error");
  tsv_lib.init_ssl(0, NULL);
  return 1;
}

static int tsv_load(void) {
  pthread_mutex_lock(&tsv_gate);
  if (tsv_ready == 0) {
    tsv_ready = tsv_load_now();
  }
  int r = tsv_ready;
  pthread_mutex_unlock(&tsv_gate);
  return r;
}

// OpenSSL's last error as text after what ("" when there is none), and the
// error queue cleared.
static void tsv_err(char* out, size_t cap, const char* what) {
  char err[200] = "";
  if (tsv_ready == 1) {
    unsigned long e = tsv_lib.err_get();
    if (e != 0) {
      tsv_lib.err_text(e, err, sizeof err);
    }
    tsv_lib.err_clear();
  }
  snprintf(out, cap, "%s%s%s", what, *err ? ": " : "", err);
}

static int tsv_late(IoWork* w) {
  return w->time != 0 && io_tick() >= w->time;
}

static int tsv_valid(intptr_t fd) {
  return fd >= 0 && fd < TSV_MAX_FD;
}

// TlsSrv.listen
// -------------

// TlsSrv.listen(host, port): Base's TCP.listen, once OpenSSL loads.
Term tsv_listen_run(Env e, Term* f, IoWork* w) {
  if (tsv_load() != 1) {
    return io_fail(e, ENOTSUP, tsv_why);
  }
  struct sockaddr_in at;
  u64 len;
  char* host = io_cstr(e, f[0], &len);
  int valid = !io_nul(host, len) && io_sys_addr(host, (u32)f[1], &at) == 0;
  free(host);
  if (!valid) {
    return io_fail(e, EINVAL, NULL);
  }
  int fd = socket(AF_INET, SOCK_STREAM, 0);
  if (fd < 0) {
    return io_fail(e, (u32)errno, NULL);
  }
  int one = 1;
  setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
  if (bind(fd, (struct sockaddr*)&at, sizeof at) < 0 || listen(fd, 512) < 0
    || fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) < 0) {
    u32 code = (u32)errno;
    close(fd);
    return io_fail(e, code, NULL);
  }
  return io_done(e, io_hand(fd));
}

// The context
// -----------

// ALPN: http/1.1 when the client offers it, else no ALPN at all.
static int tsv_alpn(void* ssl, const unsigned char** out, unsigned char* outlen,
  const unsigned char* in, unsigned inlen, void* arg) {
  for (unsigned i = 0; i < inlen;) {
    unsigned n = in[i];
    if (i + 1 + n > inlen) {
      break;
    }
    if (n == 8 && memcmp(in + i + 1, "http/1.1", 8) == 0) {
      *out    = in + i + 1;
      *outlen = 8;
      return TSV_ALPN_OK;
    }
    i += 1 + n;
  }
  return TSV_ALPN_NOACK;
}

// What a cached context was made from.
typedef struct {
  char*  cert;
  char*  key;
  char*  ca;
  struct stat st[3];
  void*  ctx;
} TsvCtx;

static TsvCtx tsv_ctx;

static void tsv_stat(const char* path, struct stat* st) {
  memset(st, 0, sizeof *st);
  if (*path != 0) {
    stat(path, st);
  }
}

static int tsv_same_file(const struct stat* a, const struct stat* b) {
  return a->st_ino == b->st_ino && a->st_size == b->st_size
    && a->st_mtime == b->st_mtime && a->st_dev == b->st_dev;
}

// The context for these files: the cached one, or a new one (then cached).
// NULL with text set when the files do not make one.
static void* tsv_context(const char* cert, const char* key, const char* ca,
  char* text, size_t cap) {
  struct stat st[3];
  tsv_stat(cert, &st[0]);
  tsv_stat(key, &st[1]);
  tsv_stat(ca, &st[2]);
  if (tsv_ctx.ctx != NULL && strcmp(tsv_ctx.cert, cert) == 0
    && strcmp(tsv_ctx.key, key) == 0 && strcmp(tsv_ctx.ca, ca) == 0
    && tsv_same_file(&tsv_ctx.st[0], &st[0]) && tsv_same_file(&tsv_ctx.st[1], &st[1])
    && tsv_same_file(&tsv_ctx.st[2], &st[2])) {
    return tsv_ctx.ctx;
  }
  void* ctx = tsv_lib.ctx_new(tsv_lib.server_method());
  if (ctx == NULL) {
    tsv_err(text, cap, "TLS: SSL_CTX_new");
    return NULL;
  }
  tsv_lib.ctx_ctrl(ctx, TSV_CTRL_MIN_PROTO, TSV_TLS_1_2, NULL);
  tsv_lib.ctx_ctrl(ctx, TSV_CTRL_MODE, TSV_MODE_PARTIAL_WRITE | TSV_MODE_MOVING_BUFFER, NULL);
  // A peer that closes without close_notify reads as an end of stream.
  if (tsv_lib.version_num() >= 0x30000000UL) {
    if (tsv_lib.ctx_options != NULL) {
      tsv_lib.ctx_options(ctx, TSV_OP_IGNORE_EOF);
    } else {
      tsv_lib.ctx_ctrl(ctx, TSV_CTRL_OPTIONS, (long)TSV_OP_IGNORE_EOF, NULL);
    }
  }
  static const unsigned char sid[] = "bend-vk8s";
  tsv_lib.ctx_sid_ctx(ctx, sid, sizeof sid - 1);
  tsv_lib.ctx_alpn_cb(ctx, tsv_alpn, NULL);
  if (tsv_lib.ctx_chain_file(ctx, cert) != 1) {
    tsv_err(text, cap, "TLS: cannot load the certificate chain");
    tsv_lib.ctx_free(ctx);
    return NULL;
  }
  if (tsv_lib.ctx_key_file(ctx, key, TSV_FILETYPE_PEM) != 1
    || tsv_lib.ctx_check_key(ctx) != 1) {
    tsv_err(text, cap, "TLS: cannot load the key, or it does not match the certificate");
    tsv_lib.ctx_free(ctx);
    return NULL;
  }
  if (*ca != 0) {
    void* names = NULL;
    if (tsv_lib.ctx_verify_locations(ctx, ca, NULL) != 1
      || (names = tsv_lib.load_client_ca(ca)) == NULL) {
      tsv_err(text, cap, "TLS: cannot load the client CA bundle");
      tsv_lib.ctx_free(ctx);
      return NULL;
    }
    tsv_lib.ctx_client_ca_list(ctx, names);  // the context owns names
    tsv_lib.ctx_set_verify(ctx, TSV_VERIFY_PEER | TSV_VERIFY_FAIL_NO_CERT, NULL);
  }
  tsv_lib.err_clear();
  if (tsv_ctx.ctx != NULL) {
    tsv_lib.ctx_free(tsv_ctx.ctx);  // live SSLs keep their own reference
  }
  free(tsv_ctx.cert);
  free(tsv_ctx.key);
  free(tsv_ctx.ca);
  tsv_ctx.cert = io_mem(strdup(cert));
  tsv_ctx.key  = io_mem(strdup(key));
  tsv_ctx.ca   = io_mem(strdup(ca));
  memcpy(tsv_ctx.st, st, sizeof st);
  tsv_ctx.ctx  = ctx;
  return ctx;
}

// TlsSrv.handshake
// ----------------

// The handshake's state, owned by w->data.
typedef struct {
  int   fd;
  void* ssl;
  int   ask;  // a client certificate is required
  u32   code;
  char  text[320];
} TsvHs;

// Fails the handshake: the connection closes, since its Socket was consumed.
static Term tsv_hs_fail(Env e, IoWork* w) {
  TsvHs* h = (TsvHs*)w->data;
  if (h->ssl != NULL) {
    tsv_lib.ssl_free(h->ssl);
  }
  if (tsv_valid(h->fd)) {
    tsv_conn[h->fd] = NULL;
  }
  close(h->fd);
  Term r = io_fail(e, h->code, h->text);
  free(h);
  return r;
}

// Drives SSL_accept on the non-blocking socket, parking while it waits,
// under one deadline for the whole of it.
static Term tsv_hs_more(Env e, IoWork* w) {
  TsvHs* h = (TsvHs*)w->data;
  int ret = tsv_lib.ssl_accept(h->ssl);
  if (ret == 1) {
    tsv_conn[h->fd] = h->ssl;
    Term r = io_done(e, io_hand(h->fd));
    free(h);
    return r;
  }
  int k = tsv_lib.ssl_get_error(h->ssl, ret);
  if (k == TSV_WANT_READ || k == TSV_WANT_WRITE) {
    if (!tsv_late(w)) {
      return io_wait_on(w, h->fd, k == TSV_WANT_READ ? POLLIN : POLLOUT, w->time,
        tsv_hs_more);
    }
    tsv_lib.err_clear();
    h->code = ETIMEDOUT;
    snprintf(h->text, sizeof h->text, "TLS: handshake timed out");
    return tsv_hs_fail(e, w);
  }
  long v = tsv_lib.ssl_verify_result(h->ssl);
  void* peer = h->ask ? tsv_lib.ssl_peer_cert(h->ssl) : NULL;
  if (peer != NULL) {
    tsv_lib.x509_free(peer);
  }
  if (h->ask && v != 0) {
    h->code = EACCES;
    snprintf(h->text, sizeof h->text, "TLS: client certificate rejected: %s",
      tsv_lib.verify_text(v));
    tsv_lib.err_clear();
  } else if (h->ask && peer == NULL) {
    h->code = EACCES;
    tsv_err(h->text, sizeof h->text, "TLS: client certificate required");
  } else {
    h->code = ECONNRESET;
    tsv_err(h->text, sizeof h->text, "TLS: handshake failed");
  }
  return tsv_hs_fail(e, w);
}

// TlsSrv.handshake(sock, cert_path, key_path, ca_path, ms)
Term tsv_handshake_run(Env e, Term* f, IoWork* w) {
  TsvHs* h = io_mem(calloc(1, sizeof *h));
  h->fd = (int)io_hand_v(f[0]);
  w->data = (char*)h;
  w->time = io_until((u32)f[4] == 0 ? 30000 : (u32)f[4]);
  u64 n;
  char* cert = io_cstr(e, f[1], &n);
  char* key  = io_cstr(e, f[2], &n);
  char* ca   = io_cstr(e, f[3], &n);
  h->ask = *ca != 0;
  void* ctx = NULL;
  if (!tsv_valid(h->fd)) {
    h->code = EMFILE;
    snprintf(h->text, sizeof h->text, "TLS: descriptor %d is past the table", h->fd);
  } else if (tsv_load() != 1) {
    h->code = ENOTSUP;
    snprintf(h->text, sizeof h->text, "%s", tsv_why);
  } else if ((ctx = tsv_context(cert, key, ca, h->text, sizeof h->text)) == NULL) {
    h->code = EINVAL;
  } else if ((h->ssl = tsv_lib.ssl_new(ctx)) == NULL) {
    h->code = ENOMEM;
    tsv_err(h->text, sizeof h->text, "TLS: SSL_new");
  }
  free(cert);
  free(key);
  free(ca);
  if (h->ssl == NULL) {
    return tsv_hs_fail(e, w);
  }
  if (tsv_conn[h->fd] != NULL) {
    // A TLS socket ended by Socket.close left its SSL behind.
    tsv_lib.ssl_free(tsv_conn[h->fd]);
    tsv_conn[h->fd] = NULL;
  }
  int one = 1;
  setsockopt(h->fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
#ifdef SO_NOSIGPIPE
  setsockopt(h->fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
#endif
  fcntl(h->fd, F_SETFL, fcntl(h->fd, F_GETFL) | O_NONBLOCK);
  tsv_lib.ssl_set_fd(h->ssl, h->fd);
  return tsv_hs_more(e, w);
}

// Moving bytes
// ------------

// The error of an SSL call that did not finish: 0 with *evts set when it
// must wait for the socket, 0 with *evts 0 at the end of the stream, else
// an errno.
static u32 tsv_why_not(void* ssl, int ret, short* evts) {
  int k = tsv_lib.ssl_get_error(ssl, ret);
  int err = errno;
  *evts = 0;
  if (k == TSV_WANT_READ) {
    *evts = POLLIN;
    return 0;
  }
  if (k == TSV_WANT_WRITE) {
    *evts = POLLOUT;
    return 0;
  }
  tsv_lib.err_clear();
  if (k == TSV_ZERO_RETURN || (k == TSV_SYSCALL && ret == 0 && err == 0)) {
    return 0;
  }
  return k == TSV_SYSCALL && err != 0 && err != EAGAIN ? (u32)err : ECONNRESET;
}

// Reads up to cap bytes from an end: > 0 bytes read, 0 to wait for
// *evts, -1 at the end of the stream or on an error (*code).
static int tsv_read(int fd, void* ssl, char* buf, int cap, short* evts, u32* code) {
  *evts = 0;
  *code = 0;
  if (ssl == NULL) {
    ssize_t n = recv(fd, buf, (size_t)cap, 0);
    if (n > 0) {
      return (int)n;
    }
    if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
      *evts = POLLIN;
      return 0;
    }
    *code = n < 0 ? (u32)errno : 0;
    return -1;
  }
  errno = 0;
  int n = tsv_lib.ssl_read(ssl, buf, cap);
  if (n > 0) {
    return n;
  }
  *code = tsv_why_not(ssl, n, evts);
  return *evts != 0 ? 0 : -1;
}

// Writes up to len bytes to an end: > 0 bytes written, 0 to wait for
// *evts, -1 on an error (*code).
static int tsv_write(int fd, void* ssl, const char* buf, int len, short* evts, u32* code) {
  *evts = 0;
  *code = 0;
  if (ssl == NULL) {
#ifdef MSG_NOSIGNAL
    ssize_t n = send(fd, buf, (size_t)len, MSG_NOSIGNAL);
#else
    ssize_t n = send(fd, buf, (size_t)len, 0);
#endif
    if (n > 0) {
      return (int)n;
    }
    if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
      *evts = POLLOUT;
      return 0;
    }
    *code = n < 0 ? (u32)errno : EPIPE;
    return -1;
  }
  errno = 0;
  int n = tsv_lib.ssl_write(ssl, buf, len);
  if (n > 0) {
    return n;
  }
  *code = tsv_why_not(ssl, n, evts);
  if (*evts != 0) {
    return 0;
  }
  *code = *code == 0 ? EPIPE : *code;
  return -1;
}

static int tsv_is_tls(intptr_t fd) {
  return tsv_valid(fd) && tsv_conn[fd] != NULL;
}

// Send: w->data holds the bytes, w->made how many are sent.
static Term tsv_send_more(Env e, IoWork* w) {
  int   fd   = (int)w->hand;
  void* ssl  = tsv_conn[fd];
  u32   code = 0;
  while ((u64)w->made < w->size) {
    if (tsv_late(w)) {
      code = ETIMEDOUT;
      break;
    }
    u64   left = w->size - (u64)w->made;
    short evts;
    int n = tsv_write(fd, ssl, w->data + w->made, left > INT32_MAX ? INT32_MAX : (int)left,
      &evts, &code);
    if (n > 0) {
      w->made += n;
      continue;
    }
    if (n == 0) {
      return io_wait_on(w, fd, evts, w->time, tsv_send_more);
    }
    break;
  }
  free(w->data);
  return io_tup(e, io_hand(w->hand), code == 0
    ? io_done(e, term_pak(CID(Unit), 0)) : io_fail(e, code, NULL));
}

static Term tsv_not_tls(Env e, Term sock) {
  return io_tup(e, sock, io_fail(e, EBADF, "TLS: not a TLS connection"));
}

// TlsSrv.send(sock, text, ms)
Term tsv_send_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  if (!tsv_is_tls(w->hand)) {
    return tsv_not_tls(e, f[0]);
  }
  w->data = io_cstr(e, f[1], &w->size);
  w->made = 0;
  w->time = (u32)f[2] == 0 ? 0 : io_until(f[2]);
  return tsv_send_more(e, w);
}

#ifdef CID(TlsSrv.send_bytes)

// TlsSrv.send_bytes(sock, bytes, ms): a value past 255 fails with EINVAL
// before any byte is sent.
Term tsv_send_bytes_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  if (!tsv_is_tls(w->hand)) {
    return tsv_not_tls(e, f[0]);
  }
  for (Term s = f[1]; term_aux(s) == CID(Con);) {
    u64 l = term_peek(e.mem, s);
    if (e.mem[l] > 255) {
      return io_tup(e, f[0], io_fail(e, EINVAL, "TLS: a byte past 255"));
    }
    s = e.mem[l + 1];
  }
  w->data = io_cbuf(e, f[1], &w->size, CID(Con));
  w->made = 0;
  w->time = (u32)f[2] == 0 ? 0 : io_until(f[2]);
  return tsv_send_more(e, w);
}

#endif

#ifdef CID(TlsSrv.recv)

// Recv: up to w->size bytes into w->data.
static Term tsv_recv_more(Env e, IoWork* w) {
  int   fd = (int)w->hand;
  short evts;
  u32   code;
  int n = tsv_read(fd, tsv_conn[fd], w->data, (int)w->size, &evts, &code);
  if (n == 0) {
    if (!tsv_late(w)) {
      return io_wait_on(w, fd, evts, w->time, tsv_recv_more);
    }
    code = ETIMEDOUT;
  }
  Term r = n > 0 ? io_done(e, io_box(e, CID(Some), io_list(e, w->data, (u64)n)))
    : code == 0 ? io_done(e, term_pak(CID(None), 0)) : io_fail(e, code, NULL);
  free(w->data);
  return io_tup(e, io_hand(w->hand), r);
}

// TlsSrv.recv(sock, max, ms)
Term tsv_recv_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  if (!tsv_is_tls(w->hand)) {
    return tsv_not_tls(e, f[0]);
  }
  w->size = (u32)f[1] == 0 ? 16384 : (u32)f[1] > (1u << 20) ? (1u << 20) : (u32)f[1];
  w->data = io_mem(malloc(w->size));
  w->time = (u32)f[2] == 0 ? 0 : io_until(f[2]);
  return tsv_recv_more(e, w);
}

#endif

// TlsSrv.peer
// -----------

// Appends value to out (at *n, cap bytes) escaped as RFC 4514 does.
static void tsv_put_value(char* out, size_t cap, size_t* n, const unsigned char* v, int len) {
  for (int i = 0; i < len && *n + 3 < cap; i += 1) {
    unsigned char c = v[i];
    int esc = c == ',' || c == '+' || c == '"' || c == '\\' || c == '<' || c == '>'
      || c == ';' || (i == 0 && (c == '#' || c == ' ')) || (i == len - 1 && c == ' ');
    if (esc) {
      out[(*n)++] = '\\';
    }
    out[(*n)++] = (char)c;
  }
  out[*n] = 0;
}

// The subject of cert, RFC 4514: last attribute first, "TYPE=value", ",".
static void tsv_subject(void* cert, char* out, size_t cap) {
  void*  name = tsv_lib.x509_subject(cert);
  int    cnt  = name == NULL ? 0 : tsv_lib.name_count(name);
  size_t n    = 0;
  out[0] = 0;
  for (int i = cnt - 1; i >= 0 && n + 8 < cap; i -= 1) {
    void* ent = tsv_lib.name_entry(name, i);
    void* obj = tsv_lib.entry_object(ent);
    int   nid = tsv_lib.obj_nid(obj);
    const char* sn = nid != 0 ? tsv_lib.nid_short(nid) : NULL;
    char  type[80];
    if (sn != NULL) {
      snprintf(type, sizeof type, "%s", sn);
    } else if (tsv_lib.obj_text(type, sizeof type, obj, 1) <= 0) {
      snprintf(type, sizeof type, "?");
    }
    unsigned char* val = NULL;
    int len = tsv_lib.asn1_utf8(&val, tsv_lib.entry_data(ent));
    n += (size_t)snprintf(out + n, cap - n, "%s%s=", n > 0 ? "," : "", type);
    if (n >= cap) {
      n = cap - 1;
    }
    if (len > 0) {
      tsv_put_value(out, cap, &n, val, len);
    }
    if (val != NULL) {
      tsv_lib.crypto_free(val, __FILE__, __LINE__);
    }
  }
  tsv_lib.err_clear();
}

// TlsSrv.peer(sock): the verified client certificate's subject.
Term tsv_peer_run(Env e, Term* f, IoWork* w) {
  intptr_t fd = (intptr_t)io_hand_v(f[0]);
  if (!tsv_is_tls(fd)) {
    return tsv_not_tls(e, f[0]);
  }
  void* ssl  = tsv_conn[fd];
  void* cert = tsv_lib.ssl_peer_cert(ssl);
  if (cert == NULL) {
    return io_tup(e, f[0], io_fail(e, ENOENT, "TLS: the client sent no certificate"));
  }
  long v = tsv_lib.ssl_verify_result(ssl);
  if (v != 0) {
    tsv_lib.x509_free(cert);
    char text[320];
    snprintf(text, sizeof text, "TLS: client certificate not verified: %s",
      tsv_lib.verify_text(v));
    return io_tup(e, f[0], io_fail(e, EACCES, text));
  }
  char* out = io_mem(malloc(4096));
  tsv_subject(cert, out, 4096);
  tsv_lib.x509_free(cert);
  Term r = io_done(e, io_str(e, out, strlen(out)));
  free(out);
  return io_tup(e, f[0], r);
}

// TlsSrv.close
// ------------

// Ends a connection: a best-effort close_notify (the socket is
// non-blocking, so it never waits), then the descriptor closes.
static void tsv_end(int fd) {
  if (tsv_is_tls(fd)) {
    tsv_lib.ssl_shutdown(tsv_conn[fd]);
    tsv_lib.err_clear();
    tsv_lib.ssl_free(tsv_conn[fd]);
    tsv_conn[fd] = NULL;
  }
  if (fd >= 0) {
    close(fd);
  }
}

// TlsSrv.close(sock)
Term tsv_close_run(Env e, Term* f, IoWork* w) {
  tsv_end((int)io_hand_v(f[0]));
  return term_pak(CID(Unit), 0);
}

// TlsSrv.splice
// -------------

#define TSV_PUMP 16384

// One end of a splice, and the bytes read from it, not yet written to the
// other end.
typedef struct {
  int   fd;
  void* ssl;
  int   len;
  int   off;
  short want;  // the events this end waits for, both directions together
  char  buf[TSV_PUMP];
} TsvEnd;

typedef struct {
  TsvEnd end[2];
  int    mux;  // epoll or kqueue: readable when either end is ready
  short  armed[2];
} TsvSplice;

// Moves bytes from end i to the other end until one of them must wait.
// 1 when either end has closed (or failed), else 0.
static int tsv_pump(TsvSplice* p, int i) {
  TsvEnd* src = &p->end[i];
  TsvEnd* dst = &p->end[1 - i];
  for (;;) {
    short evts;
    u32   code;
    if (src->off == src->len) {
      src->off = src->len = 0;
      int n = tsv_read(src->fd, src->ssl, src->buf, TSV_PUMP, &evts, &code);
      if (n < 0) {
        return 1;
      }
      if (n == 0) {
        src->want |= evts;
        return 0;
      }
      src->len = n;
    }
    int m = tsv_write(dst->fd, dst->ssl, src->buf + src->off, src->len - src->off, &evts, &code);
    if (m < 0) {
      return 1;
    }
    if (m == 0) {
      dst->want |= evts;
      return 0;
    }
    src->off += m;
  }
}

// Points the multiplexer at what each end waits for.
static int tsv_arm(TsvSplice* p) {
  for (int i = 0; i < 2; i += 1) {
    TsvEnd* x = &p->end[i];
    if (x->want == p->armed[i]) {
      continue;
    }
#ifdef __linux__
    struct epoll_event ev = { .events = 0, .data = { .fd = x->fd } };
    ev.events = (x->want & POLLIN ? EPOLLIN : 0) | (x->want & POLLOUT ? EPOLLOUT : 0);
    if (epoll_ctl(p->mux, EPOLL_CTL_MOD, x->fd, &ev) < 0) {
      return -1;
    }
#else
    struct kevent ch[2];
    EV_SET(&ch[0], x->fd, EVFILT_READ, EV_ADD | (x->want & POLLIN ? EV_ENABLE : EV_DISABLE),
      0, 0, NULL);
    EV_SET(&ch[1], x->fd, EVFILT_WRITE, EV_ADD | (x->want & POLLOUT ? EV_ENABLE : EV_DISABLE),
      0, 0, NULL);
    if (kevent(p->mux, ch, 2, NULL, 0, NULL) < 0) {
      return -1;
    }
#endif
    p->armed[i] = x->want;
  }
  return 0;
}

// Takes the multiplexer's ready events (they only woke us): 1 when an
// end has hung up or failed. epoll reports that even for an end we do not
// wait on, so the splice ends after one more round instead of spinning.
static int tsv_drain(TsvSplice* p) {
  int hup = 0;
#ifdef __linux__
  struct epoll_event evs[4];
  int n = epoll_wait(p->mux, evs, 4, 0);
  for (int i = 0; i < n; i += 1) {
    hup |= (evs[i].events & (EPOLLHUP | EPOLLERR)) != 0;
  }
#else
  struct kevent evs[4];
  struct timespec now = { 0, 0 };
  int n = kevent(p->mux, NULL, 0, evs, 4, &now);
  for (int i = 0; i < n; i += 1) {
    hup |= (evs[i].flags & EV_ERROR) != 0;
  }
#endif
  return hup;
}

static Term tsv_splice_end(Env e, IoWork* w) {
  TsvSplice* p = (TsvSplice*)w->data;
  tsv_end(p->end[0].fd);
  tsv_end(p->end[1].fd);
  if (p->mux >= 0) {
    close(p->mux);
  }
  free(p);
  return term_pak(CID(Unit), 0);
}

static Term tsv_splice_more(Env e, IoWork* w) {
  TsvSplice* p = (TsvSplice*)w->data;
  int hup = tsv_drain(p);
  p->end[0].want = p->end[1].want = 0;
  if (tsv_pump(p, 0) || tsv_pump(p, 1) || hup || tsv_arm(p) < 0) {
    return tsv_splice_end(e, w);
  }
  return io_wait_on(w, p->mux, POLLIN, 0, tsv_splice_more);
}

// TlsSrv.splice(a, b): consumes both sockets and closes them at the end.
Term tsv_splice_run(Env e, Term* f, IoWork* w) {
  TsvSplice* p = io_mem(calloc(1, sizeof *p));
  w->data = (char*)p;
  for (int i = 0; i < 2; i += 1) {
    p->end[i].fd  = (int)io_hand_v(f[i]);
    p->end[i].ssl = tsv_is_tls(p->end[i].fd) ? tsv_conn[p->end[i].fd] : NULL;
    p->armed[i]   = -1;
    fcntl(p->end[i].fd, F_SETFL, fcntl(p->end[i].fd, F_GETFL) | O_NONBLOCK);
  }
#ifdef __linux__
  p->mux = epoll_create1(EPOLL_CLOEXEC);
  for (int i = 0; i < 2 && p->mux >= 0; i += 1) {
    struct epoll_event ev = { .events = EPOLLIN, .data = { .fd = p->end[i].fd } };
    if (epoll_ctl(p->mux, EPOLL_CTL_ADD, p->end[i].fd, &ev) < 0) {
      close(p->mux);
      p->mux = -1;
    }
  }
#else
  p->mux = kqueue();
  if (p->mux >= 0) {
    fcntl(p->mux, F_SETFD, FD_CLOEXEC);
  }
#endif
  if (p->mux < 0 || p->end[0].fd == p->end[1].fd) {
    return tsv_splice_end(e, w);
  }
  return tsv_splice_more(e, w);
}

// Each effect registers only when the program uses it: an unused def has
// no id.
static void __attribute__((constructor)) tsv_use(void) {
  // A write to a peer that hung up must fail with EPIPE, not kill us.
  signal(SIGPIPE, SIG_IGN);
#ifdef CID(TlsSrv.listen)
  io_eff(CID(TlsSrv.listen), tsv_listen_run);
#endif
#ifdef CID(TlsSrv.handshake)
  io_eff(CID(TlsSrv.handshake), tsv_handshake_run);
#endif
#ifdef CID(TlsSrv.peer)
  io_eff(CID(TlsSrv.peer), tsv_peer_run);
#endif
#ifdef CID(TlsSrv.send)
  io_eff(CID(TlsSrv.send), tsv_send_run);
#endif
#ifdef CID(TlsSrv.send_bytes)
  io_eff(CID(TlsSrv.send_bytes), tsv_send_bytes_run);
#endif
#ifdef CID(TlsSrv.recv)
  io_eff(CID(TlsSrv.recv), tsv_recv_run);
#endif
#ifdef CID(TlsSrv.splice)
  io_eff(CID(TlsSrv.splice), tsv_splice_run);
#endif
#ifdef CID(TlsSrv.close)
  io_eff(CID(TlsSrv.close), tsv_close_run);
#endif
}
