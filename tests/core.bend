import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/sync/core.bend as C

# Tests for src/sync/core.bend. The laws in laws/core.bend transcribe
# vcluster's own tests; these cover the rest of the framework: the JSON merge
# patch (the examples of RFC 7386, appendix A, which evanphx/json-patch
# follows), the reconcile decision of syncer.go (UID guard, stale cache,
# skip-backsync, exclusion), the generic delete shapes, the status split of
# ApplyObjectPatch and the importer rule of enqueuePhysical. Expected values
# follow vcluster's Go code.

def pj.r(r: Result<&2, &2, String, J.Json>) -> J.Json:
  match r:
    case Fail{e}:
      J.JStr{"PARSE ERROR: " ++ e}
    case Done{j}:
      j

def pj(s: String) -> J.Json:
  pj.r(J.Json.parse(s))

def show_bool(b: Bool) -> String:
  match b:
    case True{}:
      "true"
    case False{}:
      "false"

def show_decision(d: C.Decision) -> String:
  match d:
    case C.DSkip{}:
      "skip"
    case C.DRequeue{}:
      "requeue"
    case C.DRequeueAfter{ms}:
      "requeue after " ++ U32.show(ms)
    case C.DDeleteHost{h, r}:
      "delete host: " ++ r
    case C.DSync{vo, v, po, p}:
      "sync"
    case C.DToHost{po, v}:
      "to host"
    case C.DToVirtual{vo, p}:
      "to virtual"

def show_side(s: C.Side) -> String:
  match s:
    case C.Host{}:
      "host"
    case C.Virtual{}:
      "virtual"

def show_write(w: C.Write) -> String:
  match w:
    case C.Create{s, o}:
      "create " ++ show_side(s) ++ " " ++ J.Json.show(o)
    case C.Patch{s, st, p}:
      "patch " ++ show_side(s) ++ " status=" ++ show_bool(st) ++ " " ++ J.Json.show(p)
    case C.Delete{s, o, r}:
      "delete " ++ show_side(s) ++ " " ++ C.Core.name(o) ++ " (" ++ r ++ ")"

def show_writes(ws: List<&2, C.Write>) -> String:
  match ws:
    case Nil{}:
      ""
    case Con{w, r}:
      show_write(w) ++ "; " ++ show_writes(r)

def show_again(a: C.Again) -> String:
  match a:
    case C.Settled{}:
      "settled"
    case C.AgainNow{}:
      "requeue"
    case C.AgainAfter{ms}:
      "requeue after " ++ U32.show(ms)

def show_out(o: C.Out) -> String:
  match o:
    case C.Out{ws, a}:
      "[" ++ show_writes(ws) ++ "] " ++ show_again(a)

def report(name: String, got: String, want: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name ++ ": got " ++ got ++ ", want " ++ want)

def check(name: String, +got: String, +want: String) -> IO(Unit):
  report(name, got, want, String.eq(got, want))

# A JSON result against an expected document (order-free).
def check_json(name: String, +got: J.Json, +want: String) -> IO(Unit):
  report(name, J.Json.show(got), want, C.Core.json_same(got, pj(want)))

# MergePatch(doc, patch).
def merge(doc: String, patch: String) -> J.Json:
  C.Core.apply_patch(pj(doc), pj(patch))

# CreateMergePatch then MergePatch gives the target back.
def round_trip(+a: String, +b: String) -> Bool:
  C.Core.json_same(C.Core.apply_patch(pj(a), C.Core.merge_patch(pj(a), pj(b))), pj(b))

def cfg() -> C.Cfg:
  C.Cfg{"suffix", "test", "/v1, Kind=Secret", "secrets", True{}, True{}, False{}}

def cfg_nouid() -> C.Cfg:
  C.Cfg{"suffix", "test", "/v1, Kind=Secret", "secrets", True{}, False{}, False{}}

def cfg_fh() -> C.Cfg:
  C.Cfg{"suffix", "test", "/v1, Kind=ConfigMap", "from-host-configmap", True{}, True{}, True{}}

def v1() -> J.Json:
  pj("{\"metadata\":{\"name\":\"a\",\"namespace\":\"default\",\"uid\":\"123\",\"resourceVersion\":\"10\"}}")

def host_uid(uid: String, extra: String) -> J.Json:
  pj("{\"metadata\":{\"name\":\"a-x-default-x-suffix\",\"namespace\":\"test\",\"resourceVersion\":\"10\"" ++ extra ++ ",\"annotations\":{\"vcluster.loft.sh/object-uid\":\"" ++ uid ++ "\"}}}")

def host_plain(rv: String, extra: String) -> J.Json:
  pj("{\"metadata\":{\"name\":\"a-x-default-x-suffix\",\"namespace\":\"test\",\"resourceVersion\":\"" ++ rv ++ "\"" ++ extra ++ "}}")

