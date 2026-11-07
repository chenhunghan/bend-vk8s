import Base
import ../host/syncer.bend as S
import bend-kube-runtime@0.5.1.0/src/queue.bend as Q
import bend-kube-runtime@0.2.0.0/src/json.bend as J

# An early list queues a key while another source has not listed yet.
# Readiness must be checked before pop marks the key as running.
def T.pending() -> S.SSt:
  S.SSt{Nil{}, Q.Queue.add(Q.Queue.new(1), "services/default/before-start"),
    Map.new(&2, J.Json), Map.new(&2, J.Json)}

def T.check(ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS initial list keeps its key until stores are ready")
    case False{}:
      IO.print("FAIL initial list loses its key before stores are ready")

def T.ready(r: S.SSt & Maybe<&2, String>) -> IO(Unit):
  match r:
    case (s, Some{k}):
      T.check(String.eq(k, "services/default/before-start"))
    case (s, None{}):
      T.check(False{})

def T.waiting(r: S.SSt & Maybe<&2, String>) -> IO(Unit):
  match r:
    case (s, None{}):
      T.ready(S.Sync.pop_ready(True{}, s))
    case (s, Some{k}):
      T.check(False{})

def main() -> IO(Unit):
  T.waiting(S.Sync.pop_ready(False{}, T.pending()))
