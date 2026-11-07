import Base
import ../src/sync/mappings.bend as M
import bend-kube-runtime@0.2.0.0/src/json.bend as J

# Spec for src/sync/mappings.bend (vcluster pkg/mappings: store/store.go,
# generic/recorder.go, generic/mapper.go, resources/configmaps.go,
# resources/secrets.go, resources/namespaces.go).
#
# The concrete laws transcribe every case of store_test.go, recorder_test.go,
# mapper_test.go, configmaps_test.go and secrets_test.go (vcluster a8ab30e).
# Expected values are the Go tests' literals and assertions. vcluster's tests
# run with VClusterName "suffix"; the target namespace is
# testingutil.DefaultTestTargetNamespace ("test") unless a test sets another.
# NewRandomMapping's random names are fixed distinct names here. Where a test
# asserts len(store.mappings), len(store.hostToVirtualName),
# len(store.virtualToHostName) and len(store.ReferencesTo(..)), the law
# compares the list of those numbers.

# Fixtures.

def Laws.mappings.secret() -> String:
  "/v1, Kind=Secret"

def Laws.mappings.pod() -> String:
  "/v1, Kind=Pod"

# A NewRandomMapping stand-in: virtual and host names from a tag.
def Laws.mappings.rnd(g: String, +tag: String) -> M.NM:
  M.NM{g, M.NN{tag ++ "-vns", tag ++ "-vn"}, M.NN{tag ++ "-hns", tag ++ "-hn"}}

def Laws.mappings.secret_m() -> M.NM:
  Laws.mappings.rnd(Laws.mappings.secret(), "secret")

def Laws.mappings.other_secret_m() -> M.NM:
  Laws.mappings.rnd(Laws.mappings.secret(), "other-secret")

def Laws.mappings.pod_m() -> M.NM:
  Laws.mappings.rnd(Laws.mappings.pod(), "pod")

def Laws.mappings.other_pod_m() -> M.NM:
  Laws.mappings.rnd(Laws.mappings.pod(), "other-pod")

def Laws.mappings.virt(x: M.NM) -> M.Obj:
  match x:
    case M.NM{g, v, h}:
      M.Obj{g, v}

def Laws.mappings.empty() -> M.Res:
  M.Ok{M.Store.new(None{})}

# One store step after another; an error stops the chain.
def Laws.mappings.add(r: M.Res, +nm: M.NM, b: M.NM) -> M.Res:
  match r:
    case M.Ok{s}:
      M.Store.add_reference(s, nm, b)
    case M.Err{e}:
      M.Err{e}

def Laws.mappings.self(r: M.Res, +nm: M.NM) -> M.Res:
  Laws.mappings.add(r, nm, nm)

def Laws.mappings.del_ref(r: M.Res, +nm: M.NM, b: M.NM) -> M.Res:
  match r:
    case M.Ok{s}:
      M.Ok{M.Store.delete_reference(s, nm, b)}
    case M.Err{e}:
      M.Err{e}

def Laws.mappings.del(r: M.Res, nm: M.NM) -> M.Res:
  match r:
    case M.Ok{s}:
      M.Ok{M.Store.delete_mapping(s, nm)}
    case M.Err{e}:
      M.Err{e}

def Laws.mappings.gc(r: M.Res, live_v: List<&2, M.Obj>, live_h: List<&2, M.Obj>) -> M.Res:
  match r:
    case M.Ok{s}:
      M.Ok{M.Store.collect(s, live_v, live_h)}
    case M.Err{e}:
      M.Err{e}

def Laws.mappings.ev(r: M.Res, e: M.MEvent) -> M.Res:
  match r:
    case M.Ok{s}:
      M.Ok{M.Store.apply(s, e)}
    case M.Err{x}:
      M.Err{x}

def Laws.mappings.refs_to(+s: M.Store, o: M.Obj) -> Nat:
  match o:
    case M.Obj{g, n}:
      List.length(&2, M.NM, M.Store.references_to(s, g, n))

def Laws.mappings.refs_all(+s: M.Store, os: List<&2, M.Obj>) -> List<&2, Nat>:
  match os:
    case Nil{}:
      []
    case Con{o, t}:
      Laws.mappings.refs_to(s, o) <> Laws.mappings.refs_all(s, t)

# [len(mappings), len(hostToVirtualName), len(virtualToHostName),
#  len(ReferencesTo(o)) for each o]; [] after an error.
def Laws.mappings.stats(r: M.Res, os: List<&2, M.Obj>) -> List<&2, Nat>:
  match r:
    case M.Ok{+s}:
      M.Store.size(s) <> M.Store.keys(M.H2V{}, s) <> M.Store.keys(M.V2H{}, s) <> Laws.mappings.refs_all(s, os)
    case M.Err{e}:
      []

# Whether the step failed with an error containing the text.
def Laws.mappings.err_has(r: M.Res, text: String) -> Bool:
  match r:
    case M.Ok{s}:
      False{}
    case M.Err{e}:
      String.contains(e, text)

