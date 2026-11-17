import Base
import ../src/oci/fill.bend as F

# Spec for src/oci/fill.bend: the fill-and-follow state machine of the OCI
# pull-through mirror. Expected values come from the OCI distribution-spec
# (spec.md: 404 for unknown content, the error codes BLOB_UNKNOWN,
# MANIFEST_UNKNOWN, DENIED, TOOMANYREQUESTS, Docker-Content-Digest and
# Content-Length on a 200, clients verify digests), RFC 9110 (502 Bad
# Gateway, 504 Gateway Timeout), containerd (a mirror must send headers
# within 30 s; core/remotes/docker/resolver.go tries the next host after
# any 4xx or 5xx) and the design the user approved on 2026-11-17: the
# first miss fills while serving, later requests follow the fill, commit
# only on a digest match, discard on a mismatch, per-digest and connection
# caps.

# the first miss starts one upstream fetch
law oci_fill.first_miss_fetches:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}]))
    == [F.Fetch{"sha256:a"}] : List<&2, F.Act>}

# a second request for the digest follows the fill: no second fetch
law oci_fill.second_follows:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Get{2, "sha256:a", True{}, False{}, False{}, 0}]))
    == [F.Fetch{"sha256:a"}] : List<&2, F.Act>}

# the upstream 200 goes to every waiting client at once, in arrival order
law oci_fill.headers_to_all:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Get{2, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 200, "1024"}]))
    == [F.Fetch{"sha256:a"}, F.Send{1, "sha256:a", "1024"}, F.Send{2, "sha256:a", "1024"}] : List<&2, F.Act>}

# a client that comes after the headers streams the fill at once
law oci_fill.late_follower:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 200, "1024"}, F.Get{2, "sha256:a", True{}, False{}, False{}, 0}]))
    == [F.Fetch{"sha256:a"}, F.Send{1, "sha256:a", "1024"}, F.Send{2, "sha256:a", "1024"}] : List<&2, F.Act>}

# the fill is committed when its digest is the one asked for
law oci_fill.commit_on_match:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 200, "3"}, F.Ended{"sha256:a", "sha256:a"}]))
    == [F.Fetch{"sha256:a"}, F.Send{1, "sha256:a", "3"}, F.Commit{"sha256:a"}] : List<&2, F.Act>}

# a committed fill is no longer in progress
law oci_fill.commit_clears:
  {F.Fill.es(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 200, "3"}, F.Ended{"sha256:a", "sha256:a"}]))
    == [] : List<&2, F.Entry>}

# a digest mismatch discards the fill and cuts off its clients
law oci_fill.discard_on_mismatch:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Get{2, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 200, "3"}, F.Ended{"sha256:a", "sha256:b"}]))
    == [F.Fetch{"sha256:a"}, F.Send{1, "sha256:a", "3"}, F.Send{2, "sha256:a", "3"}, F.Abort{1}, F.Abort{2}, F.Discard{"sha256:a"}] : List<&2, F.Act>}

# after a discard the next request fetches again
law oci_fill.refetch_after_discard:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 200, "3"}, F.Ended{"sha256:a", "sha256:b"}, F.Get{2, "sha256:a", True{}, False{}, False{}, 0}]))
    == [F.Fetch{"sha256:a"}, F.Send{1, "sha256:a", "3"}, F.Abort{1}, F.Discard{"sha256:a"}, F.Fetch{"sha256:a"}] : List<&2, F.Act>}

# a cached digest is served from the cache
law oci_fill.cached:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, True{}, False{}, 0}]))
    == [F.Cache{1}] : List<&2, F.Act>}

# a Range request the cache cannot serve goes upstream, uncached
law oci_fill.ranged_miss_passes:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, True{}, 0}]))
    == [F.Pass{1}] : List<&2, F.Act>}

# upstream 404 maps to 404 "BLOB_UNKNOWN"
law oci_fill.upstream_404_blob:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 404, ""}]))
    == [F.Fetch{"sha256:a"}, F.Reply{1, 404, "BLOB_UNKNOWN"}, F.Discard{"sha256:a"}] : List<&2, F.Act>}

