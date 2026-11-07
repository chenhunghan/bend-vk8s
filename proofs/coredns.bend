import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../laws/coredns.bend as L
import ../src/guest/coredns.bend as C

# Proofs of laws/coredns.bend: `def L.<law>` for each law. Every law
# closes by computation: the concrete ones render the tests' configs, and
# the general ones look up literal keys in a config whose leaves are the
# law's variables.

def L.coredns.manifests_default():
  {==}

def L.coredns.manifests_overwrite():
  {==}

def L.coredns.manifests_embedded():
  {==}

def L.coredns.manifests_default_cluster_domain():
  {==}

def L.coredns.manifests_custom_cluster_domain():
  {==}

def L.coredns.manifests_security_context():
  {==}

def L.coredns.corefile_embedded():
  {==}

def L.coredns.corefile_overwrite():
  {==}

def L.coredns.image_known_version():
  {==}

def L.coredns.image_unknown_version():
  {==}

def L.coredns.image_custom_registry():
  {==}

def L.coredns.image_registry_trailing_slash():
  {==}

def L.coredns.pinned_1_36():
  {==}

def L.coredns.pinned_1_35():
  {==}

def L.coredns.pinned_1_34():
  {==}

def L.coredns.pinned_1_33():
  {==}

def L.coredns.pinned_1_32():
  {==}

def L.coredns.pinned_1_31():
  {==}

def L.coredns.pinned_1_30():
  {==}

def L.coredns.pinned_none():
  {==}

def L.coredns.default_image():
  {==}

def L.coredns.label():
  {==}

def L.coredns.default_matches_static_file():
  {==}

def L.coredns.default_manifest_renders():
  {==}

def L.coredns.render_is_manifests(cfg):
  {==}

def L.coredns.values_cluster_domain(d, ip, img, r, u, g):
  {==}

def L.coredns.values_service_ip(d, ip, img, r, u, g):
  {==}

def L.coredns.values_replicas(d, ip, img, r, u, g):
  {==}

def L.coredns.values_no_rewrite(d, ip, img, r, u, g):
  {==}

def L.coredns.vars_of_cfg(d, ip, img, r, u, g):
  {==}
