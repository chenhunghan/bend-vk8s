// The guest's system calls (host/gsys.bend): what PID 1 and the node's
// snapshotter ran a busybox process for (mkdir, rm, mv, test, ls,
// mountpoint, mount, umount, rmdir, hwclock, fstrim, tar to /dev/null).
// Every decision is Bend's (src/guest/sysop.bend, host/gsys.bend): which
// directories of a path to make, what an errno means, what to trim, what
// a tree holds. Each effect here is one system call (ls: one directory
// read; drain: one file read to its end), its arguments checked.
//
// Why C, and why not bend-vmm's V.Fs (which the host half uses): Base
// has no directory, stat, mount, clock or ioctl effect, and V.Fs lives in
// bend-vmm's hvf.c, whose constructors block SIGTERM, SIGINT and SIGHUP
// and set BENDRTS for the process and its children: wrong for PID 1 and
// for a daemon it starts. V.Fs also has no stat that follows a link, no
// device, link count or block count, and no mount. Every name starts
// with gsys_. Each effect registers only when the program reaches its def.

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>
#ifdef __linux__
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <linux/fs.h>
#endif

#ifndef O_CLOEXEC
#define O_CLOEXEC 0
#endif

// A path argument: a malloc'ed C string, or NULL (and *code EINVAL) when
// it is empty or holds a NUL.
static __attribute__((unused)) char* gsys_path(Env e, Term t, u32* code) {
  u64   n = 0;
  char* p = io_cstr(e, t, &n);
  if (io_nul(p, n) || n == 0) {
    free(p);
    *code = EINVAL;
    return NULL;
  }
  return p;
}

// A text argument that may be empty (a mount's source, type or data).
static __attribute__((unused)) char* gsys_text(Env e, Term t, u32* code) {
  u64   n = 0;
  char* p = io_cstr(e, t, &n);
  if (io_nul(p, n)) {
    free(p);
    *code = EINVAL;
    return NULL;
  }
  return p;
}

static __attribute__((unused)) Term gsys_words(Env e, const u32* ws, int n) {
  Term xs = term_pak(CID(Nil), 0);
  for (int i = n; i > 0; i--) {
    xs = io_node(e, CID(Con), (Term)ws[i - 1], xs);
  }
  return xs;
}

// Gsys.mkdir(path, mode): mkdir(2). 0, or the errno.
#ifdef CID(Gsys.mkdir)
Term gsys_mkdir_run(Env e, Term* f, IoWork* w) {
  u32   code = 0;
  char* path = gsys_path(e, f[0], &code);
  if (path != NULL && mkdir(path, (mode_t)((u32)f[1] & 07777)) != 0) code = (u32)errno;
  free(path);
  return (Term)code;
}
#endif

// Gsys.stat(path, follow): stat(2) (follow 1) or lstat(2) (follow 0) as
// ten words: st_mode, st_nlink, then the high and low halves of st_dev,
// st_ino, st_size and st_blocks (512-byte units).
#ifdef CID(Gsys.stat)
Term gsys_stat_run(Env e, Term* f, IoWork* w) {
  u32         code = 0;
  char*       path = gsys_path(e, f[0], &code);
  u32         follow = (u32)f[1];
  struct stat st;
  if (path != NULL && follow > 1) code = EINVAL;
  if (path != NULL && code == 0 && (follow ? stat(path, &st) : lstat(path, &st)) != 0) code = (u32)errno;
  free(path);
  if (code != 0) return io_fail(e, code, NULL);
  u64 dev = (u64)st.st_dev, ino = (u64)st.st_ino, size = (u64)st.st_size, blocks = (u64)st.st_blocks;
  u64 nlink = (u64)st.st_nlink;
  u32 ws[10] = {(u32)st.st_mode, nlink > 0xffffffffull ? 0xffffffffu : (u32)nlink,
                (u32)(dev >> 32), (u32)dev, (u32)(ino >> 32), (u32)ino,
                (u32)(size >> 32), (u32)size, (u32)(blocks >> 32), (u32)blocks};
  return io_done(e, gsys_words(e, ws, 10));
}
#endif

