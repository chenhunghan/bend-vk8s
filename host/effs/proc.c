// Process supervision for vk8s as PID 1: start a program in its own
// session with its output appended to a log, and reap every exited child
// (orphans reparented to PID 1 included).
// Programs are started here, never with Base's Process.run, whose waitpid
// on its own child would race this reaper.

#include <spawn.h>
#include <sys/wait.h>
#include <signal.h>
#include <fcntl.h>

extern char** environ;

static char** proc_argv(Env e, Term prog, Term xs, u32* argc, int* bad) {
  u64 len = 0;
  u32 cap = 8;
  char** argv = io_mem(calloc(cap, sizeof(char*)));
  argv[0] = io_cstr(e, prog, &len);
  if (io_nul(argv[0], len)) *bad = 1;
  *argc = 1;
  while (term_aux(xs) == CID(Con)) {
    Term pair[2];
    spare_free(e, cls_fit(2), ctr_take(e, xs, 2, pair));
    char* a = io_cstr(e, pair[0], &len);
    if (io_nul(a, len)) *bad = 1;
    if (*argc + 1 >= cap) { cap *= 2; argv = io_mem(realloc(argv, cap * sizeof(char*))); }
    argv[(*argc)++] = a;
    xs = pair[1];
  }
  argv[*argc] = NULL;
  return argv;
}

// Proc.start(prog, args, log): log "" keeps the console.
Term proc_start_run(Env e, Term* f, IoWork* w) {
  u32 argc = 0; int bad = 0; u64 len = 0;
  char** argv = proc_argv(e, f[0], f[1], &argc, &bad);
  char* log = io_cstr(e, f[2], &len);
  int code = bad ? EINVAL : 0;
  pid_t child = -1;
  posix_spawn_file_actions_t acts;
  posix_spawnattr_t attr;
  if (code == 0) code = posix_spawn_file_actions_init(&acts);
  if (code == 0) {
    // Early in boot /dev is not mounted yet: then stdin stays the console.
    if (access("/dev/null", R_OK) == 0) {
      posix_spawn_file_actions_addopen(&acts, 0, "/dev/null", O_RDONLY, 0);
    }
    if (len > 0) {
      posix_spawn_file_actions_addopen(&acts, 1, log, O_WRONLY | O_CREAT | O_APPEND, 0644);
      posix_spawn_file_actions_adddup2(&acts, 1, 2);
    }
#ifndef __APPLE__
    posix_spawn_file_actions_addclosefrom_np(&acts, 3);
#endif
    posix_spawnattr_init(&attr);
    sigset_t def; sigemptyset(&def); sigaddset(&def, SIGPIPE);
    posix_spawnattr_setsigdefault(&attr, &def);
    sigset_t none; sigemptyset(&none);
    posix_spawnattr_setsigmask(&attr, &none);
    short flags = POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK;
#ifdef POSIX_SPAWN_SETSID
    flags |= POSIX_SPAWN_SETSID;
#endif
    posix_spawnattr_setflags(&attr, flags);
    code = posix_spawn(&child, argv[0], &acts, &attr, argv, environ);
    posix_spawnattr_destroy(&attr);
    posix_spawn_file_actions_destroy(&acts);
  }
  for (u32 i = 0; i < argc; i++) free(argv[i]);
  free(argv); free(log);
  return code != 0 ? io_fail(e, code, NULL) : io_done(e, (Term)(u32)child);
}

// Proc.reap(): every exited child as (pid, status); status is the exit code,
// or 128 + the signal.
Term proc_reap_run(Env e, Term* f, IoWork* w) {
  Term list = term_pak(CID(Nil), 0);
  for (;;) {
    int st = 0;
    pid_t p = waitpid(-1, &st, WNOHANG);
    if (p <= 0) break;
    u32 code = WIFEXITED(st) ? (u32)WEXITSTATUS(st) : WIFSIGNALED(st) ? 128 + (u32)WTERMSIG(st) : 1;
    list = io_node(e, CID(Con), io_tup(e, (Term)(u32)p, (Term)code), list);
  }
  return list;
}

static void __attribute__((constructor)) proc_use(void) {
  io_eff(CID(Proc.start), proc_start_run);
  io_eff(CID(Proc.reap), proc_reap_run);
}
