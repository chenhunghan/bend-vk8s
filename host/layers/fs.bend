import Base

# Layer files
# ===========
#
# The file IO under the shared layer store (src/layers/store.bend): what
# unpacking a layer into ~/.vk8s/layers/<hex> needs and Base and
# bend-vmm's V.Fs do not give. Every decision is the caller's, in Bend
# (src/layers/fill.bend says what to create and where); these effects
# only run system calls. effs/layer_fs.c says why each one is C;
# effs/layer_fs.js stands in on the JavaScript lane, where every effect
# fails with ENOSYS (38).
#
# Offsets and lengths are 64-bit, as a pair of U32: hi * 2^32 + lo, so a
# layer past 4 GiB unpacks. Paths are taken as given; nothing is created
# through a symbolic link at a path's end.

def LayerFs.Res(-A: Type) -> Type:
  Result<&1, &1, U32 & String, A>

# Effects
# -------

# Up to max bytes (at most 2 MiB) of file from offset hi * 2^32 + lo:
# fewer only at the end of the file, none at or past it. file is any Base
# File (File.open(path, "r")); its position does not move.
def LayerFs.read(file: File, off_hi: U32, off_lo: U32, max: U32) -> IO(File & LayerFs.Res(List<&2, U32>)):
  import "./effs/layer_fs.c"
  import "./effs/layer_fs.js"

# A new file at dst (mode 0644, never over anything there, never through
# a symbolic link) holding exactly len_hi * 2^32 + len_lo bytes of file
# from offset off_hi * 2^32 + off_lo; fsynced and closed. The file ending
# first fails with EIO, and a failure leaves no dst.
def LayerFs.copy(file: File, off_hi: U32, off_lo: U32, len_hi: U32, len_lo: U32, dst: String) ->
  IO(File & LayerFs.Res(Unit)):
  import "./effs/layer_fs.c"
  import "./effs/layer_fs.js"

# One entry at path, by kind (LayerFs.dir and the others below): a
# directory (0755; one already there is fine), an empty file (0644), a
# symbolic link to the bytes arg, a hard link to the file at the path
# arg, a file (0644, fsynced) holding the bytes arg, or a new directory
# (LayerFs.new_dir: one already there fails too). Anything already at
# path, but a directory for LayerFs.dir, fails with EEXIST.
def LayerFs.make(kind: U32, path: String, arg: List<&2, U32>) -> IO(LayerFs.Res(Unit)):
  import "./effs/layer_fs.c"
  import "./effs/layer_fs.js"

# fsync of the directory at path. On macOS the entries reach the drive
# but its cache is not flushed: a LayerFs.full_sync after it does that.
def LayerFs.fsync_dir(path: String) -> IO(LayerFs.Res(Unit)):
  import "./effs/layer_fs.c"
  import "./effs/layer_fs.js"

# F_FULLFSYNC of the directory at path on macOS (fsync elsewhere): the
# drive writes its whole cache, so every entry fsynced before it, in any
# directory, survives a crash. One per layer, after its fsyncs.
def LayerFs.full_sync(path: String) -> IO(LayerFs.Res(Unit)):
  import "./effs/layer_fs.c"
  import "./effs/layer_fs.js"

# A new file at path (0644, never over anything there, never through a
# symbolic link), open for writing: a layer's image (src/layers/sqfs.bend).
def LayerFs.create(path: String) -> IO(LayerFs.Res(File)):
  import "./effs/layer_fs.c"
  import "./effs/layer_fs.js"

# bytes written at offset at_hi * 2^32 + at_lo of dst.
def LayerFs.put_at(dst: File, at_hi: U32, at_lo: U32, bytes: List<&2, U32>) -> IO(File & LayerFs.Res(Unit)):
  import "./effs/layer_fs.c"
  import "./effs/layer_fs.js"

# len_hi * 2^32 + len_lo bytes of file from offset off_hi * 2^32 +
# off_lo, written at offset at_hi * 2^32 + at_lo of dst. The file
# ending first fails with EIO.
def LayerFs.copy_at(file: File, off_hi: U32, off_lo: U32, len_hi: U32, len_lo: U32, dst: File, at_hi: U32, at_lo: U32) ->
  IO(File & (File & LayerFs.Res(Unit))):
  import "./effs/layer_fs.c"
  import "./effs/layer_fs.js"

# fsync of dst.
def LayerFs.sync_file(dst: File) -> IO(File & LayerFs.Res(Unit)):
  import "./effs/layer_fs.c"
  import "./effs/layer_fs.js"

# Renames the directory from to to, never replacing a directory with
# entries at to: that fails with EEXIST (17).
def LayerFs.rename_dir(from: String, to: String) -> IO(LayerFs.Res(Unit)):
  import "./effs/layer_fs.c"
  import "./effs/layer_fs.js"

# Removes path and everything under it, never following a symbolic link.
# A path that is not there is done.
def LayerFs.remove_tree(path: String) -> IO(LayerFs.Res(Unit)):
  import "./effs/layer_fs.c"
  import "./effs/layer_fs.js"

# The kinds of LayerFs.make
# -------------------------

def LayerFs.dir() -> U32:
  0

def LayerFs.empty() -> U32:
  1

def LayerFs.symlink() -> U32:
  2

def LayerFs.link() -> U32:
  3

def LayerFs.file() -> U32:
  4

def LayerFs.new_dir() -> U32:
  5

# errno 17, what LayerFs.rename_dir answers when the target is there.
def LayerFs.eexist() -> U32:
  17
