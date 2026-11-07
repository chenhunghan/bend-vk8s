import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/translate/names.bend as N
import ../src/translate/services.bend as S
import ../src/translate/storage.bend as T

# Spec for src/translate/storage.bend (vcluster
# pkg/controllers/resources/persistentvolumeclaims, persistentvolumes,
# storageclasses, priorityclasses, csinodes).
#
# The concrete laws transcribe every case of
# persistentvolumeclaims/syncer_test.go, persistentvolumes/syncer_test.go,
# persistentvolumes/fake_syncer_test.go, storageclasses/syncer_test.go,
# priorityclasses/syncer_test.go and csinodes/syncer_test.go (vcluster
# a8ab30e); these packages have no translate tests. Inputs are the tests'
# objects and events, expected objects the tests' expected states.
# vcluster's tests run with VClusterName "suffix", target namespace "test"
# and current namespace "vcluster".
#
# Objects compare in canonical form (T.St.canon_outcome), as the tests compare
# YAML. The test harness (pkg/syncer/testing/testing.go:204-248) strips the
# resource version, the UID and the vcluster.loft.sh/managed-by label before
# it compares: the laws leave out resource versions the fake client sets,
# and keep the managed-by label as vcluster's HostLabelsMap writes it (on a
# cluster-scoped host object that is the cluster marker "test-x-suffix").
# A deletion timestamp (time.Now() in the tests) is a fixed text here.
# Where the syncer reads a cluster (the virtual claim of a volume, the
# virtual node of a CSINode, the selector result), the law passes what the
# test's fake clients hold. NewSyncEvent leaves the old objects nil: those
# steps return before reading them, and the laws pass null.

# Test fixtures.

def Laws.storage.cfg() -> S.Cfg:
  S.Cfg{"suffix", "test", "vcluster"}

def Laws.storage.str(k: String, v: String) -> J.KV:
  J.KV{k, J.JStr{v}}

def Laws.storage.num(k: String, v: String) -> J.KV:
  J.KV{k, J.JNum{v}}

def Laws.storage.obj(k: String, fs: List<&2, J.KV>) -> J.KV:
  J.KV{k, J.Json.obj(fs)}

def Laws.storage.arr(k: String, xs: List<&2, J.Json>) -> J.KV:
  J.KV{k, J.Json.arr(xs)}

def Laws.storage.out(ws: List<&2, T.Write>) -> T.Outcome:
  T.St.canon_outcome(T.Outcome{ws, S.NoRequeue{}, ""})

# metav1.ObjectMeta{Name, Namespace, Labels, Annotations}.
def Laws.storage.meta(name: String, ns: String, labels: List<&2, J.KV>, annotations: List<&2, J.KV>) -> J.KV:
  Laws.storage.obj("metadata", [Laws.storage.str("name", name), Laws.storage.str("namespace", ns), Laws.storage.obj("labels", labels), Laws.storage.obj("annotations", annotations)])

# metav1.ObjectMeta{Name, Labels, Annotations} of a cluster-scoped object.
def Laws.storage.cmeta(name: String, labels: List<&2, J.KV>, annotations: List<&2, J.KV>) -> J.KV:
  Laws.storage.obj("metadata", [Laws.storage.str("name", name), Laws.storage.obj("labels", labels), Laws.storage.obj("annotations", annotations)])

# The deletion timestamp of the tests' deleting objects.
def Laws.storage.now() -> J.KV:
  Laws.storage.str("deletionTimestamp", "2026-11-05T00:00:00Z")

def Laws.storage.no_old() -> J.Json:
  J.JNull{}

def Laws.storage.nodel() -> T.Del:
  T.Del{J.JNull{}, J.JNull{}}

# persistentvolumeclaims/syncer_test.go fixtures.

def Laws.storage.pvc_cfg() -> T.PvcCfg:
  T.PvcCfg{False{}, False{}, True{}}

def Laws.storage.pvc_look() -> T.PvcLook:
  T.PvcLook{False{}, True{}, None{}, "", "2026-11-05T00:00:00Z"}

def Laws.storage.pvc_name() -> String:
  "testpvc-x-testns-x-suffix"

def Laws.storage.pvc_ann() -> List<&2, J.KV>:
  [Laws.storage.str("vcluster.loft.sh/object-name", "testpvc"),
   Laws.storage.str("vcluster.loft.sh/object-namespace", "testns"),
   Laws.storage.str("vcluster.loft.sh/object-uid", ""),
   Laws.storage.str("vcluster.loft.sh/object-kind", "/v1, Kind=PersistentVolumeClaim"),
   Laws.storage.str("vcluster.loft.sh/object-host-namespace", "test"),
   Laws.storage.str("vcluster.loft.sh/object-host-name", Laws.storage.pvc_name())]

def Laws.storage.pvc_labels() -> List<&2, J.KV>:
  [Laws.storage.str("vcluster.loft.sh/managed-by", "suffix"), Laws.storage.str("vcluster.loft.sh/namespace", "testns")]

# vObjectMeta
def Laws.storage.pvc_vmeta() -> J.KV:
  Laws.storage.meta("testpvc", "testns", [], [])

# pObjectMeta
def Laws.storage.pvc_pmeta() -> J.KV:
  Laws.storage.meta(Laws.storage.pvc_name(), "test", Laws.storage.pvc_labels(), Laws.storage.pvc_ann())

# basePvc
def Laws.storage.base_pvc() -> J.Json:
  J.Json.obj([Laws.storage.pvc_vmeta()])

# createdPvc
def Laws.storage.created_pvc() -> J.Json:
  J.Json.obj([Laws.storage.pvc_pmeta()])

# deletePvc
def Laws.storage.delete_pvc() -> J.Json:
  J.Json.obj([Laws.storage.obj("metadata", [Laws.storage.str("name", "testpvc"), Laws.storage.str("namespace", "testns"),
    Laws.storage.arr("finalizers", [J.JStr{"kubernetes"}]), Laws.storage.now()])])

