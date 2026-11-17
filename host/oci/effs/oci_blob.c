// OCI blob transfer
// =================

// Why this is C. It is the OCI mirror's one foreign part, and the
// smallest one that works (docs/GOAL.md, "Pure Bend as far as possible").
// Two copies, and nothing else:
// - socket -> file (fetch), with the blob's SHA-256 computed as the bytes
//   pass. Pure-Bend SHA-256 runs at about 0.38 MiB/s.
// - file -> socket (send), to serve a blob. A Base file read puts each
//   byte in a Bend list cell, and Base's and BinFile's offsets and sizes
//   are U32, while a layer can be larger than 4 GiB. Serving is the same
//   irreducible copy as the fetch, so it stays here too: sendfile(2) on a
//   plain socket on Linux, else a pread loop.
// So these bytes never enter Bend, and the effects answer only results
// and the hex digest. HTTP framing, digest checks, retries, the store's
// layout and every other decision are Bend (src/oci/, host/oci/). The
// file calls around the store (facts for kind and size, rename, remove,
// ls, mkdir -p, mtime) are bend-vmm's V.Fs, so this file has no other.
//
// The effects (host/oci/blob.bend):
// - OciBlob.create(path): a new file (0600) and its SHA-256 state.
// - OciBlob.fetch(blob, sock, head, hi, lo, ms): head, then exactly
//   hi * 2^32 + lo bytes from the socket, into the file and the hash.
// - OciBlob.commit(blob): fsync, close, and the hex SHA-256 of every byte.
// - OciBlob.send(sock, file, off_hi, off_lo, len_hi, len_lo, ms): a
//   64-bit byte range of the file (any Base File: File.open gives one)
//   to the socket: sendfile(2) on a plain socket on Linux; elsewhere,
//   and on a TLS socket, pread then send(2) or the TLS hook.
//
// SHA-256 is libcrypto's EVP digest, loaded with dlopen as the TLS code
// loads OpenSSL, so the program has no link-time dependency;
// BEND_KUBE_LIBCRYPTO names the library when the search misses it.
//
// Socket waits park on the event loop (io_wait_on) and never block it. A
// transfer moves at most OCB_TURN bytes, then steps aside for the other
// computations until the next poll. File reads and writes run on the loop
// between waits: they hit the page cache, and a helper thread cannot park
// on a socket. Creating the file and fsync run on an IO helper (io_work).
//
// TLS. This file knows no TLS library. A program that has TLS sockets
// sets the three hooks below (host/effs/tls_server.c does, for its
// TlsSrv sessions); a socket that no hook claims is a plain TCP socket.
// Each hook is a tentative definition, repeated word for word in the
// provider, so the program names one pointer whichever files it holds:
// - oci_tls_has(fd): 1 when fd is a TLS session.
// - oci_tls_read(fd, buf, cap, evts, code): > 0 bytes read; 0 to wait
//   for *evts (POLLIN or POLLOUT); -1 at the end of the stream (*code 0)
//   or on an error (*code an errno); -2 when fd is no TLS session.
// - oci_tls_write(fd, buf, len, evts, code): > 0 bytes written; 0 to wait
//   for *evts; -1 on an error (*code); -2 when fd is no TLS session.
//
// Every name here starts with ocb_ (or oci_ for the hooks).

#include <dlfcn.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <unistd.h>
#ifdef __linux__
#include <sys/sendfile.h>
#endif

#ifndef O_CLOEXEC
#define O_CLOEXEC 0
#endif
// The sockets are non-blocking anyway (ocb_nonblock); SIGPIPE is ignored
// by the runtime.
#ifndef MSG_DONTWAIT
#define MSG_DONTWAIT 0
#endif
#ifdef MSG_NOSIGNAL
#define OCB_NOSIGNAL MSG_NOSIGNAL
#else
#define OCB_NOSIGNAL 0
#endif

