import Base
import bend-kube-runtime@0.11.0.0/src/json.bend as J
import ../src/cli/drain.bend as D

# Spec for src/cli/drain.bend: vk8s node delete's drain, as vcluster's
# node delete runs kubectl's drain library (vcluster
# cmd/vclusterctl/cmd/node/delete.go: Force, IgnoreAllDaemonSets,
# DeleteEmptyDirData, GracePeriodSeconds 30, Timeout 30m) instead of a
# kubectl process (docs/GOAL.md section 11, fewer shell-outs).
#
# Proposed: every law in this file (new module). Expected values come from
# k8s.io/kubectl v0.36.3 (vcluster's go.mod): pkg/drain/filters.go (the
# filter chain and its messages), pkg/drain/drain.go (EvictPod, evictPods,
# waitForDelete, GetPodsForDeletion), pkg/drain/cordon.go, and
# pkg/cmd/drain/drain.go (EvictErrorRetryDelay 5 s, the kubectl command's,
# which vk8s ran before; ChunkSize cmdutil.DefaultChunkSize 500); and
# vcluster's pollNodeStatus for the lost-node check.

# Fixtures: a pod's facts as the filters see them.
def Laws.drain.pod(ctrl: Bool, ds: Bool, fin: Bool, mirror: Bool, empty: Bool) -> D.Pod:
  D.Pod{"default", "p", "u1", ctrl, ds, "ds1", fin, mirror, empty, False{}}

# Settings (drain.Helper in vcluster's delete.go; the kubectl command's
# retry delay and chunk size).
law drain.grace:
  {D.Drain.grace() == 30 : U32}

law drain.timeout:
  {D.Drain.timeout_secs() == 1800 : U32}

law drain.retry:
  {D.Drain.retry_ms() == 5000 : U32}

law drain.poll:
  {D.Drain.poll_ms() == 1000 : U32}

law drain.chunk:
  {D.Drain.chunk() == 500 : U32}

# The filter chain (filters.go). A pod of a ReplicaSet goes.
law drain.status.managed:
  {D.Drain.status(Laws.drain.pod(True{}, False{}, False{}, False{}, False{}), D.DsFound{})
    == D.Status{True{}, "Okay", ""} : D.Status}

# A running DaemonSet pod whose DaemonSet exists stays, with
# daemonSetWarning (IgnoreAllDaemonSets).
law drain.status.daemonset:
  {D.Drain.status(Laws.drain.pod(True{}, True{}, False{}, False{}, False{}), D.DsFound{})
    == D.Status{False{}, "Warning", "ignoring DaemonSet-managed Pods"} : D.Status}

# An orphaned DaemonSet pod goes (Force); the later filters' Okay replaces
# the orphan warning.
law drain.status.daemonset_orphan:
  {D.Drain.status(Laws.drain.pod(True{}, True{}, False{}, False{}, False{}), D.DsGone{"daemonsets.apps \"ds1\" not found"})
    == D.Status{True{}, "Okay", ""} : D.Status}

# Another error looking the DaemonSet up keeps the pod as an error.
law drain.status.daemonset_error:
  {D.Drain.status(Laws.drain.pod(True{}, True{}, False{}, False{}, False{}), D.DsErr{"boom"})
    == D.Status{False{}, "Error", "boom"} : D.Status}

# A finished DaemonSet pod goes.
law drain.status.daemonset_finished:
  {D.Drain.status(Laws.drain.pod(True{}, True{}, True{}, False{}, False{}), D.DsFound{})
    == D.Status{True{}, "Okay", ""} : D.Status}

# A mirror pod is skipped.
law drain.status.mirror:
  {D.Drain.status(Laws.drain.pod(False{}, False{}, False{}, True{}, False{}), D.DsFound{})
    == D.Status{False{}, "Skip", ""} : D.Status}

# A running pod with no controller goes, with unmanagedWarning (Force).
law drain.status.unmanaged:
  {D.Drain.status(Laws.drain.pod(False{}, False{}, False{}, False{}, False{}), D.DsFound{})
    == D.Status{True{}, "Warning", "deleting Pods that declare no controller"} : D.Status}

# The local storage warning is dropped by the unreplicated filter (the
# TODO in localStorageFilter): a managed pod with an emptyDir is Okay.
law drain.status.empty_dir:
  {D.Drain.status(Laws.drain.pod(True{}, False{}, False{}, False{}, True{}), D.DsFound{})
    == D.Status{True{}, "Okay", ""} : D.Status}

