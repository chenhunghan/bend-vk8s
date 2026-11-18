// Layer files
// ===========

// The file IO of the shared layer store (host/layers/fs.bend): what
// unpacking an image layer into ~/.vk8s/layers/<hex> needs and Base and
// bend-vmm's V.Fs do not give. Every decision (what to create, where,
// in which order, what to keep) is Bend's (src/layers/); this file only
// runs the system calls. Every name starts with lfs_.
//
// Why C (docs/GOAL.md, "Pure Bend as far as possible"): a layer's file
// data is a byte range of the decompressed tar, and a layer can pass
// 4 GiB, while Base's and BinFile's offsets are U32 and a Base read puts
// each byte in a list cell. So the copy is pread/write here and its
// bytes never enter Bend. The rest (a 64-bit block read, entry creation,
// directory fsync, rename and recursive remove) are a few system calls
// each that Base and V.Fs lack: symlink(2), link(2), O_EXCL creation,
// a no-replace rename of a directory, and a remove that never follows a
// symbolic link.
//
// The effects:
// - LayerFs.read(file, off_hi, off_lo, max): up to max bytes (at most
//   2 MiB) at a 64-bit offset; fewer only at the end of the file.
// - LayerFs.copy(file, off_hi, off_lo, len_hi, len_lo, dst): a new file
//   at dst (0644, O_EXCL, no symbolic link followed) with exactly that
//   range of file; fsync, close. copy_file_range(2) on Linux where the
//   kernel has it (a reflink on file systems that share blocks), else a
//   pread/write loop. The file ending first fails with EIO.
// - LayerFs.make(kind, path, arg): one entry: 0 a directory (0755; one
//   already there is fine), 1 an empty file (0644), 2 a symbolic link to
//   the bytes arg, 3 a hard link to the file at the path arg (the link
//   itself when arg is a symbolic link), 4 a file (0644) holding the
//   bytes arg, fsynced, 5 a new directory (0755; one already there fails
//   with EEXIST, so two fills never share a tmp directory). Nothing is created through a symbolic link at
//   path, and a file or link already at path fails with EEXIST.
// - LayerFs.fsync_dir(path): fsync of a directory (F_FULLFSYNC on macOS,
//   so the drive's cache is written too).
// - LayerFs.rename_dir(from, to): rename(2) that never replaces what is
//   at to: renameat2(RENAME_NOREPLACE) on Linux, renamex_np(RENAME_EXCL)
//   on macOS. A directory already at to fails with EEXIST (the caller
//   lost a publish race). Where the kernel lacks the flag, rename(2): it
//   fails with ENOTEMPTY or EEXIST onto a directory with entries, and a
//   layer directory onto an empty one holds the same (empty) layer.
// - LayerFs.remove_tree(path): removes path and everything under it,
//   never following a symbolic link (each directory is opened with
//   O_NOFOLLOW and its entries are removed with unlinkat). A path that is
//   not there is removed already.
//
// Every effect but read runs on an IO helper thread (io_work): a big
// copy, fsync and a deep remove never block the loop. read moves at most
// 2 MiB, from the page cache, and also runs on a helper.

#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#ifdef __linux__
#include <sys/syscall.h>
#endif

#ifndef O_CLOEXEC
#define O_CLOEXEC 0
#endif
#ifndef O_DIRECTORY
#define O_DIRECTORY 0
#endif

// The most one LayerFs.read answers: an extended header's data is at
// most 1 MiB (src/layers/tar.bend), a header block 512 bytes.
#define LFS_READ_MAX (2u << 20)
// The buffer of a copy without copy_file_range.
#define LFS_BUF (1u << 20)
// How deep LayerFs.remove_tree goes (each level holds a descriptor).
#define LFS_DEPTH 512

typedef struct {
  int   file;  // the source (read, copy)
  u64   at;    // its offset
  u64   len;   // bytes to copy, or the most to read
  u32   kind;  // LayerFs.make's kind
  char* path;  // dst, path, from
  u64   np;
  char* arg;   // make's bytes, rename's to
  u64   na;
  u64   got;   // bytes read
  char* buf;
  u32   code;
  const char* text;
} LfsJob;