int (*oci_tls_has)(int fd);
int (*oci_tls_read)(int fd, char* buf, int cap, short* evts, u32* code);
int (*oci_tls_write)(int fd, const char* buf, int len, short* evts, u32* code);

// The buffer of one transfer, and the most it moves before it steps
// aside.
#define OCB_BUF    (1 << 20)
#define OCB_TURN   (16u << 20)
#define OCB_MAX_FD 65536

// libcrypto
// ---------

typedef struct {
  void*       (*ctx_new)(void);
  void        (*ctx_free)(void*);
  const void* (*sha256)(void);
  int         (*init)(void*, const void*, void*);
  int         (*update)(void*, const void*, size_t);
  int         (*final)(void*, unsigned char*, unsigned int*);
} OcbLib;

static OcbLib          ocb_lib;
static int             ocb_ready;  // 0 untried, 1 loaded, -1 missing
static char            ocb_why[200];
static pthread_mutex_t ocb_gate = PTHREAD_MUTEX_INITIALIZER;

#define OCB_SYM(h, field, name) \
  if ((*(void**)&ocb_lib.field = dlsym(h, name)) == NULL) { \
    snprintf(ocb_why, sizeof ocb_why, "OciBlob: %s is missing", name); \
    return -1; \
  }

static int ocb_load_now(void) {
  static const char* const names[] = {
    "libcrypto.so.3", "libcrypto.so.1.1", "libcrypto.so",
    "/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib",
    "/usr/local/opt/openssl@3/lib/libcrypto.3.dylib",
    "libcrypto.3.dylib", NULL };
  const char* own = getenv("BEND_KUBE_LIBCRYPTO");
  void* h = NULL;
  if (own != NULL && *own != 0) {
    h = dlopen(own, RTLD_NOW | RTLD_LOCAL);
  }
  for (u32 i = 0; h == NULL && (own == NULL || *own == 0) && names[i] != NULL; i += 1) {
    h = dlopen(names[i], RTLD_NOW | RTLD_LOCAL);
  }
  if (h == NULL) {
    snprintf(ocb_why, sizeof ocb_why, "OciBlob: libcrypto not found (set BEND_KUBE_LIBCRYPTO)");
    return -1;
  }
  OCB_SYM(h, ctx_new, "EVP_MD_CTX_new");
  OCB_SYM(h, ctx_free, "EVP_MD_CTX_free");
  OCB_SYM(h, sha256, "EVP_sha256");
  OCB_SYM(h, init, "EVP_DigestInit_ex");
  OCB_SYM(h, update, "EVP_DigestUpdate");
  OCB_SYM(h, final, "EVP_DigestFinal_ex");
  return 1;
}

static __attribute__((unused)) int ocb_load(void) {
  pthread_mutex_lock(&ocb_gate);
  if (ocb_ready == 0) {
    ocb_ready = ocb_load_now();
  }
  int r = ocb_ready;
  pthread_mutex_unlock(&ocb_gate);
  return r;
}

// The hash states
// ---------------

// A blob's SHA-256 state, by its descriptor. Only the loop touches it.
static void* ocb_sum[OCB_MAX_FD];

static __attribute__((unused)) void* ocb_sum_of(int fd) {
  return fd >= 0 && fd < OCB_MAX_FD ? ocb_sum[fd] : NULL;
}

// Frees fd's state, if any: at commit, or when a blob ended by File.close
// left it and its descriptor number comes back.
static __attribute__((unused)) void ocb_sum_drop(int fd) {
  if (fd >= 0 && fd < OCB_MAX_FD && ocb_sum[fd] != NULL) {
    ocb_lib.ctx_free(ocb_sum[fd]);
    ocb_sum[fd] = NULL;
  }
}

