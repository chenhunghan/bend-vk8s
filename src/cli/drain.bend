import Base
import bend-kube-runtime@0.12.0.0/src/json.bend as J

# Draining a node (vk8s node delete)
# ==================================
#
# vcluster node delete cordons the node, drains it with kubectl's drain
# library and deletes it (vcluster cmd/vclusterctl/cmd/node/delete.go):
#
#   drain.Helper{Force: true, IgnoreAllDaemonSets: true,
#     DeleteEmptyDirData: true, Timeout: 30 * time.Minute,
#     GracePeriodSeconds: 30}
#
# This module holds every decision of that drain (k8s.io/kubectl v0.36.3,
# pkg/drain: filters.go, drain.go, cordon.go; pkg/cmd/drain for the 5 s
# retry delay the kubectl command vk8s ran before used); host/vk8s.bend
# makes the calls through bend-kube-runtime's client:
#
#   1. cordon: a patch of spec.unschedulable to true, unless it is already
#      true (CordonHelper.UpdateIfRequired);
#   2. the node's pods: a list with the field selector spec.nodeName=NODE
#      (GetPodsForDeletion), in pages of 500 (kubectl's default chunk);
#   3. each pod through the filters (makeFilters: skipDeleted, daemonSet,
#      mirrorPod, localStorage, unreplicated; the first that keeps the pod
#      stops the chain, else the last status counts); a DaemonSet-managed
#      pod that is still running needs its DaemonSet looked up first;
#   4. an Eviction (policy/v1) for each pod to delete, through the pods'
#      eviction subresource, with gracePeriodSeconds 30; a 429 (a
#      PodDisruptionBudget) retries after 5 s, a 404 is done;
#   5. each evicted pod waited for (1 s polls) until it is gone or a pod of
#      another UID took its name; all within 30 minutes.

# A pod as the filters see it.
#   ctrl: it has a controller (metav1.GetControllerOf: an owner reference
#     with controller: true);
#   ds: that controller is a DaemonSet of apps/v1 (isControllerRefDaemonSet);
#   finished: its phase is Succeeded or Failed;
#   mirror: it carries the kubernetes.io/config.mirror annotation;
#   empty_dir: one of its volumes is an emptyDir (hasLocalStorage);
#   deleting: it has a deletionTimestamp.
type Pod is Data:
  Pod{ns: String, name: String, uid: String, ctrl: Bool, ds: Bool, ds_name: String, finished: Bool,
    mirror: Bool, empty_dir: Bool, deleting: Bool}

def Drain.Pod.ns(p: Pod) -> String:
  match p:
    case Pod{ns, name, uid, ctrl, ds, dn, fin, mirror, empty, del}:
      ns

def Drain.Pod.name(p: Pod) -> String:
  match p:
    case Pod{ns, name, uid, ctrl, ds, dn, fin, mirror, empty, del}:
      name

def Drain.Pod.uid(p: Pod) -> String:
  match p:
    case Pod{ns, name, uid, ctrl, ds, dn, fin, mirror, empty, del}:
      uid

def Drain.Pod.deleting(p: Pod) -> Bool:
  match p:
    case Pod{ns, name, uid, ctrl, ds, dn, fin, mirror, empty, del}:
      del

# What the DaemonSet lookup of a DaemonSet-managed pod answered: found, not
# found (with the API's message), or another error.
type DsAns is Data:
  DsFound{}
  DsGone{msg: String}
  DsErr{msg: String}

# kubectl's PodDeleteStatus: whether the pod goes, the reason ("Okay",
# "Skip", "Warning", "Error") and the message.
type Status is Data:
  Status{delete: Bool, reason: String, message: String}

# What an eviction answered: accepted (wait for the pod to go), the pod is
# gone already, retry after the delay, or a failure.
type Evict is Data:
  EvOk{}
  EvGone{}
  EvRetry{}
  EvFail{}

# One poll of an evicted pod: gone, still there, or the poll failed.
type Wait is Data:
  WGone{}
  WPending{}
  WFail{}

# Settings (vcluster's drain.Helper; the kubectl command's retry delay)
# --------------------------------------------------------------------

def Drain.grace() -> U32:
  30

def Drain.timeout_secs() -> U32:
  1800

def Drain.retry_ms() -> U32:
  5000

def Drain.poll_ms() -> U32:
  1000