static __attribute__((unused)) LfsJob* lfs_job(void) {
  LfsJob* j = io_mem(calloc(1, sizeof *j));
  j->file = -1;
  return j;
}

static __attribute__((unused)) void lfs_free(LfsJob* j) {
  free(j->path);
  free(j->arg);
  free(j->buf);
  free(j);
}

static __attribute__((unused)) Term lfs_result(Env e, LfsJob* j) {
  return j->code != 0 ? io_fail(e, j->code, j->text) : io_done(e, term_pak(CID(Unit), 0));
}

// The result of an effect that hands back no file, and the end of its
// job.
static __attribute__((unused)) Term lfs_path_pack(Env e, IoWork* w) {
  LfsJob* j = (LfsJob*)w->data;
  Term    r = lfs_result(e, j);
  lfs_free(j);
  return r;
}

// fsync, retried on EINTR: 0 or an errno.
static __attribute__((unused)) u32 lfs_sync(int fd) {
  int n;
  do {
    n = fsync(fd);
  } while (n < 0 && errno == EINTR);
  return n < 0 ? (u32)errno : 0;
}

// Writes all n bytes: 0 or an errno.
static __attribute__((unused)) u32 lfs_write_all(int fd, const char* p, u64 n) {
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

// A new regular file at path: 0644 whatever the umask, never through a
// symbolic link, never over anything there. -1 with errno set.
static __attribute__((unused)) int lfs_create(const char* path) {
  int fd;
  do {
    fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0644);
  } while (fd < 0 && errno == EINTR);
  if (fd >= 0 && fchmod(fd, 0644) != 0) {
    int err = errno;
    close(fd);
    unlink(path);
    errno = err;
    return -1;
  }
  return fd;
}

// LayerFs.read
// ------------

#ifdef CID(LayerFs.read)

static void lfs_read_call(IoWork* w) {
  LfsJob* j = (LfsJob*)w->data;
  while (j->got < j->len) {
    ssize_t n;
    do {
      n = pread(j->file, j->buf + j->got, (size_t)(j->len - j->got), (off_t)(j->at + j->got));
    } while (n < 0 && errno == EINTR);
    if (n < 0) {
      j->code = (u32)errno;
      return;
    }
    if (n == 0) {
      return;
    }
    j->got += (u64)n;
  }
}

static Term lfs_read_pack(Env e, IoWork* w) {
  LfsJob* j = (LfsJob*)w->data;
  Term r = j->code != 0 ? io_fail(e, j->code, j->text) : io_done(e, io_list(e, j->buf, j->got));
  Term out = io_tup(e, io_hand(j->file), r);
  lfs_free(j);
  return out;
}

// LayerFs.read(file, off_hi, off_lo, max)
Term lfs_read_run(Env e, Term* f, IoWork* w) {
  LfsJob* j = lfs_job();
  w->data = (char*)j;
  j->file = (int)io_hand_v(f[0]);
  j->at   = ((u64)(u32)f[1] << 32) | (u64)(u32)f[2];
  j->len  = (u32)f[3] < LFS_READ_MAX ? (u64)(u32)f[3] : (u64)LFS_READ_MAX;
  j->buf  = io_mem(malloc((size_t)j->len + 1));
  if ((int64_t)j->at < 0) {
    j->code = EINVAL;
    j->text = "LayerFs: the offset passes 2^63";
    return lfs_read_pack(e, w);
  }
  return io_work(w, lfs_read_call, lfs_read_pack);
}

#endif

// LayerFs.copy
// ------------

#ifdef CID(LayerFs.copy)

#if defined(__linux__) && defined(SYS_copy_file_range)
// copy_file_range(2) from j->at: > 0 bytes copied, 0 when the source
// ended, -1 with errno set; ENOSYS, EXDEV, EINVAL and EOPNOTSUPP mean
// "use the buffer".
static int64_t lfs_cfr(LfsJob* j, int out, u64 left) {
  int64_t off  = (int64_t)j->at;
  size_t  want = left < (1u << 30) ? (size_t)left : (1u << 30);
  ssize_t n;
  do {
    n = (ssize_t)syscall(SYS_copy_file_range, j->file, &off, out, NULL, want, 0u);
  } while (n < 0 && errno == EINTR);
  return (int64_t)n;
}
#endif

