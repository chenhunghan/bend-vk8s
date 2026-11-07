import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/translate/services.bend as S
import ../src/translate/storage.bend as T

# Tests for src/translate/storage.bend. The laws in laws/storage.bend
# transcribe vcluster's syncer tests; these cover the rest: priority
# capping, priority classes from the host, claim storage classes, selectors,
# volume names and data sources with real volumes, claim deletion options,
# the recreate lock, real volume creation and locks, storage class and
# CSINode deletes, and fake volume claims. Expected values follow vcluster's
# Go code (VClusterName "suffix", target namespace "test", current
# namespace "vcluster", as in its tests). Objects print in canonical form:
# keys sorted by byte, zero values left out.

def cfg() -> S.Cfg:
  S.Cfg{"suffix", "test", "vcluster"}

def unwrap(r: Result<&2, &2, String, J.Json>) -> J.Json:
  match r:
    case Fail{e}:
      J.JStr{"parse error: " ++ e}
    case Done{x}:
      x

def js(s: String) -> J.Json:
  unwrap(J.Json.parse(s))

def show(j: J.Json) -> String:
  J.Json.show(S.Svc.canon(j))

def show_rq(r: S.Requeue) -> String:
  match r:
    case S.NoRequeue{}:
      "done"
    case S.RequeueNow{}:
      "requeue"
    case S.RequeueAfter{s}:
      "after " ++ U32.show(s)

def show_del(d: T.Del) -> String:
  match d:
    case T.Del{g, u}:
      " grace=" ++ show(g) ++ " uid=" ++ show(u)

def show_write(w: T.Write) -> String:
  match w:
    case T.HostCreate{o}:
      "host create"
    case T.HostUpdate{o}:
      "host update"
    case T.HostDelete{ns, n, d}:
      "host delete " ++ ns ++ "/" ++ n ++ show_del(d)
    case T.VirtualCreate{o}:
      "virtual create"
    case T.VirtualUpdate{o}:
      "virtual update"
    case T.VirtualDelete{ns, n, d}:
      "virtual delete " ++ ns ++ "/" ++ n ++ show_del(d)

def show_writes(ws: List<&2, T.Write>) -> String:
  match ws:
    case Nil{}:
      ""
    case Con{w, r}:
      show_write(w) ++ "; " ++ show_writes(r)

# The writes (kind and target), the requeue and the error of an outcome.
def show_out(o: T.Outcome) -> String:
  match o:
    case T.Outcome{ws, rq, e}:
      show_writes(ws) ++ show_rq(rq) ++ e

def write_obj(w: T.Write) -> J.Json:
  match w:
    case T.HostCreate{o}:
      o
    case T.HostUpdate{o}:
      o
    case T.HostDelete{ns, n, d}:
      J.JNull{}
    case T.VirtualCreate{o}:
      o
    case T.VirtualUpdate{o}:
      o
    case T.VirtualDelete{ns, n, d}:
      J.JNull{}

def nth_of(n: Nat, ws: List<&2, T.Write>) -> J.Json:
  match n ws:
    case _ Nil{}:
      J.JNull{}
    case 0n Con{w, r}:
      write_obj(w)
    case 1n+p Con{w, r}:
      nth_of(p, r)

# The object of the n-th write of an outcome (from 0).
def nth(n: Nat, o: T.Outcome) -> J.Json:
  match o:
    case T.Outcome{ws, rq, e}:
      nth_of(n, ws)

def first(o: T.Outcome) -> J.Json:
  nth(0n, o)

def at(+o: J.Json, path: List<&2, String>) -> String:
  show(J.Json.at(o, path))

def show_bool(b: Bool) -> String:
  match b:
    case True{}:
      "true"
    case False{}:
      "false"

def report(name: String, got: String, want: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name ++ ": got " ++ got ++ ", want " ++ want)

def check(name: String, +got: String, +want: String) -> IO(Unit):
  report(name, got, want, String.eq(got, want))

