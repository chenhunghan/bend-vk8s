import Base
import bend-kube-runtime@0.12.0.0/src/pb.bend as P
import ../oci/size.bend as N
import ./snap.bend as S
import ./store.bend as Y
import ./fill.bend as F

# containerd's snapshots API on the wire, for the node's proxy
# snapshotter (host/snapshotter.bend). containerd talks to a proxy
# snapshotter over gRPC on a Unix socket (docs/PLUGINS.md, proxy_plugins
# with type "snapshot"), with the service
# containerd.services.snapshots.v1.Snapshots of
# api/services/snapshots/v1/snapshots.proto. Pure: the method of a call,
# its request as an S.Op, and S.Res as the answer's messages or status.
# src/layers/snap.bend decides every call; the host runs the effects.
#
# Messages (field numbers of snapshots.proto and types/mount.proto):
#   PrepareSnapshotRequest, ViewSnapshotRequest: snapshotter 1, key 2,
#     parent 3, labels 4 (map<string, string>)
#   CommitSnapshotRequest: snapshotter 1, name 2, key 3, labels 4, parent 5
#   MountsRequest, RemoveSnapshotRequest, StatSnapshotRequest,
#     UsageRequest: snapshotter 1, key 2
#   UpdateSnapshotRequest: snapshotter 1, info 2, update_mask 3
#     (google.protobuf.FieldMask: paths 1)
#   ListSnapshotsRequest: snapshotter 1, filters 2; CleanupRequest:
#     snapshotter 1
#   Prepare, View and Mounts answer mounts 1 (repeated Mount: type 1,
#     source 2, target 3, options 4); Stat and Update answer info 1 (Info:
#     name 1, parent 2, kind 3 (VIEW 1, ACTIVE 2, COMMITTED 3), created_at
#     4, updated_at 5 (Timestamp: seconds 1, nanos 2), labels 6); List
#     streams ListSnapshotsResponse (info 1, repeated), 100 infos a
#     message as containerd's own service sends them
#     (plugins/services/snapshots/service.go); Usage answers size 1 and
#     inodes 2 (int64); Commit, Remove and Cleanup answer
#     google.protobuf.Empty.
#   The snapshotter field names the proxy plugin; one socket serves one
#   snapshotter, so it is not read. Spb.request reads no List filters
#   (OList); Spb.request.v2 reads them (OWalk), and the snapshotter
#   applies them as containerd's snapshots do (src/layers/filters.bend).
#
# Errors are gRPC statuses, as containerd's errgrpc maps errdefs:
# NotFound 5, AlreadyExists 6, FailedPrecondition 9, InvalidArgument 3,
# with errdefs' messages.
#
# The shared layer store's layout in the node: src/layers/store.bend
# names a layer's directory /mnt/layers/<hex> (Lay.mount), and part 1
# publishes the layer's files there (~/.vk8s/layers/<hex> on the host).
# The snapshotter hands out that directory as it is. Usage of it comes
# from the layer's record that its fill published beside it,
# /mnt/layers/<hex>.rec (Fill.rec.mount, Fill.rec.parse.v2): the host
# reads it (Spb.rec.probe) and S.Sn.apply.v2 answers its size and
# inodes (Spb.uses); only a layer without one is measured.

type SpMeth is Data:
  SmPrepare{}
  SmView{}
  SmMounts{}
  SmCommit{}
  SmRemove{}
  SmStat{}
  SmUpdate{}
  SmList{}
  SmUsage{}
  SmCleanup{}

# A call's answer.
type SpAns is Data:
  # one message, then OK
  AnReply{msg: List<&2, U32>}
  # the messages of a server stream, then OK
  AnStream{msgs: List<&2, List<&2, U32>>}
  # a status other than OK
  AnStatus{code: U32, msg: String}
  # Usage: the host measures path (Spb.measure_args), then answers
  # Spb.measured of what it printed
  AnMeasure{path: String}

