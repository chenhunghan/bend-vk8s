import Base
import ../src/oci/fill.bend as F

# tests/oci_fill.bend: every concrete law of laws/oci_fill.bend, run. One
# PASS/FAIL line per case; on a FAIL, both sides as text.

def T.check(+name: String, +got: String, +want: String) -> IO(Unit):
  T.check.go(String.eq(got, want), name, got, want)

def T.check.go(ok: Bool, +name: String, +got: String, +want: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name ++ ": got " ++ got ++ ", want " ++ want)

def T.act(a: F.Act) -> String:
  match a:
    case F.Cache{c}:
      "Cache{" ++ U32.show(c) ++ "}"
    case F.Pass{c}:
      "Pass{" ++ U32.show(c) ++ "}"
    case F.Fetch{d}:
      "Fetch{" ++ d ++ "}"
    case F.Send{c, d, l}:
      "Send{" ++ U32.show(c) ++ "," ++ d ++ "," ++ l ++ "}"
    case F.Reply{c, s, k}:
      "Reply{" ++ U32.show(c) ++ "," ++ U32.show(s) ++ "," ++ k ++ "}"
    case F.Commit{d}:
      "Commit{" ++ d ++ "}"
    case F.Discard{d}:
      "Discard{" ++ d ++ "}"
    case F.Abort{c}:
      "Abort{" ++ U32.show(c) ++ "}"

def T.acts(xs: List<&2, F.Act>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, t}:
      T.act(x) ++ ";" ++ T.acts(t)

