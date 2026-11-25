# One squashfs image per layer (host file churn)

Status: approved 2026-11-19, in progress. Replaces the unpacked directory
tree of the shared layer store (docs/GOAL.md section 10, "Shared image
layers on by default").

## Why

Today a fill writes every tar entry of a layer as its own host file under
`~/.vk8s/tmp/<hex>.<n>/`, plus a `.bend-meta` file per directory, then
renames the tree into `~/.vk8s/layers/<hex>`; gc deletes it entry by
entry. An image is thousands of host file creates and as many deletes.
On a Mac whose endpoint security records every file create, rename and
delete, a layer store this busy (and the cold-pull bench, which wiped and
refilled it every run) overloaded that agent and hung the Mac twice
(2026-11-19). Writes into one open file cost that agent almost nothing.

## Design

- A layer is one file, `~/.vk8s/layers/<hex>.sqfs`: a squashfs 4.0 image
  of the layer's tar, written by the host filler. Everything is stored
  uncompressed (flags NOI, NOD, NOF and NO_FRAG; data blocks carry the
  uncompressed bit 1 << 24, metadata headers the bit 1 << 15), so the
  writer needs no compressor and a guest reads file data at offsets in
  the image. The layer blob in the image cache stays compressed.
- Format: Linux v6.12 fs/squashfs/squashfs_fs.h (super block, inodes,
  directory headers and entries, id table, xattr tables) and xattr.h.
  The block size is 128 KiB (block_log 17). Compression id 1 (zlib) is
  recorded, as squashfs requires a valid one, and nothing is compressed.
- What a node sees is what the tar says, natively: modes, owners (id
  table), mtimes, hard links (one inode, nlink), symbolic links, device
  nodes, fifos, xattrs (security.capability and others), whiteouts (a
  character device 0:0, overlayfs's whiteout) and opaque directories
  (xattr trusted.overlay.opaque=y). bend-vmm's .bend-meta share mode is
  no longer needed for layers.
- The writer (pure, src/layers/sqfs.bend): the tar entries (Tar.plan's
  Ent list, tar order) and, for each regular file, where its data went in
  the image become the inode table, the directory table, the id table and
  the xattr tables, then the super block. Inodes are numbered and emitted
  in post-order (children before their directory, the root last), as
  mksquashfs does, so a directory's listing and inode are written once
  its children's inode references are known.
- The host fill (host/layers/unpack.bend): blob -> one decompressed tar
  (`<root>/tmp/<hex>.<n>.tar`, as today) -> a new image file
  `<root>/tmp/<hex>.<n>.sqfs` (96 zero bytes, then each regular file's
  data copied from the tar in 128 KiB blocks, then the tables, then the
  super block written at offset 0) -> fsync -> the records -> one rename
  to `<root>/layers/<hex>.sqfs` -> F_FULLFSYNC of `<root>/layers`. The
  tar is removed. No per-entry host file, no .bend-meta.
- The guest (host/snapshotter.bend, src/layers/snap.bend): a layer whose
  image is in the store is loop-mounted read-only
  (`mount -t squashfs -o loop,ro /mnt/layers/<hex>.sqfs /run/vk8s/layers/<hex>`)
  when a snapshot first needs it, and the mount is the overlay lowerdir.
  The guest loads `loop` (scripts/guest/modules.txt; squashfs is already
  in modules.early.txt). A store left by an older vk8s (directories) is
  still read: a directory `<hex>` is used as before.
- gc removes one file per layer (and its records).

## Host file operations per layer fill

| | today | squashfs |
|---|---|---|
| blob in oci | tmp + rename | tmp + rename |
| decompressed tar | create + delete | create + delete |
| layer | one create per tar entry and per directory's .bend-meta, one rename | one create + one rename |
| records | 2 x (tmp + rename) | 2 x (tmp + rename) |
| lock | create + delete | create + delete |
| gc later | one delete per entry | one delete |

About 12 operations per layer, whatever its size, instead of thousands
per image. Measured in Linux CI (find -newer counts of a fill, before and
after), then once on the Mac with `fs_usage` run by the user.

## Work items

- S1 the writer: src/layers/sqfs.bend, laws/layers_sqfs.bend (format
  constants from squashfs_fs.h, byte layouts of each structure, metadata
  block framing, inode references, directory runs), proofs, and
  tests/layers_sqfs.sh on Linux CI: images of small tars checked with
  `unsquashfs -lln` against `tar -tvf`, and a loop mount by the kernel.
- S2 host fill: write the image instead of the tree (new LayerFs effects
  to write and copy at an offset), gc of `<hex>.sqfs`, records unchanged.
- S3 guest: loop mount, lowerdir, `loop` module, old-store fallback.
- S4 evidence: Linux CI file-op counts before/after, the KVM store-on
  regression (43/0), then the user's one-fill fs_usage check on the Mac.
  Only then any Mac bench, with fewer runs and no full wipes.

## The first exec from a fresh mount (v6, 2026-11-24)

A node reads a layer image through its loop device from the store's 9p
share, with no cache on the share, so nothing of a layer is in the node's
page cache until a container reads it. The first exec from a layer just
mounted waits for its program and libraries, after the kubelet has
reported the container Running. The conformance test "Pods should support
retrieving logs from the container over websockets" reads the log once,
without follow, as soon as the pod is Running: in CI (kvm-regression,
standalone, store on; runs 45395906166 and 45417515516) it read an empty
log 78 ms after the framework saw Running, on a node that had pulled
busybox (1.26 s) for that pod.

Measured on a Mac VM node (2026-11-24, 30 rounds each of: remove the
image, unmount its layer, create the pod, read the log once when the API
shows Running):

| | store on, before | store off | store on, v6 |
|---|---|---|---|
| empty reads, read within 5 ms of Running | 30 of 30 | 0 of 30 | 0 of 30 |
| empty reads, `kubectl logs` after `kubectl wait` | 11 of 30 | 0 of 30 | 0 of 30 |
| StartContainer returned to first log byte, median (range) | +62 ms (+28 to +143) | -7 ms (-12 to 0) | -7 ms (-11 to 0) |
| pull of busybox, median | 0.41 s | 0.50 s | 0.49 s |

The share is the cost: bend-vmm answers a 9p read at 9 to 30 ms per MiB
whatever the request size (src/fs/p9wire.bend: an Rread carries its data
as a Bend list of bytes; the same VM reads its virtio-blk disk at about
1 ms per MiB), and
busybox's `sh` reads 1.1 MiB to start. A larger readahead on the loop
device does not help (same bytes), and reading the loop device first does
not either (squashfs does not read through the block device's cache).

So the node's snapshotter reads a small layer image once, right after it
mounts it and before it answers the Prepare that mounted it
(host/snapshotter.bend Snapd.warm; `busybox tar -cf /dev/null -C
/mnt/layers/<hex> .`, src/layers/store.bend Lay.warm_args.v6): the pull
ends with the layer in the page cache. Small is at most 8 MiB of regular
files, from the layer's record (src/layers/pb.bend Spb.warm.v6). The read
runs beside the other calls, as the ask to the filler does. A layer the
filler has just published is read the same way (10 rounds with the layer
removed from the host's store each time: 0 empty reads). At boot a
control plane read 21 layers of its add-ons in 357 ms in all.

A larger layer is left to its first reads. Reading every layer up to 256
MiB beside the pull was tried and dropped: agnhost's 157 MiB took its
pull from 0.5 s to 1.5 s, and its start, which touches little of its 75
MiB binary, was already 3 ms behind StartContainer without it. With v6
agnhost's pull is 0.67 s (two of its eleven layers are small: 7.8 and
1.4 MiB). A start that needs many MiB of a large layer (an interpreter,
many shared libraries) still waits for the share after Running: that
cost is bend-vmm's 9p read path.

## The pack disk (v7, 2026-11-25)

A VM node no longer reads a layer image through the share. Its VM has a
pack (bend-vmm `--pack layers`: one read-only virtio-blk disk, empty at
start), and the image joins it when the node first mounts the layer
(src/layers/pack.bend, laws/layers_pack.bend; host/snapshotter.bend,
host/layers/serve.bend, host/effs/pack_loop.c).

- The host starts a VM on the layer store with `--pack layers`,
  `VK8S_PACK=<vm>` on the kernel command line (`<vm>` is the VM's folder
  under ~/.vk8s/clusters: `<cluster>` or `<cluster>/nodes/worker-<i>`)
  and a new random key in its share (`pack.key`; Pack.flags.v7,
  Pack.key_file.v7). `VK8S_PACK=0` in the host's environment leaves all
  three out.
- The snapshotter uses the pack when its environment has VK8S_PACK, a
  virtio-blk disk has the serial `layers` and the share has the key.
  For a layer whose image the store holds (`test -f` on the share, as
  before) it sends the filler `pack <vm> <key> <chain>` and waits at
  most 5 s. The filler checks the key against the file in that VM's
  share, makes sure the store holds the layer (Ls.present.v3), sends
  `pack add <root>/layers/<hex>.sqfs` to the VM's control socket and
  answers `at <offset> <length>`. The node mounts that range:
  LOOP_CONFIGURE with the offset, the length as size limit, read-only
  and autoclear, then squashfs (one C effect, PackDev.mount: busybox's
  losetup has no size limit, and its mount takes offset= only for a
  regular file). It first waits, up to 2 s, until the device has grown
  to hold the range (the guest takes the new capacity in a work item).
- Any other outcome (no answer, a "no", a failed mount) ends in the
  loop mount from the share. A filler from before the pack answers "no
  not a valid ask".
- When a call lets a layer go and no snapshot stands on it
  (Pack.gone.v7), the node unmounts it, removes the mount point and
  sends `drop <vm> <key> <chain>`; the filler reads the VM's pack table
  (`status json`) and sends `pack drop <offset>` for each live entry of
  the image. Without a pack a layer stays mounted until the node stops,
  as before.
- gc counts every layer that is live on a VM's pack as held
  (Lf.held.v7: `status json` of each VM folder's control socket, at the
  plan and again under the layer's lock). A hibernated VM answers
  `status json` with its table.
- The snapshotter writes layers.held when it starts (before, only when a
  call took or let go a layer: a cluster restored under another name
  had none until then).
- The share stays: the probes of the store, the layers' records
  (`<hex>.rec`), directories of an older store, and the fall back.

Measured on a Mac (Apple M5 Pro, macOS 27.2.1, one-node VM clusters, 3
with the pack and 3 with VK8S_PACK=0 in the order pack, share, share,
pack, pack, share; the store and the image cache held the image):

| | pack | share |
|---|---|---|
| cold read of an nginx pod's root file system (`tar` of / to a pipe, 200,192,000 bytes; the node's caches dropped; 9 reads), median (range) | 240 ms (228 to 278) | 1952 ms (1785 to 2170) |
| the same read warm (3) | 70 to 72 ms | 80 to 85 ms |
| first nginx pod, `kubectl run` to Ready (3) | 1035, 1087, 1098 ms | 1051, 1051, 1096 ms |
| a repeat pod (6) | 571 to 644 ms | 598 to 641 ms |
| the filler's answer to a pack line | 1 to 3 ms a layer | |

A pod's start does not change: nginx reads little to start, and a
small layer was already read once at its mount (v6 above). What changes
is every later cold read of a layer.
