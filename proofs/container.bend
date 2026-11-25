import Base
import bend-kube-runtime@0.12.0.0/src/json.bend as J
import ../laws/container.bend as L
import ../src/guest/plan.bend as P
import ../src/guest/container.bend as C

# Proofs of laws/container.bend: `def L.<law>` for each law. Every law is
# concrete, so each proof computes.

def L.container.caps():
  {==}

def L.container.config_privileged():
  {==}

def L.container.cgroup_delegation():
  {==}

def L.container.mounts():
  {==}

def L.container.config():
  {==}

def L.container.cgroup_steps():
  {==}

def L.container.boot.head():
  {==}

def L.container.no_modules_step.kine():
  {==}

def L.container.no_modules_step.etcd():
  {==}

def L.container.vm_boot_loads_modules():
  {==}

def L.container.kubelet_cgroup_root():
  {==}

def L.container.sysctls():
  {==}

def L.container.share():
  {==}

def L.container.runsc_caps():
  {==}

def L.container.runsc_caps_held():
  {==}

def L.container.lacks():
  {==}

def L.container.layers_mounts():
  {==}

def L.container.mounts_v2_on():
  {==}

def L.container.mounts_v2_off(d, s, a, x):
  {==}
