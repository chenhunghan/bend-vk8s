import Base

# Binary files
# ============
#
# Raw bytes to and from regular files, for what vk8s moves that is not
# text: the open-format snapshot's tar stream, which the proven codec in
# src/standalone/snapshot.bend makes and reads (bytes are List<&2, U32>,
# one byte per U32, 0..255; gzip -3 runs in the shell), and store dumps.
# Base's File.open creates files 0644; these create them 0600. Both
# host/vk8s.bend and host/init.bend may import this module.
#
# effs/bin_file.c serves native builds; every effect runs on an IO helper
# thread. effs/bin_file.js stands in on the JavaScript lane, where every
# effect fails with ENOSYS (38).
#
# Streaming: a dump can be hundreds of MB, so write it with BinFile.append
# a chunk at a time, and read it with BinFile.read a range at a time
# (BinFile.read_all does so in 1 MiB ranges). Offsets and sizes are U32,
# so a file past 4 GiB fails BinFile.size with EOVERFLOW.
#
# The handle is Base's File. Every effect but close hands it back beside
# its result, also on failure; end it with BinFile.close (or File.close).

def BinFile.Res(-A: Type) -> Type:
  Result<&1, &1, U32 & String, A>

# Effects
# -------

# Opens the regular file at path to read. A symbolic link as the last
# component fails (ELOOP), and anything but a regular file (a directory, a
# FIFO, a device) fails with EINVAL.
def BinFile.open(path: String) -> IO(BinFile.Res(File)):
  import "./effs/bin_file.c"
  import "./effs/bin_file.js"

# Creates the file at path to write, or truncates it, and sets its mode to
# 0600 whatever the umask or its mode before. Every write goes at the end.
# Refuses links and non-regular files as BinFile.open does.
def BinFile.create(path: String) -> IO(BinFile.Res(File)):
  import "./effs/bin_file.c"
  import "./effs/bin_file.js"

# Writes the bytes at the end of a file from BinFile.create. A value past
# 255 fails with EINVAL before any byte is written; a write error may
# leave a prefix written.
def BinFile.append(file: File, data: List<&2, U32>) -> IO(File & BinFile.Res(Unit)):
  import "./effs/bin_file.c"
  import "./effs/bin_file.js"

# Up to max bytes from offset (at most 16 MiB a call): fewer only at the
# end of the file, none at or past it. The file's position does not move.
def BinFile.read(file: File, offset: U32, max: U32) -> IO(File & BinFile.Res(List<&2, U32>)):
  import "./effs/bin_file.c"
  import "./effs/bin_file.js"

# The size in bytes; EOVERFLOW past 4 GiB.
def BinFile.size(file: File) -> IO(File & BinFile.Res(U32)):
  import "./effs/bin_file.c"
  import "./effs/bin_file.js"

def BinFile.close(file: File) -> IO(Unit):
  import "./effs/bin_file.c"
  import "./effs/bin_file.js"

# Composed
# --------

# The range BinFile.read_all asks for at a time.
def BinFile.chunk() -> U32:
  1048576

def BinFile.end(-A: Type, p: File & BinFile.Res(A)) -> IO(BinFile.Res(A)):
  match p:
    case (f, r):
      do IO<BinFile.Res(A)>:
        BinFile.close(f)
        return r

def BinFile.append_all.next(r: File & BinFile.Res(Unit), again: File -> IO(File & BinFile.Res(Unit))) ->
  IO(File & BinFile.Res(Unit)):
  match r:
    case (f, Done{u}):
      again(f)
    case (f, Fail{e}):
      IO.pure(File & BinFile.Res(Unit), (f, Fail{e}))

def BinFile.append_all.go(chunks: List<List<&2, U32>>, file: File) -> IO(File & BinFile.Res(Unit)):
  match chunks:
    case Nil{}:
      IO.pure(File & BinFile.Res(Unit), (file, Done{Unit{}}))
    case Con{c, t}:
      do IO<File & BinFile.Res(Unit)>:
        r : File & BinFile.Res(Unit) <- BinFile.append(file, c)
        BinFile.append_all.next(r, f => BinFile.append_all.go(t, f))

# Appends each chunk in turn; stops at the first failure.
def BinFile.append_all(file: File, chunks: List<List<&2, U32>>) -> IO(File & BinFile.Res(Unit)):
  BinFile.append_all.go(chunks, file)

