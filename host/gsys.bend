import Base
import ../src/guest/sysop.bend as Y
import ./layers/fs.bend as LFS

# The guest's system calls, and what PID 1 (host/init.bend) and the
# node's snapshotter (host/snapshotter.bend) build on them in place of a
# busybox process (docs/GOAL.md section 11, "Fewer shell-outs"):
# mkdir -p, rm -f, mv -f, test -d, test -f, ls, mountpoint -q, mount
# -o bind, umount, rmdir, hwclock -s -u, fstrim -v, du -sk with find |
# wc -l, tar to /dev/null and the log trim. The effects are one system
# call each (host/effs/gsys.c says why they are C); src/guest/sysop.bend
# decides. rm -rf is LayerFs.remove_tree and the trim's copy is
# LayerFs.copy (host/layers/fs.bend), which the layer filler already has.

# mkdir(2): 0, or the errno.
def Gsys.mkdir(path: String, mode: U32) -> IO(U32):
  import "./effs/gsys.c"
  import "./effs/gsys.js"

# stat(2) (follow 1) or lstat(2) (follow 0): the ten words Y.Sysop.stat
# reads.
def Gsys.stat(path: String, follow: U32) -> IO(Result<&1, &1, U32 & String, List<U32>>):
  import "./effs/gsys.c"
  import "./effs/gsys.js"

# The names in a directory, but . and .., in the directory's order.
def Gsys.ls(dir: String) -> IO(Result<&1, &1, U32 & String, List<String>>):
  import "./effs/gsys.c"
  import "./effs/gsys.js"

# rename(2), unlink(2), rmdir(2): 0, or the errno.
def Gsys.rename(from: String, to: String) -> IO(U32):
  import "./effs/gsys.c"
  import "./effs/gsys.js"

def Gsys.unlink(path: String) -> IO(U32):
  import "./effs/gsys.c"
  import "./effs/gsys.js"

def Gsys.rmdir(path: String) -> IO(U32):
  import "./effs/gsys.c"
  import "./effs/gsys.js"

# mount(2) (fstype and data "" are NULL) and umount2(2): 0, or the errno.
def Gsys.mount(source: String, target: String, fstype: String, flags: U32, data: String) -> IO(U32):
  import "./effs/gsys.c"
  import "./effs/gsys.js"

def Gsys.umount(target: String, flags: U32) -> IO(U32):
  import "./effs/gsys.c"
  import "./effs/gsys.js"

# clock_settime(CLOCK_REALTIME) to a whole second since 1970 (Linux
# only): 0, or the errno.
def Gsys.settime(seconds: U32) -> IO(U32):
  import "./effs/gsys.c"
  import "./effs/gsys.js"

# FITRIM over the file system that holds path, on a helper thread: the
# bytes discarded, as (high, low).
def Gsys.fitrim(path: String) -> IO(Result<&1, &1, U32 & String, U32 & U32>):
  import "./effs/gsys.c"
  import "./effs/gsys.js"

# A regular file read to its end, its bytes dropped, on a helper thread:
# the bytes read, as (high, low).
def Gsys.drain(path: String) -> IO(Result<&1, &1, U32 & String, U32 & U32>):
  import "./effs/gsys.c"
  import "./effs/gsys.js"

# --- stat, test -d, test -f, mountpoint -q

def Gs.stat.of(r: Result<&1, &1, U32 & String, List<U32>>) -> Maybe<&2, Y.Stat>:
  match r:
    case Fail{e}:
      None{}
    case Done{ws}:
      Y.Sysop.stat(ws)

# follow 1: stat (through a link at the end); 0: lstat.
def Gs.stat(+path: String, +follow: U32) -> IO(Maybe<&2, Y.Stat>):
  do IO<Maybe<&2, Y.Stat>>:
    r : Result<&1, &1, U32 & String, List<U32>> <- Gsys.stat(path, follow)
    return Gs.stat.of(r)

