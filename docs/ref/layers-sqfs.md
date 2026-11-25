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
  of the layer's tar, written by the host filler. File data is stored in
  lz4 blocks (since 2026-11-25; docs/ref/layers-compress.md): each
  128 KiB block compressed on its own, a block that does not shrink
  stored as it is (its size word carries the bit 1 << 24). The tables
  are stored raw (metadata headers carry the bit 1 << 15; flags NOI, NOF
  and NO_FRAG): compressing them saves 0.3%. The compressor is
  bend-kube-runtime's `Zip.blocks`, a C routine with no library, file to
  file, so file data never becomes a Bend list. Images written before
  are all raw (compression id 1, flag NOD); a node reads both, and the
  store keeps them until gc removes the layer.
- Format: Linux v6.12 fs/squashfs/squashfs_fs.h (super block, inodes,
  directory headers and entries, id table, xattr tables) and xattr.h.
  The block size is 128 KiB (block_log 17). The super block names lz4
  (compression id 5) and sets COMP_OPT: the kernel refuses an lz4 image
  without the compressor's options, 10 bytes after the super block, so
  the data starts at 106.
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
