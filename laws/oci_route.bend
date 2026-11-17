import Base
import ../src/oci/route.bend as R
import ../src/oci/grammar.bend as G
import ../src/oci/size.bend as N

# Spec for src/oci/route.bend (W1 of the OCI mirror): routing, the error
# body, Range, and the name, tag and digest grammars. Expected values come
# from opencontainers/distribution-spec spec.md, RFC 9110, CNCF
# distribution (registry/handlers, registry/storage/blobserver.go,
# registry/api/errcode) and containerd core/remotes/docker, never from Bend.
# E below is sha256 of the empty string.

# spec.md end-1: GET /v2/ is the version check.
law oci_route.ping:
  {R.Route.request("GET", "/v2/") == R.Ping{False{}} : R.Req}

law oci_route.ping_head:
  {R.Route.request("HEAD", "/v2/") == R.Ping{True{}} : R.Req}

# distribution registry/handlers/app.go apiBase: 200, "{}", application/json,
# Content-Length 2, and Docker-Distribution-API-Version on every response.
law oci_route.ping_response:
  {R.Route.ping(False{}) == R.Resp{200, [R.Hdr{"Content-Type", "application/json"}, R.Hdr{"Content-Length", "2"}, R.Hdr{"Docker-Distribution-API-Version", "registry/2.0"}], R.JsonBody{"{}"}} : R.Resp}

