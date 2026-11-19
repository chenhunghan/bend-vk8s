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