# changedResources: Requests{"storage": Quantity{Format: "teststoragerequest"}},
# whose JSON is the zero quantity "0".
def Laws.storage.changed_resources() -> J.KV:
  Laws.storage.obj("spec", [Laws.storage.obj("resources", [Laws.storage.obj("requests", [Laws.storage.str("storage", "0")])])])

def Laws.storage.other_ann() -> J.KV:
  Laws.storage.str("otherAnnotationKey", "update this")

# updatePvc
def Laws.storage.update_pvc() -> J.Json:
  J.Json.obj([Laws.storage.meta("testpvc", "testns", [], [Laws.storage.other_ann()]), Laws.storage.changed_resources()])

# updatePvc with its annotations set to nil (vObjOld of "Update forward").
def Laws.storage.update_pvc_old() -> J.Json:
  J.Json.obj([Laws.storage.pvc_vmeta(), Laws.storage.changed_resources()])

# updatedPvc
def Laws.storage.updated_pvc() -> J.Json:
  J.Json.obj([Laws.storage.meta(Laws.storage.pvc_name(), "test", Laws.storage.pvc_labels(),
    List.append(&2, J.KV, Laws.storage.pvc_ann(), [Laws.storage.other_ann()])), Laws.storage.changed_resources()])

def Laws.storage.bind_ann() -> List<&2, J.KV>:
  [Laws.storage.str("pv.kubernetes.io/bind-completed", "testannotation"),
   Laws.storage.str("pv.kubernetes.io/bound-by-controller", "testannotation2"),
   Laws.storage.str("volume.beta.kubernetes.io/storage-provisioner", "testannotation3")]

# backwardUpdateAnnotationsPvc
def Laws.storage.backward_ann_pvc() -> J.Json:
  J.Json.obj([Laws.storage.meta(Laws.storage.pvc_name(), "test", Laws.storage.pvc_labels(),
    List.append(&2, J.KV, Laws.storage.pvc_ann(), Laws.storage.bind_ann()))])

# backwardUpdatedAnnotationsPvc
def Laws.storage.backward_anned_pvc() -> J.Json:
  J.Json.obj([Laws.storage.meta("testpvc", "testns", [], Laws.storage.bind_ann())])

def Laws.storage.myvolume() -> J.KV:
  Laws.storage.obj("spec", [Laws.storage.str("volumeName", "myvolume")])

def Laws.storage.testmode() -> J.KV:
  Laws.storage.obj("status", [Laws.storage.arr("accessModes", [J.JStr{"testmode"}])])

# backwardUpdateStatusPvc
def Laws.storage.backward_status_pvc() -> J.Json:
  J.Json.obj([Laws.storage.pvc_pmeta(), Laws.storage.myvolume(), Laws.storage.testmode()])

# backwardUpdatedStatusPvc
def Laws.storage.backward_statused_pvc() -> J.Json:
  J.Json.obj([Laws.storage.pvc_vmeta(), Laws.storage.myvolume(), Laws.storage.testmode()])

def Laws.storage.volume(n: String) -> J.KV:
  Laws.storage.obj("spec", [Laws.storage.str("volumeName", n)])

# persistentvolumeclaims/syncer_test.go TestSync.

# "Create forward": SyncToHost(basePvc).
law storage.pvc_create_forward:
  {T.St.canon_outcome(T.St.Pvc.to_host(Laws.storage.cfg(), Laws.storage.pvc_cfg(), Laws.storage.pvc_look(), None{}, Laws.storage.base_pvc()))
    == Laws.storage.out([T.HostCreate{Laws.storage.created_pvc()}]) : T.Outcome}

# "Delete forward with create function": SyncToHost(deletePvc) deletes the
# virtual claim with grace period 0.
law storage.pvc_delete_forward_create:
  {T.St.canon_outcome(T.St.Pvc.to_host(Laws.storage.cfg(), Laws.storage.pvc_cfg(), Laws.storage.pvc_look(), None{}, Laws.storage.delete_pvc()))
    == Laws.storage.out([T.VirtualDelete{"testns", "testpvc", T.Del{J.JNum{"0"}, J.JNull{}}}]) : T.Outcome}

# "Update forward":
# Sync(NewSyncEventWithOld(createdPvc, createdPvc, updatePvc without annotations, updatePvc)).
law storage.pvc_update_forward:
  {T.St.canon_outcome(T.St.Pvc.sync(Laws.storage.cfg(), Laws.storage.pvc_cfg(), Laws.storage.pvc_look(), Laws.storage.created_pvc(), Laws.storage.created_pvc(), Laws.storage.update_pvc_old(), Laws.storage.update_pvc()))
    == Laws.storage.out([T.HostUpdate{Laws.storage.updated_pvc()}]) : T.Outcome}

# "Update forward not needed":
# Sync(NewSyncEventWithOld(createdPvc, createdPvc, basePvc, basePvc)).
law storage.pvc_update_forward_not_needed:
  {T.St.canon_outcome(T.St.Pvc.sync(Laws.storage.cfg(), Laws.storage.pvc_cfg(), Laws.storage.pvc_look(), Laws.storage.created_pvc(), Laws.storage.created_pvc(), Laws.storage.base_pvc(), Laws.storage.base_pvc()))
    == Laws.storage.out([]) : T.Outcome}

# "Delete forward with update function": Sync(NewSyncEvent(createdPvc,
# deletePvc)) deletes the host claim with the virtual grace period (nil)
# and the host UID ("") as precondition.
law storage.pvc_delete_forward_update:
  {T.St.canon_outcome(T.St.Pvc.sync(Laws.storage.cfg(), Laws.storage.pvc_cfg(), Laws.storage.pvc_look(), Laws.storage.no_old(), Laws.storage.created_pvc(), Laws.storage.no_old(), Laws.storage.delete_pvc()))
    == Laws.storage.out([T.HostDelete{"test", Laws.storage.pvc_name(), T.Del{J.JNull{}, J.JStr{""}}}]) : T.Outcome}