// Gsys.ls(dir): the names in a directory, but . and .., in the order the
// directory gives them.
#ifdef CID(Gsys.ls)
Term gsys_ls_run(Env e, Term* f, IoWork* w) {
  u32   code = 0;
  char* path = gsys_path(e, f[0], &code);
  DIR*  d    = NULL;
  if (path != NULL && (d = opendir(path)) == NULL) code = (u32)errno;
  free(path);
  if (code != 0) return io_fail(e, code, NULL);
  Term xs = term_pak(CID(Nil), 0);
  struct dirent* de;
  while ((de = readdir(d)) != NULL) {
    if (strcmp(de->d_name, ".") != 0 && strcmp(de->d_name, "..") != 0) {
      xs = io_node(e, CID(Con), io_str(e, de->d_name, strlen(de->d_name)), xs);
    }
  }
  closedir(d);
  return io_done(e, xs);
}
#endif

// Gsys.rename(from, to): rename(2). 0, or the errno.
#ifdef CID(Gsys.rename)
Term gsys_rename_run(Env e, Term* f, IoWork* w) {
  u32   code = 0;
  char* from = gsys_path(e, f[0], &code);
  char* to   = gsys_path(e, f[1], &code);
  if (code == 0 && rename(from, to) != 0) code = (u32)errno;
  free(from); free(to);
  return (Term)code;
}
#endif

// Gsys.unlink(path): unlink(2). 0, or the errno.
#ifdef CID(Gsys.unlink)
Term gsys_unlink_run(Env e, Term* f, IoWork* w) {
  u32   code = 0;
  char* path = gsys_path(e, f[0], &code);
  if (path != NULL && unlink(path) != 0) code = (u32)errno;
  free(path);
  return (Term)code;
}
#endif

// Gsys.rmdir(path): rmdir(2). 0, or the errno.
#ifdef CID(Gsys.rmdir)
Term gsys_rmdir_run(Env e, Term* f, IoWork* w) {
  u32   code = 0;
  char* path = gsys_path(e, f[0], &code);
  if (path != NULL && rmdir(path) != 0) code = (u32)errno;
  free(path);
  return (Term)code;
}
#endif

// Gsys.mount(source, target, fstype, flags, data): mount(2); fstype and
// data "" are NULL. 0, or the errno (ENOSYS off Linux).
#ifdef CID(Gsys.mount)
Term gsys_mount_run(Env e, Term* f, IoWork* w) {
  u32   code   = 0;
  char* source = gsys_text(e, f[0], &code);
  char* target = gsys_path(e, f[1], &code);
  char* fstype = gsys_text(e, f[2], &code);
  char* data   = gsys_text(e, f[4], &code);
#ifdef __linux__
  if (code == 0 && mount(source, target, fstype[0] ? fstype : NULL, (unsigned long)(u32)f[3], data[0] ? data : NULL) != 0)
    code = (u32)errno;
#else
  if (code == 0) code = ENOSYS;
#endif
  free(source); free(target); free(fstype); free(data);
  return (Term)code;
}
#endif

// Gsys.umount(target, flags): umount2(2). 0, or the errno (ENOSYS off
// Linux).
#ifdef CID(Gsys.umount)
Term gsys_umount_run(Env e, Term* f, IoWork* w) {
  u32   code   = 0;
  char* target = gsys_path(e, f[0], &code);
#ifdef __linux__
  if (target != NULL && umount2(target, (int)(u32)f[1]) != 0) code = (u32)errno;
#else
  if (target != NULL) code = ENOSYS;
#endif
  free(target);
  return (Term)code;
}
#endif

// Gsys.settime(seconds): clock_settime(CLOCK_REALTIME) to that second
// since 1970, no fraction. 0, or the errno. Linux only (ENOSYS
// elsewhere): a test on a developer's machine never sets its clock.
#ifdef CID(Gsys.settime)
Term gsys_settime_run(Env e, Term* f, IoWork* w) {
#ifdef __linux__
  struct timespec ts = {(time_t)(u32)f[0], 0};
  return (Term)(u32)(clock_settime(CLOCK_REALTIME, &ts) == 0 ? 0 : errno);
#else
  return (Term)(u32)ENOSYS;
#endif
}
#endif

// A job on an IO helper thread: a path in, a 64-bit count out.
typedef struct {
  char* path;
  u64   count;
  u32   code;
} GsysJob;