def pvc_cfg(classes: Bool, snapshots: Bool, fake: Bool) -> T.PvcCfg:
  T.PvcCfg{classes, snapshots, fake}

def look(limited: Bool, host_class: Bool) -> T.PvcLook:
  T.PvcLook{limited, host_class, None{}, "", "2026-11-05T00:00:00Z"}

def pc(v: String) -> J.Json:
  js("{\"metadata\":{\"name\":\"high\"},\"value\":" ++ v ++ ",\"globalDefault\":true}")

def pc_value(v: String) -> String:
  at(first(T.St.Pc.to_host(cfg(), T.PcCfg{True{}, False{}}, None{}, pc(v))), ["value"])

def pvc(spec: String) -> J.Json:
  js("{\"metadata\":{\"name\":\"c\",\"namespace\":\"ns1\"},\"spec\":" ++ spec ++ "}")

def pvc_spec(p: T.PvcCfg, host_class: Bool, spec: String) -> String:
  at(first(T.St.Pvc.to_host(cfg(), p, look(False{}, host_class), None{}, pvc(spec))), ["spec"])

def hpvc(meta: String) -> J.Json:
  js("{\"metadata\":{\"name\":\"c-x-ns1-x-suffix\",\"namespace\":\"test\"" ++ meta ++ "}}")

def vpvc(meta: String) -> J.Json:
  js("{\"metadata\":{\"name\":\"c\",\"namespace\":\"ns1\"" ++ meta ++ "}}")

