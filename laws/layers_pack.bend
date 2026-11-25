import Base
import ../src/layers/pack.bend as K
import ../src/layers/ask.bend as A
import ../src/layers/serve.bend as SV
import ../src/layers/snap.bend as S
import ../src/layers/store.bend as Y
import ../src/layers/fill.bend as F

# Spec for src/layers/pack.bend: a VM node's layer images on bend-vmm's
# pack disk.
#
# Proposed: every law of this file is new (feat/pack-disk). Sources:
# - the pack itself, `pack add PATH` answering "OFFSET LENGTH", `pack
#   drop OFFSET` answering "dropped", the errors' "error: ..." and the
#   table in `status json`: bend-vmm's README ("Packs: host files as one
#   growing disk") and src/disk/pack.bend (Pack.added, Pack.no_pack,
#   Pack.json), package 0x51718d1816cd36f20955e9590377c5e5; a name is 1
#   to 20 of A-Z a-z 0-9 . _ - and a number 1 to 19 digits there;
# - the VM's folders: src/cli/cli.bend Cli.dir and Cli.node_dir;
# - the layer image's path: src/layers/store.bend Lay.img.v3;
# - everything else (the lines between node and filler, the key, the
#   kernel command line's VK8S_PACK, what gc holds, what a node
#   unmounts) is vk8s's own design, not vcluster's behaviour.

def layers_pack.fx.c() -> String:
  "sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1"

def layers_pack.fx.d() -> String:
  "sha256:9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0"

def layers_pack.fx.key() -> String:
  "0k3v9q2m7x1c5b8n4j6h0a"

def layers_pack.fx.img() -> String:
  "/Users/u/.vk8s/layers/c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1.sqfs"

def layers_pack.fx.img_d() -> String:
  "/Users/u/.vk8s/layers/9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0.sqfs"

# `status json` of a VM with two entries, the second dropped, as
# bend-vmm's Ctl.with_pack and Pack.json write it.
def layers_pack.fx.json() -> String:
  "{\"state\":\"running\",\"pack\":{\"name\":\"layers\",\"size\":103809024,\"entries\":["
    ++ "{\"offset\":0,\"length\":100663296,\"path\":\"/Users/u/.vk8s/layers/c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1.sqfs\",\"live\":true},"
    ++ "{\"offset\":101711872,\"length\":4096,\"path\":\"/Users/u/.vk8s/layers/9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0.sqfs\",\"live\":false}]}}"

def layers_pack.fx.table() -> List<&2, K.PkEnt>:
  [ K.PkEnt{"0", "100663296", layers_pack.fx.img(), True{}},
    K.PkEnt{"101711872", "4096", layers_pack.fx.img_d(), False{}} ]

# The control plane's flags, shortened to what the pack touches.
def layers_pack.fx.flags() -> +List<String>:
  [ "--share", "/Users/u/.vk8s/clusters/dev/share,quota=1G",
    "--share", "/Users/u/.vk8s/layers,tag=layers,meta,ro",
    "--control", "/Users/u/.vk8s/clusters/dev/ctl.sock",
    "--cmdline", "console=ttyAMA0 quiet panic=5 VK8S_NAME=dev VK8S_LAYERS=1",
    "--balloon", "auto" ]

# Names
# -----

law layers_pack.name:
  {K.Pack.name.v7() == "layers" : String}

law layers_pack.env:
  {K.Pack.env.v7() == "VK8S_PACK" : String}

# A VM's name is its folder under ~/.vk8s/clusters.
law layers_pack.vm.control_plane:
  {K.Pack.vm.v7("/Users/u/.vk8s", "/Users/u/.vk8s/clusters/dev/data.img") == "dev" : String}

law layers_pack.vm.worker:
  {K.Pack.vm.v7("/Users/u/.vk8s", "/Users/u/.vk8s/clusters/dev/nodes/worker-2/data.img") == "dev/nodes/worker-2" : String}

# A data disk anywhere else names no VM (the node host's, a test's).
law layers_pack.vm.elsewhere:
  {K.Pack.vm.v7("/Users/u/.vk8s", "/Users/u/.vk8s/nodehost/data.img") == "" : String}

law layers_pack.vm.other_file:
  {K.Pack.vm.v7("/Users/u/.vk8s", "/Users/u/.vk8s/clusters/dev/disk.img") == "" : String}

law layers_pack.vm_ok.control_plane:
  {K.Pack.vm_ok.v7("dev-1") == True{} : Bool}

