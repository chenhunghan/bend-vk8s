import Base
import ../laws/extras.bend as L
import ../src/cli/extras.bend as X
import ../src/guest/extras.bend as G
import ../src/guest/plan.bend as P

# Proofs of laws/extras.bend: `def L.<law>` for each law. The concrete
# laws compute; the general ones hold by the first match of the def they
# name (a node or a VM without extras takes the unchanged branch).

def L.extras.has_flag():
  {==}

def L.extras.drop():
  {==}

def L.extras.drop_after_dash():
  {==}

def L.extras.setting():
  {==}

def L.extras.setting.ro_suffix():
  {==}

def L.extras.setting.none():
  {==}

def L.extras.check.ok():
  {==}

def L.extras.check.refused():
  {==}

def L.extras.check.reserved():
  {==}

def L.extras.max_mounts():
  {==}

def L.extras.check.six_mounts():
  {==}

def L.extras.check.twice():
  {==}

def L.extras.env_name():
  {==}

def L.extras.merge.kind():
  {==}

def L.extras.merge.none():
  {==}

def L.extras.merge.record():
  {==}

def L.extras.with_record():
  {==}

def L.extras.keep():
  {==}

def L.extras.vmm_flags():
  {==}

def L.extras.vmm_flags.no_sockets():
  {==}

def L.extras.vmm_flags.none(vmdir, flags):
  {==}

def L.extras.sorted.nested():
  {==}

def L.extras.links():
  {==}

def L.extras.share_text():
  {==}

def L.extras.share_file():
  {==}

def L.extras.parse():
  {==}

def L.extras.parse.none():
  {==}

def L.extras.mount_steps():
  {==}

def L.extras.sock_daemon():
  {==}

def L.extras.sock_steps.none():
  {==}

def L.extras.setup_steps():
  {==}

def L.extras.setup_cmd.soft():
  {==}

def L.extras.env_path():
  {==}

def L.extras.with_imports():
  {==}

def L.extras.with_imports.once(text):
  {==}

def L.extras.apply():
  {==}

def L.extras.apply.no_script():
  {==}

def L.extras.apply.none(steps):
  {==}
