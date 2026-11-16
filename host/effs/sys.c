// Signals for vk8s as PID 1 and SIGTERM and SIGINT for vk8s in native
// mode (a normal host process). The power button and power-off are in
// power.c: the vk8s host binary reaches NInit (native mode) but never
// Sys.power or Sys.poweroff, and Bend emits a CID only for a reached def.

#include <signal.h>
#include <string.h>
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

static void __attribute__((constructor)) sys_use(void) {
  io_eff(CID(Proc.signal), proc_signal_run);
  io_eff(CID(Sys.term), sys_term_run);
}