# A Prepare that names a shared layer (the label
# containerd.io/snapshot.ref): the chain ID and the directory that holds
# the layer when the store has it.
type SpProbe is Data:
  SpProbe{chain: String, path: String}

# Methods
# -------

def Spb.service() -> String:
  "/containerd.services.snapshots.v1.Snapshots/"

def Spb.meth.of(+n: String) -> Maybe<&2, SpMeth>:
  Bool.pick(Maybe<&2, SpMeth>, String.eq(n, "Prepare"), Some{SmPrepare{}},
  Bool.pick(Maybe<&2, SpMeth>, String.eq(n, "View"), Some{SmView{}},
  Bool.pick(Maybe<&2, SpMeth>, String.eq(n, "Mounts"), Some{SmMounts{}},
  Bool.pick(Maybe<&2, SpMeth>, String.eq(n, "Commit"), Some{SmCommit{}},
  Bool.pick(Maybe<&2, SpMeth>, String.eq(n, "Remove"), Some{SmRemove{}},
  Bool.pick(Maybe<&2, SpMeth>, String.eq(n, "Stat"), Some{SmStat{}},
  Bool.pick(Maybe<&2, SpMeth>, String.eq(n, "Update"), Some{SmUpdate{}},
  Bool.pick(Maybe<&2, SpMeth>, String.eq(n, "List"), Some{SmList{}},
  Bool.pick(Maybe<&2, SpMeth>, String.eq(n, "Usage"), Some{SmUsage{}},
  Bool.pick(Maybe<&2, SpMeth>, String.eq(n, "Cleanup"), Some{SmCleanup{}}, None{}))))))))))

# The method a call's :path names, None for any other.
def Spb.method(+path: String) -> Maybe<&2, SpMeth>:
  Bool.pick(Maybe<&2, SpMeth>, String.starts_with(path, Spb.service()), Spb.meth.of(String.drop(path, 44n)), None{})

# Requests
# --------

def Spb.labels.of(xs: List<&2, P.PbStr>) -> List<&2, S.Label>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{P.PbStr{k, v}, t}:
      Con{S.Label{k, v}, Spb.labels.of(t)}

def Spb.op.create.go(active: Bool, key: String, parent: String, ls: List<&2, S.Label>) -> Result<&2, &2, String, S.Op>:
  match active:
    case True{}:
      Done{S.OPrepare{key, parent, ls}}
    case False{}:
      Done{S.OView{key, parent, ls}}

def Spb.op.create(active: Bool, key: String, parent: String, r: Result<&2, &2, String, List<&2, P.PbStr>>) ->
  Result<&2, &2, String, S.Op>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{xs}:
      Spb.op.create.go(active, key, parent, Spb.labels.of(xs))

def Spb.op.commit(name: String, key: String, parent: String, r: Result<&2, &2, String, List<&2, P.PbStr>>) ->
  Result<&2, &2, String, S.Op>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{xs}:
      Done{S.OCommit{name, key, parent, Spb.labels.of(xs)}}

def Spb.op.update.labels(name: String, r: Result<&2, &2, String, List<&2, P.PbStr>>, paths: List<&2, String>) ->
  Result<&2, &2, String, S.Op>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{xs}:
      Done{S.OUpdate{name, Spb.labels.of(xs), paths}}

def Spb.op.update.mask(+info: List<&2, P.PbField>, r: Result<&2, &2, String, List<&2, P.PbField>>) ->
  Result<&2, &2, String, S.Op>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{+mask}:
      Spb.op.update.labels(P.Pb.get_str(info, 1), P.Pb.get_str_map(info, 6), P.Pb.all_str(mask, 1))

def Spb.op.update(i: Result<&2, &2, String, List<&2, P.PbField>>, mask: Result<&2, &2, String, List<&2, P.PbField>>) ->
  Result<&2, &2, String, S.Op>:
  match i:
    case Fail{e}:
      Fail{e}
    case Done{+info}:
      Spb.op.update.mask(info, mask)

