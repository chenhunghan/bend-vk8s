import Base
import ../laws/assets.bend as L
import ../src/cli/assets.bend as A

def L.assets.url():
  {==}

def L.assets.dir():
  {==}

def L.assets.fetch_checks_sum():
  {==}

def L.assets.strict_lists_members():
  {==}

def L.assets.fetch_sh_unique_staging():
  {==}

def L.assets.sha_tool_fallback():
  {==}

def L.assets.strict_sha_tool_fallback():
  {==}

def L.assets.role_sets.standalone():
  {==}

def L.assets.role_sets.standalone_cached():
  {==}

def L.assets.role_sets.classic():
  {==}

def L.assets.role_sets.classic_cached():
  {==}

def L.assets.role_sets.worker():
  {==}

def L.assets.role_sets.worker_cached():
  {==}

def L.assets.role_sets.cache():
  {==}

def L.assets.role_sets.unknown():
  {==}

def L.assets.set_files.picks():
  {==}

def L.assets.set_paths():
  {==}

def L.assets.file_paths():
  {==}

def L.assets.files_of():
  {==}

def L.assets.sets_named.ok():
  {==}

def L.assets.sets_named.bad():
  {==}

def L.assets.fetch_into.skips_present():
  {==}

def L.assets.fetch_into.checks_sum():
  {==}

def L.assets.fetch_into.staging():
  {==}

def L.assets.fetch_into.no_overwrite():
  {==}

def L.assets.optional.images():
  {==}

def L.assets.optional.cache():
  {==}

def L.assets.optional.node():
  {==}

def L.assets.optional.control_plane():
  {==}

def L.assets.optional.classic():
  {==}

def L.assets.present.drops_absent():
  {==}

def L.assets.absent.lists_absent():
  {==}

def L.assets.missing_required.no_images():
  {==}

def L.assets.missing_required.node():
  {==}

def L.assets.missing_optional.images():
  {==}

def L.assets.missing_optional.cache():
  {==}

def L.assets.missing_required.cache():
  {==}

def L.assets.present.all():
  {==}

def L.assets.host_dir.release():
  {==}

def L.assets.host_dir.local():
  {==}

def L.assets.host_fetch.mac():
  {==}

def L.assets.host_fetch.unpinned(m, h):
  {==}

def L.assets.host_fetch.linux(fs, h):
  match fs:
    case Nil{}:
      {==}
    case Con{f, t}:
      {==}

def L.assets.host_fetch.have(fs, m):
  match fs:
    case Nil{}:
      {==}
    case Con{f, t}:
      match m:
        case True{}:
          {==}
        case False{}:
          {==}

def L.assets.role_sets.v2.plain(role, cached):
  {==}

def L.assets.role_sets.v2.standalone_both():
  {==}

def L.assets.role_sets.v2.standalone_images_gvisor():
  {==}

def L.assets.role_sets.v2.standalone_etcd():
  {==}

def L.assets.role_sets.v2.worker_gvisor():
  {==}

def L.assets.role_sets.v2.classic_etcd():
  {==}

def L.assets.role_sets.v2.cache():
  {==}

def L.assets.optional.gvisor():
  {==}

def L.assets.optional.etcd():
  {==}

def L.assets.missing_required.gvisor():
  {==}

def L.assets.split():
  {==}

def L.assets.unsplit.old_release():
  {==}

def L.assets.unsplit.new_release():
  {==}

def L.assets.unsplit.local():
  {==}

def L.assets.not_in():
  {==}
