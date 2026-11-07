/* musl has no posix_spawn_file_actions_addclosefrom_np; musl's spawn ignores
   errors from close actions, so closing each fd from `from` up works. */
#include <spawn.h>
static inline int posix_spawn_file_actions_addclosefrom_np(posix_spawn_file_actions_t *a, int from) {
  for (int fd = from; fd < 1024; fd++) { int r = posix_spawn_file_actions_addclose(a, fd); if (r) return r; }
  return 0;
}
