import Base
import ../src/oci/store.bend as S
import ../src/oci/size.bend as N

# Spec for src/oci/store.bend (W3 of the OCI mirror): the on-disk layout,
# the sidecar, last-use expiry and the prune plan. The layout, the 72 h
# expiry since last use and "prune empties everything" are user decisions
# of 2026-11-17; the grammars come from distribution/reference and the
# image-spec; nothing here comes from Bend. E is sha256(""), F sha256("abc").

# User decision 2026-11-17: objects expire 72 h (259200 s) after their last use.
law oci_store.ttl_72h:
  {S.Store.ttl() == 259200 : U32}

# Layout (user decision 2026-11-17): <root>/<registry>/blobs/sha256/<ab>/<hex>,
# its sidecar beside it, and fills in <root>/tmp.
law oci_store.paths:
  {S.Store.paths("/c", "docker.io", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", 7) == Some{S.Paths{"/c/docker.io/blobs/sha256/e3/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "/c/docker.io/blobs/sha256/e3/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.meta", "/c/tmp/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.7"}} : Maybe<&2, S.Paths>}

law oci_store.blob_path:
  {S.Store.blob_path("/c", "registry.k8s.io", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == Some{"/c/registry.k8s.io/blobs/sha256/e3/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"} : Maybe<&2, String>}

law oci_store.meta_path:
  {S.Store.meta_path("/c", "registry.k8s.io", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == Some{"/c/registry.k8s.io/blobs/sha256/e3/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.meta"} : Maybe<&2, String>}

# distribution/reference: a registry host may carry a :port.
law oci_store.registry_with_port:
  {S.Store.blob_path("/c", "localhost:5000", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") == Some{"/c/localhost:5000/blobs/sha256/ba/ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"} : Maybe<&2, String>}

# Host names are case-insensitive (RFC 4343): one directory per registry.
law oci_store.registry_lowercased:
  {S.Store.blob_path("/c", "Docker.IO", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == Some{"/c/docker.io/blobs/sha256/e3/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"} : Maybe<&2, String>}

# distribution/reference domain grammar: no path from a name outside it.
law oci_store.registry_refused.dot_dot:
  {S.Store.blob_path("/c", "..", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == None{} : Maybe<&2, String>}

law oci_store.registry_refused.dot:
  {S.Store.blob_path("/c", ".", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == None{} : Maybe<&2, String>}

law oci_store.registry_refused.empty:
  {S.Store.blob_path("/c", "", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == None{} : Maybe<&2, String>}

law oci_store.registry_refused.slash:
  {S.Store.blob_path("/c", "a/b", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == None{} : Maybe<&2, String>}

law oci_store.registry_refused.empty_label:
  {S.Store.blob_path("/c", "a..b", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == None{} : Maybe<&2, String>}

law oci_store.registry_refused.dash_first:
  {S.Store.blob_path("/c", "-a.com", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == None{} : Maybe<&2, String>}

law oci_store.registry_refused.dash_last:
  {S.Store.blob_path("/c", "a-.com", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == None{} : Maybe<&2, String>}

law oci_store.registry_refused.empty_port:
  {S.Store.blob_path("/c", "a.com:", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == None{} : Maybe<&2, String>}

law oci_store.registry_refused.bad_port:
  {S.Store.blob_path("/c", "a.com:x", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == None{} : Maybe<&2, String>}

law oci_store.registry_refused.two_ports:
  {S.Store.blob_path("/c", "a.com:1:2", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == None{} : Maybe<&2, String>}

law oci_store.registry_refused.ipv6:
  {S.Store.blob_path("/c", "[::1]:5000", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == None{} : Maybe<&2, String>}

law oci_store.registry_refused.space:
  {S.Store.blob_path("/c", "a b", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == None{} : Maybe<&2, String>}

# image-spec: sha256 is "sha256:" and [a-f0-9]{64}; nothing else names a file.
law oci_store.digest_refused.traversal:
  {S.Store.blob_path("/c", "docker.io", "sha256:../../../etc/passwd") == None{} : Maybe<&2, String>}

law oci_store.digest_refused.upper_hex:
  {S.Store.blob_path("/c", "docker.io", "sha256:E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855") == None{} : Maybe<&2, String>}

law oci_store.digest_refused.short:
  {S.Store.blob_path("/c", "docker.io", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b85") == None{} : Maybe<&2, String>}

law oci_store.digest_refused.long:
  {S.Store.blob_path("/c", "docker.io", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b8550") == None{} : Maybe<&2, String>}

law oci_store.digest_refused.sha512:
  {S.Store.blob_path("/c", "docker.io", "sha512:abababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababab") == None{} : Maybe<&2, String>}

law oci_store.digest_refused.no_algorithm:
  {S.Store.blob_path("/c", "docker.io", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == None{} : Maybe<&2, String>}

law oci_store.digest_refused.empty:
  {S.Store.blob_path("/c", "docker.io", "") == None{} : Maybe<&2, String>}

# For every root and digest, a registry outside the grammar builds no path.
law oci_store.never_unvalidated.dot_dot:
  for +root: String
  for +d: String
  {S.Store.blob_path(root, "..", d) == None{} : Maybe<&2, String>}

law oci_store.never_unvalidated.dot:
  for +root: String
  for +d: String
  {S.Store.blob_path(root, ".", d) == None{} : Maybe<&2, String>}

law oci_store.never_unvalidated.slash:
  for +root: String
  for +d: String
  {S.Store.blob_path(root, "a/b", d) == None{} : Maybe<&2, String>}

law oci_store.never_unvalidated.empty:
  for +root: String
  for +d: String
  {S.Store.blob_path(root, "", d) == None{} : Maybe<&2, String>}

law oci_store.tmp_dir:
  {S.Store.tmp_dir("/c") == "/c/tmp" : String}

# The sidecar records the media type, the size and the time of last use.
law oci_store.meta.render:
  {S.Store.meta.render(S.Meta{"application/vnd.oci.image.manifest.v1+json", N.Size{0, 527}, 1763337600}) == "oci-cache-meta 1\nmedia-type application/vnd.oci.image.manifest.v1+json\nsize 527\nlast-use 1763337600\n" : String}

law oci_store.meta.parse:
  {S.Store.meta.parse("oci-cache-meta 1\nmedia-type application/vnd.oci.image.manifest.v1+json\nsize 527\nlast-use 1763337600\n") == Some{S.Meta{"application/vnd.oci.image.manifest.v1+json", N.Size{0, 527}, 1763337600}} : Maybe<&2, S.Meta>}

# Sizes past 4 GiB survive the sidecar.
law oci_store.meta.parse_5gib:
  {S.Store.meta.parse("oci-cache-meta 1\nmedia-type application/octet-stream\nsize 5368709120\nlast-use 0\n") == Some{S.Meta{"application/octet-stream", N.Size{1, 1073741824}, 0}} : Maybe<&2, S.Meta>}

# A sidecar this version did not write is a miss.
law oci_store.meta.parse_other_version:
  {S.Store.meta.parse("oci-cache-meta 2\nmedia-type application/vnd.oci.image.manifest.v1+json\nsize 527\nlast-use 1763337600\n") == None{} : Maybe<&2, S.Meta>}

law oci_store.meta.parse_bad_media:
  {S.Store.meta.parse("oci-cache-meta 1\nmedia-type text\nsize 527\nlast-use 1763337600\n") == None{} : Maybe<&2, S.Meta>}

law oci_store.meta.parse_bad_size:
  {S.Store.meta.parse("oci-cache-meta 1\nmedia-type application/vnd.oci.image.manifest.v1+json\nsize 52x\nlast-use 1763337600\n") == None{} : Maybe<&2, S.Meta>}

law oci_store.meta.parse_time_overflow:
  {S.Store.meta.parse("oci-cache-meta 1\nmedia-type application/vnd.oci.image.manifest.v1+json\nsize 527\nlast-use 4294967296\n") == None{} : Maybe<&2, S.Meta>}

law oci_store.meta.parse_empty:
  {S.Store.meta.parse("") == None{} : Maybe<&2, S.Meta>}

# spec.md: the registry SHOULD NOT include parameters on Content-Type.
law oci_store.meta.new_drops_parameters:
  {S.Store.meta.new("application/json; charset=utf-8", N.Size{0, 2}, 1763337600) == S.Meta{"application/json", N.Size{0, 2}, 1763337600} : S.Meta}

# RFC 6838 4.2: a media type is type/subtype of restricted-name characters;
# anything else is stored as application/octet-stream.
law oci_store.meta.new_refuses_header_injection:
  {S.Store.meta.new("text/plain\r\nX-Evil: 1", N.Size{0, 2}, 1763337600) == S.Meta{"application/octet-stream", N.Size{0, 2}, 1763337600} : S.Meta}

law oci_store.meta.new_keeps_oci_type:
  {S.Store.meta.new("application/vnd.oci.image.manifest.v1+json", N.Size{0, 527}, 1763337600) == S.Meta{"application/vnd.oci.image.manifest.v1+json", N.Size{0, 527}, 1763337600} : S.Meta}

# Kept until 72 h since the last use have passed.
law oci_store.expiry.fresh:
  {S.Store.expired(S.Meta{"application/vnd.oci.image.manifest.v1+json", N.Size{0, 527}, 1763337600}, 1763596799) == False{} : Bool}

# Expired once 72 h have passed since the last use.
law oci_store.expiry.at_72h:
  {S.Store.expired(S.Meta{"application/vnd.oci.image.manifest.v1+json", N.Size{0, 527}, 1763337600}, 1763596800) == True{} : Bool}

# A clock that went back expires nothing.
law oci_store.expiry.clock_back:
  {S.Store.expired(S.Meta{"application/vnd.oci.image.manifest.v1+json", N.Size{0, 527}, 1763337600}, 1763337590) == False{} : Bool}

# A hit records its time of use.
law oci_store.touch:
  {S.Store.touch(S.Meta{"application/vnd.oci.image.manifest.v1+json", N.Size{0, 527}, 1763337600}, 1763837600) == S.Meta{"application/vnd.oci.image.manifest.v1+json", N.Size{0, 527}, 1763837600} : S.Meta}

# A hit, even on an expired object, serves it and renews it.
law oci_store.hit_renews:
  {S.Store.hit("oci-cache-meta 1\nmedia-type application/vnd.oci.image.manifest.v1+json\nsize 527\nlast-use 1763337600\n", 1763596800) == Some{S.Meta{"application/vnd.oci.image.manifest.v1+json", N.Size{0, 527}, 1763596800}} : Maybe<&2, S.Meta>}

# A hit at t keeps the object until t + 72 h.
law oci_store.hit_then_fresh:
  {S.Store.expired(S.Meta{"application/vnd.oci.image.manifest.v1+json", N.Size{0, 527}, 1763737600}, 1763996799) == False{} : Bool}

law oci_store.hit_unreadable:
  {S.Store.hit("garbage", 1763337600) == None{} : Maybe<&2, S.Meta>}

# The sweep deletes an expired object and its sidecar, and keeps a fresh one.
law oci_store.sweep.expired_only:
  {S.Store.sweep("/c", 1763596800, [S.Item{"docker.io", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", Some{"oci-cache-meta 1\nmedia-type application/octet-stream\nsize 10\nlast-use 1763337600\n"}}, S.Item{"docker.io", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", Some{"oci-cache-meta 1\nmedia-type application/octet-stream\nsize 10\nlast-use 1763437600\n"}}]) == ["/c/docker.io/blobs/sha256/e3/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "/c/docker.io/blobs/sha256/e3/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.meta"] : List<&2, String>}

# An object without a readable sidecar cannot be served, so it goes.
law oci_store.sweep.no_sidecar:
  {S.Store.sweep("/c", 1763596800, [S.Item{"ghcr.io", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", None{}}]) == ["/c/ghcr.io/blobs/sha256/ba/ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "/c/ghcr.io/blobs/sha256/ba/ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad.meta"] : List<&2, String>}

# Files whose names fail the grammar give no path, so nothing to delete.
law oci_store.sweep.invalid_names:
  {S.Store.sweep("/c", 1763596800, [S.Item{"..", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", None{}}, S.Item{"docker.io", "sha256:../x", None{}}]) == [] : List<&2, String>}

law oci_store.sweep.empty:
  {S.Store.sweep("/c", 1763596800, []) == [] : List<&2, String>}

# User decision 2026-11-17: `cache prune` removes everything: tmp and every
# registry directory (a directory outside the grammar is not ours).
law oci_store.prune:
  {S.Store.prune("/c", ["docker.io", "registry.k8s.io", "..", "ghcr.io"]) == ["/c/tmp", "/c/docker.io", "/c/registry.k8s.io", "/c/ghcr.io"] : List<&2, String>}

# Every prune plan empties the fills in progress.
law oci_store.prune_tmp_first:
  for +root: String
  for +rs: List<&2, String>
  {List.head(&2, String, S.Store.prune(root, rs)) == Some{root ++ "/tmp"} : Maybe<&2, String>}

# spec.md: content is verified against its digest before it is kept.
law oci_store.verified:
  {S.Store.verified("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", Some{N.Size{0, 0}}, N.Size{0, 0}) == True{} : Bool}

law oci_store.verified_wrong_hash:
  {S.Store.verified("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", None{}, N.Size{0, 3}) == False{} : Bool}

# A length that differs from the declared Content-Length is refused.
law oci_store.verified_wrong_size:
  {S.Store.verified("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", Some{N.Size{0, 1}}, N.Size{0, 0}) == False{} : Bool}
