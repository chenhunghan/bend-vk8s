import Base
import ../src/layers/sqfs.bend as Q

# Spec for src/layers/sqfs.bend: one uncompressed squashfs 4.0 image per
# layer of the shared layer store (docs/ref/layers-sqfs.md).
#
# Proposed: every law of this file is new (feat/layers-sqfs, work item S1).
# Sources:
# - constants: Linux v6.12 fs/squashfs/squashfs_fs.h (SQUASHFS_MAGIC,
#   SQUASHFS_METADATA_SIZE, SQUASHFS_COMPRESSED_BIT, ..._BIT_BLOCK,
#   SQUASHFS_INVALID_FRAG, the *_TYPE values, the NOI/NOD/NOF/NO_FRAG
#   flag bits, ZLIB_COMPRESSION) and squashfs-tools' NOX (bit 8) and
#   NO_XATTR (bit 9);
# - bytes: an image squashfs-tools 4.7.5 wrote (`sqfstar -noI -noD -noF
#   -noX -no-fragments -mkfs-time 1700000000 -all-time 1700000000`) of a
#   tar holding etc/ (0755), etc/hi (0644, "hello\n") and etc/ln (-> hi,
#   0777), uid 0 gid 0; each law names the offset its bytes come from.
#   That image numbers etc 1, hi 2, ln 3 and the root 4, and puts hi's
#   inode at 0, ln's at 36, etc's at 62 and the root's at 94 of the inode
#   table; its id table is 0, 502, 20 (the root is the user's).
# - Linux new_encode_dev (include/linux/kdev_t.h) for rdev.

# Constants
# ---------

law layers_sqfs.magic:
  {Q.Sqfs.le32(Q.Sqfs.magic()) == [104, 115, 113, 115] : +List<U32>}
law layers_sqfs.meta:
  {Q.Sqfs.meta() == 8192 : U32}
law layers_sqfs.block:
  {Q.Sqfs.block() == 131072 : U32}
law layers_sqfs.block_log:
  {Q.Sqfs.block_log() == 17 : U32}
law layers_sqfs.meta_raw:
  {Q.Sqfs.meta_raw() == 32768 : U32}
law layers_sqfs.block_raw:
  {Q.Sqfs.block_raw() == 16777216 : U32}
law layers_sqfs.none:
  {Q.Sqfs.none() == 4294967295 : U32}
law layers_sqfs.zlib:
  {Q.Sqfs.zlib() == 1 : U32}
law layers_sqfs.types:
  {[Q.Sqfs.t_dir(), Q.Sqfs.t_reg(), Q.Sqfs.t_sym(), Q.Sqfs.t_blk(), Q.Sqfs.t_chr(), Q.Sqfs.t_fifo(), Q.Sqfs.t_sock()]
    == [1, 2, 3, 4, 5, 6, 7] : +List<U32>}
law layers_sqfs.types_ext:
  {[Q.Sqfs.t_ext(1), Q.Sqfs.t_ext(2), Q.Sqfs.t_ext(3), Q.Sqfs.t_ext(5)] == [8, 9, 10, 12] : +List<U32>}
# NOI | NOD | NOF | NO_FRAG | NOX, and NO_XATTR when no inode has any.
law layers_sqfs.flags_xattrs:
  {Q.Sqfs.flags(True{}) == 283 : U32}
law layers_sqfs.flags_none:
  {Q.Sqfs.flags(False{}) == 795 : U32}
law layers_sqfs.rdev:
  {Q.Sqfs.rdev(1, 3) == 259 : U32}
law layers_sqfs.rdev_big_minor:
  {Q.Sqfs.rdev(8, 300) == 1050668 : U32}

# Metadata blocks and references
# ------------------------------

# The oracle's inode table header at 0x66: 126 bytes, stored uncompressed.
law layers_sqfs.frame_header:
  {List.take(&2, U32, Q.Sqfs.frame(List.replicate(U32, 126n, 0)), 2n) == [126, 128] : +List<U32>}
law layers_sqfs.framed_len:
  {Q.Sqfs.framed_len(126) == 128 : U32}
law layers_sqfs.framed_len_two_blocks:
  {Q.Sqfs.framed_len(8193) == 8197 : U32}
# The oracle's root inode reference (super block 0x20): offset 94 of block 0.
law layers_sqfs.ref_root:
  {Q.Sqfs.ref_lo(94) == 94 : U32}