def T.es(xs: List<&2, F.Entry>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{F.Entry{d, b, body, l, ws}, t}:
      d ++ ";" ++ T.es(t)

def main() -> IO(Unit):
  do IO<Unit>:
    T.check("oci_fill.first_miss_fetches",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}]))),
      T.acts([F.Fetch{"sha256:a"}]))
    T.check("oci_fill.second_follows",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Get{2, "sha256:a", True{}, False{}, False{}, 0}]))),
      T.acts([F.Fetch{"sha256:a"}]))
    T.check("oci_fill.headers_to_all",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Get{2, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 200, "1024"}]))),
      T.acts([F.Fetch{"sha256:a"}, F.Send{1, "sha256:a", "1024"}, F.Send{2, "sha256:a", "1024"}]))
    T.check("oci_fill.late_follower",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 200, "1024"}, F.Get{2, "sha256:a", True{}, False{}, False{}, 0}]))),
      T.acts([F.Fetch{"sha256:a"}, F.Send{1, "sha256:a", "1024"}, F.Send{2, "sha256:a", "1024"}]))
    T.check("oci_fill.commit_on_match",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 200, "3"}, F.Ended{"sha256:a", "sha256:a"}]))),
      T.acts([F.Fetch{"sha256:a"}, F.Send{1, "sha256:a", "3"}, F.Commit{"sha256:a"}]))
    T.check("oci_fill.commit_clears",
      T.es(F.Fill.es(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 200, "3"}, F.Ended{"sha256:a", "sha256:a"}]))),
      T.es([]))
    T.check("oci_fill.discard_on_mismatch",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Get{2, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 200, "3"}, F.Ended{"sha256:a", "sha256:b"}]))),
      T.acts([F.Fetch{"sha256:a"}, F.Send{1, "sha256:a", "3"}, F.Send{2, "sha256:a", "3"}, F.Abort{1}, F.Abort{2}, F.Discard{"sha256:a"}]))
    T.check("oci_fill.refetch_after_discard",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 200, "3"}, F.Ended{"sha256:a", "sha256:b"}, F.Get{2, "sha256:a", True{}, False{}, False{}, 0}]))),
      T.acts([F.Fetch{"sha256:a"}, F.Send{1, "sha256:a", "3"}, F.Abort{1}, F.Discard{"sha256:a"}, F.Fetch{"sha256:a"}]))
    T.check("oci_fill.cached",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, True{}, False{}, 0}]))),
      T.acts([F.Cache{1}]))
    T.check("oci_fill.ranged_miss_passes",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, True{}, 0}]))),
      T.acts([F.Pass{1}]))
    T.check("oci_fill.upstream_404_blob",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 404, ""}]))),
      T.acts([F.Fetch{"sha256:a"}, F.Reply{1, 404, "BLOB_UNKNOWN"}, F.Discard{"sha256:a"}]))
    T.check("oci_fill.upstream_404_manifest",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", False{}, False{}, False{}, 0}, F.Head{"sha256:a", 404, ""}]))),
      T.acts([F.Fetch{"sha256:a"}, F.Reply{1, 404, "MANIFEST_UNKNOWN"}, F.Discard{"sha256:a"}]))
    T.check("oci_fill.upstream_401",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 401, ""}]))),
      T.acts([F.Fetch{"sha256:a"}, F.Reply{1, 403, "DENIED"}, F.Discard{"sha256:a"}]))
    T.check("oci_fill.upstream_403",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 403, ""}]))),
      T.acts([F.Fetch{"sha256:a"}, F.Reply{1, 403, "DENIED"}, F.Discard{"sha256:a"}]))
    T.check("oci_fill.upstream_429",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 429, ""}]))),
      T.acts([F.Fetch{"sha256:a"}, F.Reply{1, 429, "TOOMANYREQUESTS"}, F.Discard{"sha256:a"}]))
    T.check("oci_fill.upstream_500",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 500, ""}]))),
      T.acts([F.Fetch{"sha256:a"}, F.Reply{1, 502, ""}, F.Discard{"sha256:a"}]))
    T.check("oci_fill.upstream_503",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 503, ""}]))),
      T.acts([F.Fetch{"sha256:a"}, F.Reply{1, 502, ""}, F.Discard{"sha256:a"}]))
    T.check("oci_fill.upstream_no_response",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 0, ""}]))),
      T.acts([F.Fetch{"sha256:a"}, F.Reply{1, 502, ""}, F.Discard{"sha256:a"}]))
    T.check("oci_fill.no_length",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 200, ""}]))),
      T.acts([F.Fetch{"sha256:a"}, F.Reply{1, 502, ""}, F.Discard{"sha256:a"}]))
    T.check("oci_fill.broke_streaming",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 200, "3"}, F.Broke{"sha256:a"}]))),
      T.acts([F.Fetch{"sha256:a"}, F.Send{1, "sha256:a", "3"}, F.Abort{1}, F.Discard{"sha256:a"}]))
    T.check("oci_fill.broke_waiting",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Broke{"sha256:a"}]))),
      T.acts([F.Fetch{"sha256:a"}, F.Reply{1, 502, ""}, F.Discard{"sha256:a"}]))
    T.check("oci_fill.wait_24s",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Tick{24}]))),
      T.acts([F.Fetch{"sha256:a"}]))
    T.check("oci_fill.timeout_25s",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Tick{25}]))),
      T.acts([F.Fetch{"sha256:a"}, F.Reply{1, 504, ""}]))
    T.check("oci_fill.timeout_keeps_fill",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Tick{25}, F.Get{2, "sha256:a", True{}, False{}, False{}, 26}, F.Head{"sha256:a", 200, "3"}]))),
      T.acts([F.Fetch{"sha256:a"}, F.Reply{1, 504, ""}, F.Send{2, "sha256:a", "3"}]))
    T.check("oci_fill.no_timeout_streaming",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Head{"sha256:a", 200, "3"}, F.Tick{99}]))),
      T.acts([F.Fetch{"sha256:a"}, F.Send{1, "sha256:a", "3"}]))
    T.check("oci_fill.cap_per_digest",
      T.acts(F.Fill.acts(F.Fill.run(F.Limits{8, 1, 128, 25}, [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Get{2, "sha256:a", True{}, False{}, False{}, 0}]))),
      T.acts([F.Fetch{"sha256:a"}, F.Reply{2, 429, "TOOMANYREQUESTS"}]))
    T.check("oci_fill.cap_fills",
      T.acts(F.Fill.acts(F.Fill.run(F.Limits{1, 32, 128, 25}, [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Get{2, "sha256:b", True{}, False{}, False{}, 0}]))),
      T.acts([F.Fetch{"sha256:a"}, F.Reply{2, 429, "TOOMANYREQUESTS"}]))
    T.check("oci_fill.cap_conns",
      T.acts(F.Fill.acts(F.Fill.run(F.Limits{8, 32, 1, 25}, [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Get{2, "sha256:a", True{}, False{}, False{}, 0}]))),
      T.acts([F.Fetch{"sha256:a"}, F.Reply{2, 429, "TOOMANYREQUESTS"}]))
    T.check("oci_fill.gone",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Get{2, "sha256:a", True{}, False{}, False{}, 0}, F.Gone{1}, F.Head{"sha256:a", 200, "3"}]))),
      T.acts([F.Fetch{"sha256:a"}, F.Send{2, "sha256:a", "3"}]))
    T.check("oci_fill.gone_still_commits",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Gone{1}, F.Head{"sha256:a", 200, "3"}, F.Ended{"sha256:a", "sha256:a"}]))),
      T.acts([F.Fetch{"sha256:a"}, F.Commit{"sha256:a"}]))
    T.check("oci_fill.unknown_digest",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Head{"sha256:a", 200, "3"}, F.Ended{"sha256:a", "sha256:a"}, F.Broke{"sha256:a"}]))),
      T.acts([]))
    T.check("oci_fill.two_digests",
      T.acts(F.Fill.acts(F.Fill.run(F.Fill.limits(), [F.Get{1, "sha256:a", True{}, False{}, False{}, 0}, F.Get{2, "sha256:b", True{}, False{}, False{}, 0}, F.Head{"sha256:b", 404, ""}, F.Head{"sha256:a", 200, "3"}]))),
      T.acts([F.Fetch{"sha256:a"}, F.Fetch{"sha256:b"}, F.Reply{2, 404, "BLOB_UNKNOWN"}, F.Discard{"sha256:b"}, F.Send{1, "sha256:a", "3"}]))