law layers_pack.vm_ok.worker:
  {K.Pack.vm_ok.v7("dev/nodes/worker-12") == True{} : Bool}

# Nothing that could leave ~/.vk8s/clusters is a VM's name.
law layers_pack.vm_ok.dots:
  {K.Pack.vm_ok.v7("..") == False{} : Bool}

law layers_pack.vm_ok.up:
  {K.Pack.vm_ok.v7("dev/nodes/..") == False{} : Bool}

law layers_pack.vm_ok.deep:
  {K.Pack.vm_ok.v7("dev/share/x") == False{} : Bool}

law layers_pack.vm_ok.empty:
  {K.Pack.vm_ok.v7("") == False{} : Bool}

law layers_pack.vm_ok.upper:
  {K.Pack.vm_ok.v7("Dev") == False{} : Bool}

law layers_pack.vm_ok.worker_name:
  {K.Pack.vm_ok.v7("dev/nodes/worker-x") == False{} : Bool}

law layers_pack.vm_dir.control_plane:
  {K.Pack.vm_dir.v7("/Users/u/.vk8s", "dev") == Some{"/Users/u/.vk8s/clusters/dev"} : Maybe<&2, String>}

law layers_pack.vm_dir.worker:
  {K.Pack.vm_dir.v7("/Users/u/.vk8s", "dev/nodes/worker-2") == Some{"/Users/u/.vk8s/clusters/dev/nodes/worker-2"} : Maybe<&2, String>}

law layers_pack.vm_dir.bad:
  {K.Pack.vm_dir.v7("/Users/u/.vk8s", "../x") == None{} : Maybe<&2, String>}

# The key
# -------

law layers_pack.key_file:
  {K.Pack.key_file.v7("/Users/u/.vk8s/clusters/dev") == "/Users/u/.vk8s/clusters/dev/share/pack.key" : String}

law layers_pack.key_same.yes:
  {K.Pack.key_same.v7("0k3v9q2m7x1c5b8n4j6h0a\n", "0k3v9q2m7x1c5b8n4j6h0a") == True{} : Bool}

law layers_pack.key_same.other:
  {K.Pack.key_same.v7("0k3v9q2m7x1c5b8n4j6h0a\n", "0k3v9q2m7x1c5b8n4j6h0b") == False{} : Bool}

# No file (read as "") matches no key, not even an empty one.
law layers_pack.key_same.no_file:
  {K.Pack.key_same.v7("", "") == False{} : Bool}

law layers_pack.key_same.short:
  {K.Pack.key_same.v7("abc", "abc") == False{} : Bool}

# The VM's flags
# --------------

law layers_pack.on.yes:
  {K.Pack.on.v7(True{}, "", "dev") == True{} : Bool}

# VK8S_PACK=0 on the host is the opt-out.
law layers_pack.on.opt_out:
  {K.Pack.on.v7(True{}, "0", "dev") == False{} : Bool}

# No pack without the layer store, whatever the rest.
law layers_pack.on.no_store:
  for env: String
  for vm: String
  {K.Pack.on.v7(False{}, env, vm) == False{} : Bool}

law layers_pack.on.no_vm:
  {K.Pack.on.v7(True{}, "", "") == False{} : Bool}

law layers_pack.flags.on:
  {K.Pack.flags.v7(True{}, "dev", layers_pack.fx.flags()) ==
    [ "--share", "/Users/u/.vk8s/clusters/dev/share,quota=1G",
      "--share", "/Users/u/.vk8s/layers,tag=layers,meta,ro",
      "--control", "/Users/u/.vk8s/clusters/dev/ctl.sock",
      "--pack", "layers",
      "--cmdline", "console=ttyAMA0 quiet panic=5 VK8S_NAME=dev VK8S_LAYERS=1 VK8S_PACK=dev",
      "--balloon", "auto" ] : +List<String>}

# Off, the flags are as they were: no --pack, no VK8S_PACK.
law layers_pack.flags.off:
  for vm: String
  for flags: +List<String>
  {K.Pack.flags.v7(False{}, vm, flags) == flags : +List<String>}

# The lines between a node and the filler
# ---------------------------------------

law layers_pack.ask.render.add:
  {K.Pack.ask.render.v7(K.PkAdd{"dev", layers_pack.fx.key(), layers_pack.fx.c()}) ==
    "pack dev 0k3v9q2m7x1c5b8n4j6h0a sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1\n" : String}

