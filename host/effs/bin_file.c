// Binary files
// ============

// Raw bytes in and out of regular files, for what vk8s writes and reads
// that is not text: snapshot tar streams (src/standalone/snapshot.bend)
// and store dumps. A byte is a U32 0..255, as in Base's List<&2, U32>.
// The handle is Base's File (a user handle type is not supported), so
// File.close also closes it. Every call runs on an IO helper thread
// (io_work), so a slow disk never blocks the loop. Every name starts with
// binf_.
//
// BinFile.create makes the file 0600 whatever the umask, and also when it
// was there before (a dump can hold secrets). Both opens refuse a
// symbolic link as the last component (O_NOFOLLOW) and anything but a
// regular file (EINVAL), so a FIFO, a device or a directory planted in a
// shared directory never blocks or surprises a reader. Offsets and sizes
// are U32: a file past 4 GiB fails BinFile.size with EOVERFLOW.

#include <fcntl.h>
#include <sys/stat.h>

#ifndef O_CLOEXEC
#define O_CLOEXEC 0
#endif

// The most one BinFile.read answers: a caller reads a big file in ranges.
#define BINF_READ_MAX (16u << 20)

// An effect's failure: errno w->code, described by w->text, or by
// strerror when it is NULL.
static __attribute__((unused)) Term binf_fail(Env e, IoWork* w) {
  return io_fail(e, w->code, w->text);
}

// Open
// ----

#if defined(CID(BinFile.open)) || defined(CID(BinFile.create))

static void binf_open_call(IoWork* w) {
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
  w->text = bad == EINVAL ? (char*)"BinFile: not a regular file" : NULL;
  if (bad == 0 && (flags & O_CREAT) && fchmod(fd, 0600) != 0) {
    bad = errno;
  }
  // O_NONBLOCK only kept a FIFO from blocking the open: drop it.
  int fl = bad == 0 ? fcntl(fd, F_GETFL) : 0;
  if (bad == 0 && (fl < 0 || fcntl(fd, F_SETFL, fl & ~O_NONBLOCK) < 0)) {
    bad = errno;
  }
  if (bad != 0) {
    close(fd);
    w->code = (u32)bad;
    return;
  }
  w->code = 0;
  w->made = (intptr_t)fd;
}

static Term binf_open_pack(Env e, IoWork* w) {
  free(w->data);
  return w->code ? binf_fail(e, w) : io_done(e, io_hand(w->made));
}

static Term binf_open_start(Env e, Term* f, IoWork* w, int flags) {
  w->data = io_cstr(e, f[0], &w->size);
  w->word = (u32)flags;
  w->text = NULL;
  if (io_nul(w->data, w->size)) {
    w->code = EINVAL;
    return binf_open_pack(e, w);
  }
  return io_work(w, binf_open_call, binf_open_pack);
}

#endif

#ifdef CID(BinFile.open)

// BinFile.open(path): read only.
Term binf_open_run(Env e, Term* f, IoWork* w) {
  return binf_open_start(e, f, w, O_RDONLY);
}

#endif

#ifdef CID(BinFile.create)

// BinFile.create(path): write only, created or truncated, every write at
// the end.
Term binf_create_run(Env e, Term* f, IoWork* w) {
  return binf_open_start(e, f, w, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND);
}

#endif

// Append
// ------

#ifdef CID(BinFile.append)

static void binf_append_call(IoWork* w) {
  int     fd = (int)w->hand;
  ssize_t n  = 0;
  for (u64 at = 0; n >= 0 && at < w->size; at += (u64)n) {
    do {
      n = write(fd, w->data + at, w->size - at);
    } while (n < 0 && errno == EINTR);
    if (n == 0) {  // no progress would retry forever
      w->code = EIO;
      return;
    }
  }
  io_sys_end(w, n);
}

static Term binf_append_pack(Env e, IoWork* w) {
  free(w->data);
  Term r = w->code ? binf_fail(e, w) : io_done(e, term_pak(CID(Unit), 0));
  return io_tup(e, io_hand(w->hand), r);
}

// BinFile.append(file, bytes): a value past 255 fails with EINVAL before
// any byte is written.
Term binf_append_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  w->data = io_cbuf(e, f[1], &w->size, CID(Con));
  w->text = NULL;
  if (w->data == NULL) {
    w->code = EINVAL;
    w->text = (char*)"BinFile: a byte past 255";
    return io_tup(e, f[0], binf_fail(e, w));
  }
  w->code = 0;
  return io_work(w, binf_append_call, binf_append_pack);
}

#endif

// Read
// ----

#ifdef CID(BinFile.read)

// pread until max bytes or the end of the file. An error after some bytes
// answers them.
static void binf_read_call(IoWork* w) {
  int fd  = (int)w->hand;
  u64 got = 0;
  w->code = 0;
  while (got < w->word) {
    ssize_t n;
    do {
      n = pread(fd, w->data + got, w->word - got, (off_t)((u64)(u32)w->made + got));
    } while (n < 0 && errno == EINTR);
    if (n <= 0) {
      if (n < 0 && got == 0) {
        io_sys_end(w, n);
      }
      break;
    }
    got += (u64)n;
  }
  w->size = got;
}

static Term binf_read_pack(Env e, IoWork* w) {
  Term r = w->code ? io_fail(e, w->code, NULL) : io_done(e, io_list(e, w->data, w->size));
  free(w->data);
  return io_tup(e, io_hand(w->hand), r);
}

// BinFile.read(file, offset, max)
Term binf_read_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  w->made = (intptr_t)(u32)f[1];
  w->word = (u32)f[2] < BINF_READ_MAX ? (u32)f[2] : BINF_READ_MAX;
  w->data = io_mem(malloc((size_t)w->word + 1));
  return io_work(w, binf_read_call, binf_read_pack);
}

#endif

// Size
// ----

#ifdef CID(BinFile.size)

static void binf_size_call(IoWork* w) {
  struct stat st;
  int n = fstat((int)w->hand, &st);
  io_sys_end(w, n);
  if (n == 0) {
    w->code = (u64)st.st_size > (u64)UINT32_MAX ? EOVERFLOW : 0;
    w->word = (u32)st.st_size;
  }
}

static Term binf_size_pack(Env e, IoWork* w) {
  return io_tup(e, io_hand(w->hand), io_res(e, w, (Term)w->word));
}

// BinFile.size(file)
Term binf_size_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  return io_work(w, binf_size_call, binf_size_pack);
}

#endif

// Close
// -----

#ifdef CID(BinFile.close)

// BinFile.close(file)
Term binf_close_run(Env e, Term* f, IoWork* w) {
  close((int)io_hand_v(f[0]));
  return term_pak(CID(Unit), 0);
}

#endif

// Each effect registers only when the program uses it: an unused def has
// no id.
static void __attribute__((constructor)) binf_use(void) {
#ifdef CID(BinFile.open)
  io_eff(CID(BinFile.open), binf_open_run);
#endif
#ifdef CID(BinFile.create)
  io_eff(CID(BinFile.create), binf_create_run);
#endif
#ifdef CID(BinFile.append)
  io_eff(CID(BinFile.append), binf_append_run);
#endif
#ifdef CID(BinFile.read)
  io_eff(CID(BinFile.read), binf_read_run);
#endif
#ifdef CID(BinFile.size)
  io_eff(CID(BinFile.size), binf_size_run);
#endif
#ifdef CID(BinFile.close)
  io_eff(CID(BinFile.close), binf_close_run);
#endif
}