# A request's fields as the snapshotter's call. Cleanup's found
# directories are the host's to fill (Spb.fill).
def Spb.op(m: SpMeth, +f: List<&2, P.PbField>) -> Result<&2, &2, String, S.Op>:
  match m:
    case SmPrepare{}:
      Spb.op.create(True{}, P.Pb.get_str(f, 2), P.Pb.get_str(f, 3), P.Pb.get_str_map(f, 4))
    case SmView{}:
      Spb.op.create(False{}, P.Pb.get_str(f, 2), P.Pb.get_str(f, 3), P.Pb.get_str_map(f, 4))
    case SmMounts{}:
      Done{S.OMounts{P.Pb.get_str(f, 2)}}
    case SmCommit{}:
      Spb.op.commit(P.Pb.get_str(f, 2), P.Pb.get_str(f, 3), P.Pb.get_str(f, 5), P.Pb.get_str_map(f, 4))
    case SmRemove{}:
      Done{S.ORemove{P.Pb.get_str(f, 2)}}
    case SmStat{}:
      Done{S.OStat{P.Pb.get_str(f, 2)}}
    case SmUpdate{}:
      Spb.op.update(P.Pb.get_msg(f, 2), P.Pb.get_msg(f, 3))
    case SmList{}:
      Done{S.OList{}}
    case SmUsage{}:
      Done{S.OUsage{P.Pb.get_str(f, 2)}}
    case SmCleanup{}:
      Done{S.OCleanup{Nil{}}}

def Spb.decoded(m: SpMeth, r: Result<&2, &2, String, List<&2, P.PbField>>) -> Result<&2, &2, String, S.Op>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{+f}:
      Spb.op(m, f)

# A call's request message as the snapshotter's call; Fail when it does
# not decode (InvalidArgument).
def Spb.request(m: SpMeth, bs: List<&2, U32>) -> Result<&2, &2, String, S.Op>:
  Spb.decoded(m, P.Pb.decode(bs))

# The key a call names, for the host's log: Commit's key and name, an
# Update's name, "" for List and Cleanup.
def Spb.key(op: S.Op) -> String:
  match op:
    case S.OPrepare{k, p, ls}:
      k
    case S.OView{k, p, ls}:
      k
    case S.OCommit{n, k, p, ls}:
      k ++ " name=" ++ n
    case S.ORemove{k}:
      k
    case S.OMounts{k}:
      k
    case S.OStat{k}:
      k
    case S.OUpdate{n, ls, ps}:
      n
    case S.OUsage{k}:
      k
    case S.OList{}:
      ""
    case S.OCleanup{fs}:
      ""
    case S.OWalk{fs}:
      String.join(fs, " | ")

def Spb.is_bad(r: Result<&2, &2, String, S.Op>) -> Bool:
  match r:
    case Fail{e}:
      True{}
    case Done{o}:
      False{}

def Spb.is_cleanup(op: S.Op) -> Bool:
  match op:
    case S.OCleanup{fs}:
      True{}
    case _:
      False{}

# Cleanup with the directories found under <root>/snapshots.
def Spb.fill(op: S.Op, found: List<&2, String>) -> S.Op:
  match op:
    case S.OCleanup{fs}:
      S.OCleanup{found}
    case o:
      o

# Calls that change the snapshotter's state, which the host saves after
# them (src/layers/state.bend).
def Spb.dirty(op: S.Op) -> Bool:
  match op:
    case S.OPrepare{k, p, ls}:
      True{}
    case S.OView{k, p, ls}:
      True{}
    case S.OCommit{n, k, p, ls}:
      True{}
    case S.ORemove{k}:
      True{}
    case S.OUpdate{n, ls, ps}:
      True{}
    case _:
      False{}

# Shared layers
# -------------

def Spb.probe.of(+chain: String, m: Maybe<&2, String>) -> Maybe<&2, SpProbe>:
  match m:
    case None{}:
      None{}
    case Some{+d}:
      Some{SpProbe{chain, d}}