# "Update backwards new annotations":
# Sync(NewSyncEventWithOld(backwardUpdateAnnotationsPvc x2, basePvc x2)).
law storage.pvc_backward_annotations:
  {T.St.canon_outcome(T.St.Pvc.sync(Laws.storage.cfg(), Laws.storage.pvc_cfg(), Laws.storage.pvc_look(), Laws.storage.backward_ann_pvc(), Laws.storage.backward_ann_pvc(), Laws.storage.base_pvc(), Laws.storage.base_pvc()))
    == Laws.storage.out([T.VirtualUpdate{Laws.storage.backward_anned_pvc()}]) : T.Outcome}

# "Update backwards new status" (fake volumes):
# Sync(NewSyncEventWithOld(backwardUpdateStatusPvc x2, basePvc x2)).
law storage.pvc_backward_status:
  {T.St.canon_outcome(T.St.Pvc.sync(Laws.storage.cfg(), Laws.storage.pvc_cfg(), Laws.storage.pvc_look(), Laws.storage.backward_status_pvc(), Laws.storage.backward_status_pvc(), Laws.storage.base_pvc(), Laws.storage.base_pvc()))
    == Laws.storage.out([T.VirtualUpdate{Laws.storage.backward_statused_pvc()}]) : T.Outcome}

# "Recreate pvc if volume name is different" (fake volumes, no virtual
# volume "test2"): Sync(NewSyncEvent(host claim of volume test2, virtual
# claim of volume test)) recreates the virtual claim and requeues.
law storage.pvc_recreate:
  {T.St.canon_outcome(T.St.Pvc.sync(Laws.storage.cfg(), Laws.storage.pvc_cfg(), Laws.storage.pvc_look(), Laws.storage.no_old(), J.Json.obj([Laws.storage.pvc_pmeta(), Laws.storage.volume("test2")]), Laws.storage.no_old(), J.Json.obj([Laws.storage.pvc_vmeta(), Laws.storage.volume("test")])))
    == T.St.canon_outcome(T.Outcome{[T.VirtualDelete{"testns", "testpvc", Laws.storage.nodel()}, T.VirtualCreate{J.Json.obj([Laws.storage.pvc_vmeta(), Laws.storage.volume("test2")])}], S.RequeueNow{}, ""}) : T.Outcome}

# persistentvolumes/syncer_test.go fixtures (sync.toHost.persistentVolumes
# enabled).

def Laws.storage.pv_look(c: T.Claim) -> T.PvLook:
  T.PvLook{False{}, False{}, c}

# basePvc, as the fake client returns it.
def Laws.storage.pv_pvc() -> J.Json:
  J.Json.obj([Laws.storage.obj("metadata", [Laws.storage.str("name", "testpvc"), Laws.storage.str("namespace", "test"), Laws.storage.str("resourceVersion", "999")])])

# basePvObjectMeta
def Laws.storage.pv_meta() -> J.KV:
  Laws.storage.cmeta("testpv", [], [Laws.storage.str("vcluster.loft.sh/host-pv", "testpv")])

# backwardPvObjectMeta
def Laws.storage.pv_bmeta() -> J.KV:
  Laws.storage.cmeta("testpv", [], [Laws.storage.str("vcluster.loft.sh/host-pv", "testpv"),
    Laws.storage.str("vcluster.loft.sh/object-host-name", "testpv"),
    Laws.storage.str("vcluster.loft.sh/object-kind", "/v1, Kind=PersistentVolume"),
    Laws.storage.str("vcluster.loft.sh/object-name", "testpv"),
    Laws.storage.str("vcluster.loft.sh/object-uid", "")])

# basePvWithDelTSObjectMeta
def Laws.storage.pv_dmeta() -> J.KV:
  Laws.storage.obj("metadata", [Laws.storage.str("name", "testpv"), Laws.storage.arr("finalizers", [J.JStr{"kubernetes"}]), Laws.storage.now()])

def Laws.storage.ref(name: String, ns: String, rv: List<&2, J.KV>) -> J.KV:
  Laws.storage.obj("claimRef", List.append(&2, J.KV, [Laws.storage.str("name", name), Laws.storage.str("namespace", ns)], rv))

def Laws.storage.rv() -> List<&2, J.KV>:
  [Laws.storage.str("resourceVersion", "999")]

# basePPvcReference
def Laws.storage.pref() -> J.KV:
  Laws.storage.ref("testpvc-x-test-x-suffix", "test", Laws.storage.rv())

# baseVPvcReference
def Laws.storage.vref() -> J.KV:
  Laws.storage.ref("testpvc", "test", Laws.storage.rv())

def Laws.storage.pv(meta: J.KV, spec: List<&2, J.KV>) -> J.Json:
  J.Json.obj([meta, Laws.storage.obj("spec", spec)])

def Laws.storage.pv_status(meta: J.KV, spec: List<&2, J.KV>, status: List<&2, J.KV>) -> J.Json:
  J.Json.obj([meta, Laws.storage.obj("spec", spec), Laws.storage.obj("status", status)])

# basePPv
def Laws.storage.base_ppv() -> J.Json:
  Laws.storage.pv(Laws.storage.pv_meta(), [Laws.storage.pref()])

# basePPv as the update leaves it: the syncer adds the host annotations to
# the event's host object, which is the test's basePPv itself.
def Laws.storage.base_ppv_synced() -> J.Json:
  Laws.storage.pv(Laws.storage.pv_bmeta(), [Laws.storage.pref()])

# baseVPv
def Laws.storage.base_vpv() -> J.Json:
  Laws.storage.pv(Laws.storage.pv_meta(), [Laws.storage.vref()])

# wrongNsPPv
def Laws.storage.wrong_ns_ppv() -> J.Json:
  Laws.storage.pv(Laws.storage.pv_meta(), [Laws.storage.ref("testpvc", "wrong", Laws.storage.rv())])