static void lfs_copy_call(IoWork* w) {
  LfsJob* j  = (LfsJob*)w->data;
  int     out = lfs_create(j->path);
  if (out < 0) {
    j->code = (u32)errno;
    return;
  }
  u64 left = j->len;
#if defined(__linux__) && defined(SYS_copy_file_range)
  int fast = 1;
  while (fast && left > 0 && j->code == 0) {
    int64_t n = lfs_cfr(j, out, left);
    if (n > 0) {
      j->at += (u64)n;
      left  -= (u64)n;
    } else if (n == 0) {
      j->code = EIO;
      j->text = "LayerFs: the tar ends inside a file's data";
    } else if (errno == ENOSYS || errno == EXDEV || errno == EINVAL || errno == EOPNOTSUPP) {
      fast = 0;
    } else {
      j->code = (u32)errno;
    }
  }
#endif
  if (left > 0 && j->code == 0) {
    j->buf = malloc(LFS_BUF);
    if (j->buf == NULL) {
      j->code = ENOMEM;
    }
  }
  while (left > 0 && j->code == 0) {
    size_t  want = left < LFS_BUF ? (size_t)left : LFS_BUF;
    ssize_t n;
    do {
      n = pread(j->file, j->buf, want, (off_t)j->at);
    } while (n < 0 && errno == EINTR);
    if (n <= 0) {
      j->code = n < 0 ? (u32)errno : EIO;
      j->text = n < 0 ? NULL : "LayerFs: the tar ends inside a file's data";
      break;
    }
    j->code = lfs_write_all(out, j->buf, (u64)n);
    j->at  += (u64)n;
    left   -= (u64)n;
  }
  if (j->code == 0) {
    j->code = lfs_sync(out);
  }
  close(out);
  if (j->code != 0) {
    unlink(j->path);
  }
}

static Term lfs_copy_pack(Env e, IoWork* w) {
  LfsJob* j   = (LfsJob*)w->data;
  Term    out = io_tup(e, io_hand(j->file), lfs_result(e, j));
  lfs_free(j);
  return out;
}

// LayerFs.copy(file, off_hi, off_lo, len_hi, len_lo, dst)
Term lfs_copy_run(Env e, Term* f, IoWork* w) {
  LfsJob* j = lfs_job();
  w->data = (char*)j;
  j->file = (int)io_hand_v(f[0]);
  j->at   = ((u64)(u32)f[1] << 32) | (u64)(u32)f[2];
  j->len  = ((u64)(u32)f[3] << 32) | (u64)(u32)f[4];
  j->path = io_cstr(e, f[5], &j->np);
  if (io_nul(j->path, j->np) || j->np == 0) {
    j->code = EINVAL;
    return lfs_copy_pack(e, w);
  }
  if (j->at + j->len < j->at || (int64_t)(j->at + j->len) < 0) {
    j->code = EINVAL;
    j->text = "LayerFs: the range passes 2^63";
    return lfs_copy_pack(e, w);
  }
  return io_work(w, lfs_copy_call, lfs_copy_pack);
}

#endif

// LayerFs.make
// ------------

#ifdef CID(LayerFs.make)

static void lfs_make_call(IoWork* w) {
  LfsJob*     j = (LfsJob*)w->data;
  struct stat st;
  int         fd;
  switch (j->kind) {
    case 0:
      if (mkdir(j->path, 0755) == 0) {
        j->code = chmod(j->path, 0755) == 0 ? 0 : (u32)errno;
      } else if (errno == EEXIST && lstat(j->path, &st) == 0 && S_ISDIR(st.st_mode)) {
        j->code = 0;
      } else {
        j->code = (u32)errno;
      }
      break;
    case 1:
    case 4:
      fd = lfs_create(j->path);
      if (fd < 0) {
        j->code = (u32)errno;
        break;
      }
      if (j->kind == 4) {
        j->code = lfs_write_all(fd, j->arg, j->na);
        if (j->code == 0) {
          j->code = lfs_sync(fd);
        }
      }
      close(fd);
      if (j->code != 0) {
        unlink(j->path);
      }
      break;
    case 5:
      if (mkdir(j->path, 0755) == 0) {
        j->code = chmod(j->path, 0755) == 0 ? 0 : (u32)errno;
      } else {
        j->code = (u32)errno;
      }
      break;
    case 2:
      j->code = symlink(j->arg, j->path) == 0 ? 0 : (u32)errno;
      break;
    case 3:
      j->code = linkat(AT_FDCWD, j->arg, AT_FDCWD, j->path, 0) == 0 ? 0 : (u32)errno;
      break;
    default:
      j->code = EINVAL;
      j->text = "LayerFs: unknown entry kind";
  }
}