def Laws.mappings.store(r: M.Res) -> M.Store:
  match r:
    case M.Ok{s}:
      s
    case M.Err{e}:
      M.Store.new(None{})

def Laws.mappings.json(s: String) -> J.Json:
  Result.default(&2, &2, String, J.Json, J.Json.parse(s), J.JNull{})

# store_test.go TestDeleteReference.

def Laws.mappings.dr1() -> M.Res:
  +p = Laws.mappings.pod_m()
  +op = Laws.mappings.other_pod_m()
  +s = Laws.mappings.secret_m()
  Laws.mappings.add(Laws.mappings.add(Laws.mappings.add(Laws.mappings.self(Laws.mappings.self(Laws.mappings.self(Laws.mappings.empty(), p), op), s), s, p), s, op), Laws.mappings.other_secret_m(), p)

def Laws.mappings.dr2() -> M.Res:
  Laws.mappings.del_ref(Laws.mappings.dr1(), Laws.mappings.other_secret_m(), Laws.mappings.pod_m())

def Laws.mappings.dr3() -> M.Res:
  Laws.mappings.del(Laws.mappings.dr2(), Laws.mappings.pod_m())

def Laws.mappings.dr4() -> M.Res:
  Laws.mappings.del_ref(Laws.mappings.dr3(), Laws.mappings.secret_m(), Laws.mappings.other_pod_m())

def Laws.mappings.dr5() -> M.Res:
  Laws.mappings.del(Laws.mappings.dr4(), Laws.mappings.secret_m())

def Laws.mappings.dr_objs() -> List<&2, M.Obj>:
  [Laws.mappings.virt(Laws.mappings.secret_m()), Laws.mappings.virt(Laws.mappings.other_secret_m())]

law mappings.delete_reference_added:
  {Laws.mappings.stats(Laws.mappings.dr1(), Laws.mappings.dr_objs()) == [3n, 4n, 4n, 2n, 1n] : List<&2, Nat>}

law mappings.delete_reference_deleted:
  {Laws.mappings.stats(Laws.mappings.dr2(), Laws.mappings.dr_objs()) == [3n, 3n, 3n, 2n, 0n] : List<&2, Nat>}

law mappings.delete_reference_pod_refs:
  {List.length(&2, M.NM, M.Store.refs_of(Laws.mappings.store(Laws.mappings.dr2()), Laws.mappings.pod_m())) == 1n : Nat}

law mappings.delete_reference_pod_deleted:
  {Laws.mappings.stats(Laws.mappings.dr3(), Laws.mappings.dr_objs()) == [2n, 2n, 2n, 1n, 0n] : List<&2, Nat>}

law mappings.delete_reference_other_pod:
  {Laws.mappings.stats(Laws.mappings.dr4(), Laws.mappings.dr_objs()) == [2n, 2n, 2n, 0n, 0n] : List<&2, Nat>}

law mappings.delete_reference_secret_deleted:
  {Laws.mappings.stats(Laws.mappings.dr5(), Laws.mappings.dr_objs()) == [1n, 1n, 1n, 0n, 0n] : List<&2, Nat>}

# store_test.go TestWatching: events from another sender.

def Laws.mappings.w_save(r: M.Res, x: M.NM, rs: List<&2, M.NM>) -> M.Res:
  Laws.mappings.ev(r, M.Upd{M.Mapping{x, rs}})

def Laws.mappings.w1() -> M.Res:
  Laws.mappings.w_save(Laws.mappings.empty(), Laws.mappings.secret_m(), [Laws.mappings.pod_m()])

def Laws.mappings.w2() -> M.Res:
  Laws.mappings.w_save(Laws.mappings.w1(), Laws.mappings.other_secret_m(), [Laws.mappings.pod_m()])

def Laws.mappings.w3() -> M.Res:
  Laws.mappings.w_save(Laws.mappings.w2(), Laws.mappings.secret_m(), [])

def Laws.mappings.w4() -> M.Res:
  Laws.mappings.ev(Laws.mappings.w3(), M.Del{Laws.mappings.secret_m()})

def Laws.mappings.w5() -> M.Res:
  Laws.mappings.ev(Laws.mappings.w4(), M.Del{Laws.mappings.other_secret_m()})

def Laws.mappings.w6() -> M.Res:
  Laws.mappings.w_save(Laws.mappings.w5(), Laws.mappings.secret_m(), [Laws.mappings.pod_m()])

# DeleteReconstructed: the event carries only the kind and the virtual name.
def Laws.mappings.reconstructed(x: M.NM) -> M.NM:
  match x:
    case M.NM{g, v, h}:
      M.NM{g, v, M.NN.empty()}

def Laws.mappings.w7() -> M.Res:
  Laws.mappings.ev(Laws.mappings.w6(), M.Del{Laws.mappings.reconstructed(Laws.mappings.secret_m())})

def Laws.mappings.w_objs() -> List<&2, M.Obj>:
  [Laws.mappings.virt(Laws.mappings.pod_m())]

law mappings.watch_save:
  {Laws.mappings.stats(Laws.mappings.w1(), Laws.mappings.w_objs()) == [1n, 2n, 2n, 1n] : List<&2, Nat>}