law layers_pack.ask.render.drop:
  {K.Pack.ask.render.v7(K.PkDrop{"dev/nodes/worker-2", layers_pack.fx.key(), layers_pack.fx.c()}) ==
    "drop dev/nodes/worker-2 0k3v9q2m7x1c5b8n4j6h0a sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1\n" : String}

law layers_pack.ask.parse.add:
  {K.Pack.ask.parse.v7(K.Pack.ask.render.v7(K.PkAdd{"dev", layers_pack.fx.key(), layers_pack.fx.c()})) ==
    Some{K.PkAdd{"dev", layers_pack.fx.key(), layers_pack.fx.c()}} : Maybe<&2, K.PkAsk>}

law layers_pack.ask.parse.drop:
  {K.Pack.ask.parse.v7(K.Pack.ask.render.v7(K.PkDrop{"dev/nodes/worker-2", layers_pack.fx.key(), layers_pack.fx.c()})) ==
    Some{K.PkDrop{"dev/nodes/worker-2", layers_pack.fx.key(), layers_pack.fx.c()}} : Maybe<&2, K.PkAsk>}

# Strict: no line end, another word, a VM's name that is a path, a key
# or a chain ID that is not one, a field too many.
law layers_pack.ask.parse.no_newline:
  {K.Pack.ask.parse.v7("pack dev 0k3v9q2m7x1c5b8n4j6h0a sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1") == None{} : Maybe<&2, K.PkAsk>}

law layers_pack.ask.parse.word:
  {K.Pack.ask.parse.v7("add dev 0k3v9q2m7x1c5b8n4j6h0a sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1\n") == None{} : Maybe<&2, K.PkAsk>}

law layers_pack.ask.parse.vm:
  {K.Pack.ask.parse.v7("pack ../dev 0k3v9q2m7x1c5b8n4j6h0a sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1\n") == None{} : Maybe<&2, K.PkAsk>}

law layers_pack.ask.parse.key:
  {K.Pack.ask.parse.v7("pack dev short sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1\n") == None{} : Maybe<&2, K.PkAsk>}

law layers_pack.ask.parse.chain:
  {K.Pack.ask.parse.v7("drop dev 0k3v9q2m7x1c5b8n4j6h0a c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1\n") == None{} : Maybe<&2, K.PkAsk>}

law layers_pack.ask.parse.extra:
  {K.Pack.ask.parse.v7("pack dev 0k3v9q2m7x1c5b8n4j6h0a sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1 x\n") == None{} : Maybe<&2, K.PkAsk>}

# The two protocols on one port do not read each other's lines: the
# filler's ask is no pack line, and a pack line is no ask (so a filler
# from before the pack answers it Srv.bad.v2).
law layers_pack.ask.parse.not_an_ask:
  {K.Pack.ask.parse.v7("ask docker.io library/busybox sha256:e6693c20186f837fc393390135d8a598a96a833917917789d63766cab6c59582 sha256:9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0 sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1\n") == None{} : Maybe<&2, K.PkAsk>}

law layers_pack.ask.old_filler_refuses:
  {A.Ask.parse.v2(K.Pack.ask.render.v7(K.PkAdd{"dev", layers_pack.fx.key(), layers_pack.fx.c()})) == None{} : Maybe<&2, A.Ask>}

law layers_pack.reply.render.at:
  {K.Pack.reply.render.v7(K.PkAt{"101711872", "4096"}) == "at 101711872 4096\n" : String}

law layers_pack.reply.render.dropped:
  {K.Pack.reply.render.v7(K.PkDropped{}) == "ok dropped\n" : String}

law layers_pack.reply.render.no:
  {K.Pack.reply.render.v7(K.Pack.no.v7("the key is not this VM's")) == "no the key is not this VM's\n" : String}

law layers_pack.reply.parse.at:
  {K.Pack.reply.parse.v7("at 101711872 4096\n") == Some{K.PkAt{"101711872", "4096"}} : Maybe<&2, K.PkReply>}

law layers_pack.reply.parse.dropped:
  {K.Pack.reply.parse.v7("ok dropped\n") == Some{K.PkDropped{}} : Maybe<&2, K.PkReply>}

law layers_pack.reply.parse.no:
  {K.Pack.reply.parse.v7("no the VM has no pack\n") == Some{K.PkNo{"the VM has no pack"}} : Maybe<&2, K.PkReply>}

# A number is digits only, at most 19 (bend-vmm's Pack.parse).
law layers_pack.reply.parse.at_sign:
  {K.Pack.reply.parse.v7("at -1 4096\n") == None{} : Maybe<&2, K.PkReply>}

