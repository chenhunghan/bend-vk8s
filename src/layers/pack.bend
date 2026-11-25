import Base
import bend-kube-runtime@0.12.0.0/src/json.bend as J
import ./ask.bend as A
import ./snap.bend as S
import ./store.bend as Y

# The pack disk: a VM node's layer images on one read-only virtio-blk
# disk (docs/STATUS.md, "The pack disk"; bend-vmm README, "Packs: host
# files as one growing disk"). vk8s's own design: nothing here mirrors
# vcluster. Pure: these defs decide the VM's flags, the lines between a
# node's snapshotter and the host's filler, the lines to bend-vmm's
# control socket, what its pack table says, and what a node unmounts;
# host/ does the IO.
#
# The parts:
# - The host starts a VM node on the layer store with `--pack layers`
#   and VK8S_PACK=<vm> on the kernel command line (Pack.flags.v7), and
#   writes a key only that node's root reads into its share
#   (Pack.key_file.v7). <vm> names the VM's folder under
#   ~/.vk8s/clusters: "<cluster>" or "<cluster>/nodes/worker-<i>". The
#   layers share stays: the node probes the store and reads the layers'
#   records there, and falls back to it.
# - The node's snapshotter (host/snapshotter.bend), when it mounts a
#   layer image the store holds, asks the host's filler (the daemon of
#   src/layers/ask.bend, same port) to put the image on its pack:
#     guest: pack <vm> <key> <chain>
#     host:  at <offset> <length> | no <reason>
#   and mounts <length> bytes at <offset> of the pack device (the
#   virtio-blk disk whose serial is "layers") through a loop device
#   with that offset and size limit. Any other answer, no answer, or a
#   failed mount ends in the mount from the share, as before.
# - When the node's last snapshot on a layer goes, the snapshotter
#   unmounts the layer and tells the filler:
#     guest: drop <vm> <key> <chain>
#     host:  ok dropped | no <reason>
# - The filler reads these lines strictly (Pack.ask.parse.v7), checks
#   the key against the file in that VM's share (any pod can reach the
#   port; only the node's root reads its share), and talks to the VM's
#   control socket: `pack add PATH` (Pack.ctl.add.v7; it does not look
#   the image up first: bend-vmm's `status json` takes about 70 ms, and
#   a node asks only for a layer it has not mounted), and for a drop
#   `status json` for the pack's table, then `pack drop OFFSET` for
#   every live entry of the layer (Pack.offsets.v7), so an image that
#   was added twice is dropped whole.
# - gc keeps every layer that is live in a running VM's pack: each
#   VM's table adds its live layers to the held ones (Pack.chains.v7,
#   with src/layers/fill.bend Fill.gc.plan.v2 and Fill.gc.recheck.v2).
#
# Compatibility is explicit: a guest uses the pack only with VK8S_PACK
# on its command line, which only a host that started it with --pack
# writes. An older guest ignores both. An older filler answers a pack
# line "no bad ask" (it reads Ask.parse.v2 only), and the node mounts
# from the share.

# Names
# -----

# The pack's name, bend-vmm's --pack NAME: the serial the guest finds
# the device by (/sys/block/vd*/serial).
def Pack.name.v7() -> String:
  "layers"

# The kernel command line's variable (PID 1 passes it to its daemons).
def Pack.env.v7() -> String:
  "VK8S_PACK"

def Pack.lower(+x: U32) -> Bool:
  U32.is_ge(x, 97) && U32.is_le(x, 122)

def Pack.digit(+x: U32) -> Bool:
  U32.is_ge(x, 48) && U32.is_le(x, 57)

def Pack.name_char(c: Char) -> Bool:
  match c:
    case Chr{+x}:
      Pack.lower(x) || Pack.digit(x) || U32.is_eq(x, 45)

def Pack.key_char(c: Char) -> Bool:
  match c:
    case Chr{+x}:
      Pack.lower(x) || Pack.digit(x)

def Pack.digit_char(c: Char) -> Bool:
  match c:
    case Chr{+x}:
      Pack.digit(x)