law mappings.watch_save_other:
  {Laws.mappings.stats(Laws.mappings.w2(), Laws.mappings.w_objs()) == [2n, 3n, 3n, 2n] : List<&2, Nat>}

law mappings.watch_update:
  {Laws.mappings.stats(Laws.mappings.w3(), Laws.mappings.w_objs()) == [2n, 3n, 3n, 1n] : List<&2, Nat>}

law mappings.watch_delete:
  {Laws.mappings.stats(Laws.mappings.w4(), Laws.mappings.w_objs()) == [1n, 2n, 2n, 1n] : List<&2, Nat>}

law mappings.watch_delete_other:
  {Laws.mappings.stats(Laws.mappings.w5(), Laws.mappings.w_objs()) == [0n, 0n, 0n, 0n] : List<&2, Nat>}

law mappings.watch_save_again:
  {Laws.mappings.stats(Laws.mappings.w6(), Laws.mappings.w_objs()) == [1n, 2n, 2n, 1n] : List<&2, Nat>}

law mappings.watch_delete_reconstructed:
  {Laws.mappings.stats(Laws.mappings.w7(), Laws.mappings.w_objs()) == [0n, 0n, 0n, 0n] : List<&2, Nat>}

# store_test.go TestGarbageCollectMappings: GC sees the virtual pod only in
# the second round.

def Laws.mappings.gc_recorded() -> M.Res:
  Laws.mappings.self(Laws.mappings.self(Laws.mappings.empty(), Laws.mappings.secret_m()), Laws.mappings.pod_m())

def Laws.mappings.gc_referenced() -> M.Res:
  Laws.mappings.add(Laws.mappings.gc_recorded(), Laws.mappings.secret_m(), Laws.mappings.pod_m())

def Laws.mappings.gc1() -> M.Res:
  Laws.mappings.gc(Laws.mappings.gc_referenced(), [], [])

def Laws.mappings.gc_rerecorded() -> M.Res:
  Laws.mappings.add(Laws.mappings.self(Laws.mappings.self(Laws.mappings.gc1(), Laws.mappings.secret_m()), Laws.mappings.pod_m()), Laws.mappings.secret_m(), Laws.mappings.pod_m())

def Laws.mappings.gc2() -> M.Res:
  Laws.mappings.gc(Laws.mappings.gc_rerecorded(), [Laws.mappings.virt(Laws.mappings.pod_m())], [])

def Laws.mappings.with_host(x: M.NM, n: M.NN) -> M.NM:
  match x:
    case M.NM{g, v, h}:
      M.NM{g, v, n}

def Laws.mappings.conflicting() -> M.NM:
  Laws.mappings.with_host(Laws.mappings.secret_m(), M.NN{"other", "other"})

def Laws.mappings.gc3() -> M.Res:
  Laws.mappings.gc(Laws.mappings.gc2(), [], [])

def Laws.mappings.gc_objs() -> List<&2, M.Obj>:
  [Laws.mappings.virt(Laws.mappings.pod_m()), Laws.mappings.virt(Laws.mappings.secret_m())]

law mappings.gc_recorded:
  {Laws.mappings.stats(Laws.mappings.gc_recorded(), Laws.mappings.gc_objs()) == [2n, 2n, 2n, 0n, 0n] : List<&2, Nat>}

law mappings.gc_referenced:
  {Laws.mappings.refs_to(Laws.mappings.store(Laws.mappings.gc_referenced()), Laws.mappings.virt(Laws.mappings.secret_m())) == 1n : Nat}

law mappings.gc_collected:
  {Laws.mappings.stats(Laws.mappings.gc1(), []) == [0n, 0n, 0n] : List<&2, Nat>}

law mappings.gc_rerecorded:
  {Laws.mappings.stats(Laws.mappings.gc_rerecorded(), [Laws.mappings.virt(Laws.mappings.secret_m())]) == [2n, 2n, 2n, 1n] : List<&2, Nat>}

law mappings.gc_pod_alive:
  {Laws.mappings.stats(Laws.mappings.gc2(), [Laws.mappings.virt(Laws.mappings.secret_m())]) == [1n, 2n, 2n, 1n] : List<&2, Nat>}

law mappings.gc_conflict_self:
  {Laws.mappings.err_has(Laws.mappings.self(Laws.mappings.gc2(), Laws.mappings.conflicting()), "there is already another name mapping") == True{} : Bool}

law mappings.gc_conflict_owner:
  {Laws.mappings.err_has(Laws.mappings.add(Laws.mappings.gc2(), Laws.mappings.conflicting(), Laws.mappings.pod_m()), "there is already another name mapping") == True{} : Bool}

law mappings.gc_pod_deleted:
  {Laws.mappings.stats(Laws.mappings.gc3(), [Laws.mappings.virt(Laws.mappings.secret_m())]) == [0n, 0n, 0n, 0n] : List<&2, Nat>}

# store_test.go TestStore: a reference whose owner names only the virtual
# side creates the mapping.

