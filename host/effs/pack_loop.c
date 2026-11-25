// A layer image on the pack disk, mounted (src/layers/pack.bend,
// host/snapshotter.bend): a loop device over LENGTH bytes at OFFSET of
// the pack's block device, read-only, then squashfs on it. busybox's
// losetup has an offset but no size limit, and its mount takes offset=
// and sizelimit= only for a regular file, so this is LOOP_CONFIGURE
// (Linux 5.8) and mount(2) here. The loop device is autoclear: the mount
// holds it, and the unmount frees it.

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#ifdef __linux__
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <linux/fs.h>
#include <linux/loop.h>
#include <time.h>
#endif

#ifdef __linux__
// A decimal number of at most 19 digits, nothing else.
static int packdev_num(const char* s, unsigned long long* out) {
  size_t n = strlen(s);
  if (n == 0 || n > 19) return -1;
  unsigned long long v = 0;
  for (size_t i = 0; i < n; i++) {
    if (s[i] < '0' || s[i] > '9') return -1;
    v = v * 10 + (unsigned long long)(s[i] - '0');
  }
  *out = v;
  return 0;
}

// The pack grows by a config change that the guest's virtio-blk driver
// takes in a work item: wait (at most 2 s) until the device holds the
// range.
static int packdev_wait(int fd, unsigned long long end) {
  for (int i = 0; i < 400; i++) {
    unsigned long long size = 0;
    if (ioctl(fd, BLKGETSIZE64, &size) != 0) return errno;
    if (size >= end) return 0;
    struct timespec ts = {0, 5000000};
    nanosleep(&ts, NULL);
  }
  return ENOSPC;
}

static u32 packdev_mount(const char* dev, const char* offs, const char* lens, const char* target) {
  unsigned long long off = 0, len = 0;
  if (packdev_num(offs, &off) != 0 || packdev_num(lens, &len) != 0 || len == 0) return EINVAL;
  int back = open(dev, O_RDONLY | O_CLOEXEC);
  if (back < 0) return (u32)errno;
  int code = packdev_wait(back, off + len);
  if (code != 0) { close(back); return (u32)code; }
  int ctl = open("/dev/loop-control", O_RDWR | O_CLOEXEC);
  if (ctl < 0) { code = errno; close(back); return (u32)code; }
  int lfd = -1;
  char path[64];
  // another process may take the free device between the two calls
  for (int i = 0; i < 16 && lfd < 0; i++) {
    int n = ioctl(ctl, LOOP_CTL_GET_FREE);
    if (n < 0) { code = errno; break; }
    snprintf(path, sizeof path, "/dev/loop%d", n);
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) { code = errno; break; }
    struct loop_config cfg;
    memset(&cfg, 0, sizeof cfg);
    cfg.fd = (unsigned)back;
    cfg.info.lo_offset = off;
    cfg.info.lo_sizelimit = len;
    cfg.info.lo_flags = LO_FLAGS_READ_ONLY | LO_FLAGS_AUTOCLEAR;
    if (ioctl(fd, LOOP_CONFIGURE, &cfg) == 0) { lfd = fd; code = 0; }
    else { code = errno; close(fd); if (code != EBUSY) break; }
  }
  close(ctl);
  close(back);
  if (lfd < 0) return (u32)(code ? code : EBUSY);
  code = 0;
  if (mount(path, target, "squashfs", MS_RDONLY | MS_NOSUID, NULL) != 0) code = errno;
  // the mount keeps the device; without one, this close clears it
  close(lfd);
  return (u32)code;
}
#endif

// PackDev.mount(dev, offset, length, target): 0, or the errno.
Term packdev_mount_run(Env e, Term* f, IoWork* w) {
  u64 dl = 0, ol = 0, ll = 0, tl = 0;
  char* dev = io_cstr(e, f[0], &dl);
  char* off = io_cstr(e, f[1], &ol);
  char* len = io_cstr(e, f[2], &ll);
  char* target = io_cstr(e, f[3], &tl);
  u32 code = ENOSYS;
  if (io_nul(dev, dl) || io_nul(off, ol) || io_nul(len, ll) || io_nul(target, tl)) code = EINVAL;
#ifdef __linux__
  else code = packdev_mount(dev, off, len, target);
#endif
  free(dev); free(off); free(len); free(target);
  return (Term)code;
}

static void __attribute__((constructor)) packdev_use(void) {
  io_eff(CID(PackDev.mount), packdev_mount_run);
}