# noPvcPPv
def Laws.storage.no_pvc_ppv() -> J.Json:
  Laws.storage.pv(Laws.storage.pv_meta(), [Laws.storage.ref("wrong", "test", [])])

def Laws.storage.some_message() -> List<&2, J.KV>:
  [Laws.storage.str("message", "someMessage")]

# backwardUpdatePPv
def Laws.storage.backward_update_ppv() -> J.Json:
  Laws.storage.pv_status(Laws.storage.pv_bmeta(), [Laws.storage.pref(), Laws.storage.str("storageClassName", "someStorageClass")], Laws.storage.some_message())

# backwardUpdateVPv
def Laws.storage.backward_update_vpv() -> J.Json:
  Laws.storage.pv_status(Laws.storage.pv_meta(), [Laws.storage.vref(), Laws.storage.str("storageClassName", "someStorageClass")], Laws.storage.some_message())

def Laws.storage.retain_spec(ref: String) -> List<&2, J.KV>:
  [Laws.storage.str("persistentVolumeReclaimPolicy", "Retain"), Laws.storage.ref(ref, "test", []), Laws.storage.str("storageClassName", "retainSC")]

def Laws.storage.phase(p: String) -> List<&2, J.KV>:
  [Laws.storage.str("phase", p)]

# backwardRetainInitialVPv
def Laws.storage.retain_initial_vpv() -> J.Json:
  Laws.storage.pv_status(Laws.storage.pv_meta(), Laws.storage.retain_spec("retainPVC"), Laws.storage.phase("Bound"))

# backwardRetainedVPv
def Laws.storage.retained_vpv() -> J.Json:
  Laws.storage.pv_status(Laws.storage.pv_meta(), Laws.storage.retain_spec("retainPVC"), Laws.storage.phase("Released"))

# backwardRetainPPv
def Laws.storage.retain_ppv() -> J.Json:
  Laws.storage.pv_status(Laws.storage.pv_bmeta(), Laws.storage.retain_spec("retainPVC-x-test-x-suffix"), Laws.storage.phase("Released"))

def Laws.storage.delete_spec() -> List<&2, J.KV>:
  [Laws.storage.str("persistentVolumeReclaimPolicy", "Delete"), Laws.storage.ref("deletedPVC", "test", [])]

# backwardDeletePPv
def Laws.storage.delete_ppv() -> J.Json:
  Laws.storage.pv(Laws.storage.pv_meta(), Laws.storage.delete_spec())

# backwardDeleteVPv
def Laws.storage.delete_vpv() -> J.Json:
  Laws.storage.pv(Laws.storage.pv_meta(), Laws.storage.delete_spec())

# backwardDeleteVPvwithDelTS
def Laws.storage.delete_vpv_ts() -> J.Json:
  Laws.storage.pv(Laws.storage.pv_dmeta(), Laws.storage.delete_spec())

# pPVforDeletePVWithoutClaim
def Laws.storage.no_claim_ppv() -> J.Json:
  Laws.storage.pv(Laws.storage.pv_meta(), [Laws.storage.str("persistentVolumeReclaimPolicy", "Delete")])

# vPVforDeletePVWithoutClaim
def Laws.storage.no_claim_vpv() -> J.Json:
  Laws.storage.pv(Laws.storage.pv_dmeta(), [Laws.storage.str("persistentVolumeReclaimPolicy", "Delete")])

def Laws.storage.capacity(q: String) -> J.KV:
  Laws.storage.obj("capacity", [Laws.storage.str("storage", q)])

# capacityVPv
def Laws.storage.capacity_vpv() -> J.Json:
  Laws.storage.pv(Laws.storage.pv_meta(), [Laws.storage.capacity("5Gi"), Laws.storage.pref()])

# capacityVPv with capacity 20Gi (vObj of "Sync PV Size").
def Laws.storage.capacity_vpv20() -> J.Json:
  Laws.storage.pv(Laws.storage.pv_meta(), [Laws.storage.capacity("20Gi"), Laws.storage.pref()])

# The host volume of "Sync PV Size".
def Laws.storage.capacity_ppv() -> J.Json:
  Laws.storage.pv(Laws.storage.pv_meta(), [Laws.storage.capacity("20Gi"), Laws.storage.pref()])

# persistentvolumes/syncer_test.go TestSync.

# "Create Backward": SyncToVirtual(basePPv); its claim maps to the virtual
# basePvc.
law storage.pv_create_backward:
  {T.St.canon_outcome(T.St.Pv.to_virtual(Laws.storage.cfg(), T.Found{Laws.storage.pv_pvc()}, Laws.storage.base_ppv()))
    == Laws.storage.out([T.VirtualCreate{Laws.storage.base_vpv()}]) : T.Outcome}

# "Don't Create Backward, wrong physical namespace": SyncToVirtual(wrongNsPPv).
law storage.pv_wrong_namespace:
  {T.St.canon_outcome(T.St.Pv.to_virtual(Laws.storage.cfg(), T.Unmapped{}, Laws.storage.wrong_ns_ppv()))
    == Laws.storage.out([]) : T.Outcome}

# "Don't Create Backward, no virtual pvc": SyncToVirtual(noPvcPPv).
law storage.pv_no_virtual_pvc:
  {T.St.canon_outcome(T.St.Pv.to_virtual(Laws.storage.cfg(), T.Unmapped{}, Laws.storage.no_pvc_ppv()))
    == Laws.storage.out([]) : T.Outcome}

# "Update Backward", first call:
# Sync(NewSyncEventWithOld(backwardUpdatePPv x2, baseVPv x2)).
law storage.pv_update_backward:
  {T.St.canon_outcome(T.St.Pv.sync(Laws.storage.cfg(), False{}, Laws.storage.pv_look(T.Found{Laws.storage.pv_pvc()}), Laws.storage.backward_update_ppv(), Laws.storage.backward_update_ppv(), Laws.storage.base_vpv(), Laws.storage.base_vpv()))
    == Laws.storage.out([T.VirtualUpdate{Laws.storage.backward_update_vpv()}]) : T.Outcome}