// Writes n bytes at the end of the blob and adds them to its hash: 0, or
// an errno.
static __attribute__((unused)) u32 ocb_put(int fd, void* md, const char* p, u64 n) {
  if (ocb_lib.update(md, p, (size_t)n) != 1) {
    return EIO;
  }
  for (u64 at = 0; at < n;) {
    ssize_t k = write(fd, p + at, (size_t)(n - at));
    if (k < 0 && errno == EINTR) {
      continue;
    }
    if (k <= 0) {
      return k < 0 ? (u32)errno : EIO;
    }
    at += (u64)k;
  }
  return 0;
}

// Sockets
// -------

static __attribute__((unused)) void ocb_nonblock(int fd) {
  int fl = fcntl(fd, F_GETFL);
  if (fl >= 0 && !(fl & O_NONBLOCK)) {
    fcntl(fd, F_SETFL, fl | O_NONBLOCK);
  }
}

static __attribute__((unused)) int ocb_is_tls(int fd) {
  return oci_tls_has != NULL && oci_tls_has(fd);
}

// As oci_tls_read, for any socket.
static __attribute__((unused)) int ocb_read(int fd, char* buf, int cap, short* evts, u32* code) {
  if (oci_tls_read != NULL) {
    int n = oci_tls_read(fd, buf, cap, evts, code);
    if (n != -2) {
      return n;
    }
  }
  *evts = 0;
  *code = 0;
  ssize_t n;
  do {
    n = recv(fd, buf, (size_t)cap, MSG_DONTWAIT);
  } while (n < 0 && errno == EINTR);
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

// Files
// -----

// Opens w->data with the flags in w->word: a regular file only, no
// symbolic link as the last component; a new file is 0600 whatever the
// umask.
static __attribute__((unused)) void ocb_open_call(IoWork* w) {
  int flags = (int)w->word;
  int fd;
  do {
    fd = open(w->data, flags | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0600);
  } while (fd < 0 && errno == EINTR);
  if (fd < 0) {
    io_sys_end(w, fd);
    return;
  }
  struct stat st;
  int bad = fstat(fd, &st) != 0 ? errno : !S_ISREG(st.st_mode) ? EINVAL : 0;
  w->text = bad == EINVAL ? (char*)"OciBlob: not a regular file" : NULL;
  if (bad == 0 && (flags & O_CREAT) && fchmod(fd, 0600) != 0) {
    bad = errno;
  }
  int fl = bad == 0 ? fcntl(fd, F_GETFL) : 0;
  if (bad == 0 && (fl < 0 || fcntl(fd, F_SETFL, fl & ~O_NONBLOCK) < 0)) {
    bad = errno;
  }
  if (bad == 0 && fd >= OCB_MAX_FD) {
    bad = EMFILE;
  }
  if (bad != 0) {
    close(fd);
    w->code = (u32)bad;
    return;
  }
  w->code = 0;
  w->made = (intptr_t)fd;
}

static __attribute__((unused)) Term ocb_open_start(Env e, Term path, IoWork* w, int flags, IoPack pack) {
  w->data = io_cstr(e, path, &w->size);
  w->word = (u32)flags;
  w->text = NULL;
  if (io_nul(w->data, w->size)) {
    w->code = EINVAL;
    return pack(e, w);
  }
  return io_work(w, ocb_open_call, pack);
}

// OciBlob.create
// --------------

#ifdef CID(OciBlob.create)

static Term ocb_create_pack(Env e, IoWork* w) {
  free(w->data);
  if (w->code != 0) {
    return io_fail(e, w->code, w->text);
  }
  int fd = (int)w->made;
  ocb_sum_drop(fd);
  void* md = ocb_lib.ctx_new();
  if (md == NULL || ocb_lib.init(md, ocb_lib.sha256(), NULL) != 1) {
    if (md != NULL) {
      ocb_lib.ctx_free(md);
    }
    close(fd);
    return io_fail(e, ENOMEM, "OciBlob: cannot start a SHA-256");
  }
  ocb_sum[fd] = md;
  return io_done(e, io_hand(fd));
}

// OciBlob.create(path): created or truncated, write only, mode 0600.
Term ocb_create_run(Env e, Term* f, IoWork* w) {
  if (ocb_load() != 1) {
    return io_fail(e, ENOTSUP, ocb_why);
  }
  return ocb_open_start(e, f[0], w, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND, ocb_create_pack);
}

#endif

// OciBlob.fetch
// -------------

#ifdef CID(OciBlob.fetch)

typedef struct {
  int         file;
  int         sock;
  u64         left;   // bytes still to read from the socket
  u32         idle;   // ms with no byte that fail the fetch, 0 never
  u64         until;  // that deadline, as io_tick()
  int         fill;   // bytes in buf, not yet written
  u32         code;
  const char* text;
  char        buf[OCB_BUF];
} OcbFetch;

static Term ocb_fetch_end(Env e, IoWork* w) {
  OcbFetch* m = (OcbFetch*)w->data;
  Term r = m->code != 0 ? io_fail(e, m->code, m->text) : io_done(e, term_pak(CID(Unit), 0));
  Term out = io_tup(e, io_hand(m->file), io_tup(e, io_hand(m->sock), r));
  free(m);
  return out;
}

// Fills the buffer from the socket (a TLS read gives one record, 16 KiB
// at most) and writes it to the blob when it is full or the blob ends.
static Term ocb_fetch_more(Env e, IoWork* w) {
  OcbFetch* m    = (OcbFetch*)w->data;
  void*     md   = ocb_sum_of(m->file);
  u64       turn = 0;
  while (m->code == 0 && (m->left > 0 || m->fill > 0)) {
    if (m->fill == OCB_BUF || m->left == 0) {
      m->code = ocb_put(m->file, md, m->buf, (u64)m->fill);
      m->fill = 0;
      continue;
    }
    if (turn >= OCB_TURN) {
      // Due at the next poll: the others run first. No socket event, as a
      // TLS session may hold decrypted bytes the socket no longer shows.
      return io_wait_on(w, 0, 0, io_tick(), ocb_fetch_more);
    }
    int   room = OCB_BUF - m->fill;
    int   cap  = m->left < (u64)room ? (int)m->left : room;
    short evts;
    u32   code;
    int   n = ocb_read(m->sock, m->buf + m->fill, cap, &evts, &code);
    if (n > 0) {
      m->fill += n;
      m->left -= (u64)n;
      turn    += (u64)n;
      m->until = m->idle != 0 ? io_until(m->idle) : 0;
      continue;
    }
    if (n == 0) {
      if (m->until != 0 && io_tick() >= m->until) {
        m->code = ETIMEDOUT;
        break;
      }
      return io_wait_on(w, m->sock, evts, m->until, ocb_fetch_more);
    }
    m->code = code != 0 ? code : ECONNRESET;
    m->text = code != 0 ? NULL : "OciBlob: the peer closed before the blob's end";
  }
  return ocb_fetch_end(e, w);
}

// OciBlob.fetch(blob, sock, head, hi, lo, ms)
Term ocb_fetch_run(Env e, Term* f, IoWork* w) {
  OcbFetch* m = io_mem(malloc(sizeof *m));
  w->data  = (char*)m;
  m->file  = (int)io_hand_v(f[0]);
  m->sock  = (int)io_hand_v(f[1]);
  m->left  = ((u64)(u32)f[3] << 32) | (u64)(u32)f[4];
  m->idle  = (u32)f[5];
  m->until = m->idle != 0 ? io_until(m->idle) : 0;
  m->fill  = 0;
  m->code  = 0;
  m->text  = NULL;
  void* md = ocb_sum_of(m->file);
  u64   hn   = 0;
  char* head = NULL;
  int   bad  = 0;
#ifdef CID(Con)
  head = io_cbuf(e, f[2], &hn, CID(Con));
  bad  = head == NULL;
#endif
  if (md == NULL) {
    m->code = EBADF;
    m->text = "OciBlob: not a blob from OciBlob.create";
  } else if (bad) {
    m->code = EINVAL;
    m->text = "OciBlob: a byte past 255";
  } else if (hn > 0) {
    m->code = ocb_put(m->file, md, head, hn);
  }
  free(head);
  if (m->code != 0) {
    return ocb_fetch_end(e, w);
  }
  ocb_nonblock(m->sock);
  return ocb_fetch_more(e, w);
}

#endif

// OciBlob.commit
// --------------

#ifdef CID(OciBlob.commit)

static void ocb_commit_call(IoWork* w) {
  int n;
  do {
    n = fsync((int)w->hand);
  } while (n < 0 && errno == EINTR);
  io_sys_end(w, n);
}

static Term ocb_commit_pack(Env e, IoWork* w) {
  int           fd = (int)w->hand;
  unsigned char d[64];
  unsigned int  dn = 0;
  char          hex[129];
  void*         md = ocb_sum_of(fd);
  u32           code = w->code;
  if (code == 0 && (md == NULL || ocb_lib.final(md, d, &dn) != 1 || dn != 32)) {
    code = EIO;
  }
  for (unsigned int i = 0; i < dn && i < 32; i += 1) {
    snprintf(hex + 2 * i, 3, "%02x", d[i]);
  }
  ocb_sum_drop(fd);
  close(fd);
  return code != 0 ? io_fail(e, code, NULL) : io_done(e, io_str(e, hex, 64));
}

// OciBlob.commit(blob): consumes the blob.
Term ocb_commit_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  if (ocb_sum_of((int)w->hand) == NULL) {
    close((int)w->hand);
    return io_fail(e, EBADF, "OciBlob: not a blob from OciBlob.create");
  }
  return io_work(w, ocb_commit_call, ocb_commit_pack);
}

