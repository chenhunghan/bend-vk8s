import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../laws/pods.bend as L
import ../src/translate/pods.bend as P
import ../src/translate/meta.bend as M

# Proofs of laws/pods.bend: `def L.<law>` for each law.
#
# The concrete laws compute. The general laws rest on the shape of the
# translated pod: Pods.with puts a member first, so reading the containers,
# the labels or the annotations of a host pod is a few steps of computation
# on literal keys, whatever the configuration, the inputs and the pod are.
# The container laws then go by induction on the container list
# (pods.names_tr): each translated container starts with the virtual
# container's name. Status idempotence splits on whether the virtual API
# server drops ObservedGeneration (pods.desired_twice).

# Concrete laws: both sides compute.

def L.pods.affinity_no_selector():
  {==}

def L.pods.affinity_empty_namespaces_null_selector():
  {==}

def L.pods.affinity_null_selector_namespaces():
  {==}

def L.pods.affinity_empty_selector_namespaces():
  {==}

def L.pods.affinity_namespaces_and_selector():
  {==}

def L.pods.affinity_selector_no_namespaces():
  {==}

def L.pods.affinity_selector_expressions():
  {==}

def L.pods.volume_ephemeral():
  {==}

def L.pods.volume_hostpath_kubelet():
  {==}

def L.pods.volume_hostpath_logs():
  {==}

def L.pods.rewrite_hosts_args():
  {==}

def L.pods.rewrite_hosts_init_container():
  {==}

def L.pods.rewrite_hosts_mount():
  {==}

def L.pods.rewrite_hosts_default_registry():
  {==}

def L.pods.rewrite_hosts_image_override():
  {==}

def L.pods.resources_new_host():
  {==}

def L.pods.resources_old_host():
  {==}

def L.pods.claims_name():
  {==}

def L.pods.claims_template():
  {==}

def L.pods.claims_both():
  {==}

def L.pods.claims_empty():
  {==}

def L.pods.claims_name_disabled():
  {==}

def L.pods.claims_template_disabled():
  {==}

def L.pods.claims_both_disabled():
  {==}

def L.pods.claim_status_mapped():
  {==}

def L.pods.claim_status_unmapped():
  {==}

def L.pods.claim_status_missing():
  {==}

def L.pods.enforced_toleration_dedup():
  {==}

def L.pods.tolerations_add():
  {==}

def L.pods.tolerations_remove():
  {==}

def L.pods.tolerations_enforced_missing():
  {==}

def L.pods.tolerations_admission():
  {==}

def L.pods.tolerations_drift_enforced():
  {==}

def L.pods.tolerations_drift_virtual():
  {==}

def L.pods.tolerations_race():
  {==}

def L.pods.conditions_131_divergence():
  {==}

def L.pods.conditions_131_status_change():
  {==}

def L.pods.conditions_131_host_generation():
  {==}

def L.pods.conditions_133_divergence():
  {==}

def L.pods.conditions_134_change():
  {==}

def L.pods.conditions_unknown_version():
  {==}

def L.pods.observed_generation_133():
  {==}

def L.pods.observed_generation_134():
  {==}

def L.pods.observed_generation_unknown():
  {==}

def L.pods.divergence_133():
  {==}

def L.pods.divergence_134():
  {==}

def L.pods.divergence_unknown():
  {==}

def L.pods.qos_class_kept():
  {==}

def L.pods.desired_status_133():
  {==}

def L.pods.desired_status_134():
  {==}

def L.pods.desired_status_unknown():
  {==}

def L.pods.desired_status_inputs():
  {==}

def L.pods.sync_table_delete_virtual_pod():
  {==}

def L.pods.sync_table_injected_sidecar():
  {==}

def L.pods.sync_table_node_selector():
  {==}

def L.pods.sync_table_no_security_standard():
  {==}

def L.pods.sync_table_privileged():
  {==}

def L.pods.sync_table_restricted():
  {==}

def L.pods.sync_table_labels():
  {==}

def L.pods.sync_map_hostpaths():
  {==}

def L.pods.sync_priority_class_from_host():
  {==}

def L.pods.sync_priority_class_to_host():
  {==}

def L.pods.sync_pods_priority_class_name():
  {==}

def L.pods.resize_patch_differs():
  {==}

def L.pods.resize_patch_equal():
  {==}

def L.pods.resize_patch_only_diffs():
  {==}

def L.pods.resize_patch_missing_on_host():
  {==}

def L.pods.resize_unknown_host():
  {==}

def L.pods.resize_old_host():
  {==}

def L.pods.terminating_status_propagates():
  {==}

def L.pods.terminating_status_unchanged():
  {==}

# General laws.

law pods.names_tr:
  for +ctx: P.CCtx
  for +kind: P.CKind
  for +l: List<&2, J.Json>
  {P.Pods.names(J.Json.items(J.Json.arr(P.Pods.tr_containers(ctx, kind, l)))) == P.Pods.names(l) : List<&2, String>}

def pods.names_tr(ctx, kind, l):
  match l:
    case Nil{}:
      {==}
    case Con{c, r}:
      %pods.names_tr(ctx, kind, r) : {P.Pods.str(c, "name") <> P.Pods.names(J.Json.items(J.Json.arr(P.Pods.tr_containers(ctx, kind, r)))) == P.Pods.str(c, "name") <> _ : List<&2, String>}
      {==}

def L.pods.containers_kept(cfg, inp, v):
  pods.names_tr(P.Pods.ctx(cfg, inp, v), P.CMain{}, J.Json.items(J.Json.at(v, ["spec", "containers"])))

def L.pods.ephemeral_containers_kept(cfg, inp, v):
  pods.names_tr(P.Pods.ctx(cfg, inp, v), P.CEph{}, J.Json.items(J.Json.at(v, ["spec", "ephemeralContainers"])))

def L.pods.marker_label(cfg, inp, v):
  {==}

def L.pods.object_name(cfg, inp, v):
  {==}

def L.pods.object_namespace(cfg, inp, v):
  {==}

law pods.desired_twice:
  for b: Bool
  for +h: J.Json
  for +vs: J.Json
  {P.Pods.desired.if(b, h, P.Pods.desired.if(b, h, vs)) == P.Pods.desired.if(b, h, vs) : J.Json}

def pods.desired_twice(b, h, vs):
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

def L.pods.status_idempotent(cfg, h, vs):
  pods.desired_twice(P.Pods.strips(cfg), h, vs)