# "Update Backward", second call: the test reads the synced objects back
# into the old objects' variables, so old and new agree, and nothing changes.
law storage.pv_update_backward_again:
  {T.St.canon_outcome(T.St.Pv.sync(Laws.storage.cfg(), False{}, Laws.storage.pv_look(T.Found{Laws.storage.pv_pvc()}), Laws.storage.backward_update_ppv(), Laws.storage.backward_update_ppv(), Laws.storage.backward_update_vpv(), Laws.storage.backward_update_vpv()))
    == Laws.storage.out([]) : T.Outcome}

# "Delete Backward by update backward": Sync(NewSyncEvent(noPvcPPv, baseVPv)).
law storage.pv_delete_backward:
  {T.St.canon_outcome(T.St.Pv.sync(Laws.storage.cfg(), False{}, Laws.storage.pv_look(T.Unmapped{}), Laws.storage.no_old(), Laws.storage.no_pvc_ppv(), Laws.storage.no_old(), Laws.storage.base_vpv()))
    == Laws.storage.out([T.VirtualDelete{"", "testpv", Laws.storage.nodel()}]) : T.Outcome}

# "Delete Backward not needed":
# Sync(NewSyncEventWithOld(basePPv x2, baseVPv x2)). The virtual volume
# stays; the host volume gets the host annotations (the test's expected
# basePPv is the same object the syncer changes).
law storage.pv_delete_not_needed:
  {T.St.canon_outcome(T.St.Pv.sync(Laws.storage.cfg(), False{}, Laws.storage.pv_look(T.Found{Laws.storage.pv_pvc()}), Laws.storage.base_ppv(), Laws.storage.base_ppv(), Laws.storage.base_vpv(), Laws.storage.base_vpv()))
    == Laws.storage.out([T.HostUpdate{Laws.storage.base_ppv_synced()}]) : T.Outcome}

# "Sync PV Size":
# Sync(NewSyncEventWithOld(host volume x2, capacityVPv, capacityVPv with 20Gi)).
law storage.pv_size:
  {T.St.canon_outcome(T.St.Pv.sync(Laws.storage.cfg(), False{}, Laws.storage.pv_look(T.Found{Laws.storage.pv_pvc()}), Laws.storage.capacity_ppv(), Laws.storage.capacity_ppv(), Laws.storage.capacity_vpv(), Laws.storage.capacity_vpv20()))
    == Laws.storage.out([T.HostUpdate{Laws.storage.pv(Laws.storage.pv_bmeta(), [Laws.storage.capacity("20Gi"), Laws.storage.pref()])},
      T.VirtualUpdate{Laws.storage.pv(Laws.storage.pv_meta(), [Laws.storage.capacity("20Gi"), Laws.storage.vref()])}]) : T.Outcome}

# "Retain PV and update PV Status when reclaim policy is Retain":
# Sync(NewSyncEventWithOld(backwardRetainPPv x2, backwardRetainInitialVPv x2));
# the claim maps to a virtual claim that is gone.
law storage.pv_retain:
  {T.St.canon_outcome(T.St.Pv.sync(Laws.storage.cfg(), False{}, Laws.storage.pv_look(T.Missing{}), Laws.storage.retain_ppv(), Laws.storage.retain_ppv(), Laws.storage.retain_initial_vpv(), Laws.storage.retain_initial_vpv()))
    == Laws.storage.out([T.VirtualUpdate{Laws.storage.retained_vpv()}]) : T.Outcome}

# "Delete PV when reclaim policy is Delete":
# Sync(NewSyncEvent(backwardDeletePPv, backwardDeleteVPv)).
law storage.pv_delete_reclaim_delete:
  {T.St.canon_outcome(T.St.Pv.sync(Laws.storage.cfg(), False{}, Laws.storage.pv_look(T.Unmapped{}), Laws.storage.no_old(), Laws.storage.delete_ppv(), Laws.storage.no_old(), Laws.storage.delete_vpv()))
    == Laws.storage.out([T.VirtualDelete{"", "testpv", Laws.storage.nodel()}]) : T.Outcome}

# "Wait for the VPV to be deleted, when reclaim policy is Delete":
# Sync(NewSyncEvent(backwardDeletePPv, backwardDeleteVPvwithDelTS)) waits.
law storage.pv_wait_deleted:
  {T.St.canon_outcome(T.St.Pv.sync(Laws.storage.cfg(), False{}, Laws.storage.pv_look(T.Unmapped{}), Laws.storage.no_old(), Laws.storage.delete_ppv(), Laws.storage.no_old(), Laws.storage.delete_vpv_ts()))
    == T.Outcome{[], S.RequeueAfter{1}, ""} : T.Outcome}

# "Delete PPV without an associated PVC":
# Sync(NewSyncEvent(pPVforDeletePVWithoutClaim, vPVforDeletePVWithoutClaim)).
law storage.pv_delete_without_claim:
  {T.St.canon_outcome(T.St.Pv.sync(Laws.storage.cfg(), False{}, Laws.storage.pv_look(T.Unmapped{}), Laws.storage.no_old(), Laws.storage.no_claim_ppv(), Laws.storage.no_old(), Laws.storage.no_claim_vpv()))
    == T.Outcome{[T.HostDelete{"", "testpv", Laws.storage.nodel()}], S.RequeueAfter{1}, ""} : T.Outcome}

# persistentvolumes/fake_syncer_test.go fixtures.

# basePvc
def Laws.storage.fake_pvc() -> J.Json:
  J.Json.obj([Laws.storage.obj("metadata", [Laws.storage.str("name", "testpvc"), Laws.storage.str("namespace", "testns"), Laws.storage.str("resourceVersion", "999")]),
    Laws.storage.obj("spec", [Laws.storage.str("volumeName", "mypv"), Laws.storage.str("storageClassName", "mystorageclass")])])