def Laws.mappings.st_virtual() -> M.NN:
  M.NN{"virtual-namespace", "virtual-name"}

def Laws.mappings.st_host() -> M.NN:
  M.NN{"host-namespace", "host-name"}

def Laws.mappings.st_nm() -> M.NM:
  M.NM{Laws.mappings.secret(), Laws.mappings.st_virtual(), Laws.mappings.st_host()}

def Laws.mappings.st_base() -> M.NM:
  M.NM{Laws.mappings.secret(), Laws.mappings.st_virtual(), M.NN.empty()}

def Laws.mappings.st1() -> M.Res:
  Laws.mappings.add(Laws.mappings.empty(), Laws.mappings.st_nm(), Laws.mappings.st_base())

def Laws.mappings.st2() -> M.Res:
  Laws.mappings.add(Laws.mappings.st1(), Laws.mappings.st_nm(), Laws.mappings.st_base())

law mappings.store_virtual_to_host:
  {M.Store.virtual_to_host(Laws.mappings.store(Laws.mappings.st1()), Laws.mappings.secret(), Laws.mappings.st_virtual()) == Some{Laws.mappings.st_host()} : Maybe<&2, M.NN>}

law mappings.store_host_to_virtual:
  {M.Store.host_to_virtual(Laws.mappings.store(Laws.mappings.st1()), Laws.mappings.secret(), Laws.mappings.st_host()) == Some{Laws.mappings.st_virtual()} : Maybe<&2, M.NN>}

law mappings.store_host_to_virtual_empty:
  {M.Store.host_to_virtual(Laws.mappings.store(Laws.mappings.st1()), Laws.mappings.secret(), M.NN.empty()) == None{} : Maybe<&2, M.NN>}

law mappings.store_inner:
  {Laws.mappings.stats(Laws.mappings.st1(), []) == [1n, 1n, 1n] : List<&2, Nat>}

law mappings.store_not_added:
  {Laws.mappings.stats(Laws.mappings.st2(), []) == [1n, 1n, 1n] : List<&2, Nat>}

law mappings.store_mapping:
  {M.Store.has_mapping(Laws.mappings.store(Laws.mappings.st2()), Laws.mappings.st_nm()) == True{} : Bool}

law mappings.store_mapping_refs:
  {List.length(&2, M.NM, M.Store.refs_of(Laws.mappings.store(Laws.mappings.st2()), Laws.mappings.st_nm())) == 0n : Nat}

law mappings.store_collected:
  {M.Store.has_mapping(Laws.mappings.store(Laws.mappings.gc(Laws.mappings.st2(), [], [])), Laws.mappings.st_nm()) == False{} : Bool}

law mappings.store_collected_inner:
  {Laws.mappings.stats(Laws.mappings.gc(Laws.mappings.st2(), [], []), []) == [0n, 0n, 0n] : List<&2, Nat>}

# store_test.go TestRecordMapping: an owner that names only the host
# kube-root-ca.crt does not match the reference's host name, so nothing is
# recorded.

law mappings.record_mapping_root_ca:
  {M.Store.size(Laws.mappings.store(M.Store.add_reference(M.Store.new(None{}), M.NM{"/v1, Kind=ConfigMap", M.NN{"default", "kube-root-ca.crt"}, M.NN{"vcluster-namespace", "vcluster-kube-root-ca.crt-x-vcluster"}}, M.NM{"/v1, Kind=ConfigMap", M.NN.empty(), M.NN{"vcluster-namespace", "kube-root-ca.crt"}}))) == 0n : Nat}

# recorder_test.go TestRecorderMigrate: host objects migrate into the store
# (Mapper: NewMapper(Secret, translate.Default.HostName), target "test").

def Laws.mappings.ctx(target: String, owner: Maybe<&2, M.NM>, reg: List<&2, String>) -> M.Ctx:
  M.Ctx{target, "suffix", owner, Some{reg}, False{}, False{}}

def Laws.mappings.migrate(o: String) -> List<&2, M.Mapping>:
  M.Store.mappings(M.Rec.migrate(M.KGeneric{}, Laws.mappings.ctx("test", None{}, []), M.Store.new(None{}), Laws.mappings.secret(), [Laws.mappings.json(o)], []))

law mappings.recorder_migrate_simple:
  {Laws.mappings.migrate("{\"metadata\":{\"name\":\"host-secret-1\",\"namespace\":\"test\",\"annotations\":{\"vcluster.loft.sh/object-name\":\"virtual-secret-1\",\"vcluster.loft.sh/object-namespace\":\"virtual-namespace-1\",\"vcluster.loft.sh/object-kind\":\"/v1, Kind=Secret\"},\"labels\":{\"vcluster.loft.sh/namespace\":\"virtual-namespace-1\",\"vcluster.loft.sh/managed-by\":\"suffix\"}}}")
    == [M.Mapping{M.NM{"/v1, Kind=Secret", M.NN{"virtual-namespace-1", "virtual-secret-1"}, M.NN{"test", "host-secret-1"}}, []}] : List<&2, M.Mapping>}

