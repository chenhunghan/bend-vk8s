import Base
import ../laws/oci_store.bend as L

# Proofs of laws/oci_store.bend: every law computes on both sides.

def L.oci_store.ttl_72h():
  {==}

def L.oci_store.paths():
  {==}

def L.oci_store.blob_path():
  {==}

def L.oci_store.meta_path():
  {==}

def L.oci_store.registry_with_port():
  {==}

def L.oci_store.registry_lowercased():
  {==}

def L.oci_store.registry_refused.dot_dot():
  {==}

def L.oci_store.registry_refused.dot():
  {==}

def L.oci_store.registry_refused.empty():
  {==}

def L.oci_store.registry_refused.slash():
  {==}

def L.oci_store.registry_refused.empty_label():
  {==}

def L.oci_store.registry_refused.dash_first():
  {==}

def L.oci_store.registry_refused.dash_last():
  {==}

def L.oci_store.registry_refused.empty_port():
  {==}

def L.oci_store.registry_refused.bad_port():
  {==}

def L.oci_store.registry_refused.two_ports():
  {==}

def L.oci_store.registry_refused.ipv6():
  {==}

def L.oci_store.registry_refused.space():
  {==}

def L.oci_store.digest_refused.traversal():
  {==}

def L.oci_store.digest_refused.upper_hex():
  {==}

def L.oci_store.digest_refused.short():
  {==}

def L.oci_store.digest_refused.long():
  {==}

def L.oci_store.digest_refused.sha512():
  {==}

def L.oci_store.digest_refused.no_algorithm():
  {==}

def L.oci_store.digest_refused.empty():
  {==}

def L.oci_store.never_unvalidated.dot_dot(root, d):
  {==}

def L.oci_store.never_unvalidated.dot(root, d):
  {==}

def L.oci_store.never_unvalidated.slash(root, d):
  {==}

def L.oci_store.never_unvalidated.empty(root, d):
  {==}

def L.oci_store.tmp_dir():
  {==}

def L.oci_store.meta.render():
  {==}

def L.oci_store.meta.parse():
  {==}

def L.oci_store.meta.parse_5gib():
  {==}

def L.oci_store.meta.parse_other_version():
  {==}

def L.oci_store.meta.parse_bad_media():
  {==}

def L.oci_store.meta.parse_bad_size():
  {==}

def L.oci_store.meta.parse_time_overflow():
  {==}

def L.oci_store.meta.parse_empty():
  {==}

def L.oci_store.meta.new_drops_parameters():
  {==}

def L.oci_store.meta.new_refuses_header_injection():
  {==}

def L.oci_store.meta.new_keeps_oci_type():
  {==}

def L.oci_store.expiry.fresh():
  {==}

def L.oci_store.expiry.at_72h():
  {==}

def L.oci_store.expiry.clock_back():
  {==}

def L.oci_store.touch():
  {==}

def L.oci_store.hit_renews():
  {==}

def L.oci_store.hit_then_fresh():
  {==}

def L.oci_store.hit_unreadable():
  {==}

def L.oci_store.sweep.expired_only():
  {==}

def L.oci_store.sweep.no_sidecar():
  {==}

def L.oci_store.sweep.invalid_names():
  {==}

def L.oci_store.sweep.empty():
  {==}

def L.oci_store.prune():
  {==}

def L.oci_store.prune_tmp_first(root, rs):
  {==}

def L.oci_store.verified():
  {==}

def L.oci_store.verified_wrong_hash():
  {==}

def L.oci_store.verified_wrong_size():
  {==}

def L.oci_store.lapse.grace_10min():
  {==}

def L.oci_store.lapse():
  {==}

def L.oci_store.lapse.kept_through_grace():
  {==}

def L.oci_store.lapse.expires_after_grace():
  {==}

def L.oci_store.lapse.hit_keeps_72h():
  {==}

def L.oci_store.lapse.hit_then_72h():
  {==}

def L.oci_store.lapse.never_later():
  {==}

def L.oci_store.lapse.early_clock():
  {==}

def L.oci_store.lapse.sidecar():
  {==}

def L.oci_store.lapse.sidecar_unreadable():
  {==}

def L.oci_store.lapse.sweep():
  {==}