def Laws.storage.fake_meta(finalizers: List<&2, J.KV>) -> J.KV:
  Laws.storage.obj("metadata", List.append(&2, J.KV, [Laws.storage.str("name", "mypv"),
    Laws.storage.obj("labels", [Laws.storage.str("vcluster.loft.sh/fake-pv", "true")]),
    Laws.storage.obj("annotations", [Laws.storage.str("kubernetes.io/createdby", "fake-pv-provisioner"),
      Laws.storage.str("pv.kubernetes.io/bound-by-controller", "true"),
      Laws.storage.str("pv.kubernetes.io/provisioned-by", "fake-pv-provisioner")])], finalizers))

def Laws.storage.fake_spec() -> J.KV:
  Laws.storage.obj("spec", [Laws.storage.obj("flexVolume", [Laws.storage.str("driver", "fake")]),
    Laws.storage.obj("claimRef", [Laws.storage.str("kind", "PersistentVolumeClaim"), Laws.storage.str("namespace", "testns"),
      Laws.storage.str("name", "testpvc"), Laws.storage.str("apiVersion", "v1"), Laws.storage.str("resourceVersion", "999")]),
    Laws.storage.str("persistentVolumeReclaimPolicy", "Delete"), Laws.storage.str("storageClassName", "mystorageclass")])

# basePv
def Laws.storage.fake_pv() -> J.Json:
  J.Json.obj([Laws.storage.fake_meta([]), Laws.storage.fake_spec(), Laws.storage.obj("status", Laws.storage.phase("Bound"))])

# pvWithFinalizers
def Laws.storage.fake_pv_finalizers() -> J.Json:
  J.Json.obj([Laws.storage.fake_meta([Laws.storage.arr("finalizers", [J.JStr{"myfinalizer"}])]), Laws.storage.fake_spec(), Laws.storage.obj("status", Laws.storage.phase("Bound"))])

# persistentvolumes/fake_syncer_test.go TestFakeSync.

# "Create": FakeSyncToVirtual(mypv) with basePvc in the virtual cluster.
law storage.fake_create:
  {T.St.canon_outcome(T.St.Fake.to_virtual("mypv", [Laws.storage.fake_pvc()]))
    == Laws.storage.out([T.VirtualCreate{Laws.storage.fake_pv()}]) : T.Outcome}

# "Create not needed": FakeSyncToVirtual(mypv) with no claims.
law storage.fake_create_not_needed:
  {T.St.canon_outcome(T.St.Fake.to_virtual("mypv", []))
    == Laws.storage.out([]) : T.Outcome}

# "Delete": FakeSync(pvWithFinalizers) with no claims deletes the volume,
# then removes its finalizers.
law storage.fake_delete:
  {T.St.canon_outcome(T.St.Fake.sync(Laws.storage.fake_pv_finalizers(), []))
    == Laws.storage.out([T.VirtualDelete{"", "mypv", Laws.storage.nodel()}, T.VirtualUpdate{Laws.storage.fake_pv()}]) : T.Outcome}

# "Delete not existent pv": FakeSync(basePv) with no claims; the delete
# finds nothing (a not-found delete is no error).
law storage.fake_delete_missing:
  {T.St.canon_outcome(T.St.Fake.sync(Laws.storage.fake_pv(), []))
    == Laws.storage.out([T.VirtualDelete{"", "mypv", Laws.storage.nodel()}]) : T.Outcome}

# storageclasses/syncer_test.go fixtures (sync.toHost.storageClasses enabled).

def Laws.storage.sc_name() -> String:
  "vcluster-testsc-x-test-x-suffix"

def Laws.storage.sc_ann() -> List<&2, J.KV>:
  [Laws.storage.str("vcluster.loft.sh/object-name", "testsc"),
   Laws.storage.str("vcluster.loft.sh/object-uid", ""),
   Laws.storage.str("vcluster.loft.sh/object-kind", "storage.k8s.io/v1, Kind=StorageClass"),
   Laws.storage.str("vcluster.loft.sh/object-host-name", Laws.storage.sc_name())]

def Laws.storage.provisioner() -> J.KV:
  Laws.storage.str("provisioner", "my-provisioner")

def Laws.storage.parameters() -> J.KV:
  Laws.storage.obj("parameters", [Laws.storage.str("TEST", "TEST")])

# vObject
def Laws.storage.sc_v() -> J.Json:
  J.Json.obj([Laws.storage.obj("metadata", [Laws.storage.str("name", "testsc"), Laws.storage.str("resourceVersion", "999")]), Laws.storage.provisioner()])

# vObjectUpdated
def Laws.storage.sc_v_updated() -> J.Json:
  J.Json.obj([Laws.storage.obj("metadata", [Laws.storage.str("name", "testsc"), Laws.storage.str("resourceVersion", "999")]), Laws.storage.provisioner(), Laws.storage.parameters()])

# pObject, labels as the test writes them (MarkerLabel: VClusterName).
def Laws.storage.sc_p() -> J.Json:
  J.Json.obj([Laws.storage.cmeta(Laws.storage.sc_name(), [Laws.storage.str("vcluster.loft.sh/managed-by", "suffix")], Laws.storage.sc_ann()), Laws.storage.provisioner()])

# pObject as SyncToHost creates it: HostLabelsMap writes the cluster marker.
def Laws.storage.sc_p_created() -> J.Json:
  J.Json.obj([Laws.storage.cmeta(Laws.storage.sc_name(), [Laws.storage.str("vcluster.loft.sh/managed-by", "test-x-suffix")], Laws.storage.sc_ann()), Laws.storage.provisioner()])