law layers_pack.reply.parse.at_long:
  {K.Pack.reply.parse.v7("at 12345678901234567890 4096\n") == None{} : Maybe<&2, K.PkReply>}

law layers_pack.reply.parse.at_one:
  {K.Pack.reply.parse.v7("at 4096\n") == None{} : Maybe<&2, K.PkReply>}

# The filler's replies to an ask are no pack reply.
law layers_pack.reply.parse.present:
  {K.Pack.reply.parse.v7("ok present\n") == None{} : Maybe<&2, K.PkReply>}

# A filler from before the pack answers a pack line with Srv.bad.v2,
# which the node reads as a no and mounts from the share.
law layers_pack.reply.old_filler:
  {K.Pack.reply.parse.v7(A.Ask.reply.render.v2(SV.Srv.bad.v2())) == Some{K.PkNo{"not a valid ask"}} : Maybe<&2, K.PkReply>}

law layers_pack.wait:
  {K.Pack.wait.ms.v7() == 5000 : U32}

# bend-vmm's control socket
# -------------------------

law layers_pack.ctl.add:
  {K.Pack.ctl.add.v7(layers_pack.fx.img()) == "pack add /Users/u/.vk8s/layers/c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1.sqfs" : String}

law layers_pack.ctl.drop:
  {K.Pack.ctl.drop.v7("101711872") == "pack drop 101711872" : String}

law layers_pack.ctl.added:
  {K.Pack.ctl.added.v7("101711872 4096\n") == Some{K.PkAt{"101711872", "4096"}} : Maybe<&2, K.PkReply>}

law layers_pack.ctl.added.no_pack:
  {K.Pack.ctl.added.v7("error: no pack (start the VM with --pack NAME)") == None{} : Maybe<&2, K.PkReply>}

law layers_pack.ctl.added.cannot_open:
  {K.Pack.ctl.added.v7("error: cannot open /x.sqfs (errno 2)") == None{} : Maybe<&2, K.PkReply>}

law layers_pack.ctl.dropped:
  {K.Pack.ctl.dropped.v7("dropped\n") == True{} : Bool}

law layers_pack.ctl.dropped.error:
  {K.Pack.ctl.dropped.v7("error: no live entry at 4096") == False{} : Bool}

law layers_pack.table:
  {K.Pack.table.v7(layers_pack.fx.json()) == layers_pack.fx.table() : List<&2, K.PkEnt>}

# A VM without a pack, and an answer that is not JSON, have no entry.
law layers_pack.table.no_pack:
  {K.Pack.table.v7("{\"state\":\"running\"}") == Nil{} : List<&2, K.PkEnt>}

law layers_pack.table.not_json:
  {K.Pack.table.v7("error: no socket") == Nil{} : List<&2, K.PkEnt>}

# A drop ends the live entries of the layer's image; a dropped entry is
# not dropped again.
law layers_pack.offsets.live:
  {K.Pack.offsets.v7(layers_pack.fx.table(), layers_pack.fx.img()) == ["0"] : List<&2, String>}

law layers_pack.offsets.dropped:
  {K.Pack.offsets.v7(layers_pack.fx.table(), layers_pack.fx.img_d()) == Nil{} : List<&2, String>}

# An image added twice (two live entries) is dropped at both.
law layers_pack.offsets.twice:
  {K.Pack.offsets.v7([K.PkEnt{"0", "4096", "/a.sqfs", True{}}, K.PkEnt{"1048576", "8192", "/b.sqfs", True{}},
    K.PkEnt{"2097152", "4096", "/a.sqfs", True{}}], "/a.sqfs") == ["0", "2097152"] : List<&2, String>}

# gc
# --

law layers_pack.chain:
  {K.Pack.chain.v7("/Users/u/.vk8s", layers_pack.fx.img()) == Some{layers_pack.fx.c()} : Maybe<&2, String>}

law layers_pack.chain.agrees_with_store:
  {K.Pack.chain.v7("/Users/u/.vk8s", Maybe.default(&2, String, Y.Lay.img.v3("/Users/u/.vk8s", layers_pack.fx.d()), "")) ==
    Some{layers_pack.fx.d()} : Maybe<&2, String>}

law layers_pack.chain.elsewhere:
  {K.Pack.chain.v7("/Users/u/.vk8s", "/tmp/c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1.sqfs") == None{} : Maybe<&2, String>}

