import Base
import ./snap.bend as S

# The node snapshotter's state on the node disk (<root>/state), so a
# restart of the snapshotter (the supervisor restarts it 5 s after an
# exit) or a reboot keeps every snapshot containerd knows, as the overlay
# snapshotter keeps its own in metadata.db (core/snapshots/storage/
# bolt.go). Pure: the text of a state, and the state of a text. The host
# writes <root>/state.tmp and renames it over <root>/state after every
# call that changes the state (src/layers/pb.bend Spb.dirty).
#
# Format (vk8s design): line 1 "bend-snap 1"; line 2 "next <id>"; then
# one line per snapshot, in the snapshotter's order, of space-separated
# fields: key, id, kind (active, view, committed), parent, layer,
# created, updated, then each label's key and value. Each field is "="
# and its text with %, space, newline, carriage return and tab written
# %p, %s, %n, %r and %t, so a field never holds a separator and an
# empty one is "=". The root and the node name are the snapshotter's
# arguments, not part of the file.

def Sst.esc.c(+c: U32) -> String:
  Bool.pick(String, U32.is_eq(c, 37), "%p",
  Bool.pick(String, U32.is_eq(c, 32), "%s",
  Bool.pick(String, U32.is_eq(c, 10), "%n",
  Bool.pick(String, U32.is_eq(c, 13), "%r",
  Bool.pick(String, U32.is_eq(c, 9), "%t", SCon{Chr{c}, SNil{}})))))