law drain.status.empty_dir_unmanaged:
  {D.Drain.status(Laws.drain.pod(False{}, False{}, False{}, False{}, True{}), D.DsFound{})
    == D.Status{True{}, "Warning", "deleting Pods that declare no controller"} : D.Status}

# A finished pod with no controller goes without a warning.
law drain.status.finished_unmanaged:
  {D.Drain.status(Laws.drain.pod(False{}, False{}, True{}, False{}, False{}), D.DsFound{})
    == D.Status{True{}, "Okay", ""} : D.Status}

# A mirror pod never goes, whatever else holds.
law drain.mirror_stays:
  for ctrl: Bool
  for ds: Bool
  for fin: Bool
  for empty: Bool
  for ans: D.DsAns
  {D.Drain.Status.delete(D.Drain.decide(ctrl, ds, fin, True{}, empty, ans)) == False{} : Bool}

# A finished pod that is not a mirror always goes.
law drain.finished_goes:
  for ctrl: Bool
  for ds: Bool
  for empty: Bool
  for ans: D.DsAns
  {D.Drain.Status.delete(D.Drain.decide(ctrl, ds, True{}, False{}, empty, ans)) == True{} : Bool}

# Only a running DaemonSet pod needs its DaemonSet looked up.
law drain.ds_name.running:
  {D.Drain.ds_name(Laws.drain.pod(True{}, True{}, False{}, False{}, False{})) == "ds1" : String}

law drain.ds_name.finished:
  {D.Drain.ds_name(Laws.drain.pod(True{}, True{}, True{}, False{}, False{})) == "" : String}

law drain.ds_name.other:
  {D.Drain.ds_name(Laws.drain.pod(True{}, False{}, False{}, False{}, False{})) == "" : String}

# A pod's facts from its JSON: GetControllerOf takes the owner reference
# with controller: true; isControllerRefDaemonSet needs kind DaemonSet and
# apiVersion apps/v1; the mirror annotation is kubernetes.io/config.mirror
# (corev1.MirrorPodAnnotationKey).
def Laws.drain.ref(kind: String, api: String, ctrl: Bool) -> J.Json:
  J.Json.obj([J.KV{"apiVersion", J.JStr{api}}, J.KV{"kind", J.JStr{kind}}, J.KV{"name", J.JStr{"o"}},
    J.KV{"controller", J.JBool{ctrl}}])

def Laws.drain.json(refs: List<&2, J.Json>, +anns: List<&2, J.KV>, +phase: String, vols: List<&2, J.Json>) -> J.Json:
  J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"p"}}, J.KV{"namespace", J.JStr{"ns"}}, J.KV{"uid", J.JStr{"u"}},
    J.KV{"annotations", J.Json.obj(anns)}, J.KV{"ownerReferences", J.Json.arr(refs)}])},
    J.KV{"spec", J.Json.obj([J.KV{"volumes", J.Json.arr(vols)}])},
    J.KV{"status", J.Json.obj([J.KV{"phase", J.JStr{phase}}])}])

law drain.pod.daemonset:
  {D.Drain.pod(Laws.drain.json([Laws.drain.ref("DaemonSet", "apps/v1", True{})], [], "Running", []))
    == D.Pod{"ns", "p", "u", True{}, True{}, "o", False{}, False{}, False{}, False{}} : D.Pod}

# A DaemonSet of another API version is not one (isControllerRefDaemonSet).
law drain.pod.daemonset_other_api:
  {D.Drain.pod(Laws.drain.json([Laws.drain.ref("DaemonSet", "extensions/v1beta1", True{})], [], "Running", []))
    == D.Pod{"ns", "p", "u", True{}, False{}, "o", False{}, False{}, False{}, False{}} : D.Pod}

# An owner that is not the controller does not count.
law drain.pod.not_controller:
  {D.Drain.pod(Laws.drain.json([Laws.drain.ref("DaemonSet", "apps/v1", False{})], [], "Running", []))
    == D.Pod{"ns", "p", "u", False{}, False{}, "", False{}, False{}, False{}, False{}} : D.Pod}

law drain.pod.mirror_emptydir_failed:
  {D.Drain.pod(Laws.drain.json([], [J.KV{"kubernetes.io/config.mirror", J.JStr{"abc"}}], "Failed",
      [J.Json.obj([J.KV{"name", J.JStr{"v"}}, J.KV{"emptyDir", J.Json.obj([])}])]))
    == D.Pod{"ns", "p", "u", False{}, False{}, "", True{}, True{}, True{}, False{}} : D.Pod}

