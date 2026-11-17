import Base
import ../laws/layers_store.bend as L
import ../src/layers/store.bend as Y

# Proofs of laws/layers_store.bend: each law computes on both sides, but
# layers_store.gc_drops_only_free, by induction on the store.

# A free layer put in front of free layers leaves them all free.
law layers_store.put_free:
  for b: Bool
  for c: String
  for d: String
  for p: String
  for u: U32
  for r: List<&2, Y.Layer>
  for h: {Y.Lay.all_free(r) == True{} : Bool}
  {Y.Lay.all_free(Y.Lay.gc.drop.put(b, Y.Layer{c, d, p, Nil{}, u}, r)) == True{} : Bool}

def layers_store.put_free(b, c, d, p, u, r, h):
  match b:
    case True{}:
      h
    case False{}:
      h

def L.layers_store.ttl_72h():
  {==}

def L.layers_store.chain_first():
  {==}

def L.layers_store.chain_second():
  {==}

def L.layers_store.chains():
  {==}

def L.layers_store.chain_base(d):
  {==}

def L.layers_store.dir():
  {==}

def L.layers_store.tmp():
  {==}

def L.layers_store.mount():
  {==}

def L.layers_store.refuse_traversal():
  {==}

def L.layers_store.refuse_upper_hex():
  {==}

def L.layers_store.publish():
  {==}

def L.layers_store.publish_refused():
  {==}

def L.layers_store.add():
  {==}

def L.layers_store.add_twice():
  {==}

def L.layers_store.acquire():
  {==}

def L.layers_store.acquire_twice():
  {==}

def L.layers_store.acquire_missing():
  {==}

def L.layers_store.release():
  {==}

def L.layers_store.gc_fresh():
  {==}

def L.layers_store.gc_expired():
  {==}

def L.layers_store.gc_clock_back():
  {==}

def L.layers_store.gc_held():
  {==}

def L.layers_store.gc_paths():
  {==}

def L.layers_store.held_never_dropped(c, d, p, h, hs, u, now):
  {==}

# A held layer is never dropped; a free one is dropped onto free ones.
def L.layers_store.gc_drops_only_free(ls, now):
  match ls:
    case Nil{}:
      {==}
    case Con{Y.Layer{c, d, p, Nil{}, u}, t}:
      layers_store.put_free(Y.Lay.expired(u, now), c, d, p, u, Y.Lay.gc.drop(t, now), L.layers_store.gc_drops_only_free(t, now))
    case Con{Y.Layer{c, d, p, Con{x, xs}, u}, t}:
      L.layers_store.gc_drops_only_free(t, now)