def Drain.chunk() -> U32:
  500

# Pod statuses (filters.go)
# -------------------------

def Drain.ds_warning() -> String:
  "ignoring DaemonSet-managed Pods"

def Drain.local_warning() -> String:
  "deleting Pods with local storage"

def Drain.unmanaged_warning() -> String:
  "deleting Pods that declare no controller"

def Drain.okay() -> Status:
  Status{True{}, "Okay", ""}

def Drain.skip() -> Status:
  Status{False{}, "Skip", ""}

def Drain.warn(d: Bool, +m: String) -> Status:
  Status{d, "Warning", m}

def Drain.error(+m: String) -> Status:
  Status{False{}, "Error", m}

def Drain.Status.delete(s: Status) -> Bool:
  match s:
    case Status{d, r, m}:
      d

def Drain.then.go(d: Bool, +r: String, +m: String, next: Status) -> Status:
  match d:
    case True{}:
      next
    case False{}:
      Status{False{}, r, m}

# The filter chain: a status that keeps the pod stops it; one that deletes
# it hands on to the next filter.
def Drain.then(s: Status, next: Status) -> Status:
  match s:
    case Status{d, +r, +m}:
      Drain.then.go(d, r, m, next)

def Drain.f_ds.ans(ans: DsAns) -> Status:
  match ans:
    case DsFound{}:
      Drain.warn(False{}, Drain.ds_warning())
    case DsGone{m}:
      Drain.warn(True{}, m)
    case DsErr{m}:
      Drain.error(m)

# daemonSetFilter (Force, IgnoreAllDaemonSets): a running DaemonSet pod
# stays while its DaemonSet exists; an orphan goes.
def Drain.f_ds(ds: Bool, fin: Bool, ans: DsAns) -> Status:
  match ds fin:
    case True{} False{}:
      Drain.f_ds.ans(ans)
    case _ _:
      Drain.okay()

# mirrorPodFilter: a static pod's mirror stays.
def Drain.f_mirror(mirror: Bool) -> Status:
  match mirror:
    case True{}:
      Drain.skip()
    case False{}:
      Drain.okay()

# localStorageFilter (DeleteEmptyDirData).
def Drain.f_local(empty: Bool, fin: Bool) -> Status:
  match empty fin:
    case True{} False{}:
      Drain.warn(True{}, Drain.local_warning())
    case _ _:
      Drain.okay()

# unreplicatedFilter (Force).
def Drain.f_unrep(fin: Bool, ctrl: Bool) -> Status:
  match fin ctrl:
    case True{} _:
      Drain.okay()
    case False{} True{}:
      Drain.okay()
    case False{} False{}:
      Drain.warn(True{}, Drain.unmanaged_warning())

# The chain of makeFilters for a pod's facts (skipDeleted is Okay:
# vcluster sets no SkipWaitForDeleteTimeoutSeconds).
def Drain.decide(ctrl: Bool, ds: Bool, +fin: Bool, mirror: Bool, empty: Bool, ans: DsAns) -> Status:
  Drain.then(Drain.okay(), Drain.then(Drain.f_ds(ds, fin, ans), Drain.then(Drain.f_mirror(mirror),
    Drain.then(Drain.f_local(empty, fin), Drain.f_unrep(fin, ctrl)))))

def Drain.status(p: Pod, ans: DsAns) -> Status:
  match p:
    case Pod{ns, name, uid, ctrl, ds, dn, fin, mirror, empty, del}:
      Drain.decide(ctrl, ds, fin, mirror, empty, ans)

def Drain.ds_name.go(ds: Bool, fin: Bool, +n: String) -> String:
  match ds fin:
    case True{} False{}:
      n
    case _ _:
      ""

# The DaemonSet to look up before the pod's status ("" for none): the
# controller of a DaemonSet-managed pod that has not finished.
def Drain.ds_name(p: Pod) -> String:
  match p:
    case Pod{ns, name, uid, ctrl, ds, +dn, fin, mirror, empty, del}:
      Drain.ds_name.go(ds, fin, dn)

# The message the client-go error of a missing DaemonSet prints
# (apierrors.NewNotFound: `daemonsets.apps "NAME" not found`).
def Drain.ds_gone(+name: String) -> String:
  "daemonsets.apps \"" ++ name ++ "\" not found"

# A pod's facts from its JSON
# ---------------------------