law drain.pod.succeeded:
  {D.Drain.pod(Laws.drain.json([], [], "Succeeded", []))
    == D.Pod{"ns", "p", "u", False{}, False{}, "", True{}, False{}, False{}, False{}} : D.Pod}

# Requests: GetPodsForDeletion's field selector, the cordon patch, the
# policy/v1 Eviction with the grace period, on the pods/eviction
# subresource.
law drain.field_selector:
  {D.Drain.field_selector("w-1") == "spec.nodeName=w-1" : String}

law drain.cordon:
  {J.Json.show(D.Drain.cordon()) == "{\"spec\":{\"unschedulable\":true}}" : String}

law drain.needs_cordon.schedulable:
  {D.Drain.needs_cordon(J.Json.obj([J.KV{"spec", J.Json.obj([])}])) == True{} : Bool}

law drain.needs_cordon.cordoned:
  {D.Drain.needs_cordon(J.Json.obj([J.KV{"spec", J.Json.obj([J.KV{"unschedulable", J.JBool{True{}}}])}])) == False{} : Bool}

# EvictPod's policy/v1 Eviction (field by field: Go's encoder adds
# "creationTimestamp":null to the metadata, which the API ignores).
law drain.eviction.api:
  {J.Json.at(D.Drain.eviction("ns", "p"), ["apiVersion"]) == J.JStr{"policy/v1"} : J.Json}

law drain.eviction.kind:
  {J.Json.at(D.Drain.eviction("ns", "p"), ["kind"]) == J.JStr{"Eviction"} : J.Json}

law drain.eviction.name:
  {J.Json.at(D.Drain.eviction("ns", "p"), ["metadata", "name"]) == J.JStr{"p"} : J.Json}

law drain.eviction.namespace:
  {J.Json.at(D.Drain.eviction("ns", "p"), ["metadata", "namespace"]) == J.JStr{"ns"} : J.Json}

law drain.eviction.grace:
  {J.Json.at(D.Drain.eviction("ns", "p"), ["deleteOptions", "gracePeriodSeconds"]) == J.JNum{"30"} : J.Json}

law drain.eviction_path:
  {D.Drain.eviction_path("ns", "p") == "/api/v1/namespaces/ns/pods/p/eviction" : String}

# evictPods: success waits, 404 is done, 429 retries, a terminating
# namespace's 403 waits for a deleting pod and retries another, the rest
# fail.
law drain.evict.created:
  {D.Drain.on_evict(201, False{}, False{}) == D.EvOk{} : D.Evict}

law drain.evict.ok:
  {D.Drain.on_evict(200, False{}, False{}) == D.EvOk{} : D.Evict}

law drain.evict.not_found:
  {D.Drain.on_evict(404, False{}, False{}) == D.EvGone{} : D.Evict}

law drain.evict.pdb:
  {D.Drain.on_evict(429, False{}, False{}) == D.EvRetry{} : D.Evict}

law drain.evict.terminating_deleting:
  {D.Drain.on_evict(403, True{}, True{}) == D.EvOk{} : D.Evict}

law drain.evict.terminating:
  {D.Drain.on_evict(403, True{}, False{}) == D.EvRetry{} : D.Evict}

law drain.evict.forbidden:
  {D.Drain.on_evict(403, False{}, True{}) == D.EvFail{} : D.Evict}

law drain.evict.error:
  {D.Drain.on_evict(500, False{}, False{}) == D.EvFail{} : D.Evict}

law drain.terminating:
  {D.Drain.terminating(J.Json.obj([J.KV{"details", J.Json.obj([J.KV{"causes",
      J.Json.arr([J.Json.obj([J.KV{"type", J.JStr{"NamespaceTerminating"}}])])}])}])) == True{} : Bool}

law drain.terminating.none:
  {D.Drain.terminating(J.Json.obj([J.KV{"reason", J.JStr{"Forbidden"}}])) == False{} : Bool}

# waitForDelete: gone on 404 or another UID, pending on the same pod, an
# error otherwise.
law drain.wait.not_found:
  {D.Drain.wait(404, "", "u1") == D.WGone{} : D.Wait}

law drain.wait.replaced:
  {D.Drain.wait(200, "u2", "u1") == D.WGone{} : D.Wait}

law drain.wait.same:
  {D.Drain.wait(200, "u1", "u1") == D.WPending{} : D.Wait}

