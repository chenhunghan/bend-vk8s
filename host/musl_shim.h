/* musl has no posix_spawn_file_actions_addclosefrom_np; musl's spawn ignores
   errors from close actions, so closing each fd from `from` up to the
   process's open-file limit works: no descriptor can exist at or above
   RLIMIT_NOFILE's soft limit, which sysconf(_SC_OPEN_MAX) reports. */
#include <spawn.h>
#include <unistd.h>
static inline int posix_spawn_file_actions_addclosefrom_np(posix_spawn_file_actions_t *a, int from) {
  long max = sysconf(_SC_OPEN_MAX);
  if (max < 0 || max > 1048576) max = 1048576;
  for (int fd = from; fd < (int)max; fd++) { int r = posix_spawn_file_actions_addclose(a, fd); if (r) return r; }
  return 0;
}