def Drain.is_true(j: J.Json) -> Bool:
  match j:
    case J.JBool{b}:
      b
    case _:
      False{}

def Drain.ctrl.pick(+r: J.Json, rest: J.Json, hit: Bool) -> J.Json:
  match hit:
    case True{}:
      r
    case False{}:
      rest

# The first owner reference with controller: true (JNull for none).
def Drain.ctrl(rs: List<&2, J.Json>) -> J.Json:
  match rs:
    case Nil{}:
      J.JNull{}
    case Con{+r, t}:
      Drain.ctrl.pick(r, Drain.ctrl(t), Drain.is_true(J.Json.get(r, "controller")))

def Drain.empty_dir(vs: List<&2, J.Json>) -> Bool:
  match vs:
    case Nil{}:
      False{}
    case Con{v, t}:
      Bool.or(Bool.not(J.Json.is_null(J.Json.get(v, "emptyDir"))), Drain.empty_dir(t))

def Drain.pod.of(+meta: J.Json, +c: J.Json, +phase: String, +spec: J.Json) -> Pod:
  Pod{J.Json.str_or(J.Json.get(meta, "namespace"), ""), J.Json.str_or(J.Json.get(meta, "name"), ""),
    J.Json.str_or(J.Json.get(meta, "uid"), ""), Bool.not(J.Json.is_null(c)),
    String.eq(J.Json.str_or(J.Json.get(c, "kind"), ""), "DaemonSet") && String.eq(J.Json.str_or(J.Json.get(c, "apiVersion"), ""), "apps/v1"),
    J.Json.str_or(J.Json.get(c, "name"), ""),
    Bool.or(String.eq(phase, "Succeeded"), String.eq(phase, "Failed")),
    Bool.not(J.Json.is_null(J.Json.at(meta, ["annotations", "kubernetes.io/config.mirror"]))),
    Drain.empty_dir(J.Json.items(J.Json.get(spec, "volumes"))),
    Bool.not(J.Json.is_null(J.Json.get(meta, "deletionTimestamp")))}

def Drain.pod(+j: J.Json) -> Pod:
  +meta : J.Json = J.Json.get(j, "metadata")
  Drain.pod.of(meta, Drain.ctrl(J.Json.items(J.Json.get(meta, "ownerReferences"))),
    J.Json.str_or(J.Json.at(j, ["status", "phase"]), ""), J.Json.get(j, "spec"))

def Drain.pods(xs: List<&2, J.Json>) -> List<&2, Pod>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      Con{Drain.pod(x), Drain.pods(t)}

# Requests
# --------

# GetPodsForDeletion's field selector (fields.SelectorFromSet).
def Drain.field_selector(+node: String) -> String:
  "spec.nodeName=" ++ node

# The cordon patch (CordonHelper: spec.unschedulable set to desired).
def Drain.cordon() -> J.Json:
  J.Json.obj([J.KV{"spec", J.Json.obj([J.KV{"unschedulable", J.JBool{True{}}}])}])

# Whether the node needs the cordon patch (UpdateIfRequired: not when
# spec.unschedulable is already true).
def Drain.needs_cordon(+node: J.Json) -> Bool:
  Bool.not(Drain.is_true(J.Json.at(node, ["spec", "unschedulable"])))

# The policy/v1 Eviction of a pod (EvictPod), its delete options holding
# the grace period (makeDeleteOptions).
def Drain.eviction(+ns: String, +name: String) -> J.Json:
  J.Json.obj([J.KV{"apiVersion", J.JStr{"policy/v1"}}, J.KV{"kind", J.JStr{"Eviction"}},
    J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{name}}, J.KV{"namespace", J.JStr{ns}}])},
    J.KV{"deleteOptions", J.Json.obj([J.KV{"gracePeriodSeconds", J.Json.u32(Drain.grace())}])}])

# The eviction subresource of a pod.
def Drain.eviction_path(+ns: String, +name: String) -> String:
  "/api/v1/namespaces/" ++ ns ++ "/pods/" ++ name ++ "/eviction"

# Answers
# -------

def Drain.cause_term(cs: List<&2, J.Json>) -> Bool:
  match cs:
    case Nil{}:
      False{}
    case Con{c, t}:
      Bool.or(String.eq(J.Json.str_or(J.Json.get(c, "type"), ""), "NamespaceTerminating"), Drain.cause_term(t))