#endif

// OciBlob.send
// ------------

#ifdef CID(OciBlob.send)

typedef struct {
  int         sock;
  int         file;
  int         tls;
  u64         at;     // the file offset of the next byte to send
  u64         left;   // bytes still to send
  u32         idle;
  u64         until;
  int         len;    // bytes in buf, read from the file at `at`
  int         off;    // of them, sent
  u32         code;
  const char* text;
  char        buf[OCB_BUF];
} OcbSend;

static Term ocb_send_end(Env e, IoWork* w) {
  OcbSend* m = (OcbSend*)w->data;
  Term r = m->code != 0 ? io_fail(e, m->code, m->text) : io_done(e, term_pak(CID(Unit), 0));
  Term out = io_tup(e, io_hand(m->sock), io_tup(e, io_hand(m->file), r));
  free(m);
  return out;
}

#ifdef __linux__

// One step on a plain socket, with sendfile(2): > 0 bytes sent, 0 to wait
// for the socket, -1 on an error (m->code).
static int64_t ocb_send_file(OcbSend* m) {
  size_t  want = m->left < (1u << 30) ? (size_t)m->left : (1u << 30);
  off_t   off  = (off_t)m->at;
  ssize_t n    = sendfile(m->sock, m->file, &off, want);
  if (n > 0) {
    return (int64_t)n;
  }
  if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) {
    return 0;
  }
  m->code = n < 0 ? (u32)errno : EIO;
  m->text = n < 0 ? NULL : "OciBlob: the file ends before the range";
  return -1;
}