# spec.md end-2: GET /v2/<name>/blobs/<digest>.
law oci_route.blob_by_digest:
  {R.Route.request("GET", "/v2/library/alpine/blobs/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == R.Fetch{False{}, R.Blob{}, "library/alpine", G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}} : R.Req}

# spec.md "Checking if content exists": HEAD of a blob.
law oci_route.blob_head:
  {R.Route.request("HEAD", "/v2/library/alpine/blobs/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == R.Fetch{True{}, R.Blob{}, "library/alpine", G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}} : R.Req}

# spec.md end-3: GET /v2/<name>/manifests/<digest>.
law oci_route.manifest_by_digest:
  {R.Route.request("GET", "/v2/alpine/manifests/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == R.Fetch{False{}, R.Manifest{}, "alpine", G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}} : R.Req}

law oci_route.manifest_head:
  {R.Route.request("HEAD", "/v2/alpine/manifests/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == R.Fetch{True{}, R.Manifest{}, "alpine", G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}} : R.Req}

# A name has any number of "/" components.
law oci_route.nested_name:
  {R.Route.request("GET", "/v2/a/b/c/manifests/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == R.Fetch{False{}, R.Manifest{}, "a/b/c", G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}} : R.Req}

# The endpoint is the second-to-last segment; "manifests" may be a name component.
law oci_route.name_with_endpoint_word:
  {R.Route.request("GET", "/v2/x/manifests/blobs/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == R.Fetch{False{}, R.Blob{}, "x/manifests", G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}} : R.Req}

# containerd (core/remotes/docker resolver.go addNamespace) asks a mirror with
# ?ns=<upstream host>; the query does not change the route.
law oci_route.query_ignored:
  {R.Route.request("GET", "/v2/library/alpine/blobs/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855?ns=docker.io") == R.Fetch{False{}, R.Blob{}, "library/alpine", G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}} : R.Req}

# A pull-only mirror refuses tags with 404: containerd's resolver (resolver.go
# Resolve) takes a 404 as "not on this host" and tries the next one, and
# spec.md lists 404 as end-3's only failure code.
law oci_route.tag_refused:
  {R.Route.req.status(R.Route.request("GET", "/v2/library/alpine/manifests/latest")) == 404 : U32}

# spec.md Error Codes: the body names the code UNSUPPORTED.
law oci_route.tag_refused_body:
  {R.Route.req.body(R.Route.request("GET", "/v2/library/alpine/manifests/latest")) == "{\"errors\":[{\"code\":\"UNSUPPORTED\",\"message\":\"pull-only mirror: resolve tags upstream and pull by digest\"}]}\n" : String}

law oci_route.tag_refused_head:
  {R.Route.req.status(R.Route.request("HEAD", "/v2/library/alpine/manifests/v1.2.3")) == 404 : U32}

# A HEAD response has no body (RFC 9110 9.3.2).
law oci_route.tag_refused_head_no_body:
  {R.Route.req.body(R.Route.request("HEAD", "/v2/library/alpine/manifests/v1.2.3")) == "" : String}

# spec.md: an unsupported digest algorithm SHOULD be 400; only sha256 is supported.
law oci_route.manifest_sha512:
  {R.Route.req.status(R.Route.request("GET", "/v2/alpine/manifests/sha512:abababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababab")) == 400 : U32}

# distribution errcode DIGEST_INVALID and its message.
law oci_route.manifest_sha512_body:
  {R.Route.req.body(R.Route.request("GET", "/v2/alpine/manifests/sha512:abababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababababab")) == "{\"errors\":[{\"code\":\"DIGEST_INVALID\",\"message\":\"provided digest did not match uploaded content\"}]}\n" : String}

# image-spec: a sha256 encoded part is exactly 64 hex digits.
law oci_route.blob_short_digest:
  {R.Route.req.status(R.Route.request("GET", "/v2/alpine/blobs/sha256:abc")) == 400 : U32}

# image-spec: sha256 hex digits are lowercase [a-f0-9].
law oci_route.blob_upper_digest:
  {R.Route.req.status(R.Route.request("GET", "/v2/alpine/blobs/sha256:E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855")) == 400 : U32}

# spec.md end-2: blobs are fetched by digest only.
law oci_route.blob_by_tag:
  {R.Route.req.status(R.Route.request("GET", "/v2/alpine/blobs/latest")) == 400 : U32}

# Neither a tag nor a digest: no such manifest.
law oci_route.manifest_bad_reference:
  {R.Route.req.status(R.Route.request("GET", "/v2/alpine/manifests/.bad")) == 404 : U32}

# spec.md name grammar: lowercase only; distribution answers NAME_INVALID (400).
law oci_route.name_upper:
  {R.Route.req.status(R.Route.request("GET", "/v2/Library/alpine/blobs/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")) == 400 : U32}

law oci_route.name_upper_body:
  {R.Route.req.body(R.Route.request("GET", "/v2/Library/alpine/blobs/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")) == "{\"errors\":[{\"code\":\"NAME_INVALID\",\"message\":\"invalid repository name\"}]}\n" : String}

law oci_route.name_empty_component:
  {R.Route.req.status(R.Route.request("GET", "/v2/a//b/blobs/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")) == 400 : U32}

law oci_route.name_dot_dot:
  {R.Route.req.status(R.Route.request("GET", "/v2/../etc/blobs/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")) == 400 : U32}

# spec.md: [a-z0-9]+((\.|_|__|-+)[a-z0-9]+)*(\/[a-z0-9]+((\.|_|__|-+)[a-z0-9]+)*)*
law oci_route.name.ok_plain:
  {G.Gram.name("library/alpine") == True{} : Bool}

law oci_route.name.ok_separators:
  {G.Gram.name("a.b/c-d_e") == True{} : Bool}

law oci_route.name.ok_double_underscore:
  {G.Gram.name("a__b") == True{} : Bool}

law oci_route.name.ok_dashes:
  {G.Gram.name("a--b") == True{} : Bool}

law oci_route.name.bad_triple_underscore:
  {G.Gram.name("a___b") == False{} : Bool}

law oci_route.name.bad_mixed_separator:
  {G.Gram.name("a.-b") == False{} : Bool}

law oci_route.name.bad_double_dot:
  {G.Gram.name("a..b") == False{} : Bool}

law oci_route.name.bad_trailing_slash:
  {G.Gram.name("a/") == False{} : Bool}

law oci_route.name.bad_leading_dash:
  {G.Gram.name("-a") == False{} : Bool}

law oci_route.name.bad_trailing_underscore:
  {G.Gram.name("a_") == False{} : Bool}

law oci_route.name.bad_empty:
  {G.Gram.name("") == False{} : Bool}

law oci_route.name.bad_colon:
  {G.Gram.name("a:b") == False{} : Bool}

# distribution/reference: a name holds at most 255 characters.
law oci_route.name.too_long:
  {G.Gram.name(String.repeat("a", 256n)) == False{} : Bool}

law oci_route.name.longest:
  {G.Gram.name(String.repeat("a", 255n)) == True{} : Bool}

# spec.md: [a-zA-Z0-9_][a-zA-Z0-9._-]{0,127}
law oci_route.tag.ok_latest:
  {G.Gram.tag("latest") == True{} : Bool}

law oci_route.tag.ok_version:
  {G.Gram.tag("v1.2.3-rc_1") == True{} : Bool}

law oci_route.tag.ok_underscore_first:
  {G.Gram.tag("_x") == True{} : Bool}

law oci_route.tag.bad_dot_first:
  {G.Gram.tag(".x") == False{} : Bool}

law oci_route.tag.bad_dash_first:
  {G.Gram.tag("-x") == False{} : Bool}

law oci_route.tag.bad_empty:
  {G.Gram.tag("") == False{} : Bool}

law oci_route.tag.longest:
  {G.Gram.tag(String.repeat("a", 128n)) == True{} : Bool}

law oci_route.tag.too_long:
  {G.Gram.tag(String.repeat("a", 129n)) == False{} : Bool}

# end-8 is not served by a pull-only mirror.
law oci_route.tags_list_unsupported:
  {R.Route.req.status(R.Route.request("GET", "/v2/alpine/tags/list")) == 404 : U32}

law oci_route.catalog_unsupported:
  {R.Route.req.status(R.Route.request("GET", "/v2/_catalog")) == 404 : U32}

# spec.md: a client falls back to the referrers tag schema on 404.
law oci_route.referrers_unsupported:
  {R.Route.req.status(R.Route.request("GET", "/v2/alpine/referrers/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")) == 404 : U32}

law oci_route.not_v2:
  {R.Route.req.status(R.Route.request("GET", "/v1/_ping")) == 404 : U32}

# Pushes (end-4a..end-7) are refused: distribution's UNSUPPORTED is 405.
law oci_route.push_refused:
  {R.Route.req.status(R.Route.request("POST", "/v2/alpine/blobs/uploads/")) == 405 : U32}

law oci_route.push_refused_body:
  {R.Route.req.body(R.Route.request("POST", "/v2/alpine/blobs/uploads/")) == "{\"errors\":[{\"code\":\"UNSUPPORTED\",\"message\":\"The operation is unsupported.\"}]}\n" : String}

# RFC 9110 15.5.6: a 405 lists the allowed methods in Allow.
law oci_route.not_allowed_allow:
  {R.Route.header(R.Route.not_allowed(), "Allow") == Some{"GET, HEAD"} : Maybe<&2, String>}

law oci_route.not_allowed_length:
  {R.Route.header(R.Route.not_allowed(), "Content-Length") == Some{"78"} : Maybe<&2, String>}

# spec.md end-2: 404 with BLOB_UNKNOWN; the body as distribution's errcode.ServeJSON
# writes it.
law oci_route.blob_missing:
  {R.Route.missing(R.Blob{}, False{}) == R.Resp{404, [R.Hdr{"Content-Type", "application/json"}, R.Hdr{"Content-Length", "74"}, R.Hdr{"Docker-Distribution-API-Version", "registry/2.0"}], R.JsonBody{"{\"errors\":[{\"code\":\"BLOB_UNKNOWN\",\"message\":\"blob unknown to registry\"}]}\n"}} : R.Resp}

law oci_route.manifest_unknown_body:
  {R.Route.req.body(R.Route.request("GET", "/v2/alpine/manifests/.bad")) == "{\"errors\":[{\"code\":\"MANIFEST_UNKNOWN\",\"message\":\"manifest unknown\"}]}\n" : String}

law oci_route.range.first_100:
  {R.Route.range(Some{"bytes=0-99"}, RFC 9110 14.1.2: bytes=0-99 is the first 100 bytes., "\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"", N.Size{0, 1000}) == R.Part{N.Size{0, 0}, N.Size{0, 99}} : R.Ranged}

law oci_route.range.open_end:
  {R.Route.range(Some{"bytes=100-"}, RFC 9110 14.1.1: an absent last-pos means to the end., "\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"", N.Size{0, 1000}) == R.Part{N.Size{0, 100}, N.Size{0, 999}} : R.Ranged}

law oci_route.range.suffix:
  {R.Route.range(Some{"bytes=-100"}, RFC 9110 14.1.1: -100 is the last 100 bytes., "\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"", N.Size{0, 1000}) == R.Part{N.Size{0, 900}, N.Size{0, 999}} : R.Ranged}

law oci_route.range.suffix_longer:
  {R.Route.range(Some{"bytes=-2000"}, RFC 9110 14.1.1: a suffix longer than the representation selects all of it., "\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"", N.Size{0, 1000}) == R.Part{N.Size{0, 0}, N.Size{0, 999}} : R.Ranged}

law oci_route.range.last_past_end:
  {R.Route.range(Some{"bytes=0-5000"}, RFC 9110 14.1.1: a last-pos past the end is cut to length - 1., "\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"", N.Size{0, 1000}) == R.Part{N.Size{0, 0}, N.Size{0, 999}} : R.Ranged}

law oci_route.range.last_byte:
  {R.Route.range(Some{"bytes=999-999"}, None{}, "\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"", N.Size{0, 1000}) == R.Part{N.Size{0, 999}, N.Size{0, 999}} : R.Ranged}

law oci_route.range.first_at_end:
  {R.Route.range(Some{"bytes=1000-"}, RFC 9110 14.1.1: unsatisfiable when first-pos is not less than the length., "\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"", N.Size{0, 1000}) == R.Unsat{} : R.Ranged}

law oci_route.range.backwards:
  {R.Route.range(Some{"bytes=5-4"}, RFC 9110 14.1.1: last-pos below first-pos is invalid; Go http.ServeContent answers 416., "\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"", N.Size{0, 1000}) == R.Unsat{} : R.Ranged}

law oci_route.range.suffix_zero:
  {R.Route.range(Some{"bytes=-0"}, RFC 9110 14.1.1: a suffix-length of 0 is unsatisfiable., "\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"", N.Size{0, 1000}) == R.Unsat{} : R.Ranged}

law oci_route.range.malformed:
  {R.Route.range(Some{"bytes=abc"}, Go http.ServeContent: a malformed bytes range is 416., "\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"", N.Size{0, 1000}) == R.Unsat{} : R.Ranged}

law oci_route.range.empty_set:
  {R.Route.range(Some{"bytes="}, None{}, "\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"", N.Size{0, 1000}) == R.Unsat{} : R.Ranged}

law oci_route.range.two_dashes:
  {R.Route.range(Some{"bytes=1-2-3"}, None{}, "\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"", N.Size{0, 1000}) == R.Unsat{} : R.Ranged}

law oci_route.range.overflow:
  {R.Route.range(Some{"bytes=0-99999999999999999999"}, Go parses positions as int64; a value past it is an invalid range., "\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"", N.Size{0, 1000}) == R.Unsat{} : R.Ranged}

law oci_route.range.unknown_unit:
  {R.Route.range(Some{"items=0-1"}, RFC 9110 14.2: a server MUST ignore a Range with a unit it does not understand., "\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"", N.Size{0, 1000}) == R.Whole{} : R.Ranged}

law oci_route.range.several:
  {R.Route.range(Some{"bytes=0-1,5-6"}, RFC 9110 14.2: a server MAY ignore Range; several ranges are served whole., "\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"", N.Size{0, 1000}) == R.Whole{} : R.Ranged}

law oci_route.range.unit_case:
  {R.Route.range(Some{"BYTES=0-0"}, RFC 9110 14.1: range units are case-insensitive., "\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"", N.Size{0, 1000}) == R.Part{N.Size{0, 0}, N.Size{0, 0}} : R.Ranged}

law oci_route.range.list_whitespace:
  {R.Route.range(Some{"bytes= 0-0 ,"}, RFC 9110 5.6.1: optional whitespace and empty list elements., "\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"", N.Size{0, 1000}) == R.Part{N.Size{0, 0}, N.Size{0, 0}} : R.Ranged}

law oci_route.range.empty_blob:
  {R.Route.range(Some{"bytes=0-"}, RFC 9110 14.1.1: an empty representation satisfies no int-range., "\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"", N.Size{0, 0}) == R.Unsat{} : R.Ranged}

# RFC 9110 13.1.5: an If-Range that does not match the ETag gets the whole representation.
law oci_route.range.if_range_other:
  {R.Route.range(Some{"bytes=0-0"}, Some{"\"sha256:0000\""}, "\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"", N.Size{0, 1000}) == R.Whole{} : R.Ranged}

law oci_route.range.if_range_same:
  {R.Route.range(Some{"bytes=0-0"}, Some{"\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\""}, "\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"", N.Size{0, 1000}) == R.Part{N.Size{0, 0}, N.Size{0, 0}} : R.Ranged}

law oci_route.range.past_4gib:
  {R.Route.range(Some{"bytes=4294967296-"}, Byte positions are 64-bit: a range of a 5 GiB layer past 4 GiB., "\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"", N.Size{1, 1073741824}) == R.Part{N.Size{1, 0}, N.Size{1, 1073741823}} : R.Ranged}

# RFC 9110 14.2: without Range, the whole representation.
law oci_route.range.absent:
  for +ir: Maybe<&2, String>
  for +e: String
  for +size: N.Size
  {R.Route.range(None{}, ir, e, size) == R.Whole{} : R.Ranged}

# RFC 9110 14.2: Range is defined for GET only; a HEAD ignores it.
law oci_route.range.head_ignored:
  for +r: Maybe<&2, String>
  for +ir: Maybe<&2, String>
  for +e: String
  for +size: N.Size
  {R.Route.range.get(True{}, r, ir, e, size) == R.Whole{} : R.Ranged}

# spec.md end-2: 200 for a blob the mirror has.
law oci_route.blob_ok:
  {R.Route.status(R.Route.found(R.Blob{}, False{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/octet-stream", N.Size{0, 1000}, None{}, None{})) == 200 : U32}

# spec.md: a successful response MUST carry Docker-Content-Digest.
law oci_route.blob_ok_digest:
  {R.Route.header(R.Route.found(R.Blob{}, False{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/octet-stream", N.Size{0, 1000}, None{}, None{}), "Docker-Content-Digest") == Some{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"} : Maybe<&2, String>}

law oci_route.blob_ok_length:
  {R.Route.header(R.Route.found(R.Blob{}, False{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/octet-stream", N.Size{0, 1000}, None{}, None{}), "Content-Length") == Some{"1000"} : Maybe<&2, String>}

law oci_route.blob_ok_type:
  {R.Route.header(R.Route.found(R.Blob{}, False{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/octet-stream", N.Size{0, 1000}, None{}, None{}), "Content-Type") == Some{"application/octet-stream"} : Maybe<&2, String>}

# distribution blobserver.go: ETag is the quoted digest.
law oci_route.blob_ok_etag:
  {R.Route.header(R.Route.found(R.Blob{}, False{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/octet-stream", N.Size{0, 1000}, None{}, None{}), "ETag") == Some{"\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\""} : Maybe<&2, String>}

# Go http.ServeContent: Accept-Ranges: bytes.
law oci_route.blob_ok_accept_ranges:
  {R.Route.header(R.Route.found(R.Blob{}, False{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/octet-stream", N.Size{0, 1000}, None{}, None{}), "Accept-Ranges") == Some{"bytes"} : Maybe<&2, String>}

# distribution blobserver.go: max-age of 365 days; header names are case-insensitive.
law oci_route.blob_ok_cache_control:
  {R.Route.header(R.Route.found(R.Blob{}, False{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/octet-stream", N.Size{0, 1000}, None{}, None{}), "cache-control") == Some{"max-age=31536000"} : Maybe<&2, String>}

law oci_route.blob_ok_body:
  {R.Route.body(R.Route.found(R.Blob{}, False{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/octet-stream", N.Size{0, 1000}, None{}, None{})) == R.Stream{N.Size{0, 0}, N.Size{0, 1000}} : R.Body}

# spec.md: HEAD of an existing blob is 200, and it ignores Range (RFC 9110 14.2).
law oci_route.blob_head_ok:
  {R.Route.status(R.Route.found(R.Blob{}, True{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/octet-stream", N.Size{0, 1000}, Some{"bytes=0-99"}, None{})) == 200 : U32}

# spec.md: a HEAD response MUST carry the size in Content-Length.
law oci_route.blob_head_length:
  {R.Route.header(R.Route.found(R.Blob{}, True{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/octet-stream", N.Size{0, 1000}, Some{"bytes=0-99"}, None{}), "Content-Length") == Some{"1000"} : Maybe<&2, String>}

law oci_route.blob_head_no_body:
  {R.Route.body(R.Route.found(R.Blob{}, True{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/octet-stream", N.Size{0, 1000}, Some{"bytes=0-99"}, None{})) == R.NoBody{} : R.Body}

# RFC 9110 15.3.7: one satisfiable range is 206 Partial Content.
law oci_route.blob_partial:
  {R.Route.status(R.Route.found(R.Blob{}, False{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/octet-stream", N.Size{0, 1000}, Some{"bytes=0-99"}, None{})) == 206 : U32}

# RFC 9110 14.4: Content-Range: bytes first-last/complete-length.
law oci_route.blob_partial_range:
  {R.Route.header(R.Route.found(R.Blob{}, False{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/octet-stream", N.Size{0, 1000}, Some{"bytes=0-99"}, None{}), "Content-Range") == Some{"bytes 0-99/1000"} : Maybe<&2, String>}

law oci_route.blob_partial_length:
  {R.Route.header(R.Route.found(R.Blob{}, False{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/octet-stream", N.Size{0, 1000}, Some{"bytes=0-99"}, None{}), "Content-Length") == Some{"100"} : Maybe<&2, String>}

law oci_route.blob_partial_digest:
  {R.Route.header(R.Route.found(R.Blob{}, False{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/octet-stream", N.Size{0, 1000}, Some{"bytes=0-99"}, None{}), "Docker-Content-Digest") == Some{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"} : Maybe<&2, String>}

law oci_route.blob_partial_body:
  {R.Route.body(R.Route.found(R.Blob{}, False{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/octet-stream", N.Size{0, 1000}, Some{"bytes=0-99"}, None{})) == R.Stream{N.Size{0, 0}, N.Size{0, 100}} : R.Body}

# RFC 9110 15.5.17: an unsatisfiable range is 416.
law oci_route.blob_unsatisfiable:
  {R.Route.status(R.Route.found(R.Blob{}, False{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/octet-stream", N.Size{0, 1000}, Some{"bytes=2000-"}, None{})) == 416 : U32}

# RFC 9110 15.5.17: Content-Range: bytes */complete-length.
law oci_route.blob_unsatisfiable_range:
  {R.Route.header(R.Route.found(R.Blob{}, False{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/octet-stream", N.Size{0, 1000}, Some{"bytes=2000-"}, None{}), "Content-Range") == Some{"bytes */1000"} : Maybe<&2, String>}

law oci_route.blob_unsatisfiable_body:
  {R.Route.body(R.Route.found(R.Blob{}, False{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/octet-stream", N.Size{0, 1000}, Some{"bytes=2000-"}, None{})) == R.NoBody{} : R.Body}

law oci_route.blob_partial_past_4gib:
  {R.Route.header(R.Route.found(R.Blob{}, False{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/octet-stream", N.Size{1, 1073741824}, Some{"bytes=4294967296-"}, None{}), "Content-Range") == Some{"bytes 4294967296-5368709119/5368709120"} : Maybe<&2, String>}

law oci_route.blob_partial_past_4gib_length:
  {R.Route.header(R.Route.found(R.Blob{}, False{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/octet-stream", N.Size{1, 1073741824}, Some{"bytes=4294967296-"}, None{}), "Content-Length") == Some{"1073741824"} : Maybe<&2, String>}

# spec.md end-3: 200, the whole manifest (distribution serves manifests whole).
law oci_route.manifest_ok:
  {R.Route.status(R.Route.found(R.Manifest{}, False{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/vnd.oci.image.index.v1+json", N.Size{0, 527}, Some{"bytes=0-9"}, None{})) == 200 : U32}

# spec.md: Content-Type is the manifest's media type.
law oci_route.manifest_ok_type:
  {R.Route.header(R.Route.found(R.Manifest{}, False{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/vnd.oci.image.index.v1+json", N.Size{0, 527}, Some{"bytes=0-9"}, None{}), "Content-Type") == Some{"application/vnd.oci.image.index.v1+json"} : Maybe<&2, String>}

law oci_route.manifest_ok_digest:
  {R.Route.header(R.Route.found(R.Manifest{}, False{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/vnd.oci.image.index.v1+json", N.Size{0, 527}, Some{"bytes=0-9"}, None{}), "Docker-Content-Digest") == Some{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"} : Maybe<&2, String>}

law oci_route.manifest_ok_length:
  {R.Route.header(R.Route.found(R.Manifest{}, False{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/vnd.oci.image.index.v1+json", N.Size{0, 527}, Some{"bytes=0-9"}, None{}), "Content-Length") == Some{"527"} : Maybe<&2, String>}

law oci_route.manifest_no_range:
  {R.Route.header(R.Route.found(R.Manifest{}, False{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/vnd.oci.image.index.v1+json", N.Size{0, 527}, Some{"bytes=0-9"}, None{}), "Content-Range") == None{} : Maybe<&2, String>}

# spec.md end-2: a blob the mirror cannot get is 404.
law oci_route.blob_missing_404:
  for h: Bool
  {R.Route.status(R.Route.missing(R.Blob{}, h)) == 404 : U32}

# spec.md end-3: a manifest the mirror cannot get is 404.
law oci_route.manifest_missing_404:
  for h: Bool
  {R.Route.status(R.Route.missing(R.Manifest{}, h)) == 404 : U32}

# Pull only: a PUT of any target is 405.
law oci_route.only_get_head.put:
  for +p: String
  {R.Route.request("PUT", p) == R.Reply{R.Route.not_allowed()} : R.Req}

law oci_route.only_get_head.post:
  for +p: String
  {R.Route.request("POST", p) == R.Reply{R.Route.not_allowed()} : R.Req}

law oci_route.only_get_head.patch:
  for +p: String
  {R.Route.request("PATCH", p) == R.Reply{R.Route.not_allowed()} : R.Req}

law oci_route.only_get_head.delete:
  for +p: String
  {R.Route.request("DELETE", p) == R.Reply{R.Route.not_allowed()} : R.Req}

# Sizes are 64-bit: 5 GiB.
law oci_route.size.show_5gib:
  {N.Size.show(N.Size{1, 1073741824}) == "5368709120" : String}

law oci_route.size.show_max:
  {N.Size.show(N.Size{4294967295, 4294967295}) == "18446744073709551615" : String}

law oci_route.size.read_5gib:
  {N.Size.read("5368709120") == Some{N.Size{1, 1073741824}} : Maybe<&2, N.Size>}

law oci_route.size.read_digits_only:
  {N.Size.read("12a") == None{} : Maybe<&2, N.Size>}

# At most 18 digits: below Go's int64 limit, never wrapped.
law oci_route.size.read_19_digits:
  {N.Size.read("1000000000000000000") == None{} : Maybe<&2, N.Size>}
