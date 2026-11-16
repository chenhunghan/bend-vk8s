// Signals for vk8s as PID 1 and SIGTERM and SIGINT for vk8s in native
// mode (a normal host process). The power button and power-off are in
// power.c: the vk8s host binary reaches NInit (native mode) but never
// Sys.power or Sys.poweroff, and Bend emits a CID only for a reached def.

#include <signal.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>

// Proc.signal(pid, sig): kill(2); pid 4294967295 is -1 (every process but
// PID 1). Returns 0 or the errno.
Term proc_signal_run(Env e, Term* f, IoWork* w) {
  pid_t pid = (pid_t)(int32_t)(u32)f[0];
  int sig = (int)(u32)f[1];
  return (Term)(u32)(kill(pid, sig) == 0 ? 0 : errno);
}

static int sys_terms = 0;
static int sys_term_on = 0;

static void sys_term_handler(int sig) {
  (void)sig;
  __atomic_fetch_add(&sys_terms, 1, __ATOMIC_SEQ_CST);
}

// Sys.term(): how many SIGTERM and SIGINT arrived since the last call.
// The first call installs the handler (native mode only: the VM's PID 1
// never calls it). Bend has no signal handlers, so this stays in C.
Term sys_term_run(Env e, Term* f, IoWork* w) {
  if (!sys_term_on) {
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = sys_term_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_RESTART;
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);
    sys_term_on = 1;
  }
  return (Term)(u32)__atomic_exchange_n(&sys_terms, 0, __ATOMIC_SEQ_CST);
}

// Sys.pending(): how many SIGTERM and SIGINT arrived since the last
// Sys.term, without taking them: the native boot checks it in its steps
// and waits, and the supervisor's next Sys.term still sees them.
Term sys_pending_run(Env e, Term* f, IoWork* w) {
  return (Term)(u32)__atomic_load_n(&sys_terms, __ATOMIC_SEQ_CST);
}

// Sys.setenv(name, value): setenv(3) for this process, so every child
// it starts after inherits it (posix_spawn passes environ). Native mode
// calls it once, before its first child. Returns 0 or the errno.
Term sys_setenv_run(Env e, Term* f, IoWork* w) {
  u64 nlen = 0, vlen = 0;
  char* name = io_cstr(e, f[0], &nlen);
  char* value = io_cstr(e, f[1], &vlen);
  u32 code = 0;
  if (io_nul(name, nlen) || io_nul(value, vlen) || !name[0]) code = EINVAL;
  else if (setenv(name, value, 1) != 0) code = (u32)errno;
  free(name); free(value);
  return (Term)code;
}

static void __attribute__((constructor)) sys_use(void) {
  io_eff(CID(Proc.signal), proc_signal_run);
  io_eff(CID(Sys.term), sys_term_run);
  io_eff(CID(Sys.pending), sys_pending_run);
  io_eff(CID(Sys.setenv), sys_setenv_run);
}