# upstream 404 maps to 404 "MANIFEST_UNKNOWN"
law oci_fill.upstream_404_manifest:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", False{}, False{}, False{}, 0}, F.Head{"sha256:a", 404, ""}]))
    == [F.Fetch{"sha256:a"}, F.Reply{1, 404, "MANIFEST_UNKNOWN"}, F.Discard{"sha256:a"}] : List<&2, F.Act>}

# upstream 401 maps to 403 "DENIED"
law oci_fill.upstream_401:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 401, ""}]))
    == [F.Fetch{"sha256:a"}, F.Reply{1, 403, "DENIED"}, F.Discard{"sha256:a"}] : List<&2, F.Act>}

# upstream 403 maps to 403 "DENIED"
law oci_fill.upstream_403:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 403, ""}]))
    == [F.Fetch{"sha256:a"}, F.Reply{1, 403, "DENIED"}, F.Discard{"sha256:a"}] : List<&2, F.Act>}

# upstream 429 maps to 429 "TOOMANYREQUESTS"
law oci_fill.upstream_429:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 429, ""}]))
    == [F.Fetch{"sha256:a"}, F.Reply{1, 429, "TOOMANYREQUESTS"}, F.Discard{"sha256:a"}] : List<&2, F.Act>}

# upstream 500 maps to 502 ""
law oci_fill.upstream_500:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 500, ""}]))
    == [F.Fetch{"sha256:a"}, F.Reply{1, 502, ""}, F.Discard{"sha256:a"}] : List<&2, F.Act>}

# upstream 503 maps to 502 ""
law oci_fill.upstream_503:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 503, ""}]))
    == [F.Fetch{"sha256:a"}, F.Reply{1, 502, ""}, F.Discard{"sha256:a"}] : List<&2, F.Act>}

# upstream 0 maps to 502 ""
law oci_fill.upstream_no_response:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 0, ""}]))
    == [F.Fetch{"sha256:a"}, F.Reply{1, 502, ""}, F.Discard{"sha256:a"}] : List<&2, F.Act>}

# a 200 without a Content-Length is a bad gateway
law oci_fill.no_length:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 200, ""}]))
    == [F.Fetch{"sha256:a"}, F.Reply{1, 502, ""}, F.Discard{"sha256:a"}] : List<&2, F.Act>}

# an upstream that breaks mid-body: clients cut off, fill discarded
law oci_fill.broke_streaming:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 200, "3"}, F.Broke{"sha256:a"}]))
    == [F.Fetch{"sha256:a"}, F.Send{1, "sha256:a", "3"}, F.Abort{1}, F.Discard{"sha256:a"}] : List<&2, F.Act>}

# an upstream that breaks before its headers: 502
law oci_fill.broke_waiting:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Broke{"sha256:a"}]))
    == [F.Fetch{"sha256:a"}, F.Reply{1, 502, ""}, F.Discard{"sha256:a"}] : List<&2, F.Act>}

# 24 s without headers: the client still waits
law oci_fill.wait_24s:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Tick{24}]))
    == [F.Fetch{"sha256:a"}] : List<&2, F.Act>}

# 25 s without headers: 504, before containerd gives up at 30 s
law oci_fill.timeout_25s:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Tick{25}]))
    == [F.Fetch{"sha256:a"}, F.Reply{1, 504, ""}] : List<&2, F.Act>}

# the fill goes on after a 504: a later request follows it
law oci_fill.timeout_keeps_fill:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Tick{25}, F.Get{2, "sha256:a", True{}, False{}, False{}, 26}, F.Head{"sha256:a", 200, "3"}]))
    == [F.Fetch{"sha256:a"}, F.Reply{1, 504, ""}, F.Send{2, "sha256:a", "3"}] : List<&2, F.Act>}

# a streaming client never times out
law oci_fill.no_timeout_streaming:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 200, "3"}, F.Tick{99}]))
    == [F.Fetch{"sha256:a"}, F.Send{1, "sha256:a", "3"}] : List<&2, F.Act>}

# over the per-digest cap: 429 TOOMANYREQUESTS
law oci_fill.cap_per_digest:
  {F.Fill.acts(F.Fill.run(F.Limits{8, 1, 128, 25}, [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Get{2, "sha256:a", True{}, False{}, False{}, 0}]))
    == [F.Fetch{"sha256:a"}, F.Reply{2, 429, "TOOMANYREQUESTS"}] : List<&2, F.Act>}