# Byte 8200 of a table is offset 8 of the block that starts at 8194.
law layers_sqfs.ref_second_block:
  {[Q.Sqfs.ref_hi(8200), Q.Sqfs.ref_lo(8200)] == [0, 537001992] : +List<U32>}

# Inodes (oracle inode table, from 0x68)
# --------------------------------------

def layers_sqfs.fx.ib(code: U32, nlink: U32, lsize: U32, parent: U32, start: U32, size: U32, link: String) -> Q.Ib:
  Q.Ib{code, False{}, Q.Sqfs.none(), nlink, 0, lsize, parent, start, size, link, 0}

def layers_sqfs.fx.inode(code: U32, mode: U32, num: U32, b: Q.Ib) -> +List<U32>:
  List.append(&2, U32, Q.Sqfs.base(code, mode, 0, 0, 1700000000, num), Q.Sqfs.ib.tail(b))

# etc/hi at 0x68: data at 96, 6 bytes, one block stored uncompressed.
law layers_sqfs.inode_reg:
  {layers_sqfs.fx.inode(2, 420, 2, layers_sqfs.fx.ib(2, 1, 0, 0, 96, 6, ""))
    == [2, 0, 164, 1, 0, 0, 0, 0, 0, 241, 83, 101, 2, 0, 0, 0, 96, 0, 0, 0, 255, 255, 255, 255, 0, 0, 0, 0, 6, 0, 0, 0, 6, 0, 0, 1] : +List<U32>}
# etc/ln at 0x8c: -> hi.
law layers_sqfs.inode_sym:
  {layers_sqfs.fx.inode(3, 511, 3, layers_sqfs.fx.ib(3, 1, 0, 0, 0, 0, "hi"))
    == [3, 0, 255, 1, 0, 0, 0, 0, 0, 241, 83, 101, 3, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 104, 105] : +List<U32>}
# etc/ at 0xa6: its listing at 0 of the directory table, 32 bytes, two
# links, parent 4 (the oracle's root).
law layers_sqfs.inode_dir:
  {layers_sqfs.fx.inode(1, 493, 1, layers_sqfs.fx.ib(1, 2, 32, 4, 0, 0, ""))
    == [1, 0, 237, 1, 0, 0, 0, 0, 0, 241, 83, 101, 1, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 35, 0, 0, 0, 4, 0, 0, 0] : +List<U32>}
law layers_sqfs.blocks_three:
  {Q.Sqfs.blocks_of(300000) == [0, 0, 2, 1, 0, 0, 2, 1, 224, 147, 0, 1] : +List<U32>}
law layers_sqfs.blocks_none:
  {Q.Sqfs.blocks_of(0) == [] : +List<U32>}

# Directory listings (oracle directory table, from 0xe8)
# ------------------------------------------------------

# etc's listing: one header (2 entries, inode block 0, base 2), hi at
# inode offset 0 and ln at 36.
law layers_sqfs.listing_etc:
  {Q.Sqfs.listing([Q.Ch{2, 0, 2, "hi"}, Q.Ch{3, 36, 3, "ln"}])
    == [1, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 2, 0, 1, 0, 104, 105, 36, 0, 1, 0, 3, 0, 1, 0, 108, 110] : +List<U32>}
# The root's listing at 0x108: etc, inode 1 at offset 62.
law layers_sqfs.listing_root:
  {Q.Sqfs.listing([Q.Ch{1, 62, 1, "etc"}])
    == [0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 62, 0, 0, 0, 1, 0, 2, 0, 101, 116, 99] : +List<U32>}
law layers_sqfs.listing_empty:
  {Q.Sqfs.listing([]) == [] : +List<U32>}
# A child in another inode block starts a new header (SQUASHFS_DIR_COUNT
# and the header's start_block, squashfs_fs.h).
law layers_sqfs.listing_new_block:
  {List.length(&2, U32, Q.Sqfs.listing([Q.Ch{2, 0, 2, "a"}, Q.Ch{3, 8200, 2, "b"}])) == 42n : Nat}
law layers_sqfs.near:
  {[Q.Sqfs.near(32767), Q.Sqfs.near(32768), Q.Sqfs.near(4294934528), Q.Sqfs.near(4294934527)]
    == [True{}, False{}, True{}, False{}] : List<&2, Bool>}

# The id table (oracle 0x11f)
# ---------------------------

