import Base
import ../laws/oci_route.bend as L

# Proofs of laws/oci_route.bend: every law computes on both sides.

def L.oci_route.ping():
  {==}

def L.oci_route.ping_head():
  {==}

def L.oci_route.ping_response():
  {==}

def L.oci_route.blob_by_digest():
  {==}

def L.oci_route.blob_head():
  {==}

def L.oci_route.manifest_by_digest():
  {==}

def L.oci_route.manifest_head():
  {==}

def L.oci_route.nested_name():
  {==}

def L.oci_route.name_with_endpoint_word():
  {==}

def L.oci_route.query_ignored():
  {==}

def L.oci_route.tag_refused():
  {==}

def L.oci_route.tag_refused_body():
  {==}

def L.oci_route.tag_refused_head():
  {==}

def L.oci_route.tag_refused_head_no_body():
  {==}

def L.oci_route.manifest_sha512():
  {==}

def L.oci_route.manifest_sha512_body():
  {==}

def L.oci_route.blob_short_digest():
  {==}

def L.oci_route.blob_upper_digest():
  {==}

def L.oci_route.blob_by_tag():
  {==}

def L.oci_route.manifest_bad_reference():
  {==}

def L.oci_route.name_upper():
  {==}

def L.oci_route.name_upper_body():
  {==}

def L.oci_route.name_empty_component():
  {==}

def L.oci_route.name_dot_dot():
  {==}

def L.oci_route.name.ok_plain():
  {==}

def L.oci_route.name.ok_separators():
  {==}

def L.oci_route.name.ok_double_underscore():
  {==}

def L.oci_route.name.ok_dashes():
  {==}

def L.oci_route.name.bad_triple_underscore():
  {==}

def L.oci_route.name.bad_mixed_separator():
  {==}

def L.oci_route.name.bad_double_dot():
  {==}

def L.oci_route.name.bad_trailing_slash():
  {==}

def L.oci_route.name.bad_leading_dash():
  {==}

def L.oci_route.name.bad_trailing_underscore():
  {==}

def L.oci_route.name.bad_empty():
  {==}

def L.oci_route.name.bad_colon():
  {==}

def L.oci_route.name.too_long():
  {==}

def L.oci_route.name.longest():
  {==}

def L.oci_route.tag.ok_latest():
  {==}

def L.oci_route.tag.ok_version():
  {==}

def L.oci_route.tag.ok_underscore_first():
  {==}

def L.oci_route.tag.bad_dot_first():
  {==}

def L.oci_route.tag.bad_dash_first():
  {==}

def L.oci_route.tag.bad_empty():
  {==}

def L.oci_route.tag.longest():
  {==}

def L.oci_route.tag.too_long():
  {==}

def L.oci_route.tags_list_unsupported():
  {==}

def L.oci_route.catalog_unsupported():
  {==}

def L.oci_route.referrers_unsupported():
  {==}

def L.oci_route.not_v2():
  {==}

def L.oci_route.push_refused():
  {==}

def L.oci_route.push_refused_body():
  {==}

def L.oci_route.not_allowed_allow():
  {==}

def L.oci_route.not_allowed_length():
  {==}

def L.oci_route.blob_missing():
  {==}

def L.oci_route.manifest_unknown_body():
  {==}

def L.oci_route.range.first_100():
  {==}

def L.oci_route.range.open_end():
  {==}

def L.oci_route.range.suffix():
  {==}

def L.oci_route.range.suffix_longer():
  {==}

def L.oci_route.range.last_past_end():
  {==}

def L.oci_route.range.last_byte():
  {==}

def L.oci_route.range.first_at_end():
  {==}

def L.oci_route.range.backwards():
  {==}

def L.oci_route.range.suffix_zero():
  {==}

def L.oci_route.range.malformed():
  {==}

def L.oci_route.range.empty_set():
  {==}

def L.oci_route.range.two_dashes():
  {==}

def L.oci_route.range.overflow():
  {==}

def L.oci_route.range.unknown_unit():
  {==}

def L.oci_route.range.several():
  {==}

def L.oci_route.range.unit_case():
  {==}

def L.oci_route.range.list_whitespace():
  {==}

def L.oci_route.range.empty_blob():
  {==}

def L.oci_route.range.if_range_other():
  {==}

def L.oci_route.range.if_range_same():
  {==}

def L.oci_route.range.past_4gib():
  {==}

def L.oci_route.range.absent(ir, e, size):
  {==}

def L.oci_route.range.head_ignored(r, ir, e, size):
  {==}

def L.oci_route.blob_ok():
  {==}

def L.oci_route.blob_ok_digest():
  {==}

def L.oci_route.blob_ok_length():
  {==}

def L.oci_route.blob_ok_type():
  {==}

def L.oci_route.blob_ok_etag():
  {==}

def L.oci_route.blob_ok_accept_ranges():
  {==}

def L.oci_route.blob_ok_cache_control():
  {==}

def L.oci_route.blob_ok_body():
  {==}

def L.oci_route.blob_head_ok():
  {==}

def L.oci_route.blob_head_length():
  {==}

def L.oci_route.blob_head_no_body():
  {==}

def L.oci_route.blob_partial():
  {==}

def L.oci_route.blob_partial_range():
  {==}

def L.oci_route.blob_partial_length():
  {==}

def L.oci_route.blob_partial_digest():
  {==}

def L.oci_route.blob_partial_body():
  {==}

def L.oci_route.blob_unsatisfiable():
  {==}

def L.oci_route.blob_unsatisfiable_range():
  {==}

def L.oci_route.blob_unsatisfiable_body():
  {==}

def L.oci_route.blob_partial_past_4gib():
  {==}

def L.oci_route.blob_partial_past_4gib_length():
  {==}

def L.oci_route.manifest_ok():
  {==}

def L.oci_route.manifest_ok_type():
  {==}

def L.oci_route.manifest_ok_digest():
  {==}

def L.oci_route.manifest_ok_length():
  {==}

def L.oci_route.manifest_no_range():
  {==}

def L.oci_route.blob_missing_404(h):
  {==}

def L.oci_route.manifest_missing_404(h):
  {==}

def L.oci_route.only_get_head.put(p):
  {==}

def L.oci_route.only_get_head.post(p):
  {==}

def L.oci_route.only_get_head.patch(p):
  {==}

def L.oci_route.only_get_head.delete(p):
  {==}

def L.oci_route.size.show_5gib():
  {==}

def L.oci_route.size.show_max():
  {==}

def L.oci_route.size.read_5gib():
  {==}

def L.oci_route.size.read_digits_only():
  {==}

def L.oci_route.size.read_19_digits():
  {==}