def BinFile.write.go(r: BinFile.Res(File), data: List<&2, U32>) -> IO(BinFile.Res(Unit)):
  match r:
    case Fail{e}:
      IO.pure(BinFile.Res(Unit), Fail{e})
    case Done{f}:
      do IO<BinFile.Res(Unit)>:
        a : File & BinFile.Res(Unit) <- BinFile.append(f, data)
        BinFile.end(Unit, a)

# Creates (or truncates) path, mode 0600, writes data and closes it.
def BinFile.write(path: String, data: List<&2, U32>) -> IO(BinFile.Res(Unit)):
  do IO<BinFile.Res(Unit)>:
    r : BinFile.Res(File) <- BinFile.create(path)
    BinFile.write.go(r, data)

def BinFile.read_all.join(acc: List<&2, List<&2, U32>>) -> List<&2, U32>:
  List.concat(&2, U32, List.reverse(&2, List<&2, U32>, acc))

def BinFile.read_all.next(r: File & BinFile.Res(List<&2, U32>), acc: List<&2, List<&2, U32>>,
  again: File -> List<&2, List<&2, U32>> -> IO(File & BinFile.Res(List<&2, U32>))) ->
  IO(File & BinFile.Res(List<&2, U32>)):
  match r:
    case (f, Done{bs}):
      again(f, Con{bs, acc})
    case (f, Fail{e}):
      IO.pure(File & BinFile.Res(List<&2, U32>), (f, Fail{e}))

# n ranges of BinFile.chunk() bytes from at; acc holds the ranges read so
# far, the last first.
def BinFile.read_all.loop(n: Nat, f: File, +at: U32, acc: List<&2, List<&2, U32>>) ->
  IO(File & BinFile.Res(List<&2, U32>)):
  match n:
    case 0n:
      IO.pure(File & BinFile.Res(List<&2, U32>), (f, Done{BinFile.read_all.join(acc)}))
    case 1n+p:
      do IO<File & BinFile.Res(List<&2, U32>)>:
        r : File & BinFile.Res(List<&2, U32>) <- BinFile.read(f, at, BinFile.chunk())
        BinFile.read_all.next(r, acc, f2 => acc2 => BinFile.read_all.loop(p, f2, (at + BinFile.chunk() : U32), acc2))

def BinFile.read_all.fit(f: File, +size: U32, big: Bool) -> IO(File & BinFile.Res(List<&2, U32>)):
  match big:
    case True{}:
      IO.pure(File & BinFile.Res(List<&2, U32>), (f, Fail{(27, "BinFile: the file is larger than max")}))
    case False{}:
      BinFile.read_all.loop(U32.to_nat((size / BinFile.chunk() + 1 : U32)), f, 0, Nil{})

def BinFile.read_all.sized(s: File & BinFile.Res(U32), +max: U32) -> IO(File & BinFile.Res(List<&2, U32>)):
  match s:
    case (f, Fail{e}):
      IO.pure(File & BinFile.Res(List<&2, U32>), (f, Fail{e}))
    case (f, Done{+size}):
      BinFile.read_all.fit(f, size, U32.is_gt(size, max))

def BinFile.read_all.opened(r: BinFile.Res(File), +max: U32) -> IO(BinFile.Res(List<&2, U32>)):
  match r:
    case Fail{e}:
      IO.pure(BinFile.Res(List<&2, U32>), Fail{e})
    case Done{f}:
      do IO<BinFile.Res(List<&2, U32>)>:
        s : File & BinFile.Res(U32) <- BinFile.size(f)
        a : File & BinFile.Res(List<&2, U32>) <- BinFile.read_all.sized(s, max)
        BinFile.end(List<&2, U32>, a)

# The whole regular file at path, read in 1 MiB ranges. A file larger
# than max bytes fails with EFBIG (27) before any byte is read. Every
# byte is in memory at the end: stream a big file with BinFile.read.
def BinFile.read_all(path: String, +max: U32) -> IO(BinFile.Res(List<&2, U32>)):
  do IO<BinFile.Res(List<&2, U32>)>:
    r : BinFile.Res(File) <- BinFile.open(path)
    BinFile.read_all.opened(r, max)
