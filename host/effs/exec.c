// Replace vk8s with another program, one environment variable set
// (`vk8s connect NAME -- COMMAND`: KUBECONFIG points at the cluster).

#include <unistd.h>
#include <stdlib.h>
#include <errno.h>

static char** exec_argv(Env e, Term prog, Term xs, int* bad) {
  u64 len = 0;
  u32 cap = 8, argc = 0;
  char** argv = io_mem(calloc(cap, sizeof(char*)));
  argv[argc++] = io_cstr(e, prog, &len);
  if (io_nul(argv[0], len)) *bad = 1;
  while (term_aux(xs) == CID(Con)) {
    Term pair[2];
    spare_free(e, cls_fit(2), ctr_take(e, xs, 2, pair));
    char* a = io_cstr(e, pair[0], &len);
    if (io_nul(a, len)) *bad = 1;
    if (argc + 1 >= cap) { cap *= 2; argv = io_mem(realloc(argv, cap * sizeof(char*))); }
    argv[argc++] = a;
    xs = pair[1];
  }
  argv[argc] = NULL;
  return argv;
}

// Exec.run(prog, args, key, value): returns only on failure, with the errno.
Term exec_run_run(Env e, Term* f, IoWork* w) {
  int bad = 0; u64 len = 0;
  char** argv = exec_argv(e, f[0], f[1], &bad);
  char* key = io_cstr(e, f[2], &len);
  char* val = io_cstr(e, f[3], &len);
  if (bad) return (Term)(u32)EINVAL;
  if (key[0]) setenv(key, val, 1);
  fflush(stdout); fflush(stderr);
  execvp(argv[0], argv);
  return (Term)(u32)errno;
}

static void __attribute__((constructor)) exec_use(void) {
  io_eff(CID(Exec.run), exec_run_run);
}