# Whether an API Status names the NamespaceTerminating cause
# (apierrors.HasStatusCause(err, corev1.NamespaceTerminatingCause)).
def Drain.terminating(+status: J.Json) -> Bool:
  Drain.cause_term(J.Json.items(J.Json.at(status, ["details", "causes"])))

def Drain.on_evict.go(ok: Bool, nf: Bool, tmr: Bool, term: Bool, deleting: Bool) -> Evict:
  match ok nf tmr term deleting:
    case True{} _ _ _ _:
      EvOk{}
    case False{} True{} _ _ _:
      EvGone{}
    case False{} False{} True{} _ _:
      EvRetry{}
    case False{} False{} False{} True{} True{}:
      EvOk{}
    case False{} False{} False{} True{} False{}:
      EvRetry{}
    case False{} False{} False{} False{} _:
      EvFail{}

# What evictPods does with an eviction's answer (HTTP status code): a
# success waits for the pod; 404 is done; 429 retries; a 403 for a
# terminating namespace waits for a pod already deleting and retries for
# another; anything else fails.
def Drain.on_evict(+code: U32, term: Bool, deleting: Bool) -> Evict:
  Drain.on_evict.go(Bool.and(U32.is_ge(code, 200), U32.is_lt(code, 300)), U32.is_eq(code, 404), U32.is_eq(code, 429),
    Bool.and(U32.is_eq(code, 403), term), deleting)

def Drain.wait.go(nf: Bool, ok: Bool, same: Bool) -> Wait:
  match nf ok same:
    case True{} _ _:
      WGone{}
    case False{} True{} False{}:
      WGone{}
    case False{} True{} True{}:
      WPending{}
    case False{} False{} _:
      WFail{}

# One poll of waitForDelete: the pod is gone on 404 or when the pod of its
# name has another UID; it is pending while the same pod is there; another
# error fails.
def Drain.wait(+code: U32, +uid_now: String, +uid_was: String) -> Wait:
  Drain.wait.go(U32.is_eq(code, 404), Bool.and(U32.is_ge(code, 200), U32.is_lt(code, 300)), String.eq(uid_now, uid_was))

def Drain.lost.one(+c: J.Json) -> Bool:
  String.eq(J.Json.str_or(J.Json.get(c, "status"), ""), "Unknown")
    && String.eq(J.Json.str_or(J.Json.get(c, "message"), ""), "Kubelet stopped posting node status.")

def Drain.lost.any(cs: List<&2, J.Json>) -> Bool:
  match cs:
    case Nil{}:
      False{}
    case Con{c, t}:
      Bool.or(Drain.lost.one(c), Drain.lost.any(t))

# vcluster's pollNodeStatus: a node condition Unknown with the message
# "Kubelet stopped posting node status." ends the drain.
def Drain.lost(+node: J.Json) -> Bool:
  Drain.lost.any(J.Json.items(J.Json.at(node, ["status", "conditions"])))

def Drain.lost_msg(+node: String) -> String:
  "node \"" ++ node ++ "\" status unknown"

def Drain.lost_warning(+node: String) -> String:
  "The status of node \"" ++ node ++ "\" is unknown. This may indicate the node was shutdown or lost connectivity.  If so, try rerunning with --drain=false"

# Messages
# --------

def Drain.ref(p: Pod) -> String:
  match p:
    case Pod{ns, name, uid, ctrl, ds, dn, fin, mirror, empty, del}:
      ns ++ "/" ++ name

# evictPods' line for each pod.
def Drain.evicting(p: Pod) -> String:
  "evicting pod " ++ Drain.ref(p)

def Drain.has(xs: List<&2, String>, +x: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{+y, t}:
      Bool.or(String.eq(y, x), Drain.has(t, x))

def Drain.join(xs: List<&2, String>, +sep: String) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, Nil{}}:
      x
    case Con{x, t}:
      x ++ sep ++ Drain.join(t, sep)

def Drain.add_msg(+ms: List<&2, String>, +m: String, take: Bool) -> List<&2, String>:
  match take:
    case True{}:
      List.append(&2, String, ms, [m])
    case False{}:
      ms

def Drain.Status.message(s: Status) -> String:
  match s:
    case Status{d, r, m}:
      m

def Drain.Status.reason(s: Status) -> String:
  match s:
    case Status{d, r, m}:
      r

