# Layer disk: compressed layer images, and an image kept twice

Status: measured 2026-11-24 on the Mac (branch feat/layer-disk). Part A
answers docs/GOAL.md section 11, "Compressed layer images, if measured
better"; the product does not change. Part B changes the product: the
image cache no longer keeps a layer's compressed blob for 72 h beside
the layer in the shared layer store.

Where the disk went, one cluster, one nginx pod (private store, vk8s at
ca3ed75):

| | MiB |
|---|---|
| image cache store (`~/.vk8s/cache/store`), compressed blobs | 151 |
| layer store (`~/.vk8s/layers`), uncompressed squashfs images | 445 |

The five images (coredns, flannel, flannel-cni-plugin, kube-proxy,
nginx) are on the host twice, and the bigger copy is uncompressed.

## A. Compressed layer images

### What exists

- The writer (src/layers/sqfs.bend, host/layers/image.bend) stores
  everything raw on purpose (docs/ref/layers-sqfs.md): the super block
  names zlib (id 1) because squashfs wants a valid id, data blocks
  carry the raw bit (1 << 24) and metadata blocks 1 << 15, so the
  writer needs no compressor. File data never becomes a Bend list: it
  goes from the tar to the image in C (LayerFs.copy_at,
  host/layers/effs/layer_fs.c).
- The guest reads every squashfs compressor already. squashfs.ko of the
  Alpine linux-virt 6.18.64 kernel in the initramfs has zlib, lzo, lz4,
  xz and zstd built in and depends on no other module (`depends=` is
  empty; the assets disks are zstd squashfs and mount from the
  initramfs). Nothing changes in the guest for any of them.
- No compressor exists as a Bend effect. Base has none.
  bend-kube-runtime 0.11.0.0 has decompression only: `Unz` (gzip through
  zlib, zstd through libzstd, both opened with dlopen) and the pure-Bend
  `Gz.inflate`. bend-vmm (0x002839320e5a033b05bcedb51711713f) has
  inflate only (gzip kernels, qcow2 clusters). This repository's own C
  (layer_fs.c) copies bytes and compresses nothing.

### What it would take

Under the owner's rule (pure Bend: no new C file or function here, no
shelling out to mksquashfs), compressed blocks need one new effect, in
bend-kube-runtime beside `Unz`, which already loads the two libraries:

    Zip.blocks(kind, level, src: File, off_hi, off_lo, len_hi, len_lo,
               block: U32, dst: File, at_hi, at_lo)
      -> IO(File & (File & Result<U32 & String, List<U32>>))

It reads len bytes of src from off in blocks of `block` bytes,
compresses each block on its own (kind: zstd, zlib or lz4, as the
squashfs ids), writes it at dst's next offset from `at` (a block that
does not shrink is written raw), and answers one word a block: its
stored length, with bit 24 set when raw. That is squashfs's block list
entry, so the pure side is small: src/layers/sqfs.bend takes each
file's block words and stored length from the effect instead of
Sqfs.blist and the file size, the super block names the compressor and
drops the NOD flag, and metadata stays raw (compressing it too saves
0.3%: zstd3 against zstd3-data below). New defs and laws beside the
existing ones; no existing law changes.

Two limits of that effect:

- libzstd is not a macOS system library. `Unz` finds it only where
  Homebrew puts it. A Mac without it has zlib (and Apple's
  libcompression: lz4, zlib, lzfse; no zstd). Linux distributions ship
  libzstd.so.1. So zstd images need a fallback (raw blocks when the
  library is missing; the format allows it block by block) or zlib,
  which costs 8 times the CPU (gzip1 below).
- A compressor written in Bend is not an option at this size. Pure-Bend
  SHA-256 ran at 45 KB/s on this Mac (2026-11-24) and the pure-Bend
  gzip decoder at about 5 MB/s; the file data would also have to become
  Bend lists first. The five images are 441 MiB of file data: at
  5 MB/s that is 90 s of CPU against the 0.5 s the oracle's compressor
  needs, and against a whole fill of nginx that takes 0.94 s of CPU
  today.