law mappings.recorder_migrate_marker_missing:
  {Laws.mappings.migrate("{\"metadata\":{\"name\":\"host-secret-1\",\"namespace\":\"test\",\"annotations\":{\"vcluster.loft.sh/object-name\":\"virtual-secret-1\",\"vcluster.loft.sh/object-namespace\":\"virtual-namespace-1\",\"vcluster.loft.sh/object-kind\":\"/v1, Kind=Secret\"},\"labels\":{\"vcluster.loft.sh/namespace\":\"virtual-namespace-1\"}}}")
    == [] : List<&2, M.Mapping>}

law mappings.recorder_migrate_wrong_namespace:
  {Laws.mappings.migrate("{\"metadata\":{\"name\":\"host-secret-1\",\"namespace\":\"vcluster\",\"annotations\":{\"vcluster.loft.sh/object-name\":\"virtual-secret-1\",\"vcluster.loft.sh/object-namespace\":\"virtual-namespace-1\",\"vcluster.loft.sh/object-kind\":\"/v1, Kind=Secret\"},\"labels\":{\"vcluster.loft.sh/namespace\":\"virtual-namespace-1\",\"vcluster.loft.sh/managed-by\":\"suffix\"}}}")
    == [] : List<&2, M.Mapping>}

law mappings.recorder_migrate_wrong_kind:
  {Laws.mappings.migrate("{\"metadata\":{\"name\":\"host-secret-1\",\"namespace\":\"test\",\"annotations\":{\"vcluster.loft.sh/object-name\":\"virtual-secret-1\",\"vcluster.loft.sh/object-namespace\":\"virtual-namespace-1\",\"vcluster.loft.sh/object-kind\":\"/v1, Kind=Pod\"},\"labels\":{\"vcluster.loft.sh/namespace\":\"virtual-namespace-1\",\"vcluster.loft.sh/managed-by\":\"suffix\"}}}")
    == [] : List<&2, M.Mapping>}

# recorder_test.go TestRecorder: a recorder over a fake mapper that answers
# the requested name (`inner` is the request).

def Laws.mappings.r_test() -> M.NN:
  M.NN{"test", "test"}

def Laws.mappings.r_other() -> M.NN:
  M.NN{"other", "other"}

def Laws.mappings.r_test123() -> M.NN:
  M.NN{"test123", "test123"}

def Laws.mappings.r_owner() -> Maybe<&2, M.NM>:
  Some{M.NM{Laws.mappings.secret(), Laws.mappings.r_test(), M.NN.empty()}}

def Laws.mappings.fst(p: M.NN & M.Store) -> M.NN:
  (n, s) = p
  n

def Laws.mappings.snd(p: M.NN & M.Store) -> M.Store:
  (n, s) = p
  s

# No owner in the context: the answer is not recorded.
def Laws.mappings.r1() -> M.NN & M.Store:
  M.Rec.virtual_to_host(Laws.mappings.ctx("", None{}, []), M.Store.new(None{}), Laws.mappings.secret(), Laws.mappings.r_test(), Laws.mappings.r_test())

# The conflicting mapping test -> other.
def Laws.mappings.r2() -> M.Store:
  +c = {M.NM{Laws.mappings.secret(), Laws.mappings.r_test(), Laws.mappings.r_other()} : M.NM}
  Laws.mappings.store(M.Store.add_reference(Laws.mappings.snd(Laws.mappings.r1()), c, c))

def Laws.mappings.r_ctx() -> M.Ctx:
  Laws.mappings.ctx("", Laws.mappings.r_owner(), [])

def Laws.mappings.r3() -> M.NN & M.Store:
  M.Rec.host_to_virtual(Laws.mappings.r_ctx(), Laws.mappings.r2(), Laws.mappings.secret(), Laws.mappings.r_test(), Laws.mappings.r_test())

def Laws.mappings.r4() -> M.NN & M.Store:
  M.Rec.host_to_virtual(Laws.mappings.r_ctx(), Laws.mappings.snd(Laws.mappings.r3()), Laws.mappings.secret(), Laws.mappings.r_other(), Laws.mappings.r_other())

def Laws.mappings.r5() -> M.NN & M.Store:
  M.Rec.host_to_virtual(Laws.mappings.r_ctx(), Laws.mappings.snd(Laws.mappings.r4()), Laws.mappings.secret(), Laws.mappings.r_test123(), Laws.mappings.r_test123())

def Laws.mappings.r6() -> M.NN & M.Store:
  M.Rec.virtual_to_host(Laws.mappings.r_ctx(), Laws.mappings.snd(Laws.mappings.r5()), Laws.mappings.secret(), Laws.mappings.r_test123(), Laws.mappings.r_test123())

law mappings.recorder_unrecorded_name:
  {Laws.mappings.fst(Laws.mappings.r1()) == Laws.mappings.r_test() : M.NN}

law mappings.recorder_unrecorded:
  {M.Store.virtual_to_host(Laws.mappings.snd(Laws.mappings.r1()), Laws.mappings.secret(), Laws.mappings.r_test()) == None{} : Maybe<&2, M.NN>}