law layers_pack.chain.not_an_image:
  {K.Pack.chain.v7("/Users/u/.vk8s", "/Users/u/.vk8s/layers/c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1") == None{} : Maybe<&2, String>}

# Only the live entries hold their layers.
law layers_pack.chains:
  {K.Pack.chains.v7(layers_pack.fx.table(), "/Users/u/.vk8s") == [layers_pack.fx.c()] : List<&2, String>}

# gc keeps a layer that is live in a VM's pack, though no snapshot's
# layers.held names it and its last use is 72 h old: the plan, and the
# second look under the layer's lock.
law layers_pack.gc.plan_keeps_live:
  {F.Fill.gc.plan.v2([Y.Layer{layers_pack.fx.c(), layers_pack.fx.c(), "", Nil{}, 1000}],
    K.Pack.chains.v7(layers_pack.fx.table(), "/Users/u/.vk8s"), Nil{}, 1000000) == Nil{} : List<&2, Y.Layer>}

# The same layer without the pack's entry goes.
law layers_pack.gc.plan_drops_free:
  {F.Fill.gc.plan.v2([Y.Layer{layers_pack.fx.c(), layers_pack.fx.c(), "", Nil{}, 1000}], Nil{}, Nil{}, 1000000) ==
    [Y.Layer{layers_pack.fx.c(), layers_pack.fx.c(), "", Nil{}, 1000}] : List<&2, Y.Layer>}

# A dropped entry holds nothing.
law layers_pack.gc.plan_drops_dropped:
  {F.Fill.gc.plan.v2([Y.Layer{layers_pack.fx.d(), layers_pack.fx.d(), "", Nil{}, 1000}],
    K.Pack.chains.v7(layers_pack.fx.table(), "/Users/u/.vk8s"), Nil{}, 1000000) ==
    [Y.Layer{layers_pack.fx.d(), layers_pack.fx.d(), "", Nil{}, 1000}] : List<&2, Y.Layer>}

# The node
# --------

law layers_pack.guest:
  {K.Pack.guest.v7("dev/nodes/worker-2") == "dev/nodes/worker-2" : String}

# No VK8S_PACK (an older host, the opt-out, a node container): no pack.
law layers_pack.guest.unset:
  {K.Pack.guest.v7("") == "" : String}

law layers_pack.guest.path:
  {K.Pack.guest.v7("/etc") == "" : String}

law layers_pack.serial_file:
  {K.Pack.serial_file.v7("vdf") == "/sys/block/vdf/serial" : String}

law layers_pack.serial_is.yes:
  {K.Pack.serial_is.v7("layers\n") == True{} : Bool}

law layers_pack.serial_is.other:
  {K.Pack.serial_is.v7("\n") == False{} : Bool}

law layers_pack.dev:
  {K.Pack.dev.v7("vdf") == "/dev/vdf" : String}

# The layer a Remove let go, with no snapshot left on it, is unmounted.
law layers_pack.gone.released:
  {K.Pack.gone.v7([S.ARemove{"/x/snapshots/3"}, S.ARelease{layers_pack.fx.c(), "dev/k"}], Nil{}) == [layers_pack.fx.c()] : List<&2, String>}

# One another snapshot still stands on stays mounted.
law layers_pack.gone.still_held:
  {K.Pack.gone.v7([S.ARelease{layers_pack.fx.c(), "dev/k"}], [layers_pack.fx.d(), layers_pack.fx.c()]) == Nil{} : List<&2, String>}

law layers_pack.gone.once:
  {K.Pack.gone.v7([S.ARelease{layers_pack.fx.c(), "dev/k"}, S.ARelease{layers_pack.fx.c(), "dev/j"}], Nil{}) == [layers_pack.fx.c()] : List<&2, String>}

# A call that lets nothing go unmounts nothing.
law layers_pack.gone.acquire:
  {K.Pack.gone.v7([S.AMkdir{"/x/snapshots/3/fs"}, S.AAcquire{layers_pack.fx.c(), "dev/k"}], Nil{}) == Nil{} : List<&2, String>}

law layers_pack.gone.none:
  for left: List<&2, String>
  {K.Pack.gone.v7(Nil{}, left) == Nil{} : List<&2, String>}

law layers_pack.umount_args:
  {K.Pack.umount_args.v7(layers_pack.fx.c()) == ["umount", "/mnt/layers/c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1"] : List<&2, String>}

law layers_pack.rmdir_args:
  {K.Pack.rmdir_args.v7(layers_pack.fx.c()) == ["rmdir", "/mnt/layers/c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1"] : List<&2, String>}
