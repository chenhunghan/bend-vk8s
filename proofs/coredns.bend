import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../laws/coredns.bend as L
import ../src/guest/coredns.bend as C

# Proofs of laws/coredns.bend: `def L.<law>` for each law. Every law
# closes by computation: the concrete ones render one document (or the
# branch) of a test's config, the structural ones unfold the defs on
# open arguments, and the general ones look up literal keys in a config
# whose leaves are the law's variables.

def L.coredns.manifests_default.branch():
  {==}

def L.coredns.manifests_default.service_account():
  {==}

def L.coredns.manifests_default.cluster_role():
  {==}

def L.coredns.manifests_default.cluster_role_binding():
  {==}

def L.coredns.manifests_default.configmap():
  {==}

def L.coredns.manifests_default.deployment_pod():
  {==}

def L.coredns.manifests_default.deployment_containers():
  {==}

def L.coredns.manifests_default.service():
  {==}

def L.coredns.manifests_overwrite.branch():
  {==}

def L.coredns.manifests_overwrite.overwrite():
  {==}

def L.coredns.manifests_embedded.branch():
  {==}

def L.coredns.manifests_embedded.configmap():
  {==}

def L.coredns.manifests_embedded.service():
  {==}

def L.coredns.manifests_default_cluster_domain.branch():
  {==}

def L.coredns.manifests_default_cluster_domain.service_account():
  {==}

def L.coredns.manifests_default_cluster_domain.cluster_role():
  {==}

def L.coredns.manifests_default_cluster_domain.cluster_role_binding():
  {==}

def L.coredns.manifests_default_cluster_domain.configmap():
  {==}

def L.coredns.manifests_default_cluster_domain.deployment_pod():
  {==}

def L.coredns.manifests_default_cluster_domain.deployment_containers():
  {==}

def L.coredns.manifests_default_cluster_domain.service():
  {==}

def L.coredns.manifests_custom_cluster_domain.branch():
  {==}

def L.coredns.manifests_custom_cluster_domain.service_account():
  {==}

def L.coredns.manifests_custom_cluster_domain.cluster_role():
  {==}

def L.coredns.manifests_custom_cluster_domain.cluster_role_binding():
  {==}

def L.coredns.manifests_custom_cluster_domain.configmap():
  {==}

def L.coredns.manifests_custom_cluster_domain.deployment_pod():
  {==}

def L.coredns.manifests_custom_cluster_domain.deployment_containers():
  {==}

def L.coredns.manifests_custom_cluster_domain.service():
  {==}

def L.coredns.manifests_security_context.branch():
  {==}

def L.coredns.manifests_security_context.service_account():
  {==}

def L.coredns.manifests_security_context.cluster_role():
  {==}

def L.coredns.manifests_security_context.cluster_role_binding():
  {==}

def L.coredns.manifests_security_context.configmap():
  {==}

def L.coredns.manifests_security_context.deployment_pod():
  {==}

def L.coredns.manifests_security_context.deployment_containers():
  {==}

def L.coredns.manifests_security_context.service():
  {==}

def L.coredns.manifests_join(v, vs):
  {==}

def L.coredns.documents_full(v, vs):
  {==}

def L.coredns.deployment_parts(v, vs):
  {==}

def L.coredns.documents_embedded(v, vs):
  {==}

def L.coredns.documents_overwrite(v, vs):
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