law layers_sqfs.id_block:
  {Q.Sqfs.frame(Q.Sqfs.ids.bytes([0, 502, 20])) == [12, 128, 0, 0, 0, 0, 246, 1, 0, 0, 20, 0, 0, 0] : +List<U32>}

# Proposed: lz4 data blocks (GOAL section 11, "Compressed layer images")
# ---------------------------------------------------------------------
#
# Sources: Linux v6.12 fs/squashfs/squashfs_fs.h (LZ4_COMPRESSION 5,
# SQUASHFS_COMP_OPT bit 10) and lz4_wrapper.c (the options are required);
# bytes from an image squashfs-tools 4.7.5 wrote (`sqfstar -comp lz4 -noI
# -noF -noX -no-fragments -mkfs-time 1700000000 -all-time 1700000000`) of
# a tar holding etc/ (0755), etc/big (0644, 300000 times "a") and etc/hi
# (0644, "hello\n"), uid 0 gid 0. That image's data starts at 106; big is
# stored there in blocks of 524, 524 and 159 bytes.

law layers_sqfs.lz4:
  {Q.Sqfs.lz4() == 5 : U32}
# Sqfs.flags without NOD (2), with COMP_OPT (1024).
law layers_sqfs.flags_z_xattrs:
  {Q.Sqfs.flags_z(True{}) == 1305 : U32}
law layers_sqfs.flags_z_none:
  {Q.Sqfs.flags_z(False{}) == 1817 : U32}
# The oracle's bytes 96 to 105.
law layers_sqfs.opts_z:
  {Q.Sqfs.opts_z() == [8, 128, 1, 0, 0, 0, 0, 0, 0, 0] : +List<U32>}
law layers_sqfs.data_z:
  {Q.Sqfs.data_z() == 106 : U32}
law layers_sqfs.words:
  {Q.Sqfs.words([524, 16777222]) == [12, 2, 0, 0, 6, 0, 0, 1] : +List<U32>}
# etc/big's inode (oracle inode table, 0x529): data at 106, 300000 bytes,
# three compressed blocks.
law layers_sqfs.reword_big:
  {Q.Sqfs.reword(layers_sqfs.fx.inode(2, 420, 2, layers_sqfs.fx.ib(2, 1, 0, 0, 106, 300000, "")), [524, 524, 159])
    == [2, 0, 164, 1, 0, 0, 0, 0, 0, 241, 83, 101, 2, 0, 0, 0, 106, 0, 0, 0, 255, 255, 255, 255, 0, 0, 0, 0, 224, 147, 4, 0,
      12, 2, 0, 0, 12, 2, 0, 0, 159, 0, 0, 0] : +List<U32>}
# An inode without words (a directory, an empty file) stays as it is.
law layers_sqfs.reword_none:
  {Q.Sqfs.reword([1, 2, 3], []) == [1, 2, 3] : +List<U32>}
# An image with no entry: the super block names lz4 (offset 20), the
# flags of an image without xattrs (24), and ends with the options.
def layers_sqfs.fx.sb(i: Q.Img) -> +List<U32>:
  match i:
    case Q.Img{t, sb, e}:
      sb
law layers_sqfs.image_z_sb:
  {List.take(&2, U32, List.drop(&2, U32, layers_sqfs.fx.sb(Q.Sqfs.image_z([], 106)), 20n), 6n) == [5, 0, 17, 0, 25, 7] : +List<U32>}
law layers_sqfs.image_z_opts:
  {List.drop(&2, U32, layers_sqfs.fx.sb(Q.Sqfs.image_z([], 106)), 96n) == [8, 128, 1, 0, 0, 0, 0, 0, 0, 0] : +List<U32>}
# The raw image's super block is as before: zlib (1) and its flags, 96
# bytes; everything after the flags is the same in both.
law layers_sqfs.image_raw_sb:
  {List.take(&2, U32, List.drop(&2, U32, layers_sqfs.fx.sb(Q.Sqfs.image([], 96)), 20n), 6n) == [1, 0, 17, 0, 27, 3] : +List<U32>}
law layers_sqfs.image_raw_rest:
  {List.drop(&2, U32, layers_sqfs.fx.sb(Q.Sqfs.image([], 96)), 26n)
    == List.drop(&2, U32, List.take(&2, U32, layers_sqfs.fx.sb(Q.Sqfs.image_z([], 96)), 96n), 26n) : +List<U32>}

# All laws prove (laws/done/layers_sqfs).