# The distinct messages of the statuses whose reason is r, in order of
# first appearance.
def Drain.msgs(ss: List<&2, Status>, +r: String, +acc: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}:
      acc
    case Con{+s, t}:
      +m : String = Drain.Status.message(s)
      +hit : Bool = Bool.and(String.eq(Drain.Status.reason(s), r), Bool.not(Drain.has(acc, m)))
      Drain.msgs(t, r, Drain.add_msg(acc, m, hit))

# The pods (ns/name) whose status has reason r and message m.
def Drain.refs(ps: List<&2, Pod>, ss: List<&2, Status>, +r: String, +m: String) -> List<&2, String>:
  match ps ss:
    case Con{+p, pt} Con{+s, st}:
      +hit : Bool = Bool.and(String.eq(Drain.Status.reason(s), r), String.eq(Drain.Status.message(s), m))
      List.append(&2, String, Bool.pick(List<&2, String>, hit, [Drain.ref(p)], []), Drain.refs(pt, st, r, m))
    case _ _:
      Nil{}

def Drain.groups(ms: List<&2, String>, +ps: List<&2, Pod>, +ss: List<&2, Status>, +r: String, +pre: String, +empty: String) -> List<&2, String>:
  match ms:
    case Nil{}:
      Nil{}
    case Con{+m, t}:
      +key : String = Bool.pick(String, String.is_empty(m), empty, m)
      Con{pre ++ key ++ ": " ++ Drain.join(Drain.refs(ps, ss, r, m), ", "), Drain.groups(t, ps, ss, r, pre, empty)}

# utilerrors.NewAggregate(errs).Error(): one error as it is, several as
# "[a, b]".
def Drain.aggregate(xs: List<&2, String>) -> String:
  match xs:
    case Con{x, Nil{}}:
      x
    case Nil{}:
      ""
    case ys:
      "[" ++ Drain.join(ys, ", ") ++ "]"

# PodDeleteList.Warnings: "MESSAGE: ns/a, ns/b" per message, joined by
# "; " ("" when there are none). Go orders the messages by map iteration;
# here they come in order of first appearance.
def Drain.warnings(+ps: List<&2, Pod>, +ss: List<&2, Status>) -> String:
  Drain.join(Drain.groups(Drain.msgs(ss, "Warning", []), ps, ss, "Warning", "", ""), "; ")

# PodDeleteList.errors, aggregated as RunNodeDrain returns them: "cannot
# delete MESSAGE: ns/a, ns/b" per message ("unexpected error" for an empty
# one); "" for none.
def Drain.errors(+ps: List<&2, Pod>, +ss: List<&2, Status>) -> String:
  Drain.aggregate(Drain.groups(Drain.msgs(ss, "Error", []), ps, ss, "Error", "cannot delete ", "unexpected error"))

# The pods whose status deletes them (PodDeleteList.Pods).
def Drain.to_evict(ps: List<&2, Pod>, ss: List<&2, Status>) -> List<&2, Pod>:
  match ps ss:
    case Con{+p, pt} Con{+s, st}:
      List.append(&2, Pod, Bool.pick(List<&2, Pod>, Drain.Status.delete(s), [p], []), Drain.to_evict(pt, st))
    case _ _:
      Nil{}

# evictPods' and waitForDelete's errors.
def Drain.evict_error(p: Pod, +why: String) -> String:
  match p:
    case Pod{ns, name, uid, ctrl, ds, dn, fin, mirror, empty, del}:
      "error when evicting pods/\"" ++ name ++ "\" -n \"" ++ ns ++ "\": " ++ why

def Drain.retry_line(p: Pod, +why: String) -> String:
  match p:
    case Pod{ns, name, uid, ctrl, ds, dn, fin, mirror, empty, del}:
      "error when evicting pods/\"" ++ name ++ "\" -n \"" ++ ns ++ "\" (will retry after 5s): " ++ why

def Drain.wait_error(p: Pod, +why: String) -> String:
  match p:
    case Pod{ns, name, uid, ctrl, ds, dn, fin, mirror, empty, del}:
      "error when waiting for pod \"" ++ name ++ "\" in namespace \"" ++ ns ++ "\" to terminate: " ++ why

# The global timeout's text (Go's time.Duration 30m: "30m0s").
def Drain.timeout_text() -> String:
  "global timeout reached: 30m0s"