law drain.wait.error:
  {D.Drain.wait(500, "", "u1") == D.WFail{} : D.Wait}

# vcluster's pollNodeStatus.
law drain.lost:
  {D.Drain.lost(J.Json.obj([J.KV{"status", J.Json.obj([J.KV{"conditions", J.Json.arr([
      J.Json.obj([J.KV{"type", J.JStr{"Ready"}}, J.KV{"status", J.JStr{"Unknown"}}, J.KV{"message", J.JStr{"Kubelet stopped posting node status."}}])])}])}]))
    == True{} : Bool}

law drain.lost.ready:
  {D.Drain.lost(J.Json.obj([J.KV{"status", J.Json.obj([J.KV{"conditions", J.Json.arr([
      J.Json.obj([J.KV{"type", J.JStr{"Ready"}}, J.KV{"status", J.JStr{"True"}}, J.KV{"message", J.JStr{"kubelet is posting ready status"}}])])}])}]))
    == False{} : Bool}

law drain.lost_msg:
  {D.Drain.lost_msg("w-1") == "node \"w-1\" status unknown" : String}

# Messages: evictPods' line; Warnings and errors (one message each, where
# Go's map order cannot matter).
law drain.evicting:
  {D.Drain.evicting(Laws.drain.pod(True{}, False{}, False{}, False{}, False{})) == "evicting pod default/p" : String}

law drain.warnings:
  {D.Drain.warnings([D.Pod{"kube-system", "a", "", True{}, True{}, "d", False{}, False{}, False{}, False{}},
      D.Pod{"kube-system", "b", "", True{}, True{}, "d", False{}, False{}, False{}, False{}},
      D.Pod{"default", "c", "", True{}, False{}, "", False{}, False{}, False{}, False{}}],
      [D.Status{False{}, "Warning", "ignoring DaemonSet-managed Pods"}, D.Status{False{}, "Warning", "ignoring DaemonSet-managed Pods"},
       D.Status{True{}, "Okay", ""}])
    == "ignoring DaemonSet-managed Pods: kube-system/a, kube-system/b" : String}

law drain.warnings.none:
  {D.Drain.warnings([D.Pod{"default", "c", "", True{}, False{}, "", False{}, False{}, False{}, False{}}], [D.Status{True{}, "Okay", ""}])
    == "" : String}

law drain.errors:
  {D.Drain.errors([D.Pod{"default", "a", "", True{}, True{}, "d", False{}, False{}, False{}, False{}}],
      [D.Status{False{}, "Error", "boom"}])
    == "cannot delete boom: default/a" : String}

law drain.to_evict:
  {D.Drain.to_evict([D.Pod{"default", "a", "", True{}, False{}, "", False{}, False{}, False{}, False{}},
      D.Pod{"default", "b", "", True{}, True{}, "d", False{}, False{}, False{}, False{}}],
      [D.Status{True{}, "Okay", ""}, D.Status{False{}, "Warning", "ignoring DaemonSet-managed Pods"}])
    == [D.Pod{"default", "a", "", True{}, False{}, "", False{}, False{}, False{}, False{}}] : List<&2, D.Pod>}

# evictPods' and waitForDelete's messages (drain.go's format strings with
# %q, the retry delay printed as Go prints 5 * time.Second, the global
# timeout as 30 * time.Minute).
law drain.evict_error:
  {D.Drain.evict_error(Laws.drain.pod(True{}, False{}, False{}, False{}, False{}), "boom")
    == "error when evicting pods/\"p\" -n \"default\": boom" : String}

law drain.retry_line:
  {D.Drain.retry_line(Laws.drain.pod(True{}, False{}, False{}, False{}, False{}), "pdb")
    == "error when evicting pods/\"p\" -n \"default\" (will retry after 5s): pdb" : String}

law drain.wait_error:
  {D.Drain.wait_error(Laws.drain.pod(True{}, False{}, False{}, False{}, False{}), "context deadline exceeded")
    == "error when waiting for pod \"p\" in namespace \"default\" to terminate: context deadline exceeded" : String}

law drain.timeout_text:
  {D.Drain.timeout_text() == "global timeout reached: 30m0s" : String}

# utilerrors.NewAggregate's text: one error as it is, several in brackets.
law drain.aggregate.one:
  {D.Drain.aggregate(["a"]) == "a" : String}

law drain.aggregate.two:
  {D.Drain.aggregate(["a", "b"]) == "[a, b]" : String}

law drain.aggregate.none:
  {D.Drain.aggregate([]) == "" : String}