def Gs.dir_of(m: Maybe<&2, Y.Stat>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{s}:
      Y.Stat.is_dir(s)

def Gs.file_of(m: Maybe<&2, Y.Stat>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{s}:
      Y.Stat.is_file(s)

# test -d PATH, test -f PATH: through a link, as test does.
def Gs.is_dir(+path: String) -> IO(Bool):
  do IO<Bool>:
    m : Maybe<&2, Y.Stat> <- Gs.stat(path, 1)
    return Gs.dir_of(m)

def Gs.is_file(+path: String) -> IO(Bool):
  do IO<Bool>:
    m : Maybe<&2, Y.Stat> <- Gs.stat(path, 1)
    return Gs.file_of(m)

def Gs.mountpoint.of(here: Maybe<&2, Y.Stat>, up: Maybe<&2, Y.Stat>) -> Bool:
  match here up:
    case Some{+h} Some{+u}:
      Y.Sysop.mountpoint(h, u)
    case _ _:
      False{}

# mountpoint -q PATH (Y.Sysop.mountpoint).
def Gs.mountpoint(+path: String) -> IO(Bool):
  do IO<Bool>:
    here : Maybe<&2, Y.Stat> <- Gs.stat(path, 0)
    up : Maybe<&2, Y.Stat> <- Gs.stat(path ++ "/..", 1)
    return Gs.mountpoint.of(here, up)

# --- mkdir -p

def Gs.then(ok: Bool, rest: IO(Bool)) -> IO(Bool):
  match ok:
    case True{}:
      rest
    case False{}:
      IO.pure(Bool, False{})

def Gs.mkdir_p.made(m: Y.Made, +d: String, rest: IO(Bool)) -> IO(Bool):
  match m:
    case Y.MadeOk{}:
      rest
    case Y.MadeFail{}:
      IO.pure(Bool, False{})
    case Y.MadeStat{}:
      do IO<Bool>:
        dir : Bool <- Gs.is_dir(d)
        Gs.then(dir, rest)

def Gs.mkdir_p.go(ds: +List<String>) -> IO(Bool):
  match ds:
    case Nil{}:
      IO.pure(Bool, True{})
    case Con{+d, t}:
      do IO<Bool>:
        +code : U32 <- Gsys.mkdir(d, 511)
        Gs.mkdir_p.made(Y.Sysop.made(code), d, Gs.mkdir_p.go(t))

# mkdir -p PATH: each directory of Y.Sysop.prefixes with mode 0777 less
# the umask, one already there kept.
def Gs.mkdir_p(path: String) -> IO(Bool):
  Gs.mkdir_p.go(Y.Sysop.prefixes(path))

# mkdir -p PATH...: every path, whatever the others answer.
def Gs.mkdirs(ps: +List<String>) -> IO(Bool):
  match ps:
    case Nil{}:
      IO.pure(Bool, True{})
    case Con{p, t}:
      do IO<Bool>:
        a : Bool <- Gs.mkdir_p(p)
        b : Bool <- Gs.mkdirs(t)
        return Bool.and(a, b)

# --- rm -f, mv -f, rmdir, umount, mount -o bind, rm -rf

# rm -f PATH...: every path, whatever the others answer (Y.Sysop.unlinked).
def Gs.unlinks(ps: +List<String>) -> IO(Bool):
  match ps:
    case Nil{}:
      IO.pure(Bool, True{})
    case Con{p, t}:
      do IO<Bool>:
        code : U32 <- Gsys.unlink(p)
        b : Bool <- Gs.unlinks(t)
        return Bool.and(Y.Sysop.unlinked(code), b)

# mv -f FROM TO for a file onto a file's name in one file system (what
# its callers move: a .tmp beside its target): rename(2).
def Gs.rename(from: String, to: String) -> IO(Bool):
  do IO<Bool>:
    code : U32 <- Gsys.rename(from, to)
    return U32.is_zero(code)

def Gs.rmdir(path: String) -> IO(Bool):
  do IO<Bool>:
    code : U32 <- Gsys.rmdir(path)
    return U32.is_zero(code)

def Gs.umount(path: String) -> IO(Bool):
  do IO<Bool>:
    code : U32 <- Gsys.umount(path, 0)
    return U32.is_zero(code)

# mount -o bind SRC DST: MS_BIND (4096).
def Gs.bind(src: String, dst: String) -> IO(Bool):
  do IO<Bool>:
    code : U32 <- Gsys.mount(src, dst, "", 4096, "")
    return U32.is_zero(code)

def Gs.res_ok(r: LFS.LayerFs.Res(Unit)) -> Bool:
  match r:
    case Fail{e}:
      False{}
    case Done{u}:
      True{}

# rm -rf PATH: the tree removed, never through a link; a path that is
# not there is removed already (LayerFs.remove_tree, on a helper thread).
def Gs.rm_rf(path: String) -> IO(Bool):
  do IO<Bool>:
    r : LFS.LayerFs.Res(Unit) <- LFS.LayerFs.remove_tree(path)
    return Gs.res_ok(r)

# --- ls

def Gs.names(xs: List<String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      Con{x, Gs.names(t)}

def Gs.ls.of(r: Result<&1, &1, U32 & String, List<String>>) -> Maybe<&2, List<&2, String>>:
  match r:
    case Fail{e}:
      None{}
    case Done{xs}:
      Some{Gs.names(xs)}

# The names in dir; None when it cannot be read.
def Gs.ls(dir: String) -> IO(Maybe<&2, List<&2, String>>):
  do IO<Maybe<&2, List<&2, String>>>:
    r : Result<&1, &1, U32 & String, List<String>> <- Gsys.ls(dir)
    return Gs.ls.of(r)

# --- A tree walked: du -sk with find -xdev | wc -l, and tar to /dev/null

# The walk's state: what is counted, the regular files to read (when
# kept), the directories still to list.
type GWalk is Data:
  GWalk{tally: Y.Tally, files: List<&2, String>, dirs: List<&2, String>}

def Gs.push(on: Bool, +x: String, xs: List<&2, String>) -> List<&2, String>:
  match on:
    case True{}:
      Con{x, xs}
    case False{}:
      xs

# One entry by its lstat: counted (Y.Sysop.tally); a regular file kept
# for the read the first time its inode is met; a directory on the
# root's device listed later (find -xdev prints a directory on another
# device and does not go into it). An entry gone since the listing is
# skipped.
def Gs.walk.put(m: Maybe<&2, Y.Stat>, +path: String, +root: Y.Stat, +keep: Bool, w: GWalk) -> GWalk:
  match m w:
    case None{} w2:
      w2
    case Some{+s} GWalk{+t, files, dirs}:
      GWalk{Y.Sysop.tally(t, s), Gs.push(keep && Y.Stat.is_file(s) && Y.Sysop.fresh(t, s), path, files),
        Gs.push(Y.Stat.is_dir(s) && Y.Stat.same_dev(s, root), path, dirs)}

def Gs.walk.names(names: List<&2, String>, +dir: String, +root: Y.Stat, +keep: Bool, w: GWalk) -> IO(GWalk):
  match names:
    case Nil{}:
      IO.pure(GWalk, w)
    case Con{n, t}:
      do IO<GWalk>:
        +p : String = dir ++ "/" ++ n
        m : Maybe<&2, Y.Stat> <- Gs.stat(p, 0)
        Gs.walk.names(t, dir, root, keep, Gs.walk.put(m, p, root, keep, w))

def Gs.walk.dir(m: Maybe<&2, List<&2, String>>, +dir: String, +root: Y.Stat, +keep: Bool, w: GWalk) -> IO(GWalk):
  match m:
    case None{}:
      IO.pure(GWalk, w)
    case Some{names}:
      Gs.walk.names(names, dir, root, keep, w)

# The directories listed one at a time (at most n) until none is left.
def Gs.walk.go(n: Nat, +root: Y.Stat, +keep: Bool, w: GWalk) -> IO(GWalk):
  match n w:
    case 0n w2:
      IO.pure(GWalk, w2)
    case 1n+p GWalk{t, files, Nil{}}:
      IO.pure(GWalk, GWalk{t, files, Nil{}})
    case 1n+p GWalk{t, files, Con{+d, ds}}:
      do IO<GWalk>:
        m : Maybe<&2, List<&2, String>> <- Gs.ls(d)
        w2 : GWalk <- Gs.walk.dir(m, d, root, keep, GWalk{t, files, ds})
        Gs.walk.go(p, root, keep, w2)

def Gs.tree.go(m: Maybe<&2, Y.Stat>, +path: String, +keep: Bool) -> IO(Maybe<&2, GWalk>):
  match m:
    case None{}:
      IO.pure(Maybe<&2, GWalk>, None{})
    case Some{+s}:
      do IO<Maybe<&2, GWalk>>:
        w : GWalk <- Gs.walk.go(U32.to_nat(4294967295), s, keep, Gs.walk.put(Some{s}, path, s, keep, GWalk{Y.Sysop.tally.new(), Nil{}, Nil{}}))
        return Some{w}

# The tree at path, walked by lstat (never through a link); None when
# path is not there.
def Gs.tree(+path: String, +keep: Bool) -> IO(Maybe<&2, GWalk>):
  do IO<Maybe<&2, GWalk>>:
    m : Maybe<&2, Y.Stat> <- Gs.stat(path, 0)
    Gs.tree.go(m, path, keep)

def Gs.usage.of(m: Maybe<&2, GWalk>) -> Maybe<&2, Y.Tally>:
  match m:
    case None{}:
      None{}
    case Some{GWalk{t, files, dirs}}:
      Some{t}

# What `du -sk PATH && find PATH -xdev | wc -l` measured: the tree's
# blocks and entries (Y.Tally.kib, Y.Tally.count).
def Gs.usage(+path: String) -> IO(Maybe<&2, Y.Tally>):
  do IO<Maybe<&2, Y.Tally>>:
    m : Maybe<&2, GWalk> <- Gs.tree(path, False{})
    return Gs.usage.of(m)

def Gs.drained(r: Result<&1, &1, U32 & String, U32 & U32>) -> Bool:
  match r:
    case Fail{e}:
      False{}
    case Done{n}:
      True{}

def Gs.drain(fs: List<&2, String>) -> IO(Bool):
  match fs:
    case Nil{}:
      IO.pure(Bool, True{})
    case Con{f, t}:
      do IO<Bool>:
        r : Result<&1, &1, U32 & String, U32 & U32> <- Gsys.drain(f)
        b : Bool <- Gs.drain(t)
        return Bool.and(Gs.drained(r), b)

def Gs.warm.go(m: Maybe<&2, GWalk>) -> IO(Bool):
  match m:
    case None{}:
      IO.pure(Bool, False{})
    case Some{GWalk{t, files, dirs}}:
      Gs.drain(files)

# What `tar -cf /dev/null -C DIR .` did for the page cache: every
# regular file under dir read once (a file with several links once).
def Gs.warm(+dir: String) -> IO(Bool):
  do IO<Bool>:
    m : Maybe<&2, GWalk> <- Gs.tree(dir, True{})
    Gs.warm.go(m)

# --- Small files

def Gs.read.close(p: File & Result<&1, &1, U32 & String, String>) -> IO(String):
  match p:
    case (f, Done{s}):
      do IO<String>:
        File.close(f)
        return s
    case (f, Fail{e}):
      do IO<String>:
        File.close(f)
        return ""

def Gs.read.go(r: Result<&1, &1, U32 & String, File>) -> IO(String):
  match r:
    case Fail{e}:
      IO.pure(String, "")
    case Done{f}:
      do IO<String>:
        p : File & Result<&1, &1, U32 & String, String> <- File.read(f, 4096)
        Gs.read.close(p)

def Gs.put.close(p: File & Result<&1, &1, U32 & String, Unit>) -> IO(Bool):
  match p:
    case (f, Done{u}):
      do IO<Bool>:
        File.close(f)
        return True{}
    case (f, Fail{e}):
      do IO<Bool>:
        File.close(f)
        return False{}

def Gs.put.go(r: Result<&1, &1, U32 & String, File>, +text: String) -> IO(Bool):
  match r:
    case Fail{e}:
      IO.pure(Bool, False{})
    case Done{f}:
      do IO<Bool>:
        p : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, text)
        Gs.put.close(p)

# text written to path, opened with mode ("w": emptied first, "a": at
# its end).
def Gs.put(path: String, mode: String, +text: String) -> IO(Bool):
  do IO<Bool>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, mode)
    Gs.put.go(r, text)

# --- hwclock -s -u

def Gs.clock.set(m: Maybe<&2, U32>) -> IO(U32):
  match m:
    case None{}:
      IO.pure(U32, 38)
    case Some{s}:
      Gsys.settime(s)

# The system time set from the RTC (Y.Sysop.rtc_file, UTC), no fraction
# of a second, as hwclock -s -u sets it: 0, or an errno (38 when the
# kernel shows no RTC time there).
def Gs.clock() -> IO(U32):
  do IO<U32>:
    r : Result<&1, &1, U32 & String, File> <- File.open(Y.Sysop.rtc_file(), "r")
    text : String <- Gs.read.go(r)
    Gs.clock.set(Y.Sysop.rtc_secs(text))

# --- fstrim -v

def Gs.fstrim.line(r: Result<&1, &1, U32 & String, U32 & U32>, +path: String) -> String:
  match r:
    case Fail{(code, m)}:
      "fstrim: FITRIM " ++ path ++ ": errno " ++ U32.show(code) ++ "\n"
    case Done{(hi, lo)}:
      Y.Sysop.trim_line(path, hi, lo)

# fstrim -v PATH with its line appended to log. The trim runs on a
# helper thread; run this in a computation of its own (IO.spawn) and
# nothing waits for it.
def Gs.fstrim(+path: String, log: String) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, U32 & U32> <- Gsys.fitrim(path)
    ok : Bool <- Gs.put(log, "a", Gs.fstrim.line(r, path))
    return Unit{}

# --- The log trim

def Gs.trim.copied(p: File & LFS.LayerFs.Res(Unit)) -> IO(Bool):
  match p:
    case (f, r):
      do IO<Bool>:
        File.close(f)
        return Gs.res_ok(r)

def Gs.trim.empty(ok: Bool, +path: String) -> IO(Unit):
  match ok:
    case True{}:
      do IO<Unit>:
        done : Bool <- Gs.put(path, "w", "")
        return Unit{}
    case False{}:
      IO.pure(Unit, Unit{})

def Gs.trim.copy(r: Result<&1, &1, U32 & String, File>, +hi: U32, +lo: U32, +path: String) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.pure(Unit, Unit{})
    case Done{f}:
      do IO<Unit>:
        gone : U32 <- Gsys.unlink(path ++ ".1")
        p : File & LFS.LayerFs.Res(Unit) <- LFS.LayerFs.copy(f, hi, lo, 0, Y.Sysop.log_keep(), path ++ ".1")
        ok : Bool <- Gs.trim.copied(p)
        Gs.trim.empty(ok, path)

def Gs.trim.cut(c: Y.Cut, +path: String) -> IO(Unit):
  match c:
    case Y.CutNone{}:
      IO.pure(Unit, Unit{})
    case Y.CutAt{+hi, +lo}:
      do IO<Unit>:
        r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
        Gs.trim.copy(r, hi, lo, path)

def Gs.trim.stat(m: Maybe<&2, Y.Stat>) -> Y.Cut:
  match m:
    case None{}:
      Y.CutNone{}
    case Some{s}:
      Y.Sysop.trim_of(s)

def Gs.trim.one(log: Bool, +path: String) -> IO(Unit):
  match log:
    case False{}:
      IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        m : Maybe<&2, Y.Stat> <- Gs.stat(path, 1)
        Gs.trim.cut(Gs.trim.stat(m), path)

def Gs.trim.names(names: List<&2, String>, +dir: String) -> IO(Unit):
  match names:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+n, t}:
      do IO<Unit>:
        Gs.trim.one(Y.Sysop.is_log(n), dir ++ "/" ++ n)
        Gs.trim.names(t, dir)

def Gs.trim.dir(m: Maybe<&2, List<&2, String>>, +dir: String) -> IO(Unit):
  match m:
    case None{}:
      IO.pure(Unit, Unit{})
    case Some{names}:
      Gs.trim.names(names, dir)

# The logs of dir trimmed (src/guest/plan.bend Plan.trim_logs): each
# regular file NAME.log past 32 MiB keeps its last 8 MiB as NAME.log.1
# (a new file in place of the old one) and is emptied in place, so a
# daemon that appends goes on at the new end. A copy that fails leaves
# the log as it is.
def Gs.trim_logs(+dir: String) -> IO(Unit):
  do IO<Unit>:
    m : Maybe<&2, List<&2, String>> <- Gs.ls(dir)
    Gs.trim.dir(m, dir)
