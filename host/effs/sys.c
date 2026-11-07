// Signals, the guest's power button, and power-off for vk8s as PID 1.

#include <signal.h>
#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#ifdef __linux__
#include <linux/input.h>
#include <sys/reboot.h>
#endif

// Proc.signal(pid, sig): kill(2); pid 4294967295 is -1 (every process but
// PID 1). Returns 0 or the errno.
Term proc_signal_run(Env e, Term* f, IoWork* w) {
  pid_t pid = (pid_t)(int32_t)(u32)f[0];
  int sig = (int)(u32)f[1];
  return (Term)(u32)(kill(pid, sig) == 0 ? 0 : errno);
}

#define SYS_MAX_INPUT 16
static int sys_fds[SYS_MAX_INPUT];
static int sys_nfds = -1;

// Open every /dev/input/event* once (non-blocking).
static void sys_open_inputs(void) {
  sys_nfds = 0;
  DIR* d = opendir("/dev/input");
  if (!d) { sys_nfds = -1; return; }
  struct dirent* de;
  while ((de = readdir(d)) && sys_nfds < SYS_MAX_INPUT) {
    if (strncmp(de->d_name, "event", 5) != 0) continue;
    char p[300];
    snprintf(p, sizeof p, "/dev/input/%s", de->d_name);
    int fd = open(p, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd >= 0) sys_fds[sys_nfds++] = fd;
  }
  closedir(d);
  if (sys_nfds == 0) sys_nfds = -1;
}

// Sys.power(): how many KEY_POWER presses arrived since the last call.
// Until an input device exists it keeps looking for one.
Term sys_power_run(Env e, Term* f, IoWork* w) {
  u32 n = 0;
#ifdef __linux__
  if (sys_nfds < 0) sys_open_inputs();
  for (int i = 0; i < sys_nfds; i++) {
    struct input_event ev;
    while (read(sys_fds[i], &ev, sizeof ev) == (ssize_t)sizeof ev) {
      if (ev.type == EV_KEY && ev.code == KEY_POWER && ev.value == 1) n++;
    }
  }
#endif
  return (Term)n;
}

// Sys.poweroff(): flush the disks and power the VM off. Returns the errno
// if the kernel refuses.
Term sys_poweroff_run(Env e, Term* f, IoWork* w) {
  sync();
#ifdef __linux__
  reboot(RB_POWER_OFF);
#endif
  return (Term)(u32)errno;
}

static void __attribute__((constructor)) sys_use(void) {
  io_eff(CID(Proc.signal), proc_signal_run);
  io_eff(CID(Sys.power), sys_power_run);
  io_eff(CID(Sys.poweroff), sys_poweroff_run);
}