So today this item is blocked on a compression effect.

### What it would buy: the oracle

squashfs-tools 4.7.5 (`sqfstar`, one image file per layer from the
layer's tar on stdin, nothing unpacked on the host) wrote each layer of
the five images with the writer's geometry (128 KiB blocks, no
fragments) and one compressor, single-threaded (`-processors 1`). Size
is the sum of the image's layer images; CPU is user + system seconds of
sqfstar alone.

Size, MiB:

| image | registry blobs (gzip) | raw (today) | lz4 | zstd 1 | zstd 3 | zstd 3, data only | gzip 1 | gzip 6 | zstd 15 |
|---|---|---|---|---|---|---|---|---|---|
| coredns (13 layers) | 19.8 | 67.7 | 28.7 | 20.9 | 20.0 | 20.1 | 22.2 | 19.9 | 17.2 |
| nginx (7) | 65.6 | 188.3 | 91.7 | 72.5 | 69.6 | 69.8 | 69.7 | 65.4 | 59.7 |
| flannel-cni-plugin (2) | 5.1 | 11.1 | 6.8 | 5.5 | 5.3 | 5.3 | 5.3 | 5.0 | 4.6 |
| flannel (10) | 32.9 | 99.0 | 44.2 | 34.5 | 33.3 | 33.3 | 34.9 | 32.3 | 29.1 |
| kube-proxy (3) | 25.2 | 74.9 | 33.6 | 25.3 | 24.3 | 24.3 | 25.9 | 23.7 | 21.0 |
| all five | 148.6 | 440.9 | 205.0 | 158.7 | 152.5 | 152.8 | 157.9 | 146.3 | 131.7 |
| against raw | | | -54% | -64% | -65% | -65% | -64% | -67% | -70% |

Host CPU to write them, seconds:

| image | raw | lz4 | zstd 1 | zstd 3 | zstd 3, data only | gzip 1 | gzip 6 | zstd 15 |
|---|---|---|---|---|---|---|---|---|
| coredns | 0.09 | 0.15 | 0.17 | 0.18 | 0.18 | 0.48 | 1.24 | 4.13 |
| nginx | 0.20 | 0.29 | 0.35 | 0.42 | 0.42 | 1.36 | 3.58 | 8.32 |
| flannel-cni-plugin | 0.01 | 0.02 | 0.03 | 0.03 | 0.03 | 0.10 | 0.27 | 0.57 |
| flannel | 0.09 | 0.16 | 0.18 | 0.20 | 0.20 | 0.66 | 1.70 | 4.78 |
| kube-proxy | 0.07 | 0.12 | 0.14 | 0.17 | 0.17 | 0.54 | 1.50 | 4.01 |
| all five | 0.46 | 0.74 | 0.87 | 1.00 | 1.00 | 3.14 | 8.29 | 21.81 |

(kube-router is not an image here: it runs from the node set.) A zstd
image is the size of the registry's gzip blob.

Host CPU per fill. The Bend filler's own cost for nginx, three runs
each:

- `vk8s layers fill` with the blobs already in the cache's store
  (linked, no fetch): 0.94, 0.94, 0.95 s of CPU (0.78 s wall).
- a cold pull in a cluster (`vk8s cache serve` fetching, `vk8s layers
  serve` filling): 0.27 s + 1.18 s = 1.45 s of CPU.

The compressor's cost is the oracle's difference from raw for nginx,
which already counts the bytes it no longer writes:

| | added CPU | against 0.94 s (cache warm) | against 1.45 s (cold) |
|---|---|---|---|
| lz4 | 0.09 s | +10% | +6% |
| zstd 1 | 0.15 s | +16% | +10% |
| zstd 3 | 0.22 s | +23% | +15% |
| gzip 1 (zlib) | 1.16 s | +123% | +80% |

### The guest: time to a running pod and read cost