law mappings.recorder_conflict_empty:
  {Laws.mappings.fst(Laws.mappings.r3()) == M.NN.empty() : M.NN}

law mappings.recorder_mapping:
  {Laws.mappings.fst(Laws.mappings.r4()) == Laws.mappings.r_test() : M.NN}

law mappings.recorder_another_host:
  {Laws.mappings.fst(Laws.mappings.r5()) == Laws.mappings.r_test123() : M.NN}

law mappings.recorder_another_virtual:
  {Laws.mappings.fst(Laws.mappings.r6()) == Laws.mappings.r_test123() : M.NN}

law mappings.recorder_other_conflict:
  {Laws.mappings.err_has(M.Store.add_reference(Laws.mappings.snd(Laws.mappings.r6()), M.NM{Laws.mappings.secret(), Laws.mappings.r_other(), Laws.mappings.r_test123()}, M.NM{Laws.mappings.secret(), Laws.mappings.r_other(), Laws.mappings.r_test123()}), "there is already another name mapping") == True{} : Bool}

law mappings.recorder_managed:
  {M.Rec.is_managed(Laws.mappings.r_ctx(), Laws.mappings.snd(Laws.mappings.r6()), Laws.mappings.secret(), Laws.mappings.r_test123(), False{}) == True{} : Bool}

law mappings.recorder_not_managed:
  {M.Rec.is_managed(Laws.mappings.r_ctx(), Laws.mappings.snd(Laws.mappings.r6()), Laws.mappings.secret(), M.NN{"test123-other", "test123"}, False{}) == False{} : Bool}

# mapper_test.go TestTryToTranslateBackByAnnotations.

def Laws.mappings.by_ann(o: String) -> M.NN:
  M.Mapper.by_annotations("", "suffix", Laws.mappings.secret(), Some{Laws.mappings.json(o)})

law mappings.by_annotations_simple:
  {Laws.mappings.by_ann("{\"metadata\":{\"annotations\":{\"vcluster.loft.sh/object-name\":\"virtual-name\",\"vcluster.loft.sh/object-namespace\":\"virtual-namespace\"}}}")
    == M.NN{"virtual-namespace", "virtual-name"} : M.NN}

law mappings.by_annotations_other_annotations:
  {Laws.mappings.by_ann("{\"metadata\":{\"name\":\"host-name\",\"namespace\":\"host-namespace\",\"annotations\":{\"vcluster.loft.sh/object-kind\":\"/v1, Kind=Secret\",\"vcluster.loft.sh/object-name\":\"virtual-name\",\"vcluster.loft.sh/object-namespace\":\"virtual-namespace\",\"vcluster.loft.sh/object-host-name\":\"host-name\",\"vcluster.loft.sh/object-host-namespace\":\"host-namespace\"}}}")
    == M.NN{"virtual-namespace", "virtual-name"} : M.NN}

law mappings.by_annotations_wrong_kind:
  {Laws.mappings.by_ann("{\"metadata\":{\"name\":\"host-name\",\"namespace\":\"host-namespace\",\"annotations\":{\"vcluster.loft.sh/object-kind\":\"/v1, Kind=Pod\",\"vcluster.loft.sh/object-name\":\"virtual-name\",\"vcluster.loft.sh/object-namespace\":\"virtual-namespace\",\"vcluster.loft.sh/object-host-name\":\"host-name\",\"vcluster.loft.sh/object-host-namespace\":\"host-namespace\"}}}")
    == M.NN.empty() : M.NN}

law mappings.by_annotations_wrong_host_namespace:
  {Laws.mappings.by_ann("{\"metadata\":{\"name\":\"host-name\",\"namespace\":\"host-namespace\",\"annotations\":{\"vcluster.loft.sh/object-kind\":\"/v1, Kind=Secret\",\"vcluster.loft.sh/object-name\":\"virtual-name\",\"vcluster.loft.sh/object-namespace\":\"virtual-namespace\",\"vcluster.loft.sh/object-host-name\":\"host-name\",\"vcluster.loft.sh/object-host-namespace\":\"host-namespace-does-not-exist\"}}}")
    == M.NN.empty() : M.NN}

law mappings.by_annotations_wrong_host_name:
  {Laws.mappings.by_ann("{\"metadata\":{\"name\":\"host-name\",\"namespace\":\"host-namespace\",\"annotations\":{\"vcluster.loft.sh/object-kind\":\"/v1, Kind=Secret\",\"vcluster.loft.sh/object-name\":\"virtual-name\",\"vcluster.loft.sh/object-namespace\":\"virtual-namespace\",\"vcluster.loft.sh/object-host-name\":\"host-name-1\",\"vcluster.loft.sh/object-host-namespace\":\"host-namespace\"}}}")
    == M.NN.empty() : M.NN}

