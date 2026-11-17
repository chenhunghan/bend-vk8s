// OCI blob transfer
// =================

// Why this is C. It is the OCI mirror's one foreign part, and the
// smallest one that works (docs/GOAL.md, "Pure Bend as far as possible"):
// one hashing copy, socket -> file, with the blob's SHA-256 computed as
// the bytes pass. Pure-Bend SHA-256 runs at about 0.38 MiB/s, a layer can
// be larger than 4 GiB (Base's and BinFile's offsets and sizes are U32),
// and every byte that enters the Bend heap costs a list cell. So these
// bytes never enter Bend, and the effects answer only results and the hex
// digest. HTTP framing, digest checks, retries, the store's layout and
// every other decision are Bend (src/oci/, host/oci/). The file calls
// around the store (facts, rename, remove, ls, mkdir -p, mtime) are
// bend-vmm's V.Fs, so this file has none.
//
// The effects (host/oci/blob.bend):
// - OciBlob.create(path): a new file (0600) and its SHA-256 state.
// - OciBlob.fetch(blob, sock, head, hi, lo, ms): head, then exactly
//   hi * 2^32 + lo bytes from the socket, into the file and the hash.
// - OciBlob.commit(blob): fsync, close, and the hex SHA-256 of every byte.
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
// sets the hook below (host/effs/tls_server.c does, for its TlsSrv
// sessions); a socket that the hook does not claim is a plain TCP socket.
// The hook is a tentative definition, repeated word for word in the
// provider, so the program names one pointer whichever files it holds:
// - oci_tls_read(fd, buf, cap, evts, code): > 0 bytes read; 0 to wait
//   for *evts (POLLIN or POLLOUT); -1 at the end of the stream (*code 0)
//   or on an error (*code an errno); -2 when fd is no TLS session.
//
// Every name here starts with ocb_ (or oci_ for the hook).

#include <dlfcn.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#ifndef O_CLOEXEC
#define O_CLOEXEC 0
#endif
// The sockets are non-blocking anyway (ocb_nonblock).
#ifndef MSG_DONTWAIT
#define MSG_DONTWAIT 0
#endif

int (*oci_tls_read)(int fd, char* buf, int cap, short* evts, u32* code);

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
}