One 1-node VM cluster (2 vCPUs, 2 GiB), vk8s at ca3ed75, bend-vmm pin
0x002839320e5a033b05bcedb51711713f, the layer store on. The two big
nginx layers (188 of the image's 188.3 MiB) were replaced in a private
store by the oracle's images; the five small layers (one or two files
each) stayed. For each run the nginx pod and image were removed from
the node, the two layer images unmounted, the files swapped on the
host, the guest's page cache dropped; then the pod was started and
timed from `kubectl run` to Ready, and after that every file of its
root file system was read once (`find / -xdev -type f | xargs cat`,
200 MB). Guest CPU is /proc/stat's busy time; VMM CPU is the host CPU
of the node's `vk8s vmm` process (vCPUs and the 9p server). Three
runs each, in turn; the median:

| layer images | on disk, MiB | pod Ready, ms | VMM CPU to Ready, s | read all, ms | guest CPU, s | VMM CPU, s |
|---|---|---|---|---|---|---|
| raw, written by vk8s (today) | 188.9 | 1293 | 1.11 | 5151 | 3.52 | 9.16 |
| raw, written by sqfstar | 188.3 | 1121 | 0.98 | 4845 | 3.34 | 8.91 |
| lz4 | 91.7 | 1135 | 1.00 | 2668 | 1.89 | 4.67 |
| zstd 1 | 72.5 | 1058 | 0.89 | 2117 | 1.52 | 3.51 |
| zstd 3 | 69.6 | 1077 | 0.80 | 1907 | 1.45 | 3.16 |

All runs (variant, ms to Ready, read ms, VMM CPU of the read):
raw/vk8s 1314 4874 9.07, 1293 5270 9.73, 1258 5151 9.16; raw/sqfstar
1121 4845 8.91, 1055 4582 8.47, 1294 5176 9.47; lz4 1135 2929 4.99,
1179 2668 4.67, 1131 2337 4.50; zstd 1 1058 2261 4.28, 1197 2117 3.51,
1019 1973 3.31; zstd 3 1077 1722 2.94, 1085 4044 5.92 (an outlier),
1056 1907 3.16.

