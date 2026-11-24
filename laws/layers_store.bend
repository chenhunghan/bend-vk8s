import Base
import ../src/layers/store.bend as Y

# Spec for src/layers/store.bend: the shared read-only layer store.
# Chain IDs follow the image-spec (config.md: ChainID(L0) = DiffID(L0),
# ChainID(L0|L1) = Digest(ChainID(L0) + " " + DiffID(L1))); the values
# are Python hashlib sha256 hex digests. The diffIDs are sha256(""),
# sha256("abc") and sha256("vcluster"). Publishing by rename from tmp,
# references by holder, and expiry 72 h after the last use of a layer no
# holder holds are user decisions of 2026-11-17.

# 72 hours, in seconds.
law layers_store.ttl_72h:
  {Y.Lay.ttl() == 259200 : U32}

# Content addressing
# ------------------

law layers_store.chain_first:
  {Y.Lay.chain("", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" : String}

law layers_store.chain_second:
  {Y.Lay.chain("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") == "sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6" : String}

# The chain IDs of [sha256(""), sha256("abc"), sha256("vcluster")] are
# [e3b0..., a893..., 1fa5...]. The kernel cannot hash three times in one
# law, so the laws below split it: chain_first, chain_second and
# chain_third give each chain ID; chains_start, chains_step and
# chains_end say each layer's parent is the chain ID before it.
law layers_store.chain_third:
  {Y.Lay.chain("sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "sha256:f689954fb7af136362b02e8784233f78128dfec4e779c95aae228115091a7bc4") == "sha256:1fa549a8dd45ed584c6f33a2e664a8438cf281cc00aa267fe128f267eef4828e" : String}

law layers_store.chains_one:
  {Y.Lay.chains(["sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"]) == ["sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"] : List<&2, String>}

law layers_store.chains_two:
  {Y.Lay.chains(["sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"]) == ["sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6"] : List<&2, String>}

# The first layer has no parent.
law layers_store.chains_start:
  for +ds: List<&2, String>
  {Y.Lay.chains(ds) == Y.Lay.chains.go(ds, "") : List<&2, String>}

# Each layer's chain ID is the parent of the next layer's.
law layers_store.chains_step:
  for +p: String
  for +d: String
  for +ds: List<&2, String>
  {Y.Lay.chains.go(Con{d, ds}, p) == Con{Y.Lay.chain(p, d), Y.Lay.chains.go(ds, Y.Lay.chain(p, d))} : List<&2, String>}

law layers_store.chains_end:
  for p: String
  {Y.Lay.chains.go(Nil{}, p) == Nil{} : List<&2, String>}

# For every diffID, the first layer's chain ID is its diffID.
law layers_store.chain_base:
  for d: String
  {Y.Lay.chain("", d) == d : String}

# Paths
# -----

law layers_store.dir:
  {Y.Lay.dir("/s", "sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6") == Some{"/s/layers/a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6"} : Maybe<&2, String>}

law layers_store.tmp:
  {Y.Lay.tmp("/s", "sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", 7) == Some{"/s/tmp/a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6.7"} : Maybe<&2, String>}

# A node sees the layers share at /mnt/layers; no ":" in the path, which
# would split overlayfs' lowerdir.
law layers_store.mount:
  {Y.Lay.mount("sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6") == Some{"/mnt/layers/a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6"} : Maybe<&2, String>}

# Only "sha256:" and 64 lowercase hex digits name a layer.
law layers_store.refuse_traversal:
  {Y.Lay.dir("/s", "sha256:../../etc") == None{} : Maybe<&2, String>}

law layers_store.refuse_upper_hex:
  {Y.Lay.dir("/s", "sha256:E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855") == None{} : Maybe<&2, String>}

# Publishing
# ----------

# Unpack into tmp, fsync, rename into place, fsync the parent.
law layers_store.publish:
  {Y.Lay.publish("/s", "sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", 7) == Some{[
    Y.IoMkdir{"/s/tmp/a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6.7"},
    Y.IoUnpack{"/s/tmp/a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6.7"},
    Y.IoFsync{"/s/tmp/a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6.7"},
    Y.IoRename{"/s/tmp/a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6.7", "/s/layers/a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6"},
    Y.IoFsyncDir{"/s/layers"}]} : Maybe<&2, List<&2, Y.Io>>}

law layers_store.publish_refused:
  {Y.Lay.publish("/s", "latest", 7) == None{} : Maybe<&2, List<&2, Y.Io>>}

law layers_store.add:
  {Y.Lay.add([], "sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", 1000) == [Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", [], 1000}] : List<&2, Y.Layer>}

# A layer published twice is stored once.
law layers_store.add_twice:
  {Y.Lay.add([Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", ["n1/x"], 5}], "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", 1000) == [Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", ["n1/x"], 5}] : List<&2, Y.Layer>}

# References
# ----------

law layers_store.acquire:
  {Y.Lay.acquire([Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", [], 5}], "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "n1/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", 1000) == Some{[Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", ["n1/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"], 1000}]} : Maybe<&2, List<&2, Y.Layer>>}

law layers_store.acquire_twice:
  {Y.Lay.acquire([Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", ["n1/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"], 5}], "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "n1/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", 1000) == Some{[Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", ["n1/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"], 1000}]} : Maybe<&2, List<&2, Y.Layer>>}

law layers_store.acquire_missing:
  {Y.Lay.acquire([], "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "n1/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", 1000) == None{} : Maybe<&2, List<&2, Y.Layer>>}

# A release is a use: expiry counts from it.
law layers_store.release:
  {Y.Lay.release([Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", ["n1/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "n2/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"], 5}], "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "n1/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", 1000) == [Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", ["n2/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"], 1000}] : List<&2, Y.Layer>}

# Garbage collection
# ------------------

# Kept until 72 h since the last use have passed, then removed.
law layers_store.gc_fresh:
  {Y.Lay.gc.drop([Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", [], 1000}], 260199) == [] : List<&2, Y.Layer>}

law layers_store.gc_expired:
  {Y.Lay.gc.drop([Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", [], 1000}], 260200) == [Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", [], 1000}] : List<&2, Y.Layer>}

# A clock that went back expires nothing.
law layers_store.gc_clock_back:
  {Y.Lay.gc.drop([Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", [], 1000}], 999) == [] : List<&2, Y.Layer>}

# A held layer stays, however old.
law layers_store.gc_held:
  {Y.Lay.gc.keep([Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", ["n1/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"], 0}, Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", [], 0}], 4000000000) == [Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", ["n1/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"], 0}] : List<&2, Y.Layer>}

law layers_store.gc_paths:
  {Y.Lay.gc.paths("/s", Y.Lay.gc.drop([Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", ["n1/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"], 0}, Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", [], 0}], 4000000000)) == ["/s/layers/a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6"] : List<&2, String>}

# For every layer a holder holds, the collector keeps it.
law layers_store.held_never_dropped:
  for c: String
  for d: String
  for p: String
  for h: String
  for hs: List<&2, String>
  for u: U32
  for now: U32
  {Y.Lay.gc.drops(Y.Layer{c, d, p, Con{h, hs}, u}, now) == False{} : Bool}

# For every store and time, the collector removes only layers no holder
# holds.
law layers_store.gc_drops_only_free:
  for ls: List<&2, Y.Layer>
  for now: U32
  {Y.Lay.all_free(Y.Lay.gc.drop(ls, now)) == True{} : Bool}

# Proposed: layer images (v3, feat/layers-sqfs, docs/ref/layers-sqfs.md).
# The names are vk8s's design (the image beside the record, the share
# moved so /mnt/layers can hold a mount per layer), not upstream
# behaviour; the chain ID is image-spec config.md's example.
law layers_store.img_v3:
  {Y.Lay.img.v3("/h/.vk8s", "sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1")
    == Some{"/h/.vk8s/layers/c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1.sqfs"} : Maybe<&2, String>}
law layers_store.img_v3_bad_chain:
  {Y.Lay.img.v3("/h/.vk8s", "../etc") == None{} : Maybe<&2, String>}
law layers_store.store_v3:
  {Y.Lay.store.v3() == "/mnt/layers-store" : String}
law layers_store.store_img_v3:
  {Y.Lay.store_img.v3("sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1")
    == Some{"/mnt/layers-store/c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1.sqfs"} : Maybe<&2, String>}
law layers_store.store_dir_v3:
  {Y.Lay.store_dir.v3("sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1")
    == Some{"/mnt/layers-store/c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1"} : Maybe<&2, String>}
law layers_store.mount_unchanged_v3:
  {Y.Lay.mount("sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1")
    == Some{"/mnt/layers/c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1"} : Maybe<&2, String>}
law layers_store.mount_img_v3:
  {Y.Lay.mount_img.v3("sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1")
    == ["mount", "-t", "squashfs", "-o", "loop,ro,nosuid", "/mnt/layers-store/c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1.sqfs",
      "/mnt/layers/c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1"] : List<&2, String>}
law layers_store.mount_dir_v3:
  {Y.Lay.mount_dir.v3("sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1")
    == ["mount", "-o", "bind", "/mnt/layers-store/c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1",
      "/mnt/layers/c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1"] : List<&2, String>}


# Proposed: warm (v6, feat/ws-logs). A small layer image just mounted is
# read once, so the first exec from it does not wait for the store's share
# (the conformance test "Pods should support retrieving logs from the
# container over websockets" read an empty log 78 ms after the pod was
# Running, CI run 45395906166). The argv is vk8s's design: busybox's
# tar, with no shell, reads every regular file and writes to /dev/null.
law layers_store.warm_args_v6:
  {Y.Lay.warm_args.v6("sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1")
    == ["tar", "-cf", "/dev/null", "-C", "/mnt/layers/c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1", "."] : List<&2, String>}