def Sst.esc(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{Chr{+c}, t}:
      Sst.esc.c(c) ++ Sst.esc(t)

# The code an escape's letter stands for; any other letter stands for
# itself.
def Sst.unesc.code(+d: U32) -> U32:
  Bool.pick(U32, U32.is_eq(d, 112), 37,
  Bool.pick(U32, U32.is_eq(d, 115), 32,
  Bool.pick(U32, U32.is_eq(d, 110), 10,
  Bool.pick(U32, U32.is_eq(d, 114), 13,
  Bool.pick(U32, U32.is_eq(d, 116), 9, d)))))

def Sst.unesc.head(esc: Bool, +c: U32, t: String) -> Char:
  match esc t:
    case True{} SCon{Chr{+d}, r}:
      Chr{Sst.unesc.code(d)}
    case _ _:
      Chr{c}

def Sst.unesc.tail(esc: Bool, +t: String) -> String:
  match esc:
    case True{}:
      String.drop(t, 1n)
    case False{}:
      t

def Sst.unesc.go(fuel: Nat, s: String) -> String:
  match fuel s:
    case 0n _:
      SNil{}
    case 1n+f SNil{}:
      SNil{}
    case 1n+f SCon{Chr{+c}, +t}:
      +esc : Bool = U32.is_eq(c, 37) && Bool.not(String.is_empty(t))
      SCon{Sst.unesc.head(esc, c, t), Sst.unesc.go(f, Sst.unesc.tail(esc, t))}

def Sst.unesc(+s: String) -> String:
  Sst.unesc.go(String.length(s), s)

def Sst.field(s: String) -> String:
  " =" ++ Sst.esc(s)

# A field's text: past its "=", unescaped.
def Sst.val(+f: String) -> String:
  Sst.unesc(String.drop(f, 1n))

def Sst.kind.show(k: S.SKind) -> String:
  match k:
    case S.KActive{}:
      "active"
    case S.KView{}:
      "view"
    case S.KCommitted{}:
      "committed"

def Sst.kind.read(+s: String) -> Maybe<&2, S.SKind>:
  Bool.pick(Maybe<&2, S.SKind>, String.eq(s, "active"), Some{S.KActive{}},
  Bool.pick(Maybe<&2, S.SKind>, String.eq(s, "view"), Some{S.KView{}},
  Bool.pick(Maybe<&2, S.SKind>, String.eq(s, "committed"), Some{S.KCommitted{}}, None{})))

def Sst.labels.show(ls: List<&2, S.Label>) -> String:
  match ls:
    case Nil{}:
      ""
    case Con{S.Label{k, v}, t}:
      Sst.field(k) ++ Sst.field(v) ++ Sst.labels.show(t)

def Sst.snap.show(s: S.Snap) -> String:
  match s:
    case S.Snap{k, i, kd, p, l, ls, c, u}:
      String.drop(Sst.field(k), 1n) ++ Sst.field(U32.show(i)) ++ Sst.field(Sst.kind.show(kd)) ++ Sst.field(p) ++ Sst.field(l)
        ++ Sst.field(U32.show(c)) ++ Sst.field(U32.show(u)) ++ Sst.labels.show(ls) ++ "\n"

def Sst.snaps.show(ss: List<&2, S.Snap>) -> String:
  match ss:
    case Nil{}:
      ""
    case Con{s, t}:
      Sst.snap.show(s) ++ Sst.snaps.show(t)

# The text of a state.
def Sst.show(sn: S.Sn) -> String:
  match sn:
    case S.Sn{r, n, x, ss}:
      "bend-snap 1\nnext " ++ U32.show(x) ++ "\n" ++ Sst.snaps.show(ss)

# Reading
# -------

def Sst.label.add(+k: String, +v: String, m: Maybe<&2, List<&2, S.Label>>) -> Maybe<&2, List<&2, S.Label>>:
  match m:
    case None{}:
      None{}
    case Some{t}:
      Some{Con{S.Label{k, v}, t}}

def Sst.labels.read(fs: List<&2, String>) -> Maybe<&2, List<&2, S.Label>>:
  match fs:
    case Nil{}:
      Some{Nil{}}
    case Con{k, Con{v, t}}:
      Sst.label.add(Sst.val(k), Sst.val(v), Sst.labels.read(t))
    case Con{k, Nil{}}:
      None{}

def Sst.snap.mk(+k: String, i: Maybe<&2, U32>, kd: Maybe<&2, S.SKind>, +p: String, +l: String, c: Maybe<&2, U32>, u: Maybe<&2, U32>,
  ls: Maybe<&2, List<&2, S.Label>>) -> Maybe<&2, S.Snap>:
  match i kd c u ls:
    case Some{+i2} Some{+kd2} Some{+c2} Some{+u2} Some{+ls2}:
      Some{S.Snap{k, i2, kd2, p, l, ls2, c2, u2}}
    case _ _ _ _ _:
      None{}

def Sst.snap.read(fs: List<&2, String>) -> Maybe<&2, S.Snap>:
  match fs:
    case Con{k, Con{i, Con{kd, Con{p, Con{l, Con{c, Con{u, ls}}}}}}}:
      Sst.snap.mk(Sst.val(k), U32.read(Sst.val(i)), Sst.kind.read(Sst.val(kd)), Sst.val(p), Sst.val(l),
        U32.read(Sst.val(c)), U32.read(Sst.val(u)), Sst.labels.read(ls))
    case _:
      None{}

def Sst.snaps.cons(m: Maybe<&2, S.Snap>, rest: Maybe<&2, List<&2, S.Snap>>) -> Maybe<&2, List<&2, S.Snap>>:
  match m rest:
    case Some{+s} Some{+t}:
      Some{Con{s, t}}
    case _ _:
      None{}

def Sst.snaps.add(empty: Bool, +l: String, rest: Maybe<&2, List<&2, S.Snap>>) -> Maybe<&2, List<&2, S.Snap>>:
  match empty:
    case True{}:
      rest
    case False{}:
      Sst.snaps.cons(Sst.snap.read(String.split(l, ' ')), rest)

def Sst.snaps.read(ls: List<&2, String>) -> Maybe<&2, List<&2, S.Snap>>:
  match ls:
    case Nil{}:
      Some{Nil{}}
    case Con{+l, t}:
      Sst.snaps.add(String.is_empty(l), l, Sst.snaps.read(t))

def Sst.read.mk(ok: Bool, +root: String, +node: String, nx: Maybe<&2, U32>, ss: Maybe<&2, List<&2, S.Snap>>) -> Maybe<&2, S.Sn>:
  match ok nx ss:
    case True{} Some{+x} Some{+t}:
      Some{S.Sn{root, node, x, t}}
    case _ _ _:
      None{}

def Sst.read.lines(+root: String, +node: String, ls: List<&2, String>) -> Maybe<&2, S.Sn>:
  match ls:
    case Con{h, Con{+n, t}}:
      Sst.read.mk(String.eq(h, "bend-snap 1") && String.starts_with(n, "next "), root, node, U32.read(String.drop(n, 5n)), Sst.snaps.read(t))
    case _:
      None{}

# The state a text holds, with the snapshotter's root and node; None for
# a text that is not one (no file: the host starts afresh and empties
# <root>/snapshots, whose directories no snapshot names).
def Sst.read(+root: String, +node: String, text: String) -> Maybe<&2, S.Sn>:
  Sst.read.lines(root, node, String.lines(text))