law mappings.by_annotations_name_missing:
  {Laws.mappings.by_ann("{\"metadata\":{\"name\":\"host-name\",\"namespace\":\"host-namespace\",\"annotations\":{\"vcluster.loft.sh/object-kind\":\"/v1, Kind=Secret\",\"vcluster.loft.sh/object-namespace\":\"virtual-namespace\",\"vcluster.loft.sh/object-host-name\":\"host-name\",\"vcluster.loft.sh/object-host-namespace\":\"host-namespace\"}}}")
    == M.NN.empty() : M.NN}

# mapper_test.go TestTryToTranslateBackByStore (target "test"; the store is
# loaded from a memory backend holding one Pod mapping).

def Laws.mappings.short(name: String, ns: String) -> M.NN:
  M.Tr.host_name_short("test", "suffix", M.NN{ns, name})

def Laws.mappings.long(name: String, ns: String) -> M.NN:
  M.Tr.host_name("test", "suffix", M.NN{ns, name})

def Laws.mappings.by_store(v: M.NN, h: M.NN, req: M.NN) -> M.NN:
  M.Mapper.by_name(Laws.mappings.ctx("test", None{}, [Laws.mappings.pod()]), M.Store.load([M.Mapping{M.NM{Laws.mappings.pod(), v, h}, []}], M.Store.new(None{})), req, Laws.mappings.secret())

def Laws.mappings.inside(pre: String, n: M.NN, post: String) -> M.NN:
  match n:
    case M.NN{ns, name}:
      M.NN{ns, pre ++ name ++ post}

law mappings.by_store_simple:
  {Laws.mappings.by_store(M.NN{"test", "test"}, Laws.mappings.short("test", "test"), Laws.mappings.short("test", "test")) == M.NN{"test", "test"} : M.NN}

law mappings.by_store_wrong_name_mapping:
  {Laws.mappings.by_store(M.NN{"test", "test123"}, Laws.mappings.short("test", "test"), Laws.mappings.short("test", "test")) == M.NN.empty() : M.NN}

law mappings.by_store_match_within_name:
  {Laws.mappings.by_store(M.NN{"test", "test"}, Laws.mappings.short("test", "test"), Laws.mappings.inside("testme-", Laws.mappings.short("test", "test"), "-testme")) == M.NN{"test", "testme-test-testme"} : M.NN}

law mappings.by_store_match_multiple_within_name:
  {Laws.mappings.by_store(M.NN{"test", "test"}, Laws.mappings.short("test", "test"), Laws.mappings.inside("testme-", Laws.mappings.short("test", "test"), "-testme-" ++ M.NN.name(Laws.mappings.short("test", "test")))) == M.NN{"test", "testme-test-testme-test"} : M.NN}

law mappings.by_store_regular_name:
  {Laws.mappings.by_store(M.NN{"test", "test"}, Laws.mappings.long("test", "test"), Laws.mappings.long("test", "test")) == M.NN{"test", "test"} : M.NN}

law mappings.by_store_regular_name_in_between:
  {Laws.mappings.by_store(M.NN{"test", "test"}, Laws.mappings.long("test", "test"), Laws.mappings.inside("testme-", Laws.mappings.long("test", "test"), "")) == M.NN.empty() : M.NN}

# mapper_test.go TestTryToTranslateBackByName (target "target-namespace",
# empty store, the owner mapping in the context).

def Laws.mappings.bn_virtual() -> M.NN:
  M.NN{"virtual-namespace", "virtual-name"}

def Laws.mappings.bn_short() -> M.NN:
  M.Tr.host_name_short("target-namespace", "suffix", Laws.mappings.bn_virtual())

def Laws.mappings.by_name(host: M.NN, reg: List<&2, String>, +multi: Bool, req: M.NN) -> M.NN:
  M.Mapper.by_name(M.Ctx{"target-namespace", "suffix", Some{M.NM{Laws.mappings.secret(), Laws.mappings.bn_virtual(), host}}, Some{reg}, multi, multi}, M.Store.new(None{}), req, Laws.mappings.secret())

law mappings.by_name_single_namespace:
  {Laws.mappings.by_name(M.NN{"target-namespace", "host-name"}, [], False{}, M.NN{"target-namespace", "host-name"}) == M.NN.empty() : M.NN}

law mappings.by_name_host_name_short:
  {Laws.mappings.by_name(Laws.mappings.bn_short(), [], False{}, Laws.mappings.bn_short()) == Laws.mappings.bn_virtual() : M.NN}

law mappings.by_name_multi_namespace:
  {Laws.mappings.by_name(Laws.mappings.bn_short(), ["/v1, Kind=Namespace"], True{}, M.NN{"target-namespace", "test"}) == M.NN{"target-namespace", "test"} : M.NN}

# configmaps_test.go TestConfigMapsMapping.

law mappings.configmaps_from_pod:
  {M.ConfigMaps.from_pod(Laws.mappings.json("{\"metadata\":{\"name\":\"test\",\"namespace\":\"test\"},\"spec\":{\"containers\":[{\"name\":\"test\",\"env\":[{\"name\":\"test\",\"valueFrom\":{\"configMapKeyRef\":{\"name\":\"a\"}}}]}],\"volumes\":[{\"name\":\"test\",\"configMap\":{\"name\":\"b\"}}]}}"))
    == [M.NN{"test", "a"}, M.NN{"test", "b"}] : List<&2, M.NN>}