#endif

// One step through the buffer, as ocb_send_file: pread, then the TLS hook
// (a TLS socket) or send(2) (a plain socket, where sendfile(2) is not
// used). *evts is what to wait for.
static int64_t ocb_send_buf(OcbSend* m, short* evts) {
  *evts = POLLOUT;
  if (m->off == m->len) {
    size_t  want = m->left < OCB_BUF ? (size_t)m->left : OCB_BUF;
    ssize_t k;
    do {
      k = pread(m->file, m->buf, want, (off_t)m->at);
    } while (k < 0 && errno == EINTR);
    if (k <= 0) {
      m->code = k < 0 ? (u32)errno : EIO;
      m->text = k < 0 ? NULL : "OciBlob: the file ends before the range";
      return -1;
    }
    m->len = (int)k;
    m->off = 0;
  }
  u32 code = 0;
  int n;
  if (m->tls) {
    n = oci_tls_write(m->sock, m->buf + m->off, m->len - m->off, evts, &code);
  } else {
    ssize_t k;
    do {
      k = send(m->sock, m->buf + m->off, (size_t)(m->len - m->off), MSG_DONTWAIT | OCB_NOSIGNAL);
    } while (k < 0 && errno == EINTR);
    n    = k > 0 ? (int)k : k < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) ? 0 : -1;
    code = k < 0 && n < 0 ? (u32)errno : 0;
  }
  if (n > 0) {
    m->off += n;
    return (int64_t)n;
  }
  if (n == 0) {
    return 0;
  }
  m->code = code != 0 ? code : EPIPE;
  return -1;
}