static __attribute__((unused)) Term gsys_job_pack(Env e, IoWork* w) {
  GsysJob* j = (GsysJob*)w->data;
  Term     r = j->code != 0 ? io_fail(e, j->code, NULL)
                            : io_done(e, io_tup(e, (Term)(u32)(j->count >> 32), (Term)(u32)j->count));
  free(j->path);
  free(j);
  return r;
}

static __attribute__((unused)) Term gsys_job_run(Env e, Term* f, IoWork* w, void (*call)(IoWork*)) {
  GsysJob* j = io_mem(calloc(1, sizeof *j));
  w->data = (char*)j;
  j->path = gsys_path(e, f[0], &j->code);
  if (j->path == NULL) return gsys_job_pack(e, w);
  return io_work(w, call, gsys_job_pack);
}

// Gsys.fitrim(path): FITRIM over the whole file system that holds path
// (the ioctl of fstrim(8)), on a helper thread: the bytes it discarded,
// as (high, low).
#ifdef CID(Gsys.fitrim)
static void gsys_fitrim_call(IoWork* w) {
  GsysJob* j = (GsysJob*)w->data;
#ifdef __linux__
  int fd = open(j->path, O_RDONLY | O_CLOEXEC);
  if (fd < 0) { j->code = (u32)errno; return; }
  struct fstrim_range r;
  memset(&r, 0, sizeof r);
  r.len = (u64)-1;
  if (ioctl(fd, FITRIM, &r) != 0) j->code = (u32)errno;
  else j->count = (u64)r.len;
  close(fd);
#else
  j->code = ENOSYS;
#endif
}

Term gsys_fitrim_run(Env e, Term* f, IoWork* w) {
  return gsys_job_run(e, f, w, gsys_fitrim_call);
}
#endif

// Gsys.drain(path): reads a regular file to its end and drops the bytes
// (what tar to /dev/null did: the file is then in the page cache), on a
// helper thread: the bytes read, as (high, low). Never through a
// symbolic link; anything but a regular file fails with EINVAL.
#ifdef CID(Gsys.drain)
static void gsys_drain_call(IoWork* w) {
  GsysJob* j = (GsysJob*)w->data;
  int fd = open(j->path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
  if (fd < 0) { j->code = (u32)errno; return; }
  struct stat st;
  if (fstat(fd, &st) != 0) j->code = (u32)errno;
  else if (!S_ISREG(st.st_mode)) j->code = EINVAL;
  char* buf = j->code == 0 ? malloc(1u << 20) : NULL;
  if (j->code == 0 && buf == NULL) j->code = ENOMEM;
  while (j->code == 0) {
    ssize_t n = read(fd, buf, 1u << 20);
    if (n < 0 && errno == EINTR) continue;
    if (n < 0) j->code = (u32)errno;
    if (n <= 0) break;
    j->count += (u64)n;
  }
  free(buf);
  close(fd);
}

Term gsys_drain_run(Env e, Term* f, IoWork* w) {
  return gsys_job_run(e, f, w, gsys_drain_call);
}
#endif

static void __attribute__((constructor)) gsys_use(void) {
#ifdef CID(Gsys.mkdir)
  io_eff(CID(Gsys.mkdir), gsys_mkdir_run);
#endif
#ifdef CID(Gsys.stat)
  io_eff(CID(Gsys.stat), gsys_stat_run);
#endif
#ifdef CID(Gsys.ls)
  io_eff(CID(Gsys.ls), gsys_ls_run);
#endif
#ifdef CID(Gsys.rename)
  io_eff(CID(Gsys.rename), gsys_rename_run);
#endif
#ifdef CID(Gsys.unlink)
  io_eff(CID(Gsys.unlink), gsys_unlink_run);
#endif
#ifdef CID(Gsys.rmdir)
  io_eff(CID(Gsys.rmdir), gsys_rmdir_run);
#endif
#ifdef CID(Gsys.mount)
  io_eff(CID(Gsys.mount), gsys_mount_run);
#endif
#ifdef CID(Gsys.umount)
  io_eff(CID(Gsys.umount), gsys_umount_run);
#endif
#ifdef CID(Gsys.settime)
  io_eff(CID(Gsys.settime), gsys_settime_run);
#endif
#ifdef CID(Gsys.fitrim)
  io_eff(CID(Gsys.fitrim), gsys_fitrim_run);
#endif
#ifdef CID(Gsys.drain)
  io_eff(CID(Gsys.drain), gsys_drain_run);
#endif
}
