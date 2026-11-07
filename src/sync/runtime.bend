import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../translate/names.bend as N
import ../translate/meta.bend as M
import ../translate/services.bend as S

# Shared pure policy for the classic syncer. IO must preserve snapshots
# until all ordered writes succeed. A failed GET is not a missing object:
# only a 404 supplies None to a translator.
#
# Keep the existing translators' JSON and Outcome types. Their contracts
# use 0.2.0.0; the eventual IO adapter must bridge the 0.3.0.0 client at
# the boundary, without changing the architect-owned laws.

# Default enabled resources, in the architect's conformance-first order.
# Source: a8ab30e chart/values.yaml and resources/register.go. PV and node
# constructors always register, but select fake syncers by default.
# These are resource identifiers, not the upstream log/controller names.
# This list does not claim that every translator is implemented.
def Runtime.defaults() -> +List<String>:
  ["services", "endpoints", "endpointslices", "configmaps", "secrets", "pods",
   "fake-nodes", "events", "persistentvolumeclaims", "fake-persistentvolumes"]

# Generic namespaced mapping. The services adapter must use Svc.host_ref
# for the special default/kubernetes service; cluster resources have their
# own mapping and must not use this function.
def Runtime.host_name(vc: String, ns: String, name: String) -> String:
  N.Names.host_name(name, ns, vc)

# Only for translated, namespaced host resources. Real host nodes and
# events are not tagged by vk8s and require their own watch filters.
def Runtime.selector(vc: String) -> String:
  M.Meta.marker_label() ++ "=" ++ vc

# Annotations, not splitting the translated name, recover the virtual key.
# An empty name is unmapped; the IO adapter must not GET an empty key.
def Runtime.virtual_key(annotations: List<&2, J.KV>) -> String & String:
  +ann = S.Svc.map(J.Json.obj(annotations))
  ns name = M.Meta.lookup(M.Meta.namespace_annotation(), ann) M.Meta.lookup(M.Meta.name_annotation(), ann)
  (ns, name)

# vk8s architecture: Lease in the virtual cluster's kube-system.
# Upstream uses SafeConcatName("vcluster", vc, "controller") on the host.
def Runtime.lease_name(vc: String) -> String:
  "vcluster-syncer-" ++ vc

# delay is used only for RequeueAfter. NoRequeue and RequeueNow both have
# zero delay, but remain distinct constructors in the returned Outcome.
def Runtime.milliseconds.if(large: Bool, seconds: U32) -> U32:
  match large:
    case True{}:
      4294967295
    case False{}:
      (seconds * 1000 : U32)

def Runtime.delay(rq: S.Requeue) -> U32:
  match rq:
    case S.NoRequeue{}:
      0
    case S.RequeueNow{}:
      0
    case S.RequeueAfter{+seconds}:
      Runtime.milliseconds.if(U32.is_gt(seconds, 4294967), seconds)

# Four stable buckets. Preserve translator order inside each bucket.
# Host writes precede virtual writes; deletes precede replacement writes
# within each cluster. These writes belong to one reconcile, not a batch
# of unrelated resource kinds.
def Runtime.phase(w: S.Write) -> U32:
  match w:
    case S.HostDelete{ns, name}:
      0
    case S.HostCreate{o}:
      1
    case S.HostUpdate{o}:
      1
    case S.VirtualDelete{ns, name}:
      2
    case S.VirtualCreate{o}:
      3
    case S.VirtualUpdate{o}:
      3

def Runtime.keep(yes: Bool, w: S.Write, rest: List<&2, S.Write>) -> List<&2, S.Write>:
  match yes:
    case True{}:
      w <> rest
    case False{}:
      rest

def Runtime.bucket(ws: List<&2, S.Write>, +phase: U32) -> List<&2, S.Write>:
  match ws:
    case Nil{}:
      []
    case Con{+w, rest}:
      Runtime.keep(U32.is_eq(Runtime.phase(w), phase), w, Runtime.bucket(rest, phase))

# Equal work in each parallel branch: two scans of the same write list.
def Runtime.half(+ws: List<&2, S.Write>, +phase: U32) -> List<&2, S.Write>:
  deletes writes = Runtime.bucket(ws, phase) Runtime.bucket(ws, (phase + 1 : U32))
  List.append(&2, S.Write, deletes, writes)

def Runtime.order(+ws: List<&2, S.Write>) -> List<&2, S.Write>:
  host virtual = Runtime.half(ws, 0) Runtime.half(ws, 2)
  List.append(&2, S.Write, host, virtual)

def Runtime.ordered(out: S.Outcome) -> S.Outcome:
  match out:
    case S.Outcome{ws, rq}:
      S.Outcome{Runtime.order(ws), rq}

def Runtime.requeue(out: S.Outcome) -> S.Requeue:
  match out:
    case S.Outcome{ws, rq}:
      rq

# Comparison for the executable tests: use the translators' canonical
# comparison, never JSON text or object member order.
def Runtime.same_write(a: S.Write, b: S.Write) -> Bool:
  match a b:
    case S.HostCreate{x} S.HostCreate{y}:
      S.Svc.eq(x, y)
    case S.HostUpdate{x} S.HostUpdate{y}:
      S.Svc.eq(x, y)
    case S.VirtualCreate{x} S.VirtualCreate{y}:
      S.Svc.eq(x, y)
    case S.VirtualUpdate{x} S.VirtualUpdate{y}:
      S.Svc.eq(x, y)
    case S.HostDelete{ns, n} S.HostDelete{ms, m}:
      Bool.and(String.eq(ns, ms), String.eq(n, m))
    case S.VirtualDelete{ns, n} S.VirtualDelete{ms, m}:
      Bool.and(String.eq(ns, ms), String.eq(n, m))
    case _ _:
      False{}

def Runtime.same_writes(xs: List<&2, S.Write>, ys: List<&2, S.Write>) -> Bool:
  match xs ys:
    case Nil{} Nil{}:
      True{}
    case Con{x, xt} Con{y, yt}:
      Bool.and(Runtime.same_write(x, y), Runtime.same_writes(xt, yt))
    case _ _:
      False{}