// LayerFs.make(kind, path, arg)
Term lfs_make_run(Env e, Term* f, IoWork* w) {
  LfsJob* j = lfs_job();
  w->data = (char*)j;
  j->kind = (u32)f[0];
  j->path = io_cstr(e, f[1], &j->np);
  j->arg  = NULL;
#ifdef CID(Con)
  j->arg = io_cbuf(e, f[2], &j->na, CID(Con));
#endif
  if (j->arg == NULL) {
    j->code = EINVAL;
    j->text = "LayerFs: a byte past 255";
    return lfs_path_pack(e, w);
  }
  // The C string of arg: io_cbuf leaves room for no NUL, so copy it.
  char* z = io_mem(malloc((size_t)j->na + 1));
  memcpy(z, j->arg, (size_t)j->na);
  z[j->na] = 0;
  free(j->arg);
  j->arg = z;
  int text = j->kind == 2 || j->kind == 3;
  if (io_nul(j->path, j->np) || j->np == 0 || (text && (j->na == 0 || memchr(j->arg, 0, (size_t)j->na) != NULL))) {
    j->code = EINVAL;
    return lfs_path_pack(e, w);
  }
  return io_work(w, lfs_make_call, lfs_path_pack);
}

#endif

// LayerFs.fsync_dir
// -----------------

#ifdef CID(LayerFs.fsync_dir)