A compressed image is not slower in the guest: it is faster. A pod
start reads a few MiB and is the same within the spread (1.06-1.14 s
against 1.12-1.29 s). A full read is 1.8 to 2.5 times faster and takes
half to a third of the CPU, because the cost on this pin is the bytes
that cross the 9p share, not the decompression. bend-vmm's 9p read path
is being made faster separately; the gap will narrow with it, so the
read numbers belong to this pin (bend-vmm 0x2cb44898b57f05c48f38583063e077bf,
whose pin bump was pending when this was measured, already reads a
whole image about twice as fast on macOS, and a layer disk in place of
the share would read at a disk's speed). Once a raw read costs what a
disk read costs, a compressed image saves disk and host page cache but
no longer time: the decompression (about 0.2 s of guest CPU for nginx
at zstd's speed) is then a small cost, not a gain. Guest memory was
not measured.

### Decision under the GOAL's rule

The rule: zstd blocks "only when host CPU per fill and time to a
running pod stay within 10% while disk drops".

- Disk drops: 441 to 153-159 MiB for the five images (-64%, -65%).
- Time to a running pod stays within 10%: against today's images it
  is 12 to 18% lower, against sqfstar's raw ones between 6% lower and
  1% higher, which is the spread of the runs.
- Host CPU per fill does not stay within 10% for zstd: +16% (level 1)
  and +23% (level 3) on a fill from a warm cache, +10% and +15% on a
  cold one. lz4 does (+6 to +10%) and still halves the disk.

So by the rule as written, zstd blocks are not adopted: the filler's
CPU per fill rises by more than 10%. And nothing can be adopted yet:
there is no compression effect, and a Bend compressor is 100 times too
slow.

What the numbers say beyond the rule, for the owner's call: the CPU the
rule guards is small and paid once per layer per host (0.15 s for
nginx at zstd 1), and each cold full read of that image in a node
costs 5.4 s less VMM CPU with it. Counted over the whole cold pull
(cache 0.27 s, filler 1.18 s, the node's VMM about 1 s to Ready)
zstd 1 adds about 6%. The order of work, if this is wanted: (1) `Zip.blocks` in
bend-kube-runtime (the owner's call, a BendHub publish); (2) the v2
writer and its laws here; (3) the same three measurements with the
real writer on the then-current bend-vmm pin, lz4 and zstd 1 side by
side, since lz4 meets the rule as written.

## B. Do not keep an image twice

### Who reads a cache blob after a fill

Nobody on a node that uses the layer store. Measured with the cache's
sidecars, which record every hit (the cache logs fills, not hits): a
cluster was created, nginx started, the cluster deleted, and a second
cluster created against the warm cache and the warm layer store, nginx
started again (1.26 s). Of the cache's 50 sidecars:

- 15 moved: the index, the manifest and the config of each of the five
  images (673 to 10248 bytes each, 50 KiB together);
- 35 did not: every layer blob (32 bytes to 40.8 MB, 148.6 MiB
  together).

The filler answered 35 asks with "present" and fetched nothing; the
cache fetched nothing. containerd resolves the image through the cache
(index, manifest, config), asks the snapshotter for each layer, and
fetches no blob for a layer the snapshotter says is there.

After a fill a layer blob in the cache is read only by:

1. a node that does not use the layer store (a container or native
   node, a VM node with `VK8S_LAYERS=0`) pulling the same image;
2. a store node whose ask the filler refused (the node then unpacks the
   layer itself, from the blob);
3. a later fill of the same layer after `vk8s layers gc` removed it
   (72 h unused and held by no node).

What the filler copies: nothing since 81c5031 when the cache's store
holds the blob (a hard link at `~/.vk8s/oci`, removed again by an
automatic fill once the layer is published). On a cold pull it streams
the blob from the cache into `~/.vk8s/oci/tmp` while the cache fetches
it, and removes that copy after publishing. Either way `~/.vk8s/oci`
is empty afterwards; the copy that stayed for 72 h was the cache's own.

### The policy

When an automatic fill publishes a layer, it lapses the cache's copy of
that layer's blob: the sidecar's last use is set back to now - 72 h +
10 min (Store.lapse), and nothing else changes.

- The cache's expiry rule is untouched (Store.expired, 72 h since the
  last use), so its hourly sweep removes the blob at the first sweep
  10 minutes later.
- A hit serves an object whatever its age and records its use
  (Store.hit, unchanged). So a node that asks for the blob within the
  grace gets it from the cache and keeps it there for the full 72 h:
  "no node without the store asked for it lately" needs no new record.
- After the sweep the blob is fetched from the registry again when
  someone asks, by the same single-flight fill and digest check as any
  blob that expired. A container or native node pulling later gets it
  from the cache or through it.
- The blob file is never touched by the filler, so a request being
  served, or the filler's own link, is not cut.
- Only published layers: a refused layer's blob (case 2) keeps its
  72 h, and so does every index, manifest and config.
- `vk8s cache prune`, `vk8s layers gc`, the single-flight fill and the
  digest checks run the same code as before. `vk8s layers fill` (by
  hand) lapses nothing, as it keeps its own blob too.

Code: src/oci/store.bend `Store.lapse.grace`, `Store.lapse.at`,
`Store.lapse`, `Store.lapse.sidecar`; host/layers/fill.bend
`Lf.blob.lapse` (called from `Lf.layer.v2.end`, beside `Lf.blob.drop`,
when `Fill.blob.drop.v2` says so). Laws, proposed at the end of
laws/oci_store.bend and proven in proofs/oci_store.bend:
`oci_store.lapse.grace_10min`, `.lapse`, `.lapse.kept_through_grace`,
`.lapse.expires_after_grace`, `.lapse.hit_keeps_72h`,
`.lapse.hit_then_72h`, `.lapse.never_later`, `.lapse.early_clock`,
`.lapse.sidecar`, `.lapse.sidecar_unreadable`, `.lapse.sweep`.
tests/layers_serve.sh checks it end to end on Linux: the blob's
sidecar is lapsed and the manifest's and config's are not, the blob is
still whole, a node that asks gets it with no registry request, and
that use renews it.

### Measured

On the Mac, a private store, one 1-node cluster, the system images and
one nginx pod, everything cold at the start:

| | cache store | layer store | `~/.vk8s/oci` | sum |
|---|---|---|---|---|
| before (ca3ed75), after the pod runs | 151.0 MiB, 100 files | 445.4 MiB | 0 | 596 MiB |
| before, 72 h after the last pull (by the expiry rule, not measured) | 0 | 445.4 MiB | 0 | 445 MiB |
| after, when the pod runs | 151.7 MiB, 100 files | 445.4 MiB | 0 | 597 MiB |
| after, at the cache's first sweep past 10 min | 0.14 MiB, 30 files | 445.4 MiB | 0 | 446 MiB |

- The filler published 35 layers and lapsed 35 sidecars (155,829,013
  bytes of blobs); the 15 indexes, manifests and configs (49,724
  bytes) were not lapsed. `vk8s cache status` went from 148.6 MiB to
  47 KiB. (The sweep was brought on by restarting the cache 10.5
  minutes after the pull, since a cache sweeps when it starts; left
  alone it runs every hour.)
- A pull after the sweep on the store node (nginx removed from the
  node first): Ready in 1.09 s, the cache fetched nothing.
- A node without the layer store after the sweep (a new cluster with
  `VK8S_LAYERS=0`): every pod ran, nginx Ready in 6.2 s; the cache
  fetched the 35 layer blobs from the registries again, and none of
  them was lapsed, so they stay for that node's 72 h (cache store
  151.1 MiB again).

Host file operations per layer fill (docs/ref/layers-sqfs.md counts
about 12): two more for a published layer whose blob the cache holds,
the lapsed sidecar written as a tmp file and renamed over the cache's.
The blob's two removals (blob and sidecar) happen at the sweep after
10 minutes instead of the one after 72 h; their number is the same.

### Left

- The sweep is hourly, per registry, so the blob goes 10 to 70 minutes
  after the layer is published, not at 10. A sweep a few minutes after
  a lapse would need the filler to tell the cache, or a shorter tick.
- The cache's prefetch (Pull.prefetch.v5) fetches an image's biggest
  layers when it fetches the manifest, also when the layer store
  already holds those layers (a new image on a base the store has, or
  a manifest that expired while its layers were held). Such a blob is fetched for nothing and stays 72 h,
  because only a publish lapses. The fix is for the prefetch to ask the
  layer store first (the cache has the manifest and the config, so
  Pull.fills gives it the chain IDs); not done here, it changes the
  prefetch's decision and its laws.
- On a cold pull the blob is still written to the cache's store, linked
  or streamed by the filler, and removed later. Filling straight from
  the registry stream would write it nowhere, at the cost of the
  cache's single fetch shared with nodes that do not use the store.
- `vk8s cache status` does not say how much of the cache duplicates
  the layer store. With the lapse the duplicates leave by themselves;
  reporting them would need a record of which blob made which layer
  (the layer's record has the diffID and the chain ID, not the blob's
  digest).
- A store filled before this change keeps its blobs until 72 h after
  their last use (`vk8s cache prune` frees them now).
- Seen while measuring, not changed: the guest snapshotter never
  unmounts a layer image (a removed image's layers stay loop-mounted
  until the VM stops), and it takes an existing `/mnt/layers/<hex>`
  directory for a mounted layer without checking that it is a mount
  point.
- With both parts, the same five images would take about 153-159 MiB
  on the host (zstd layer images, no blobs) instead of 596.