static Term ocb_send_more(Env e, IoWork* w) {
  OcbSend* m    = (OcbSend*)w->data;
  u64      turn = 0;
  while (m->left > 0 && m->code == 0) {
    if (turn >= OCB_TURN) {
      return io_wait_on(w, 0, 0, io_tick(), ocb_send_more);
    }
    short   evts = POLLOUT;
#ifdef __linux__
    int64_t n    = m->tls ? ocb_send_buf(m, &evts) : ocb_send_file(m);
#else
    int64_t n    = ocb_send_buf(m, &evts);
#endif
    if (n > 0) {
      m->at   += (u64)n;
      m->left -= (u64)n;
      turn    += (u64)n;
      m->until = m->idle != 0 ? io_until(m->idle) : 0;
      continue;
    }
    if (n == 0) {
      if (m->until != 0 && io_tick() >= m->until) {
        m->code = ETIMEDOUT;
        break;
      }
      return io_wait_on(w, m->sock, evts, m->until, ocb_send_more);
    }
  }
  return ocb_send_end(e, w);
}

// OciBlob.send(sock, file, off_hi, off_lo, len_hi, len_lo, ms)
Term ocb_send_run(Env e, Term* f, IoWork* w) {
  OcbSend* m = io_mem(malloc(sizeof *m));
  w->data  = (char*)m;
  m->sock  = (int)io_hand_v(f[0]);
  m->file  = (int)io_hand_v(f[1]);
  m->at    = ((u64)(u32)f[2] << 32) | (u64)(u32)f[3];
  m->left  = ((u64)(u32)f[4] << 32) | (u64)(u32)f[5];
  m->idle  = (u32)f[6];
  m->until = m->idle != 0 ? io_until(m->idle) : 0;
  m->tls   = ocb_is_tls(m->sock);
  m->len   = 0;
  m->off   = 0;
  m->code  = 0;
  m->text  = NULL;
  if (m->at + m->left < m->at || (int64_t)(m->at + m->left) < 0) {
    m->code = EINVAL;
    m->text = "OciBlob: the range passes 2^63";
    return ocb_send_end(e, w);
  }
  ocb_nonblock(m->sock);
  return ocb_send_more(e, w);
}

#endif

// Each effect registers only when the program uses it: an unused def has
// no id.
static void __attribute__((constructor)) ocb_use(void) {
#ifdef CID(OciBlob.create)
  io_eff(CID(OciBlob.create), ocb_create_run);
#endif
#ifdef CID(OciBlob.fetch)
  io_eff(CID(OciBlob.fetch), ocb_fetch_run);
#endif
#ifdef CID(OciBlob.commit)
  io_eff(CID(OciBlob.commit), ocb_commit_run);
#endif
#ifdef CID(OciBlob.send)
  io_eff(CID(OciBlob.send), ocb_send_run);
#endif
}