# secrets_test.go TestSecretMappings.

law mappings.secrets_from_ingress:
  {M.Secrets.from_ingress(Laws.mappings.json("{\"metadata\":{\"name\":\"test\",\"namespace\":\"test\"},\"spec\":{\"tls\":[{\"secretName\":\"a\"},{\"secretName\":\"b\"}]}}"))
    == [M.NN{"test", "a"}, M.NN{"test", "b"}] : List<&2, M.NN>}

law mappings.secrets_from_pod:
  {M.Secrets.from_pod(None{}, Laws.mappings.json("{\"metadata\":{\"name\":\"test\",\"namespace\":\"test\"},\"spec\":{\"containers\":[{\"name\":\"test\",\"env\":[{\"name\":\"test\",\"valueFrom\":{\"secretKeyRef\":{\"name\":\"a\"}}}]}],\"volumes\":[{\"name\":\"test\",\"secret\":{\"secretName\":\"b\"}}]}}"))
    == [M.NN{"test", "a"}, M.NN{"test", "b"}] : List<&2, M.NN>}

# General laws.

# A complete name mapping (both names non-empty).
def Laws.mappings.nm(g: String, vns: String, vc: Char, vt: String, hns: String, hc: Char, ht: String) -> M.NM:
  M.NM{g, M.NN{vns, SCon{vc, vt}}, M.NN{hns, SCon{hc, ht}}}

# The lookup from the `d` side of nm after the step; an error gives nm's
# other side (the law then holds trivially: the store refused the record).
def Laws.mappings.ok_look(+d: M.Dir, x: M.NM, r: M.Res) -> Maybe<&2, M.NN>:
  match x:
    case M.NM{+g, +v, +h}:
      match r:
        case M.Ok{s}:
          M.Look.ms(d, M.Store.mappings(s), g, M.Dir.key(d, v, h))
        case M.Err{e}:
          Some{M.Dir.val(d, v, h)}

# Lookup after record returns the recorded name, virtual to host.
law mappings.record_lookup_virtual:
  for +ms: List<&2, M.Mapping>
  for +g: String
  for +vns: String
  for +vc: Char
  for +vt: String
  for +hns: String
  for +hc: Char
  for +ht: String
  {Laws.mappings.ok_look(M.V2H{}, Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), M.Store.add_reference(M.Store{None{}, ms}, Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)))
    == Some{M.NN{hns, SCon{hc, ht}}} : Maybe<&2, M.NN>}

# Lookup after record returns the recorded name, host to virtual.
law mappings.record_lookup_host:
  for +ms: List<&2, M.Mapping>
  for +g: String
  for +vns: String
  for +vc: Char
  for +vt: String
  for +hns: String
  for +hc: Char
  for +ht: String
  {Laws.mappings.ok_look(M.H2V{}, Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), M.Store.add_reference(M.Store{None{}, ms}, Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)))
    == Some{M.NN{vns, SCon{vc, vt}}} : Maybe<&2, M.NN>}

def Laws.mappings.again(r: M.Res, nm: M.NM) -> M.Res:
  match r:
    case M.Ok{s}:
      +x = nm
      M.Store.add_reference(s, x, x)
    case M.Err{e}:
      M.Err{e}

# Recording a name mapping (as its own owner) is idempotent: a second record
# changes nothing.
law mappings.record_idempotent:
  for +vf: Maybe<&2, String>
  for +ms: List<&2, M.Mapping>
  for +nm: M.NM
  {Laws.mappings.again(M.Store.add_reference(M.Store{vf, ms}, nm, nm), nm) == M.Store.add_reference(M.Store{vf, ms}, nm, nm) : M.Res}

# Garbage collection with no live object drops every mapping.
law mappings.collect_dead:
  for +vf: Maybe<&2, String>
  for +ms: List<&2, M.Mapping>
  {M.Store.collect(M.Store{vf, ms}, [], []) == M.Store{vf, []} : M.Store}

# A mapping neither of whose objects exists is collected, whatever
# references it holds.
law mappings.collect_dead_mapping:
  for +vf: Maybe<&2, String>
  for +ms: List<&2, M.Mapping>
  for +live_v: List<&2, M.Obj>
  for +live_h: List<&2, M.Obj>
  for +nm: M.NM
  for dead: {M.Store.live(live_v, live_h, nm) == False{} : Bool}
  {M.Store.has_mapping(M.Store.collect(M.Store{vf, ms}, live_v, live_h), nm) == False{} : Bool}

# A configmap or secret that no mapping references, not forced and without
# sync.toHost.*.all, is not used: its host copy is deleted.
law mappings.unreferenced_unused:
  for +s: M.Store
  for +g: String
  for +n: M.NN
  for none: {M.Store.references_to(s, g, n) == [] : List<&2, M.NM>}
  {M.Sync.used(False{}, False{}, s, g, n) == False{} : Bool}