def Spb.probe.chain(+chain: String) -> Maybe<&2, SpProbe>:
  Bool.pick(Maybe<&2, SpProbe>, String.is_empty(chain), None{}, Spb.probe.of(chain, Y.Lay.mount(chain)))

# The shared layer a Prepare asks for, with the directory to look for:
# the host passes the chain ID to S.Sn.apply as held (have) when that
# directory exists. None for every other call, and for a label that is
# not a sha256 chain ID.
def Spb.probe(op: S.Op) -> Maybe<&2, SpProbe>:
  match op:
    case S.OPrepare{k, p, ls}:
      Spb.probe.chain(S.Sn.lget(S.Sn.labels(ls), "containerd.io/snapshot.ref"))
    case _:
      None{}

# What S.Sn.apply takes as have: the probed chain, when found.
def Spb.have(m: Maybe<&2, SpProbe>, found: Bool) -> List<&2, String>:
  match m found:
    case Some{SpProbe{c, d}} True{}:
      [c]
    case _ _:
      Nil{}

def Spb.held.lines(+node: String, ss: List<&2, S.Snap>) -> String:
  match ss:
    case Nil{}:
      ""
    case Con{S.Snap{k, i, kd, p, +l, ls, c, u}, t}:
      Bool.pick(String, String.is_empty(l), "", l ++ " " ++ node ++ "/" ++ k ++ "\n") ++ Spb.held.lines(node, t)

# The shared layers this node holds, one "<chain ID> <holder>" line per
# snapshot that stands for one (holders as src/layers/store.bend names
# them), for the host's store: `vk8s layers gc` reads every node's file
# (Fill.held.parse, strictly: the host does not trust it) and never
# removes a layer one names. The node writes it to its share after every
# call that acquires or releases.
def Spb.held(sn: S.Sn) -> String:
  match sn:
    case S.Sn{r, +n, x, ss}:
      Spb.held.lines(n, ss)

def Spb.touches(acts: List<&2, S.Act>) -> Bool:
  match acts:
    case Nil{}:
      False{}
    case Con{S.AAcquire{c, h}, t}:
      True{}
    case Con{S.ARelease{c, h}, t}:
      True{}
    case Con{a, t}:
      Spb.touches(t)

def Spb.names.add(empty: Bool, +l: String, rest: List<&2, String>) -> List<&2, String>:
  match empty:
    case True{}:
      rest
    case False{}:
      Con{l, rest}