# pObjectUpdated
def Laws.storage.sc_p_updated() -> J.Json:
  J.Json.obj([Laws.storage.cmeta(Laws.storage.sc_name(), [Laws.storage.str("vcluster.loft.sh/managed-by", "suffix")], Laws.storage.sc_ann()), Laws.storage.provisioner(), Laws.storage.parameters()])

# storageclasses/syncer_test.go TestSync.

# "Sync Down": SyncToHost(vObject).
law storage.sc_sync_down:
  {T.St.canon_outcome(T.St.Sc.to_host(Laws.storage.cfg(), None{}, Laws.storage.sc_v()))
    == Laws.storage.out([T.HostCreate{Laws.storage.sc_p_created()}]) : T.Outcome}

# "Sync": Sync(NewSyncEventWithOld(pObject, pObject, vObject, vObjectUpdated)).
law storage.sc_sync:
  {T.St.canon_outcome(T.St.Sc.sync(Laws.storage.cfg(), Laws.storage.sc_p(), Laws.storage.sc_p(), Laws.storage.sc_v(), Laws.storage.sc_v_updated()))
    == Laws.storage.out([T.HostUpdate{Laws.storage.sc_p_updated()}]) : T.Outcome}

# priorityclasses/syncer_test.go fixtures.

# vObj (and the host pObj of TestSyncToVirtual): {Name: "stuff", Value: 1}.
def Laws.storage.pc_v() -> J.Json:
  J.Json.obj([Laws.storage.cmeta("stuff", [], []), Laws.storage.num("value", "1")])

def Laws.storage.pc_name() -> String:
  "vcluster-stuff-x-test-x-suffix"

# pObj of TestSyncToHost, with HostAnnotations(&vObj, &pObj).
def Laws.storage.pc_p() -> J.Json:
  J.Json.obj([Laws.storage.cmeta(Laws.storage.pc_name(), [Laws.storage.str("vcluster.loft.sh/managed-by", "test-x-suffix")],
      [Laws.storage.str("vcluster.loft.sh/object-name", "stuff"),
       Laws.storage.str("vcluster.loft.sh/object-uid", ""),
       Laws.storage.str("vcluster.loft.sh/object-kind", "scheduling.k8s.io/v1, Kind=PriorityClass"),
       Laws.storage.str("vcluster.loft.sh/object-host-name", Laws.storage.pc_name())]),
    Laws.storage.num("value", "1")])

# priorityclasses/syncer_test.go TestSyncToHost.

# "sync to host": toHost, SyncToHost(vObj).
law storage.pc_sync_to_host:
  {T.St.canon_outcome(T.St.Pc.to_host(Laws.storage.cfg(), T.PcCfg{True{}, False{}}, None{}, Laws.storage.pc_v()))
    == Laws.storage.out([T.HostCreate{Laws.storage.pc_p()}]) : T.Outcome}

# "sync to host create": toHost, no virtual object stored; SyncToHost(vObj).
law storage.pc_sync_to_host_create:
  {T.St.canon_outcome(T.St.Pc.to_host(Laws.storage.cfg(), T.PcCfg{True{}, False{}}, None{}, Laws.storage.pc_v()))
    == Laws.storage.out([T.HostCreate{Laws.storage.pc_p()}]) : T.Outcome}

# "sync to host delete virtual": fromHost only; SyncToHost(vObj) deletes the
# virtual class.
law storage.pc_sync_to_host_delete_virtual:
  {T.St.canon_outcome(T.St.Pc.to_host(Laws.storage.cfg(), T.PcCfg{False{}, True{}}, None{}, Laws.storage.pc_v()))
    == Laws.storage.out([T.VirtualDelete{"", "stuff", Laws.storage.nodel()}]) : T.Outcome}

# priorityclasses/syncer_test.go TestSyncToVirtual (the default selector
# matches every class).

# "sync to virtual": fromHost, SyncToVirtual(pObj) creates the virtual class.
law storage.pc_sync_to_virtual:
  {T.St.canon_outcome(T.St.Pc.to_virtual(Laws.storage.cfg(), T.PcCfg{False{}, True{}}, True{}, None{}, Laws.storage.pc_v()))
    == Laws.storage.out([T.VirtualCreate{Laws.storage.pc_v()}]) : T.Outcome}

# "sync to virtual tohost": toHost, SyncToVirtual(pObj) deletes the host class.
law storage.pc_sync_to_virtual_tohost:
  {T.St.canon_outcome(T.St.Pc.to_virtual(Laws.storage.cfg(), T.PcCfg{True{}, False{}}, True{}, None{}, Laws.storage.pc_v()))
    == Laws.storage.out([T.HostDelete{"", "stuff", Laws.storage.nodel()}]) : T.Outcome}

# csinodes/syncer_test.go fixtures.

def Laws.storage.driver(name: String, id: String) -> J.Json:
  J.Json.obj([Laws.storage.str("name", name), Laws.storage.str("nodeID", id),
    Laws.storage.arr("topologyKeys", [J.JStr{"zone"}, J.JStr{"region"}]),
    Laws.storage.obj("allocatable", [Laws.storage.num("count", "20")])])

def Laws.storage.csi_spec(ds: List<&2, J.Json>) -> J.KV:
  Laws.storage.obj("spec", [Laws.storage.arr("drivers", ds)])

def Laws.storage.csi_vmeta(labels: List<&2, J.KV>) -> J.KV:
  Laws.storage.obj("metadata", [Laws.storage.str("name", "test-node"), Laws.storage.str("resourceVersion", "999"), Laws.storage.obj("labels", labels)])

# pObj
def Laws.storage.csi_p() -> J.Json:
  J.Json.obj([Laws.storage.cmeta("test-node", [], []), Laws.storage.csi_spec([Laws.storage.driver("a", "a")])])

# vObj
def Laws.storage.csi_v() -> J.Json:
  J.Json.obj([Laws.storage.csi_vmeta([]), Laws.storage.csi_spec([Laws.storage.driver("a", "a")])])