# over the fill cap: 429 TOOMANYREQUESTS
law oci_fill.cap_fills:
  {F.Fill.acts(F.Fill.run(F.Limits{1, 32, 128, 25}, [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Get{2, "sha256:b", True{}, False{}, False{}, 0}]))
    == [F.Fetch{"sha256:a"}, F.Reply{2, 429, "TOOMANYREQUESTS"}] : List<&2, F.Act>}

# over the connection cap: 429 TOOMANYREQUESTS
law oci_fill.cap_conns:
  {F.Fill.acts(F.Fill.run(F.Limits{8, 32, 1, 25}, [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Get{2, "sha256:a", True{}, False{}, False{}, 0}]))
    == [F.Fetch{"sha256:a"}, F.Reply{2, 429, "TOOMANYREQUESTS"}] : List<&2, F.Act>}

# a client that closed its connection gets nothing more; the fill goes on
law oci_fill.gone:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Get{2, "sha256:a", True{}, False{}, False{}, 0}, F.Gone{1}, F.Head{"sha256:a", 200, "3"}]))
    == [F.Fetch{"sha256:a"}, F.Send{2, "sha256:a", "3"}] : List<&2, F.Act>}

# a fill whose clients all left is still committed
law oci_fill.gone_still_commits:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Gone{1}, F.Head{"sha256:a", 200, "3"}, F.Ended{"sha256:a", "sha256:a"}]))
    == [F.Fetch{"sha256:a"}, F.Commit{"sha256:a"}] : List<&2, F.Act>}

# events for a digest with no fill do nothing
law oci_fill.unknown_digest:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Head{"sha256:a", 200, "3"}, F.Ended{"sha256:a", "sha256:a"}, F.Broke{"sha256:a"}]))
    == [] : List<&2, F.Act>}

# fills of two digests are independent
law oci_fill.two_digests:
  {F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Get{2, "sha256:b", True{}, False{}, False{}, 0}, F.Head{"sha256:b", 404, ""}, F.Head{"sha256:a", 200, "3"}]))
    == [F.Fetch{"sha256:a"}, F.Fetch{"sha256:b"}, F.Reply{2, 404, "BLOB_UNKNOWN"}, F.Discard{"sha256:b"}, F.Send{1, "sha256:a", "3"}] : List<&2, F.Act>}

# General laws.

# A cached digest is always served from the cache, and nothing else moves.
law oci_fill.cached_serves:
  for lim: F.Limits
  for es: List<&2, F.Entry>
  for c: U32
  for d: String
  for b: Bool
  for r: Bool
  for n: U32
  {F.Fill.step(lim, es, F.Get{c, d, b, True{}, r, n}) == F.Out{es, [F.Cache{c}]} : F.Out}

# A closed connection never causes an action.
law oci_fill.gone_silent:
  for lim: F.Limits
  for es: List<&2, F.Entry>
  for c: U32
  {F.Fill.step(lim, es, F.Gone{c}) == F.Out{F.Fill.gone(es, c), []} : F.Out}

# A body whose digest is not the one asked for is never committed: the
# fill is discarded and its clients cut off.
law oci_fill.mismatch_never_commits:
  for d: String
  for got: String
  for blob: Bool
  for len: String
  for ws: List<&2, F.Wt>
  for es: List<&2, F.Entry>
  for h: {String.eq(d, got) == False{} : Bool}
  {F.Fill.ended.e(F.Entry{d, blob, True{}, len, ws}, es, d, got)
    == F.Out{F.Fill.without(es, d), List.append(&2, F.Act, F.Fill.aborts(ws), [F.Discard{d}])} : F.Out}

# A body whose digest matches is committed.
law oci_fill.match_commits:
  for d: String
  for got: String
  for blob: Bool
  for len: String
  for ws: List<&2, F.Wt>
  for es: List<&2, F.Entry>
  for h: {String.eq(d, got) == True{} : Bool}
  {F.Fill.ended.e(F.Entry{d, blob, True{}, len, ws}, es, d, got)
    == F.Out{F.Fill.without(es, d), [F.Commit{d}]} : F.Out}