def Spb.names.go(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{l, t}:
      +n : String = String.trim(l)
      Spb.names.add(String.is_empty(n), n, Spb.names.go(t))

# The names `ls -1` printed, one a line.
def Spb.names(text: String) -> List<&2, String>:
  Spb.names.go(String.lines(text))

# Directories to make before the answer.
def Spb.mkdirs(acts: List<&2, S.Act>) -> List<&2, String>:
  match acts:
    case Nil{}:
      Nil{}
    case Con{S.AMkdir{p}, t}:
      Con{p, Spb.mkdirs(t)}
    case Con{a, t}:
      Spb.mkdirs(t)

# Trees to remove once the state is saved (a crash in between leaves a
# directory that Cleanup finds).
def Spb.removes(acts: List<&2, S.Act>) -> List<&2, String>:
  match acts:
    case Nil{}:
      Nil{}
    case Con{S.ARemove{p}, t}:
      Con{p, Spb.removes(t)}
    case Con{a, t}:
      Spb.removes(t)

# Answers
# -------

def Spb.err(e: S.Err) -> SpAns:
  match e:
    case S.ENotFound{}:
      AnStatus{5, "not found"}
    case S.EExists{}:
      AnStatus{6, "already exists"}
    case S.EPrecond{}:
      AnStatus{9, "failed precondition"}
    case S.EInvalid{}:
      AnStatus{3, "invalid argument"}

def Spb.mount(m: S.Mount) -> List<&2, P.PbField>:
  match m:
    case S.Mount{t, s, os}:
      List.concat(&2, P.PbField, [P.Pb.str(1, t), P.Pb.str(2, s), P.Pb.strs(4, os)])

def Spb.mounts.go(ms: List<&2, S.Mount>) -> List<&2, List<&2, P.PbField>>:
  match ms:
    case Nil{}:
      Nil{}
    case Con{m, t}:
      Con{Spb.mount(m), Spb.mounts.go(t)}

# PrepareSnapshotResponse, ViewSnapshotResponse and MountsResponse.
def Spb.mounts(ms: List<&2, S.Mount>) -> List<&2, U32>:
  P.Pb.encode(P.Pb.msgs(1, Spb.mounts.go(ms)))

def Spb.kind(k: S.SKind) -> U32:
  match k:
    case S.KView{}:
      1
    case S.KActive{}:
      2
    case S.KCommitted{}:
      3

def Spb.pbstrs(ls: List<&2, S.Label>) -> List<&2, P.PbStr>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{S.Label{k, v}, t}:
      Con{P.PbStr{k, v}, Spb.pbstrs(t)}

# Info; a time is a Timestamp of whole seconds.
def Spb.info(i: S.Info) -> List<&2, P.PbField>:
  match i:
    case S.Info{kd, name, parent, ls, c, u}:
      List.concat(&2, P.PbField, [P.Pb.str(1, name), P.Pb.str(2, parent), P.Pb.u32(3, Spb.kind(kd)),
        P.Pb.msg(4, P.Pb.u32(1, c)), P.Pb.msg(5, P.Pb.u32(1, u)), P.Pb.str_map(6, Spb.pbstrs(ls))])

# StatSnapshotResponse and UpdateSnapshotResponse.
def Spb.stat(i: S.Info) -> List<&2, U32>:
  P.Pb.encode(P.Pb.msg(1, Spb.info(i)))

def Spb.infos(xs: List<&2, S.Info>) -> List<&2, P.PbField>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{i, t}:
      List.append(&2, P.PbField, P.Pb.msg(1, Spb.info(i)), Spb.infos(t))

def Spb.block(cur: List<&2, P.PbField>) -> List<&2, U32>:
  P.Pb.encode(List.reverse(&2, P.PbField, cur))

def Spb.group.k(full: Bool, +k: U32) -> U32:
  match full:
    case True{}:
      0
    case False{}:
      (k + 1 : U32)

def Spb.group.cur(full: Bool, +x: P.PbField, cur: List<&2, P.PbField>) -> List<&2, P.PbField>:
  match full:
    case True{}:
      Nil{}
    case False{}:
      Con{x, cur}

def Spb.group.emit(full: Bool, +x: P.PbField, cur: List<&2, P.PbField>, rest: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match full:
    case True{}:
      Con{Spb.block(Con{x, cur}), rest}
    case False{}:
      rest

def Spb.group.last(cur: List<&2, P.PbField>) -> List<&2, List<&2, U32>>:
  match cur:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      [Spb.block(Con{x, t})]

# The info fields in messages of 100 (cur: the open message's, reversed;
# k: how many it holds).
def Spb.group(xs: List<&2, P.PbField>, +k: U32, +cur: List<&2, P.PbField>) -> List<&2, List<&2, U32>>:
  match xs:
    case Nil{}:
      Spb.group.last(cur)
    case Con{+x, t}:
      +full : Bool = U32.is_eq(k, 99)
      Spb.group.emit(full, x, cur, Spb.group(t, Spb.group.k(full, k), Spb.group.cur(full, x, cur)))

# List's stream: ListSnapshotsResponse messages of up to 100 infos; none
# for no snapshot.
def Spb.list(xs: List<&2, S.Info>) -> List<&2, List<&2, U32>>:
  Spb.group(Spb.infos(xs), 0, Nil{})

# UsageResponse from a recorded usage: size (bytes, int64) and inodes.
def Spb.usage.v2(s: N.Size, +inodes: U32) -> List<&2, U32>:
  match s:
    case N.Size{h, l}:
      P.Pb.encode(List.append(&2, P.PbField, P.Pb.u64(1, P.W64{h, l}), P.Pb.u32(2, inodes)))

# The answer to a call from what S.Sn.apply answered.
def Spb.answer(r: S.Res) -> SpAns:
  match r:
    case S.RErr{e}:
      Spb.err(e)
    case S.RMounts{ms}:
      AnReply{Spb.mounts(ms)}
    case S.RInfo{i}:
      AnReply{Spb.stat(i)}
    case S.RList{xs}:
      AnStream{Spb.list(xs)}
    case S.RMeasure{+p}:
      AnMeasure{p}
    case S.RUsage{sz, n}:
      AnReply{Spb.usage.v2(sz, n)}
    case S.RZero{}:
      AnReply{Nil{}}
    case S.RDirs{ds}:
      AnReply{Nil{}}
    case S.ROk{}:
      AnReply{Nil{}}

# Usage
# -----

# How the host measures a directory: busybox sh prints du -sk's line
# (KiB of blocks, a tab, the path) and the number of entries find lists
# (every inode under it, the directory too, as containerd's
# fs.DiskUsage counts them). One shell, because find's list would be the
# whole tree as a String.
def Spb.measure_args(+path: String) -> List<&2, String>:
  ["sh", "-c", "du -sk -- \"$1\" && find \"$1\" -xdev | wc -l", "sh", path]

# UsageResponse: size (bytes, KiB times 1024 as an int64) and inodes.
def Spb.usage(+kb: U32, +inodes: U32) -> List<&2, U32>:
  P.Pb.encode(List.append(&2, P.PbField, P.Pb.u64(1, P.W64{U32.shrn(kb, 22n), U32.shln(kb, 10n)}), P.Pb.u32(2, inodes)))

def Spb.measured.go(a: Maybe<&2, U32>, b: Maybe<&2, U32>) -> SpAns:
  match a b:
    case Some{+kb} Some{+n}:
      AnReply{Spb.usage(kb, n)}
    case _ _:
      AnStatus{13, "usage: could not measure"}

def Spb.measured.lines(ls: List<&2, String>) -> SpAns:
  match ls:
    case Con{+du, Con{+n, t}}:
      Spb.measured.go(U32.read(String.trim(Maybe.default(&2, String, List.head(&2, String, String.split(du, '\t')), ""))), U32.read(String.trim(n)))
    case _:
      AnStatus{13, "usage: could not measure"}

# Usage's answer from what Spb.measure_args printed.
def Spb.measured(text: String) -> SpAns:
  Spb.measured.lines(String.lines(text))

# The wall clock in seconds since 1970 from (days, second of the day).
def Spb.epoch(+days: U32, +secs: U32) -> U32:
  ((days * 86400 : U32) + secs : U32)

# Version 2: List's filters, recorded usage
# -----------------------------------------

def Spb.op.v2(m: SpMeth, +f: List<&2, P.PbField>) -> Result<&2, &2, String, S.Op>:
  match m:
    case SmList{}:
      Done{S.OWalk{P.Pb.all_str(f, 2)}}
    case o:
      Spb.op(o, f)

def Spb.decoded.v2(m: SpMeth, r: Result<&2, &2, String, List<&2, P.PbField>>) -> Result<&2, &2, String, S.Op>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{+f}:
      Spb.op.v2(m, f)

# As Spb.request, but List carries its filters (ListSnapshotsRequest
# field 2, repeated): OWalk.
def Spb.request.v2(m: SpMeth, bs: List<&2, U32>) -> Result<&2, &2, String, S.Op>:
  Spb.decoded.v2(m, P.Pb.decode(bs))

def Spb.rec.kind(k: S.SKind, +l: String) -> Maybe<&2, SpProbe>:
  match k:
    case S.KCommitted{}:
      Bool.pick(Maybe<&2, SpProbe>, String.is_empty(l), None{}, Spb.probe.of(l, F.Fill.rec.mount(l)))
    case _:
      None{}

def Spb.rec.of(m: Maybe<&2, S.Snap>) -> Maybe<&2, SpProbe>:
  match m:
    case None{}:
      None{}
    case Some{S.Snap{k, i, kd, p, l, ls, c, u}}:
      Spb.rec.kind(kd, l)

# The record a Usage call needs: of a committed snapshot that stands for
# a shared layer, the chain ID and the layer's record in the node
# (/mnt/layers/<hex>.rec). None for every other call and snapshot.
def Spb.rec.probe(sn: S.Sn, op: S.Op) -> Maybe<&2, SpProbe>:
  match op:
    case S.OUsage{+k}:
      Spb.rec.of(S.Sn.find(S.Sn.snaps(sn), k))
    case _:
      None{}

def Spb.uses.rec(m: Maybe<&2, F.Rec>, +chain: String) -> List<&2, S.LUse>:
  match m:
    case Some{F.Rec{Y.Layer{c, d, p, hs, t}, Some{F.Use{s, n}}}}:
      Bool.pick(List<&2, S.LUse>, String.eq(c, chain), [S.LUse{chain, s, n}], Nil{})
    case _:
      Nil{}

# What S.Sn.apply.v2 takes as the recorded usage: the probed layer's
# size and inodes from its record's text (the host reads "" when there
# is none). None when the record is missing, does not parse, names
# another layer, or has no size (a version 1 record).
def Spb.uses(m: Maybe<&2, SpProbe>, text: String) -> List<&2, S.LUse>:
  match m:
    case None{}:
      Nil{}
    case Some{SpProbe{+c, d}}:
      Spb.uses.rec(F.Fill.rec.parse.v2(text), c)

# Warm (v6): a small layer image just mounted, read once
# ------------------------------------------------------
#
# Whether the node reads a layer image it has just mounted
# (src/layers/store.bend Lay.warm_args.v6) before it answers the Prepare
# that mounted it, so that the image's pull ends with the layer in the
# page cache and the container's first exec does not wait for the
# store's share after the kubelet has reported it Running.

# The largest layer read: 8 MiB of regular files. Through the share a
# Mac VM node reads 9 to 30 ms per MiB (more on a busy host), so the
# Prepare of such a layer waits a quarter of a second at most there. A
# larger layer is left to its first reads: a start touches a small part
# of it, and reading all of it would hold the share and the pull for
# files a container may never open (measured: agnhost's 157 MiB read
# beside its pull took the pull from 0.5 s to 1.5 s, for a start that
# was 3 ms behind StartContainer without it).
def Spb.warm.max.v6() -> N.Size:
  N.Size{0, 8388608}

def Spb.warm.size.v6(s: N.Size) -> Bool:
  Bool.not(N.Size.is_lt(Spb.warm.max.v6(), s))

# us is the layer's recorded usage (Spb.uses of its record): the size
# its fill counted, the bytes of its regular files, which is what the
# read reads. A layer with no recorded size (a record of version 1, or
# none) is not read: nothing bounds it.
def Spb.warm.v6(us: List<&2, S.LUse>) -> Bool:
  match us:
    case Nil{}:
      False{}
    case Con{S.LUse{c, s, n}, t}:
      Spb.warm.size.v6(s)

# No wait (v7; src/layers/ask.bend Ask.later.*.v4)
# -------------------------------------------------

# Whether a call is the node's pull activity: a snapshot made (Prepare,
# View) or committed. The kept asks wait until these stop; a Stat, a
# Usage or a List (the kubelet's and containerd's periodic calls) does
# not hold them back. None is a method the service does not have.
def Spb.busy.v7(m: Maybe<&2, SpMeth>) -> Bool:
  match m:
    case Some{SmPrepare{}}:
      True{}
    case Some{SmView{}}:
      True{}
    case Some{SmCommit{}}:
      True{}
    case _:
      False{}