# vObj as SyncToVirtual creates it (the resource version comes from the
# server).
def Laws.storage.csi_v_created() -> J.Json:
  J.Json.obj([Laws.storage.cmeta("test-node", [], []), Laws.storage.csi_spec([Laws.storage.driver("a", "a")])])

# pObjUpdated
def Laws.storage.csi_p_updated() -> J.Json:
  J.Json.obj([Laws.storage.cmeta("test-node", [], []), Laws.storage.csi_spec([Laws.storage.driver("a", "a"), Laws.storage.driver("b", "123")])])

# vObjUpdated, with the marker label the syncer sets.
def Laws.storage.csi_v_updated() -> J.Json:
  J.Json.obj([Laws.storage.csi_vmeta([Laws.storage.str("vcluster.loft.sh/managed-by", "suffix")]), Laws.storage.csi_spec([Laws.storage.driver("a", "a"), Laws.storage.driver("b", "123")])])

# csinodes/syncer_test.go TestSync.

# "Sync Up": SyncToVirtual(pObj) with the virtual node test-node.
law storage.csi_sync_up:
  {T.St.canon_outcome(T.St.Csi.to_virtual(True{}, Laws.storage.csi_p()))
    == Laws.storage.out([T.VirtualCreate{Laws.storage.csi_v_created()}]) : T.Outcome}

# "Sync Down": SyncToHost(vObj); vObj lacks the marker label and no host
# object was seen, so it stays.
law storage.csi_sync_down:
  {T.St.canon_outcome(T.St.Csi.to_host(Laws.storage.cfg(), None{}, Laws.storage.csi_v()))
    == Laws.storage.out([]) : T.Outcome}

# "Sync": Sync(NewSyncEvent(pObjUpdated, vObj)) with the virtual node.
law storage.csi_sync:
  {T.St.canon_outcome(T.St.Csi.sync(Laws.storage.cfg(), True{}, Laws.storage.csi_p_updated(), Laws.storage.csi_v()))
    == Laws.storage.out([T.VirtualUpdate{Laws.storage.csi_v_updated()}]) : T.Outcome}

# "Sync, virtual node not synced": Sync(NewSyncEvent(pObjUpdated, vObj))
# without the virtual node deletes the virtual CSINode.
law storage.csi_sync_node_missing:
  {T.St.canon_outcome(T.St.Csi.sync(Laws.storage.cfg(), False{}, Laws.storage.csi_p_updated(), Laws.storage.csi_v()))
    == Laws.storage.out([T.VirtualDelete{"", "test-node", Laws.storage.nodel()}]) : T.Outcome}

# General laws.

# A toHost cluster-scoped name is HostNameCluster: the host storage class,
# priority class and volume of a virtual object are named
# Names.host_name_cluster(name, target, vc).
law storage.sc_host_name:
  for +c: S.Cfg
  for +v: J.Json
  {S.Svc.name(T.St.Sc.translate(c, v)) == N.Names.host_name_cluster(S.Svc.name(v), S.Svc.target(c), S.Svc.vc(c)) : String}

law storage.pc_host_name:
  for +c: S.Cfg
  for +v: J.Json
  {S.Svc.name(T.St.Pc.translate(c, v)) == N.Names.host_name_cluster(S.Svc.name(v), S.Svc.target(c), S.Svc.vc(c)) : String}

law storage.pv_host_name:
  for +c: S.Cfg
  for +v: J.Json
  {S.Svc.name(T.St.Pv.translate(c, v)) == N.Names.host_name_cluster(S.Svc.name(v), S.Svc.target(c), S.Svc.vc(c)) : String}

# SyncToHost of a virtual storage class that is not deleting, with no host
# class seen, creates exactly that host class.
law storage.sc_to_host_creates:
  for +c: S.Cfg
  for +v: J.Json
  for h: {T.St.deleting(v) == False{} : Bool}
  {T.St.Sc.to_host(c, None{}, v) == T.St.done([T.HostCreate{T.St.Sc.translate(c, v)}]) : T.Outcome}

# A capped priority never exceeds vcluster's cap, 1000000000.
law storage.cap_text_bounded:
  for +t: String
  {T.St.exceeds(T.St.cap_text(t)) == False{} : Bool}

law storage.cap_bounded:
  for j: J.Json
  {T.St.exceeds_json(T.St.cap(j)) == False{} : Bool}

# The value of a host priority class never exceeds the cap.
law storage.pc_value_capped:
  for +c: S.Cfg
  for +v: J.Json
  {T.St.exceeds_json(J.Json.get(T.St.Pc.translate(c, v), "value")) == False{} : Bool}

# A value at most the cap stays as it is.
law storage.cap_keeps:
  for +t: String
  for h: {T.St.exceeds(t) == False{} : Bool}
  {T.St.cap_text(t) == t : String}

# Fake volume decisions depend only on the virtual claim set: FakeSync
# deletes a volume exactly when no claim names it ...
law storage.fake_delete_iff_unneeded:
  for +pv: J.Json
  for pvcs: List<&2, J.Json>
  {T.St.has_writes(T.St.Fake.sync(pv, pvcs)) == Bool.not(T.St.Fake.needed(S.Svc.name(pv), pvcs)) : Bool}

# ... so two volumes of one name get the same decision ...
law storage.fake_delete_same_name:
  for +a: J.Json
  for +b: J.Json
  for +pvcs: List<&2, J.Json>
  for h: {S.Svc.name(a) == S.Svc.name(b) : String}
  {T.St.has_writes(T.St.Fake.sync(a, pvcs)) == T.St.has_writes(T.St.Fake.sync(b, pvcs)) : Bool}

# ... and FakeSyncToVirtual creates one exactly when a claim names it.
law storage.fake_create_iff_needed:
  for +name: String
  for pvcs: List<&2, J.Json>
  {T.St.has_writes(T.St.Fake.to_virtual(name, pvcs)) == T.St.Fake.needed(name, pvcs) : Bool}