static void lfs_fsync_dir_call(IoWork* w) {
  LfsJob* j = (LfsJob*)w->data;
  int     fd;
  do {
    fd = open(j->path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  } while (fd < 0 && errno == EINTR);
  if (fd < 0) {
    j->code = (u32)errno;
    return;
  }
#ifdef F_FULLFSYNC
  if (fcntl(fd, F_FULLFSYNC) != 0) {
    j->code = lfs_sync(fd);
  }
#else
  j->code = lfs_sync(fd);
#endif
  close(fd);
}

// LayerFs.fsync_dir(path)
Term lfs_fsync_dir_run(Env e, Term* f, IoWork* w) {
  LfsJob* j = lfs_job();
  w->data = (char*)j;
  j->path = io_cstr(e, f[0], &j->np);
  if (io_nul(j->path, j->np) || j->np == 0) {
    j->code = EINVAL;
    return lfs_path_pack(e, w);
  }
  return io_work(w, lfs_fsync_dir_call, lfs_path_pack);
}

#endif

// LayerFs.rename_dir
// ------------------

#ifdef CID(LayerFs.rename_dir)

#ifndef RENAME_NOREPLACE
#define RENAME_NOREPLACE (1 << 0)
#endif

static void lfs_rename_call(IoWork* w) {
  LfsJob* j = (LfsJob*)w->data;
  int     n = -1;
  int     plain = 1;
#if defined(__linux__) && defined(SYS_renameat2)
  n = (int)syscall(SYS_renameat2, AT_FDCWD, j->path, AT_FDCWD, j->arg, RENAME_NOREPLACE);
  plain = n < 0 && (errno == ENOSYS || errno == EINVAL);
#elif defined(__APPLE__) && defined(RENAME_EXCL)
  n = renamex_np(j->path, j->arg, RENAME_EXCL);
  plain = n < 0 && (errno == ENOTSUP || errno == EINVAL);
#endif
  if (plain) {
    n = rename(j->path, j->arg);
  }
  j->code = n == 0 ? 0 : errno == ENOTEMPTY ? EEXIST : (u32)errno;
}

// LayerFs.rename_dir(from, to)
Term lfs_rename_run(Env e, Term* f, IoWork* w) {
  LfsJob* j = lfs_job();
  w->data = (char*)j;
  j->path = io_cstr(e, f[0], &j->np);
  j->arg  = io_cstr(e, f[1], &j->na);
  if (io_nul(j->path, j->np) || io_nul(j->arg, j->na) || j->np == 0 || j->na == 0) {
    j->code = EINVAL;
    return lfs_path_pack(e, w);
  }
  return io_work(w, lfs_rename_call, lfs_path_pack);
}

#endif

// LayerFs.remove_tree
// -------------------

#ifdef CID(LayerFs.remove_tree)

// Empties the directory open at dfd (which it closes), depth levels deep
// at most: 0 or an errno. Each pass removes what readdir shows; passes
// repeat until one finds nothing, since removing while reading may skip
// an entry (APFS).
static u32 lfs_empty(int dfd, int depth) {
  DIR* d = fdopendir(dfd);
  if (d == NULL) {
    u32 err = (u32)errno;
    close(dfd);
    return err;
  }
  u32 code = 0;
  for (int more = 1; more && code == 0;) {
    more = 0;
    rewinddir(d);
    struct dirent* ent;
    while (code == 0 && (ent = readdir(d)) != NULL) {
      const char* n = ent->d_name;
      if (strcmp(n, ".") == 0 || strcmp(n, "..") == 0) {
        continue;
      }
      more = 1;
      struct stat st;
      if (fstatat(dirfd(d), n, &st, AT_SYMLINK_NOFOLLOW) != 0) {
        code = errno == ENOENT ? 0 : (u32)errno;
        continue;
      }
      if (S_ISDIR(st.st_mode)) {
        if (depth >= LFS_DEPTH) {
          code = ELOOP;
          break;
        }
        int sub;
        do {
          sub = openat(dirfd(d), n, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        } while (sub < 0 && errno == EINTR);
        code = sub < 0 ? (u32)errno : lfs_empty(sub, depth + 1);
        if (code == 0 && unlinkat(dirfd(d), n, AT_REMOVEDIR) != 0 && errno != ENOENT) {
          code = (u32)errno;
        }
      } else if (unlinkat(dirfd(d), n, 0) != 0 && errno != ENOENT) {
        code = (u32)errno;
      }
    }
  }
  closedir(d);
  return code;
}

static void lfs_remove_call(IoWork* w) {
  LfsJob*     j = (LfsJob*)w->data;
  struct stat st;
  if (lstat(j->path, &st) != 0) {
    j->code = errno == ENOENT ? 0 : (u32)errno;
    return;
  }
  if (!S_ISDIR(st.st_mode)) {
    j->code = unlink(j->path) == 0 || errno == ENOENT ? 0 : (u32)errno;
    return;
  }
  int fd;
  do {
    fd = open(j->path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  } while (fd < 0 && errno == EINTR);
  j->code = fd < 0 ? (u32)errno : lfs_empty(fd, 0);
  if (j->code == 0 && rmdir(j->path) != 0 && errno != ENOENT) {
    j->code = (u32)errno;
  }
}

// LayerFs.remove_tree(path)
Term lfs_remove_run(Env e, Term* f, IoWork* w) {
  LfsJob* j = lfs_job();
  w->data = (char*)j;
  j->path = io_cstr(e, f[0], &j->np);
  if (io_nul(j->path, j->np) || j->np == 0) {
    j->code = EINVAL;
    return lfs_path_pack(e, w);
  }
  return io_work(w, lfs_remove_call, lfs_path_pack);
}

#endif

// Each effect registers only when the program uses it: an unused def has
// no id.
static void __attribute__((constructor)) lfs_use(void) {
#ifdef CID(LayerFs.read)
  io_eff(CID(LayerFs.read), lfs_read_run);
#endif
#ifdef CID(LayerFs.copy)
  io_eff(CID(LayerFs.copy), lfs_copy_run);
#endif
#ifdef CID(LayerFs.make)
  io_eff(CID(LayerFs.make), lfs_make_run);
#endif
#ifdef CID(LayerFs.fsync_dir)
  io_eff(CID(LayerFs.fsync_dir), lfs_fsync_dir_run);
#endif
#ifdef CID(LayerFs.rename_dir)
  io_eff(CID(LayerFs.rename_dir), lfs_rename_run);
#endif
#ifdef CID(LayerFs.remove_tree)
  io_eff(CID(LayerFs.remove_tree), lfs_remove_run);
#endif
}