def Pack.name_chars(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      Pack.name_char(c) && Pack.name_chars(t)

def Pack.key_chars(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      Pack.key_char(c) && Pack.key_chars(t)

def Pack.digits(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      Pack.digit_char(c) && Pack.digits(t)

# A cluster's name as a path piece: 1 to 63 of a-z, 0-9 and "-" (no
# ".", no "/": never a way out of ~/.vk8s/clusters).
def Pack.cluster_ok(+s: String) -> Bool:
  Bool.not(String.is_empty(s)) && Nat.is_le(String.length(s), 63n) && Pack.name_chars(s)

# A worker's folder: "worker-" and 1 to 4 digits (Cli.node_dir).
def Pack.worker_ok(+s: String) -> Bool:
  +n : String = String.drop(s, 7n)
  String.starts_with(s, "worker-") && Bool.not(String.is_empty(n)) && Nat.is_le(String.length(n), 4n) && Pack.digits(n)

def Pack.vm_parts(ps: List<&2, String>) -> Bool:
  match ps:
    case Con{c, Nil{}}:
      Pack.cluster_ok(c)
    case Con{c, Con{+n, Con{w, Nil{}}}}:
      Pack.cluster_ok(c) && String.eq(n, "nodes") && Pack.worker_ok(w)
    case _:
      False{}

# A VM's name on the wire: "<cluster>" (its control plane) or
# "<cluster>/nodes/worker-<i>", its folder under ~/.vk8s/clusters.
def Pack.vm_ok.v7(+vm: String) -> Bool:
  Pack.vm_parts(String.split(vm, '/'))

def Pack.some_if(ok: Bool, s: String) -> Maybe<&2, String>:
  match ok:
    case True{}:
      Some{s}
    case False{}:
      None{}

# The VM's folder on the host (root: ~/.vk8s), or None for a name that
# is not one.
def Pack.vm_dir.v7(+root: String, +vm: String) -> Maybe<&2, String>:
  Pack.some_if(Pack.vm_ok.v7(vm), root ++ "/clusters/" ++ vm)

def Pack.vm.cut(ok: Bool, +mid: String) -> String:
  match ok:
    case True{}:
      Bool.pick(String, Pack.vm_ok.v7(mid), mid, "")
    case False{}:
      ""

# The VM's name from its data disk's path (<root>/clusters/<vm>/data.img,
# as Cli.dir and Cli.node_dir make it); "" for any other path: such a VM
# gets no pack.
def Pack.vm.v7(+root: String, +data: String) -> String:
  +pre : String = root ++ "/clusters/"
  +rest : String = String.drop(data, String.length(pre))
  Pack.vm.cut(String.starts_with(data, pre) && String.ends_with(rest, "/data.img"),
    String.take(rest, Nat.sub(String.length(rest), 9n)))

# The key
# -------

# A key: 16 to 64 of a-z and 0-9.
def Pack.key_ok.v7(+k: String) -> Bool:
  Nat.is_ge(String.length(k), 16n) && Nat.is_le(String.length(k), 64n) && Pack.key_chars(k)

# The key's file in the VM's folder on the host: in its share, which
# only the node's root reads (and may rewrite: it is that node's key).
def Pack.key_file.v7(+vmdir: String) -> String:
  vmdir ++ "/share/pack.key"

# The file's name in the node's share.
def Pack.key_name.v7() -> String:
  "pack.key"

# Whether an ask's key is the VM's: the file's text (its line end
# dropped) is a key and equals it. No file, an empty one, or anything
# that is not a key matches nothing.
def Pack.key_same.v7(+file: String, +key: String) -> Bool:
  Pack.key_ok.v7(key) && String.eq(String.trim(file), key)

# The VM's flags
# --------------

# Whether a VM gets a pack: it is on the layer store, the host's
# VK8S_PACK is not "0" (the opt-out: the node then reads its layers over
# the share, as before), and its folder has a name (Pack.vm.v7).
def Pack.on.v7(layers: Bool, +env: String, +vm: String) -> Bool:
  layers && Bool.not(String.eq(env, "0")) && Pack.vm_ok.v7(vm)

def Pack.word.v7(+vm: String) -> String:
  " " ++ Pack.env.v7() ++ "=" ++ vm

def Pack.flags.at(hit: Bool, +x: String, +v: String, +vm: String, rest: +List<String>) -> +List<String>:
  match hit:
    case True{}:
      Con{"--pack", Con{Pack.name.v7(), Con{x, Con{v ++ Pack.word.v7(vm), rest}}}}
    case False{}:
      Con{x, Con{v, rest}}

def Pack.flags.go(xs: +List<String>, +vm: String) -> +List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, t}:
      match t:
        case Nil{}:
          [x]
        case Con{+v, t2}:
          Pack.flags.at(String.eq(x, "--cmdline"), x, v, vm, Pack.flags.go(t2, vm))

# A VM's bend-vmm flags (flag, value pairs) with the pack: `--pack
# layers` before --cmdline, whose value gains VK8S_PACK=<vm>; off, the
# flags as they are.
def Pack.flags.v7(on: Bool, +vm: String, flags: +List<String>) -> +List<String>:
  match on:
    case True{}:
      Pack.flags.go(flags, vm)
    case False{}:
      flags

# The lines between a node and the filler
# ---------------------------------------

# A node's ask: put layer chain's image on VM vm's pack, or end its
# entries there (the node has unmounted it).
type PkAsk is Data:
  PkAdd{vm: String, key: String, chain: String}
  PkDrop{vm: String, key: String, chain: String}

# The filler's answer: where the image is on the pack (decimal bytes),
# the layer's entries ended, or why not.
type PkReply is Data:
  PkAt{off: String, len: String}
  PkDropped{}
  PkNo{why: String}

# The most bytes of an ask's line, its "\n" included (the longest valid
# one is 5 + 82 + 1 + 64 + 1 + 71 + 1 = 225).
def Pack.line_max.v7() -> Nat:
  256n

def Pack.ask.render.v7(a: PkAsk) -> String:
  match a:
    case PkAdd{vm, k, c}:
      "pack " ++ vm ++ " " ++ k ++ " " ++ c ++ "\n"
    case PkDrop{vm, k, c}:
      "drop " ++ vm ++ " " ++ k ++ " " ++ c ++ "\n"

def Pack.ask.make(add: Bool, drop: Bool, ok: Bool, vm: String, k: String, c: String) -> Maybe<&2, PkAsk>:
  match add drop ok:
    case True{} _ True{}:
      Some{PkAdd{vm, k, c}}
    case False{} True{} True{}:
      Some{PkDrop{vm, k, c}}
    case _ _ _:
      None{}

def Pack.ask.fields(fs: List<&2, String>) -> Maybe<&2, PkAsk>:
  match fs:
    case Con{+w, Con{+vm, Con{+k, Con{+c, Nil{}}}}}:
      Pack.ask.make(String.eq(w, "pack"), String.eq(w, "drop"),
        Pack.vm_ok.v7(vm) && Pack.key_ok.v7(k) && A.Ask.digest_ok.v2(c), vm, k, c)
    case _:
      None{}

def Pack.ask.line(m: Maybe<&2, String>) -> Maybe<&2, PkAsk>:
  match m:
    case None{}:
      None{}
    case Some{l}:
      Pack.ask.fields(String.split(l, ' '))

# An ask read from a guest, strictly: one "\n"-ended line of at most
# Pack.line_max.v7 bytes, the word "pack" or "drop", a VM's name, a key
# and a sha256 chain ID, one space apart. Anything else is None.
def Pack.ask.parse.v7(+s: String) -> Maybe<&2, PkAsk>:
  Pack.ask.line(A.Ask.line(Pack.line_max.v7(), s))

# A decimal number of bytes: 1 to 19 digits (bend-vmm's Pack.parse).
def Pack.num_ok.v7(+s: String) -> Bool:
  Bool.not(String.is_empty(s)) && Nat.is_le(String.length(s), 19n) && Pack.digits(s)

def Pack.reply.render.v7(r: PkReply) -> String:
  match r:
    case PkAt{o, l}:
      "at " ++ o ++ " " ++ l ++ "\n"
    case PkDropped{}:
      "ok dropped\n"
    case PkNo{w}:
      "no " ++ w ++ "\n"

def Pack.reply.at.if(ok: Bool, o: String, l: String) -> Maybe<&2, PkReply>:
  match ok:
    case True{}:
      Some{PkAt{o, l}}
    case False{}:
      None{}

def Pack.reply.at(fs: List<&2, String>) -> Maybe<&2, PkReply>:
  match fs:
    case Con{+o, Con{+l, Nil{}}}:
      Pack.reply.at.if(Pack.num_ok.v7(o) && Pack.num_ok.v7(l), o, l)
    case _:
      None{}

def Pack.reply.no(m: Maybe<&2, A.Reply>) -> Maybe<&2, PkReply>:
  match m:
    case Some{A.RNo{w}}:
      Some{PkNo{w}}
    case _:
      None{}

def Pack.reply.text(at: Bool, dropped: Bool, +l: String) -> Maybe<&2, PkReply>:
  match at dropped:
    case True{} _:
      Pack.reply.at(String.split(String.drop(l, 3n), ' '))
    case False{} True{}:
      Some{PkDropped{}}
    case False{} False{}:
      Pack.reply.no(A.Ask.reply.parse.v2(l ++ "\n"))

def Pack.reply.line(m: Maybe<&2, String>) -> Maybe<&2, PkReply>:
  match m:
    case None{}:
      None{}
    case Some{+l}:
      Pack.reply.text(String.starts_with(l, "at "), String.eq(l, "ok dropped"), l)

# A reply read from the filler, strictly: one "\n"-ended line of at most
# Ask.reply_max.v2 bytes: "at " and two numbers, "ok dropped", or "no "
# and a reason as Ask.reply.parse.v2 takes it (so an older filler's
# answer to a line it does not know reads as a no). Anything else is
# None, and the node treats None as a no.
def Pack.reply.parse.v7(+s: String) -> Maybe<&2, PkReply>:
  Pack.reply.line(A.Ask.line(A.Ask.reply_max.v2(), s))

# A reason fit for the wire (Ask.why.v2).
def Pack.no.v7(+why: String) -> PkReply:
  PkNo{A.Ask.why.v2(why)}

# The longest a node waits for the filler's answer to a pack or drop
# line, in milliseconds: the filler asks the VM's control socket, a
# local call; past this the node mounts from the share.
def Pack.wait.ms.v7() -> U32:
  5000

# bend-vmm's control socket
# -------------------------

def Pack.ctl.add.v7(+path: String) -> String:
  "pack add " ++ path

def Pack.ctl.drop.v7(+off: String) -> String:
  "pack drop " ++ off

# Where bend-vmm put a file: its answer to `pack add` is "OFFSET LENGTH"
# (decimal bytes); anything else ("error: ...") is None.
def Pack.ctl.added.v7(+reply: String) -> Maybe<&2, PkReply>:
  Pack.reply.at(String.split(String.trim(reply), ' '))

# Whether bend-vmm ended an entry: its answer to `pack drop`.
def Pack.ctl.dropped.v7(+reply: String) -> Bool:
  String.eq(String.trim(reply), "dropped")

# One entry of a pack's table.
type PkEnt is Data:
  PkEnt{off: String, len: String, path: String, live: Bool}

def Pack.ent.num(j: J.Json) -> String:
  match j:
    case J.JNum{t}:
      t
    case _:
      ""

def Pack.ent.bool(j: J.Json) -> Bool:
  match j:
    case J.JBool{b}:
      b
    case _:
      False{}

def Pack.ent(+j: J.Json) -> PkEnt:
  PkEnt{Pack.ent.num(J.Json.get(j, "offset")), Pack.ent.num(J.Json.get(j, "length")),
    J.Json.str_or(J.Json.get(j, "path"), ""), Pack.ent.bool(J.Json.get(j, "live"))}

def Pack.ents(js: List<&2, J.Json>) -> List<&2, PkEnt>:
  match js:
    case Nil{}:
      Nil{}
    case Con{j, t}:
      Con{Pack.ent(j), Pack.ents(t)}

def Pack.table.of(r: Result<&2, &2, String, J.Json>) -> List<&2, PkEnt>:
  match r:
    case Fail{e}:
      Nil{}
    case Done{j}:
      Pack.ents(J.Json.items(J.Json.at(j, ["pack", "entries"])))

# The pack's table from bend-vmm's `status json`
# ("pack":{"name":..,"size":..,"entries":[{"offset":..,"length":..,
# "path":..,"live":..}]}), in offset order; none for a VM without a
# pack or an answer that is not JSON.
def Pack.table.v7(json: String) -> List<&2, PkEnt>:
  Pack.table.of(J.Json.parse(json))

# Whether an entry is a live one of the file at path, with numbers the
# filler can pass on.
def Pack.ent.holds(e: PkEnt, +path: String) -> Bool:
  match e:
    case PkEnt{+o, +l, p, live}:
      live && String.eq(p, path) && Pack.num_ok.v7(o) && Pack.num_ok.v7(l)

def Pack.ent.off(e: PkEnt) -> String:
  match e:
    case PkEnt{o, l, p, live}:
      o

def Pack.offsets.put(hit: Bool, +e: PkEnt, rest: List<&2, String>) -> List<&2, String>:
  match hit:
    case True{}:
      Con{Pack.ent.off(e), rest}
    case False{}:
      rest

# The offsets of every live entry of the file at path: what a drop ends.
def Pack.offsets.v7(es: List<&2, PkEnt>, +path: String) -> List<&2, String>:
  match es:
    case Nil{}:
      Nil{}
    case Con{+e, t}:
      Pack.offsets.put(Pack.ent.holds(e, path), e, Pack.offsets.v7(t, path))

# gc
# --

def Pack.chain.name(+n: String) -> Maybe<&2, String>:
  +c : String = "sha256:" ++ String.take(n, Nat.sub(String.length(n), 5n))
  Pack.some_if(String.ends_with(n, ".sqfs") && A.Ask.digest_ok.v2(c), c)

# The chain ID of the layer image at a path of the store at root
# (<root>/layers/<hex>.sqfs, Lay.img.v3), or None for any other path.
def Pack.chain.v7(+root: String, +path: String) -> Maybe<&2, String>:
  +pre : String = root ++ "/layers/"
  Bool.pick(Maybe<&2, String>, String.starts_with(path, pre), Pack.chain.name(String.drop(path, String.length(pre))), None{})

def Pack.chains.put(live: Bool, m: Maybe<&2, String>, rest: List<&2, String>) -> List<&2, String>:
  match live m:
    case True{} Some{c}:
      Con{c, rest}
    case _ _:
      rest

def Pack.chains.one(e: PkEnt, +root: String, rest: List<&2, String>) -> List<&2, String>:
  match e:
    case PkEnt{o, l, p, live}:
      Pack.chains.put(live, Pack.chain.v7(root, p), rest)

# The layers of the store at root that a pack's table holds live: gc
# counts them as held (Fill.hold), so it never removes a layer image
# under a VM that can read it.
def Pack.chains.v7(es: List<&2, PkEnt>, +root: String) -> List<&2, String>:
  match es:
    case Nil{}:
      Nil{}
    case Con{e, t}:
      Pack.chains.one(e, root, Pack.chains.v7(t, root))

# The node
# --------

def Pack.vm.pick(ok: Bool, vm: String) -> String:
  match ok:
    case True{}:
      vm
    case False{}:
      ""

# The VM's name as the node's environment gives it (VK8S_PACK), "" when
# it names none: then the node has no pack and mounts from the share.
def Pack.guest.v7(+env: String) -> String:
  Pack.vm.pick(Pack.vm_ok.v7(env), env)

# The virtio-blk disks a node looks at for the pack (a VM has at most
# its base, data and set disks before it).
def Pack.disks.v7() -> List<&2, String>:
  ["vda", "vdb", "vdc", "vdd", "vde", "vdf", "vdg", "vdh", "vdi", "vdj", "vdk", "vdl", "vdm", "vdn", "vdo", "vdp"]

def Pack.serial_file.v7(+disk: String) -> String:
  "/sys/block/" ++ disk ++ "/serial"

# Whether a disk's serial (the file's text) is the pack's.
def Pack.serial_is.v7(+text: String) -> Bool:
  String.eq(String.trim(text), Pack.name.v7())

def Pack.dev.v7(+disk: String) -> String:
  "/dev/" ++ disk

def Pack.gone.put(drop: Bool, +c: String, rest: List<&2, String>) -> List<&2, String>:
  match drop:
    case True{}:
      Con{c, rest}
    case False{}:
      rest

def Pack.gone.act(a: S.Act, +left: List<&2, String>, +rest: List<&2, String>) -> List<&2, String>:
  match a:
    case S.ARelease{+c, h}:
      Pack.gone.put(Bool.not(Y.Lay.holds(left, c)) && Bool.not(Y.Lay.holds(rest, c)), c, rest)
    case _:
      rest

def Pack.gone.go(acts: List<&2, S.Act>, +left: List<&2, String>) -> List<&2, String>:
  match acts:
    case Nil{}:
      Nil{}
    case Con{a, t}:
      Pack.gone.act(a, left, Pack.gone.go(t, left))

# The layers a node unmounts after a call: each one the call let go
# (its ARelease acts) that no snapshot stands on any more (left:
# Sn.layers.v3 of the state after the call), once each.
def Pack.gone.v7(acts: List<&2, S.Act>, +left: List<&2, String>) -> List<&2, String>:
  Pack.gone.go(acts, left)

# busybox's argv to unmount layer chain at Lay.mount, and to remove its
# mount point (a directory left there would read as the layer).
def Pack.umount_args.v7(chain: String) -> List<&2, String>:
  ["umount", Maybe.default(&2, String, Y.Lay.mount(chain), "")]

def Pack.rmdir_args.v7(chain: String) -> List<&2, String>:
  ["rmdir", Maybe.default(&2, String, Y.Lay.mount(chain), "")]