def main() -> IO(Unit):
  do IO<Unit>:
    # Priority capping (priorityclasses/translate.go:15-17).
    check("priority above the cap is capped", pc_value("2000000000"), "1000000000")
    check("priority at the cap stays", pc_value("1000000000"), "1000000000")
    check("priority just above the cap is capped", pc_value("1000000001"), "1000000000")
    check("priority below the cap stays", pc_value("999999999"), "999999999")
    check("negative priority stays", pc_value("-2000000000"), "-2000000000")
    check("host priority class is never global default",
      at(first(T.St.Pc.to_host(cfg(), T.PcCfg{True{}, False{}}, None{}, pc("5"))), ["globalDefault"]), "null")
    check("host priority class name",
      at(first(T.St.Pc.to_host(cfg(), T.PcCfg{True{}, False{}}, None{}, pc("5"))), ["metadata", "name"]), "\"vcluster-high-x-test-x-suffix\"")
    # Sync with toHost: the host value follows the capped virtual value
    # (translate.go:55-59).
    check("update caps the host value",
      at(first(T.St.Pc.sync(cfg(), T.PcCfg{True{}, False{}}, True{}, js("{\"metadata\":{\"name\":\"vcluster-high-x-test-x-suffix\"},\"value\":5}"), js("{\"metadata\":{\"name\":\"vcluster-high-x-test-x-suffix\"},\"value\":5}"),
        js("{\"metadata\":{\"name\":\"high\"},\"value\":5}"), js("{\"metadata\":{\"name\":\"high\"},\"value\":2000000000}"))), ["value"]),
      "1000000000")
    # Sync with fromHost: the virtual class takes the host fields (translate.go:31-35).
    check("fromHost update copies the description",
      at(first(T.St.Pc.sync(cfg(), T.PcCfg{False{}, True{}}, True{}, js("{\"metadata\":{\"name\":\"p\"},\"description\":\"d\"}"), js("{\"metadata\":{\"name\":\"p\"},\"description\":\"d\"}"),
        js("{\"metadata\":{\"name\":\"p\"}}"), js("{\"metadata\":{\"name\":\"p\"}}"))), ["description"]),
      "\"d\"")
    # The selector deletes the virtual class in Sync (syncer.go:80-89) but
    # spares allow-listed classes.
    check("class failing the selector deletes the virtual class",
      show_out(T.St.Pc.sync(cfg(), T.PcCfg{False{}, True{}}, False{}, js("{\"metadata\":{\"name\":\"p\"}}"), js("{\"metadata\":{\"name\":\"p\"}}"), js("{\"metadata\":{\"name\":\"p\"}}"), js("{\"metadata\":{\"name\":\"p\"}}"))),
      "virtual delete /p grace=null uid=null; done")
    check("allow-listed class passes the selector",
      show_out(T.St.Pc.to_virtual(cfg(), T.PcCfg{False{}, True{}}, False{}, None{}, js("{\"metadata\":{\"name\":\"system-cluster-critical\"},\"value\":2000000000}"))),
      "virtual create; done")
    check("class failing the selector is not copied in",
      show_out(T.St.Pc.to_virtual(cfg(), T.PcCfg{False{}, True{}}, False{}, None{}, js("{\"metadata\":{\"name\":\"p\"}}"))),
      "done")
    # Claims: storage classes synced (translate.go:56-61). HostAnnotations
    # lists the deprecated annotation as managed before translateSelector
    # deletes it, so vcluster.loft.sh/managed-annotations still names it.
    check("synced class is translated and the deprecated annotation goes",
      show(nth(0n, T.St.Pvc.to_host(cfg(), pvc_cfg(True{}, False{}, True{}), look(False{}, True{}), None{},
        js("{\"metadata\":{\"name\":\"c\",\"namespace\":\"ns1\",\"annotations\":{\"volume.beta.kubernetes.io/storage-class\":\"fast\"}}}")))),
      "{\"metadata\":{\"annotations\":{\"vcluster.loft.sh/managed-annotations\":\"volume.beta.kubernetes.io/storage-class\",\"vcluster.loft.sh/object-host-name\":\"c-x-ns1-x-suffix\",\"vcluster.loft.sh/object-host-namespace\":\"test\",\"vcluster.loft.sh/object-kind\":\"/v1, Kind=PersistentVolumeClaim\",\"vcluster.loft.sh/object-name\":\"c\",\"vcluster.loft.sh/object-namespace\":\"ns1\",\"vcluster.loft.sh/object-uid\":\"\"},\"labels\":{\"vcluster.loft.sh/managed-by\":\"suffix\",\"vcluster.loft.sh/namespace\":\"ns1\"},\"name\":\"c-x-ns1-x-suffix\",\"namespace\":\"test\"},\"spec\":{\"storageClassName\":\"vcluster-fast-x-test-x-suffix\"}}")
    # Real volumes (translate.go:64-87).
    check("real volumes: volume name, selector and class are translated",
      pvc_spec(pvc_cfg(False{}, False{}, False{}), True{}, "{\"volumeName\":\"v1\",\"storageClassName\":\"fast\",\"selector\":{\"matchLabels\":{\"app\":\"a\"}}}"),
      "{\"selector\":{\"matchLabels\":{\"app\":\"a\"}},\"storageClassName\":\"vcluster-fast-x-test-x-suffix\",\"volumeName\":\"vcluster-v1-x-test-x-suffix\"}")
    check("real volumes: a dynamic claim keeps a class the host has",
      pvc_spec(pvc_cfg(False{}, False{}, False{}), True{}, "{\"storageClassName\":\"fast\"}"),
      "{\"storageClassName\":\"fast\"}")
    check("real volumes: a dynamic claim translates a class the host lacks",
      pvc_spec(pvc_cfg(False{}, False{}, False{}), False{}, "{\"storageClassName\":\"fast\"}"),
      "{\"storageClassName\":\"vcluster-fast-x-test-x-suffix\"}")
    check("fake volumes keep the volume name and class",
      pvc_spec(pvc_cfg(False{}, False{}, True{}), False{}, "{\"volumeName\":\"v1\",\"storageClassName\":\"fast\"}"),
      "{\"storageClassName\":\"fast\",\"volumeName\":\"v1\"}")
    check("skip-translate keeps the volume name",
      at(first(T.St.Pvc.to_host(cfg(), pvc_cfg(False{}, False{}, False{}), look(False{}, True{}), None{},
        js("{\"metadata\":{\"name\":\"c\",\"namespace\":\"ns1\",\"annotations\":{\"vcluster.loft.sh/skip-translate\":\"true\"}},\"spec\":{\"volumeName\":\"v1\",\"dataSource\":{\"kind\":\"PersistentVolumeClaim\",\"name\":\"src\"}}}"))), ["spec"]),
      "{\"dataSource\":{\"kind\":\"PersistentVolumeClaim\",\"name\":\"src\"},\"volumeName\":\"v1\"}")
    # Data sources (translate.go:20-43).
    check("claim data source and data source ref are translated",
      pvc_spec(pvc_cfg(False{}, False{}, True{}), True{}, "{\"dataSource\":{\"kind\":\"PersistentVolumeClaim\",\"name\":\"src\"},\"dataSourceRef\":{\"kind\":\"PersistentVolumeClaim\",\"name\":\"src\",\"namespace\":\"other\"}}"),
      "{\"dataSource\":{\"kind\":\"PersistentVolumeClaim\",\"name\":\"src-x-ns1-x-suffix\"},\"dataSourceRef\":{\"kind\":\"PersistentVolumeClaim\",\"name\":\"src-x-other-x-suffix\",\"namespace\":\"other\"}}")
    check("snapshot data source keeps its name unless snapshots sync",
      pvc_spec(pvc_cfg(False{}, False{}, True{}), True{}, "{\"dataSource\":{\"kind\":\"VolumeSnapshot\",\"name\":\"snap\"}}") ++ " " ++
        pvc_spec(pvc_cfg(False{}, True{}, True{}), True{}, "{\"dataSource\":{\"kind\":\"VolumeSnapshot\",\"name\":\"snap\"}}"),
      "{\"dataSource\":{\"kind\":\"VolumeSnapshot\",\"name\":\"snap\"}} {\"dataSource\":{\"kind\":\"VolumeSnapshot\",\"name\":\"snap-x-ns1-x-suffix\"}}")
    check("limited claim is skipped",
      show_out(T.St.Pvc.to_host(cfg(), pvc_cfg(False{}, False{}, True{}), look(True{}, True{}), None{}, pvc("{}"))), "done")
    check("seen host claim deletes the virtual claim with grace 0",
      show_out(T.St.Pvc.to_host(cfg(), pvc_cfg(False{}, False{}, True{}), look(False{}, True{}), Some{hpvc("")}, pvc("{}"))),
      "virtual delete ns1/c grace=0 uid=null; done")
    # Sync deletes (syncer.go:118-138).
    check("deleting host claim deletes the virtual claim with grace 30",
      show_out(T.St.Pvc.sync(cfg(), pvc_cfg(False{}, False{}, True{}), look(False{}, True{}), J.JNull{}, hpvc(",\"deletionTimestamp\":\"t\",\"deletionGracePeriodSeconds\":10"), J.JNull{}, vpvc(""))),
      "virtual delete ns1/c grace=30 uid=null; done")
    check("graces that differ delete the virtual claim with the host grace",
      show_out(T.St.Pvc.sync(cfg(), pvc_cfg(False{}, False{}, True{}), look(False{}, True{}), J.JNull{}, hpvc(",\"deletionTimestamp\":\"t\",\"deletionGracePeriodSeconds\":10"), J.JNull{}, vpvc(",\"uid\":\"u1\",\"deletionTimestamp\":\"t\",\"deletionGracePeriodSeconds\":30"))),
      "virtual delete ns1/c grace=10 uid=\"u1\"; done")
    check("equal graces wait",
      show_out(T.St.Pvc.sync(cfg(), pvc_cfg(False{}, False{}, True{}), look(False{}, True{}), J.JNull{}, hpvc(",\"deletionTimestamp\":\"t\",\"deletionGracePeriodSeconds\":10"), J.JNull{}, vpvc(",\"deletionTimestamp\":\"t\",\"deletionGracePeriodSeconds\":10"))),
      "done")
    # Recreate with a virtual volume to lock and finalizers to drop
    # (syncer.go:264-323).
    check("recreate locks the volume and drops finalizers",
      show_out(T.St.Pvc.sync(cfg(), pvc_cfg(False{}, False{}, True{}), T.PvcLook{False{}, True{}, Some{js("{\"metadata\":{\"name\":\"b\"}}")}, "", "2026-11-05T00:00:00Z"},
        J.JNull{}, js("{\"metadata\":{\"name\":\"c-x-ns1-x-suffix\",\"namespace\":\"test\"},\"spec\":{\"volumeName\":\"b\"}}"),
        J.JNull{}, js("{\"metadata\":{\"name\":\"c\",\"namespace\":\"ns1\",\"finalizers\":[\"f\"]},\"spec\":{\"volumeName\":\"a\"}}"))),
      "virtual update; virtual update; virtual delete ns1/c grace=null uid=null; virtual create; virtual update; requeue")
    check("lock annotation is the timestamp",
      at(first(T.St.Pvc.sync(cfg(), pvc_cfg(False{}, False{}, True{}), T.PvcLook{False{}, True{}, Some{js("{\"metadata\":{\"name\":\"b\"}}")}, "", "2026-11-05T00:00:00Z"},
        J.JNull{}, js("{\"metadata\":{\"name\":\"c-x-ns1-x-suffix\",\"namespace\":\"test\"},\"spec\":{\"volumeName\":\"b\"}}"),
        J.JNull{}, js("{\"metadata\":{\"name\":\"c\",\"namespace\":\"ns1\"},\"spec\":{\"volumeName\":\"a\"}}"))), ["metadata", "annotations"]),
      "{\"vcluster.loft.sh/lock\":\"2026-11-05T00:00:00Z\"}")
    check("real volumes: an unmapped host volume is an error",
      show_out(T.St.Pvc.sync(cfg(), pvc_cfg(False{}, False{}, False{}), look(False{}, True{}),
        J.JNull{}, js("{\"metadata\":{\"name\":\"c-x-ns1-x-suffix\",\"namespace\":\"test\"},\"spec\":{\"volumeName\":\"b\"}}"),
        J.JNull{}, js("{\"metadata\":{\"name\":\"c\",\"namespace\":\"ns1\"}}"))),
      "doneerror retrieving virtual persistent volume b: not found")
    check("unmanaged host claim is copied in",
      at(first(T.St.Pvc.to_virtual(cfg(), None{}, js("{\"metadata\":{\"name\":\"c-x-ns1-x-suffix\",\"namespace\":\"test\",\"annotations\":{\"vcluster.loft.sh/object-name\":\"c\",\"vcluster.loft.sh/object-namespace\":\"ns1\"}}}"))), ["metadata"]),
      "{\"name\":\"c\",\"namespace\":\"ns1\"}")
    # Real volumes, SyncToHost (persistentvolumes/translate.go:13-23, syncer.go:100-111).
    check("host volume clears the claim ref and translates the class",
      show(first(T.St.Pv.to_host(cfg(), False{}, None{}, js("{\"metadata\":{\"name\":\"v\"},\"spec\":{\"storageClassName\":\"fast\",\"claimRef\":{\"name\":\"c\"},\"hostPath\":{\"path\":\"/d\"}}}")))),
      "{\"metadata\":{\"annotations\":{\"vcluster.loft.sh/object-host-name\":\"vcluster-v-x-test-x-suffix\",\"vcluster.loft.sh/object-kind\":\"/v1, Kind=PersistentVolume\",\"vcluster.loft.sh/object-name\":\"v\",\"vcluster.loft.sh/object-uid\":\"\"},\"labels\":{\"vcluster.loft.sh/managed-by\":\"test-x-suffix\"},\"name\":\"vcluster-v-x-test-x-suffix\"},\"spec\":{\"hostPath\":{\"path\":\"/d\"},\"storageClassName\":\"vcluster-fast-x-test-x-suffix\"}}")
    check("volume from the host drops its finalizers first",
      show_out(T.St.Pv.to_host(cfg(), False{}, None{}, js("{\"metadata\":{\"name\":\"v\",\"finalizers\":[\"f\"],\"annotations\":{\"vcluster.loft.sh/host-pv\":\"v\"}}}"))),
      "virtual update; done")
    check("locked volume waits a second",
      show_out(T.St.Pv.sync(cfg(), False{}, T.PvLook{False{}, True{}, T.Unmapped{}}, J.JNull{}, J.JNull{}, J.JNull{}, js("{\"metadata\":{\"name\":\"v\"}}"))),
      "after 1")
    check("managed host volume goes",
      show_out(T.St.Pv.to_virtual(cfg(), T.Unmapped{}, js("{\"metadata\":{\"name\":\"vcluster-v-x-test-x-suffix\",\"labels\":{\"vcluster.loft.sh/managed-by\":\"test-x-suffix\"}}}"))),
      "host delete /vcluster-v-x-test-x-suffix grace=null uid=null; done")
    # Storage classes and CSINodes.
    check("deleting virtual storage class goes",
      show_out(T.St.Sc.to_host(cfg(), None{}, js("{\"metadata\":{\"name\":\"s\",\"deletionTimestamp\":\"t\"}}"))),
      "virtual delete /s grace=null uid=null; done")
    check("default-class annotation stays on virtual",
      at(first(T.St.Sc.to_host(cfg(), None{}, js("{\"metadata\":{\"name\":\"s\",\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"true\"}}}"))), ["metadata", "annotations", "storageclass.kubernetes.io/is-default-class"]),
      "null")
    check("host storage class without virtual goes",
      show_out(T.St.Sc.to_virtual(js("{\"metadata\":{\"name\":\"vcluster-s-x-test-x-suffix\"}}"))),
      "host delete /vcluster-s-x-test-x-suffix grace=null uid=null; done")
    check("marked CSINode without host goes",
      show_out(T.St.Csi.to_host(cfg(), None{}, js("{\"metadata\":{\"name\":\"n\",\"labels\":{\"vcluster.loft.sh/managed-by\":\"suffix\"}}}"))),
      "virtual delete /n grace=null uid=null; done")
    check("CSINode without the virtual node is not copied",
      show_out(T.St.Csi.to_virtual(False{}, js("{\"metadata\":{\"name\":\"n\"}}"))), "done")
    # Fake volumes.
    check("fake volume for the first claim that names it",
      at(first(T.St.Fake.to_virtual("v", [js("{\"metadata\":{\"name\":\"a\",\"namespace\":\"n\"},\"spec\":{\"volumeName\":\"w\"}}"),
        js("{\"metadata\":{\"name\":\"b\",\"namespace\":\"n\"},\"spec\":{\"volumeName\":\"v\",\"accessModes\":[\"ReadWriteOnce\"],\"resources\":{\"requests\":{\"storage\":\"1Gi\"}}}}"),
        js("{\"metadata\":{\"name\":\"c\",\"namespace\":\"n\"},\"spec\":{\"volumeName\":\"v\"}}")])), ["spec"]),
      "{\"accessModes\":[\"ReadWriteOnce\"],\"capacity\":{\"storage\":\"1Gi\"},\"claimRef\":{\"apiVersion\":\"v1\",\"kind\":\"PersistentVolumeClaim\",\"name\":\"b\",\"namespace\":\"n\"},\"flexVolume\":{\"driver\":\"fake\"},\"persistentVolumeReclaimPolicy\":\"Delete\"}")
    check("fake volume a claim names stays",
      show_out(T.St.Fake.sync(js("{\"metadata\":{\"name\":\"v\"}}"), [js("{\"spec\":{\"volumeName\":\"v\"}}")])), "done")