def main() -> IO(Unit):
  do IO<Unit>:
    # RFC 7386 appendix A.
    check_json("merge replace", merge("{\"a\":\"b\"}", "{\"a\":\"c\"}"), "{\"a\":\"c\"}")
    check_json("merge add", merge("{\"a\":\"b\"}", "{\"b\":\"c\"}"), "{\"a\":\"b\",\"b\":\"c\"}")
    check_json("merge remove", merge("{\"a\":\"b\"}", "{\"a\":null}"), "{}")
    check_json("merge remove one", merge("{\"a\":\"b\",\"b\":\"c\"}", "{\"a\":null}"), "{\"b\":\"c\"}")
    check_json("merge array by string", merge("{\"a\":[\"b\"]}", "{\"a\":\"c\"}"), "{\"a\":\"c\"}")
    check_json("merge string by array", merge("{\"a\":\"c\"}", "{\"a\":[\"b\"]}"), "{\"a\":[\"b\"]}")
    check_json("merge nested", merge("{\"a\":{\"b\":\"c\"}}", "{\"a\":{\"b\":\"d\",\"c\":null}}"), "{\"a\":{\"b\":\"d\"}}")
    check_json("merge array of objects", merge("{\"a\":[{\"b\":\"c\"}]}", "{\"a\":[1]}"), "{\"a\":[1]}")
    check_json("merge arrays", merge("[\"a\",\"b\"]", "[\"c\",\"d\"]"), "[\"c\",\"d\"]")
    check_json("merge object by array", merge("{\"a\":\"b\"}", "[\"c\"]"), "[\"c\"]")
    check_json("merge object by null", merge("{\"a\":\"foo\"}", "null"), "null")
    check_json("merge object by string", merge("{\"a\":\"foo\"}", "\"bar\""), "\"bar\"")
    check_json("merge keeps null member", merge("{\"e\":null}", "{\"a\":1}"), "{\"e\":null,\"a\":1}")
    check_json("merge array by object", merge("[1,2]", "{\"a\":\"b\",\"c\":null}"), "{\"a\":\"b\"}")
    check_json("merge prunes new nulls", merge("{}", "{\"a\":{\"bb\":{\"ccc\":null}}}"), "{\"a\":{\"bb\":{}}}")
    # CreateMergePatch.
    check_json("diff add change remove", C.Core.merge_patch(pj("{\"a\":1,\"b\":{\"c\":2,\"d\":3},\"e\":4}"), pj("{\"a\":1,\"b\":{\"c\":5,\"d\":3},\"f\":6}")),
      "{\"b\":{\"c\":5},\"f\":6,\"e\":null}")
    check_json("diff equal", C.Core.merge_patch(pj("{\"a\":{\"b\":[1,2]}}"), pj("{\"a\":{\"b\":[1,2]}}")), "{}")
    check_json("diff type change", C.Core.merge_patch(pj("{\"a\":{\"b\":1}}"), pj("{\"a\":[1]}")), "{\"a\":[1]}")
    check_json("diff object from null", C.Core.merge_patch(pj("{\"a\":null}"), pj("{\"a\":{\"b\":1}}")), "{\"a\":{\"b\":1}}")
    check("diff round trip", show_bool(round_trip("{\"a\":{\"b\":{\"c\":1,\"d\":[1]}},\"x\":\"y\"}", "{\"a\":{\"b\":{\"d\":[2]},\"e\":true},\"z\":\"w\"}")), "true")
    # CalculateMergePatch keeps only annotations, labels and finalizers
    # under metadata.
    check_json("calc patch metadata", C.Core.calc_patch(pj("{\"metadata\":{\"resourceVersion\":\"1\",\"labels\":{\"a\":\"1\"}},\"spec\":{\"x\":1}}"),
      pj("{\"metadata\":{\"resourceVersion\":\"2\",\"labels\":{\"a\":\"2\"},\"finalizers\":[\"f\"]},\"spec\":{\"x\":2}}")),
      "{\"metadata\":{\"labels\":{\"a\":\"2\"},\"finalizers\":[\"f\"]},\"spec\":{\"x\":2}}")
    # ApplyObject: a resourceVersion-only change writes nothing; status goes
    # to the status subresource when the kind has one.
    check("apply rv only", show_writes(C.Core.apply_object(C.Host{}, pj("{\"metadata\":{\"resourceVersion\":\"1\"}}"), pj("{\"metadata\":{\"resourceVersion\":\"2\"}}"), True{})), "")
    check("apply status split", show_writes(C.Core.apply_object(C.Host{}, pj("{\"spec\":{\"a\":1},\"status\":{\"b\":1}}"), pj("{\"spec\":{\"a\":2},\"status\":{\"b\":2}}"), True{})),
      "patch host status=false {\"spec\":{\"a\":2}}; patch host status=true {\"status\":{\"b\":2}}; ")
    check("apply no status subresource", show_writes(C.Core.apply_object(C.Host{}, pj("{\"status\":{\"b\":1}}"), pj("{\"status\":{\"b\":2}}"), False{})),
      "patch host status=false {\"status\":{\"b\":2}}; ")
    # CopyBidirectional and MergeBidirectional.
    check("copy virtual changed", J.Json.show(Pair.snd(J.Json, J.Json, C.Core.copy_bidirectional(pj("1"), pj("2"), pj("1"), pj("3")))), "2")
    check("copy host changed", J.Json.show(Pair.fst(J.Json, J.Json, C.Core.copy_bidirectional(pj("1"), pj("1"), pj("1"), pj("3")))), "3")
    check_json("merge virtual changed", Pair.snd(J.Json, J.Json, C.Core.merge_bidirectional(pj("{\"a\":1}"), pj("{\"a\":2}"), pj("{\"a\":1}"), pj("{\"a\":1,\"b\":1}"))), "{\"a\":2,\"b\":1}")
    check_json("merge host changed", Pair.fst(J.Json, J.Json, C.Core.merge_bidirectional(pj("{\"a\":1,\"c\":1}"), pj("{\"a\":1,\"c\":1}"), pj("{\"a\":1}"), pj("{\"a\":3}"))), "{\"a\":3,\"c\":1}")
    check_json("merge into nil", Pair.snd(J.Json, J.Json, C.Core.merge_bidirectional(pj("{\"a\":1}"), pj("{\"a\":2}"), pj("null"), pj("null"))), "{\"a\":2}")
    # The reconcile decision.
    check("decide sync", show_decision(C.Core.decide(cfg(), True{}, None{}, Some{v1()}, None{}, Some{host_plain("10", "")})), "sync")
    check("decide to host", show_decision(C.Core.decide(cfg(), True{}, None{}, Some{v1()}, None{}, None{})), "to host")
    check("decide to virtual", show_decision(C.Core.decide(cfg(), True{}, None{}, None{}, None{}, Some{host_plain("10", "")})), "to virtual")
    check("decide uid clash", show_decision(C.Core.decide(cfg(), True{}, None{}, Some{v1()}, None{}, Some{host_uid("999", "")})), "delete host: virtual object uid is different")
    check("decide uid same", show_decision(C.Core.decide(cfg(), True{}, None{}, Some{v1()}, None{}, Some{host_uid("123", "")})), "sync")
    check("decide uid clash deleting", show_decision(C.Core.decide(cfg(), True{}, None{}, Some{v1()}, None{}, Some{host_uid("999", ",\"deletionTimestamp\":\"2024-01-01T00:00:00Z\"")})), "requeue after 1000")
    check("decide uid deletion disabled", show_decision(C.Core.decide(cfg_nouid(), True{}, None{}, Some{v1()}, None{}, Some{host_uid("999", "")})), "sync")
    check("decide stale host cache", show_decision(C.Core.decide(cfg(), True{}, None{}, Some{v1()}, Some{host_plain("11", "")}, Some{host_plain("9", "")})), "requeue")
    check("decide stale host cache numeric", show_decision(C.Core.decide(cfg(), True{}, None{}, Some{v1()}, Some{host_plain("9", "")}, Some{host_plain("10", "")})), "sync")
    check("decide stale virtual cache", show_decision(C.Core.decide(cfg(), True{}, Some{pj("{\"metadata\":{\"resourceVersion\":\"100\"}}")}, Some{v1()}, None{}, None{})), "requeue")
    check("decide skip backsync", show_decision(C.Core.decide(cfg(), True{}, None{}, None{}, None{}, Some{host_plain("10", ",\"annotations\":{\"vcluster.loft.sh/skip-backsync\":\"true\"}")})), "skip")
    check("decide unmanaged", show_decision(C.Core.decide(cfg(), False{}, None{}, Some{v1()}, None{}, Some{host_plain("10", "")})), "skip")
    check("decide controlled host", show_decision(C.Core.decide(cfg(), True{}, None{}, None{}, None{}, Some{host_plain("10", ",\"labels\":{\"vcluster.loft.sh/controlled-by\":\"x\"}")})), "skip")
    check("decide controlled by this syncer", show_decision(C.Core.decide(cfg(), True{}, None{}, None{}, None{}, Some{host_plain("10", ",\"annotations\":{\"vcluster.loft.sh/controlled-by\":\"secrets\"}")})), "to virtual")
    check("decide controlled virtual", show_decision(C.Core.decide(cfg(), True{}, None{}, Some{pj("{\"metadata\":{\"name\":\"a\",\"annotations\":{\"vcluster.loft.sh/controlled-by\":\"other\"}}}")}, None{}, None{})), "skip")
    check("decide from host marker", show_decision(C.Core.decide(cfg_fh(), True{}, None{}, None{}, None{}, Some{host_plain("10", ",\"labels\":{\"vcluster.loft.sh/managed-by\":\"suffix\"}")})), "skip")
    check("decide from host controlled virtual", show_decision(C.Core.decide(cfg_fh(), True{}, None{}, Some{pj("{\"metadata\":{\"name\":\"a\",\"labels\":{\"vcluster.loft.sh/controlled-by\":\"x\"}}}")}, None{}, None{})), "to host")
    # The generic delete shapes.
    check("to host: host gone", show_out(C.Core.to_host.create(cfg(), Some{host_plain("10", "")}, v1())), "[delete virtual a (host object was deleted); ] settled")
    check("to host: virtual deleting", show_out(C.Core.to_host.create(cfg(), None{}, pj("{\"metadata\":{\"name\":\"a\",\"namespace\":\"default\",\"deletionTimestamp\":\"2024-01-01T00:00:00Z\"}}"))), "[delete virtual a (host object was deleted); ] settled")
    check("to virtual: virtual gone", show_out(C.Core.to_host.back(cfg(), Some{v1()}, host_plain("10", ""))), "[delete host a-x-default-x-suffix (virtual object was deleted); ] settled")
    check("to virtual: unsynced host stays", show_out(C.Core.to_host.back(cfg(), None{}, host_plain("10", ""))), "[] settled")
    check("to virtual: synced host goes", show_out(C.Core.to_host.back(cfg(), None{}, host_plain("10", ",\"annotations\":{\"vcluster.loft.sh/object-kind\":\"/v1, Kind=Secret\",\"vcluster.loft.sh/object-name\":\"a\",\"vcluster.loft.sh/object-namespace\":\"default\",\"vcluster.loft.sh/object-host-name\":\"a-x-default-x-suffix\",\"vcluster.loft.sh/object-host-namespace\":\"test\"}"))),
      "[delete host a-x-default-x-suffix (virtual object was deleted); ] settled")
    check("uid delete outcome", show_out(C.Core.reconcile_to_host(cfg(), ["data"], True{}, None{}, Some{v1()}, None{}, Some{host_uid("999", "")})), "[delete host a-x-default-x-suffix (virtual object uid is different); ] settled")
    check("from host: host gone", show_out(C.Core.from_host.to_host(Some{host_plain("10", "")}, v1())), "[delete virtual a (); ] settled")
    check("from host: host deleting", show_out(C.Core.from_host.to_virtual(cfg_fh(), Some{v1()}, host_plain("10", ",\"deletionTimestamp\":\"2024-01-01T00:00:00Z\""), "a", "default", C.NsReady{})),
      "[delete virtual a (host object was deleted); ] settled")
    check("from host: namespace terminating", show_out(C.Core.from_host.to_virtual(cfg_fh(), None{}, host_plain("10", ""), "a", "default", C.NsTerminating{})), "[] requeue after 5000")
    # enqueuePhysical and the importer.
    check("enqueue managed", show_bool(C.Core.enqueue_host(True{}, True{}, False{}, False{}, v1())), "true")
    check("enqueue imported", show_bool(C.Core.enqueue_host(True{}, False{}, True{}, False{}, v1())), "true")
    check("enqueue imported on delete", show_bool(C.Core.enqueue_host(True{}, False{}, True{}, True{}, v1())), "false")
    check("enqueue no virtual name", show_bool(C.Core.enqueue_host(False{}, True{}, False{}, False{}, v1())), "false")
    check("from host managed", show_bool(C.Core.is_managed_from_host(True{}, host_plain("10", ""))), "true")
    check("from host marker not managed", show_bool(C.Core.is_managed_from_host(True{}, host_plain("10", ",\"labels\":{\"vcluster.loft.sh/managed-by\":\"\"}"))), "false")
    check("to host managed by store", show_bool(C.Core.is_managed_to_host(cfg(), True{}, None{}, host_plain("10", ""))), "true")
    check("to host not managed", show_bool(C.Core.is_managed_to_host(cfg(), False{}, None{}, host_plain("10", ""))), "false")
    check("to host managed by marker", show_bool(C.Core.is_managed_to_host(cfg(), False{}, None{}, host_plain("10", ",\"labels\":{\"vcluster.loft.sh/managed-by\":\"suffix\"},\"annotations\":{\"vcluster.loft.sh/object-name\":\"a\"}"))), "true")
