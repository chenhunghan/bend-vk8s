import Base
import bend-kube-runtime@0.11.0.0/src/json.bend as J
import ../laws/drain.bend as L
import ../src/cli/drain.bend as D

# Proofs of laws/drain.bend: `def L.<law>` for each law. The concrete laws
# compute; the general ones split on the facts the filters match.

def L.drain.grace():
  {==}

def L.drain.timeout():
  {==}

def L.drain.retry():
  {==}

def L.drain.poll():
  {==}

def L.drain.chunk():
  {==}

def L.drain.status.managed():
  {==}

def L.drain.status.daemonset():
  {==}

def L.drain.status.daemonset_orphan():
  {==}

def L.drain.status.daemonset_error():
  {==}

def L.drain.status.daemonset_finished():
  {==}

def L.drain.status.mirror():
  {==}

def L.drain.status.unmanaged():
  {==}

def L.drain.status.empty_dir():
  {==}

def L.drain.status.empty_dir_unmanaged():
  {==}

def L.drain.status.finished_unmanaged():
  {==}

def L.drain.ds_name.running():
  {==}

def L.drain.ds_name.finished():
  {==}

def L.drain.ds_name.other():
  {==}

def L.drain.pod.daemonset():
  {==}

def L.drain.pod.daemonset_other_api():
  {==}

def L.drain.pod.not_controller():
  {==}

def L.drain.pod.mirror_emptydir_failed():
  {==}

def L.drain.pod.succeeded():
  {==}

def L.drain.field_selector():
  {==}

def L.drain.cordon():
  {==}

def L.drain.needs_cordon.schedulable():
  {==}

def L.drain.needs_cordon.cordoned():
  {==}

def L.drain.eviction.api():
  {==}

def L.drain.eviction.kind():
  {==}

def L.drain.eviction.name():
  {==}

def L.drain.eviction.namespace():
  {==}

def L.drain.eviction.grace():
  {==}

def L.drain.eviction_path():
  {==}

def L.drain.evict.created():
  {==}

def L.drain.evict.ok():
  {==}

def L.drain.evict.not_found():
  {==}

def L.drain.evict.pdb():
  {==}

def L.drain.evict.terminating_deleting():
  {==}

def L.drain.evict.terminating():
  {==}

def L.drain.evict.forbidden():
  {==}

def L.drain.evict.error():
  {==}

def L.drain.terminating():
  {==}

def L.drain.terminating.none():
  {==}

def L.drain.wait.not_found():
  {==}

def L.drain.wait.replaced():
  {==}

def L.drain.wait.same():
  {==}

def L.drain.wait.error():
  {==}

def L.drain.lost():
  {==}

def L.drain.lost.ready():
  {==}

def L.drain.lost_msg():
  {==}

def L.drain.evicting():
  {==}

def L.drain.warnings():
  {==}

def L.drain.warnings.none():
  {==}

def L.drain.errors():
  {==}

def L.drain.to_evict():
  {==}

def L.drain.mirror_stays(ctrl, ds, fin, empty, ans):
  match ds fin ans:
    case True{} False{} D.DsFound{}:
      {==}
    case True{} False{} D.DsGone{m}:
      {==}
    case True{} False{} D.DsErr{m}:
      {==}
    case True{} True{} a:
      {==}
    case False{} f a:
      {==}

def L.drain.finished_goes(ctrl, ds, empty, ans):
  match ds empty:
    case True{} True{}:
      {==}
    case True{} False{}:
      {==}
    case False{} True{}:
      {==}
    case False{} False{}:
      {==}

def L.drain.evict_error():
  {==}

def L.drain.retry_line():
  {==}

def L.drain.wait_error():
  {==}

def L.drain.timeout_text():
  {==}

def L.drain.aggregate.one():
  {==}

def L.drain.aggregate.two():
  {==}

def L.drain.aggregate.none():
  {==}
