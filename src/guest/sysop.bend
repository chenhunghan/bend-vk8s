import Base

# What the guest does itself where it ran a busybox process (docs/GOAL.md
# section 11, "Fewer shell-outs": guest hot paths stop spawning busybox).
# PID 1 (host/init.bend) and the node's snapshotter (host/snapshotter.bend)
# make the system calls through host/gsys.bend; every decision is here:
# which busybox command lines of the plans PID 1 runs itself (Sysop.of;
# the plans and their laws keep the command lines), which directories
# `mkdir -p` makes, what an errno means, what a stat says, what `du -sk`
# and `find | wc -l` count, which logs the trim cuts, and the line
# `fstrim -v` prints. Each def follows busybox 1.37 (the applet's source
# is named beside it) or the kernel's API.

# --- busybox command lines PID 1 runs itself

type Op is Data:
  # mkdir -p PATH...
  Mkdirs{paths: +List<String>}
  # rm -f PATH...
  Unlinks{paths: +List<String>}
  # hwclock -s -u: the system time from the RTC, kept in UTC
  Clock{}
  # killall -SIG NAME
  Signal{sig: U32, name: String}
  # fstrim -v PATH
  Trim{path: String}
  # anything else: the process, as before
  Exec{}

def Sysop.busybox() -> String:
  "/bin/busybox"

# A word that is a path or a name for certain: not empty, and no option
# (busybox reads a leading "-" as one).
def Sysop.plain.go(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{c, t}:
      Bool.not(Char.is_eq(c, '-'))

def Sysop.plain(+s: String) -> Bool:
  Sysop.plain.go(s)

def Sysop.all_plain(ws: +List<String>) -> Bool:
  match ws:
    case Nil{}:
      True{}
    case Con{+w, t}:
      Bool.and(Sysop.plain(w), Sysop.all_plain(t))

def Sysop.some_plain(+ws: +List<String>) -> Bool:
  Bool.and(Bool.not(List.is_empty(&2, String, ws)), Sysop.all_plain(ws))

def Sysop.paths.go(ok: Bool, +op: Op) -> Op:
  match ok:
    case True{}:
      op
    case False{}:
      Exec{}

# killall's signal option: the two the plans send, by Linux's numbers on
# arm64 and x86-64 (SIGKILL 9, SIGSTOP 19; signal(7)).
def Sysop.signal.go(stop: Bool, kill: Bool) -> Maybe<&2, U32>:
  match stop kill:
    case True{} _:
      Some{19}
    case False{} True{}:
      Some{9}
    case False{} False{}:
      None{}

def Sysop.signal(+opt: String) -> Maybe<&2, U32>:
  Sysop.signal.go(String.eq(opt, "-STOP"), String.eq(opt, "-KILL"))

def Sysop.killall.go(m: Maybe<&2, U32>, +name: String) -> Op:
  match m:
    case Some{+sig}:
      Sysop.paths.go(Sysop.plain(name), Signal{sig, name})
    case None{}:
      Exec{}

def Sysop.killall(rest: +List<String>) -> Op:
  match rest:
    case Con{+opt, Con{+name, Nil{}}}:
      Sysop.killall.go(Sysop.signal(opt), name)
    case _:
      Exec{}

def Sysop.hwclock(rest: +List<String>) -> Op:
  match rest:
    case Con{+a, Con{+b, Nil{}}}:
      Sysop.paths.go(Bool.and(String.eq(a, "-s"), String.eq(b, "-u")), Clock{})
    case _:
      Exec{}

def Sysop.fstrim(rest: +List<String>) -> Op:
  match rest:
    case Con{+a, Con{+p, Nil{}}}:
      Sysop.paths.go(Bool.and(String.eq(a, "-v"), Sysop.plain(p)), Trim{p})
    case _:
      Exec{}

def Sysop.mkdir(rest: +List<String>) -> Op:
  match rest:
    case Con{+a, +ps}:
      Sysop.paths.go(Bool.and(String.eq(a, "-p"), Sysop.some_plain(ps)), Mkdirs{ps})
    case _:
      Exec{}

def Sysop.rm(rest: +List<String>) -> Op:
  match rest:
    case Con{+a, +ps}:
      Sysop.paths.go(Bool.and(String.eq(a, "-f"), Sysop.some_plain(ps)), Unlinks{ps})
    case _:
      Exec{}

def Sysop.applet(mkdir: Bool, rm: Bool, hwclock: Bool, killall: Bool, fstrim: Bool, +rest: +List<String>) -> Op:
  match mkdir rm hwclock killall fstrim:
    case True{} _ _ _ _:
      Sysop.mkdir(rest)
    case False{} True{} _ _ _:
      Sysop.rm(rest)
    case False{} False{} True{} _ _:
      Sysop.hwclock(rest)
    case False{} False{} False{} True{} _:
      Sysop.killall(rest)
    case False{} False{} False{} False{} True{}:
      Sysop.fstrim(rest)
    case False{} False{} False{} False{} False{}:
      Exec{}

def Sysop.of.args(args: +List<String>) -> Op:
  match args:
    case Nil{}:
      Exec{}
    case Con{+a, +rest}:
      Sysop.applet(String.eq(a, "mkdir"), String.eq(a, "rm"), String.eq(a, "hwclock"), String.eq(a, "killall"), String.eq(a, "fstrim"), rest)

def Sysop.of.go(bb: Bool, +args: +List<String>) -> Op:
  match bb:
    case True{}:
      Sysop.of.args(args)
    case False{}:
      Exec{}

# What PID 1 does for the command line prog args: one of its own
# operations when prog is the guest's busybox and the words are exactly a
# form it knows (an option it does not know, an empty word or a word that
# starts with "-" leaves the process); Exec for everything else.
def Sysop.of(+prog: String, +args: +List<String>) -> Op:
  Sysop.of.go(String.eq(prog, Sysop.busybox()), args)

# --- mkdir -p (busybox libbb/make_directory.c, bb_make_directory with
# FILEUTILS_RECUR)

# busybox cuts the path before the first character after each run of "/"
# and calls mkdir(2) on every cut, then on the whole path: for "/a/b" it
# makes "/", "/a/" and "/a/b". acc is the path read so far, reversed.
def Sysop.prefixes.cut(cut: Bool, +acc: String, rest: +List<String>) -> +List<String>:
  match cut:
    case True{}:
      Con{String.reverse(acc), rest}
    case False{}:
      rest

def Sysop.prefixes.go(s: String, +acc: String, +slash: Bool) -> +List<String>:
  match s:
    case SNil{}:
      [String.reverse(acc)]
    case SCon{+c, t}:
      +sl : Bool = Char.is_eq(c, '/')
      Sysop.prefixes.cut(Bool.and(slash, Bool.not(sl)), acc, Sysop.prefixes.go(t, SCon{c, acc}, sl))

def Sysop.prefixes(path: String) -> +List<String>:
  Sysop.prefixes.go(path, SNil{}, False{})

# One mkdir(2) of mkdir -p: done when it made the directory (0); when it
# answers EEXIST (17) or EISDIR (21), busybox stats the path (through a
# link) and goes on if a directory is there; any other errno fails.
type Made is Data:
  MadeOk{}
  MadeStat{}
  MadeFail{}

def Sysop.made.go(zero: Bool, exists: Bool) -> Made:
  match zero exists:
    case True{} _:
      MadeOk{}
    case False{} True{}:
      MadeStat{}
    case False{} False{}:
      MadeFail{}

def Sysop.made(+code: U32) -> Made:
  Sysop.made.go(U32.is_zero(code), Bool.or(U32.is_eq(code, 17), U32.is_eq(code, 21)))

# rm -f (busybox libbb/remove_file.c with FILEUTILS_FORCE): a path that is
# not there (ENOENT, 2) is no error; a directory (unlink's EISDIR, or
# EPERM) or anything else is.
def Sysop.unlinked(+code: U32) -> Bool:
  Bool.or(U32.is_zero(code), U32.is_eq(code, 2))

# --- stat (host/gsys.bend Gsys.stat: ten words)

type Stat is Data:
  Stat{mode: U32, nlink: U32, dev_hi: U32, dev_lo: U32, ino_hi: U32, ino_lo: U32, size_hi: U32, size_lo: U32, blocks_hi: U32, blocks_lo: U32}

def Sysop.stat(ws: List<U32>) -> Maybe<&2, Stat>:
  match ws:
    case Con{m, Con{n, Con{dh, Con{dl, Con{ih, Con{il, Con{sh, Con{sl, Con{bh, Con{bl, Nil{}}}}}}}}}}}:
      Some{Stat{m, n, dh, dl, ih, il, sh, sl, bh, bl}}
    case _:
      None{}

def Stat.mode(s: Stat) -> U32:
  match s:
    case Stat{m, n, dh, dl, ih, il, sh, sl, bh, bl}:
      m

# The file type bits of st_mode (S_IFMT, 0170000): S_IFDIR 0040000,
# S_IFREG 0100000, S_IFLNK 0120000 (inode(7)).
def Sysop.fmt(+mode: U32) -> U32:
  (mode .&. 61440 : U32)

def Stat.is_dir(s: Stat) -> Bool:
  U32.is_eq(Sysop.fmt(Stat.mode(s)), 16384)

def Stat.is_file(s: Stat) -> Bool:
  U32.is_eq(Sysop.fmt(Stat.mode(s)), 32768)

def Stat.is_link(s: Stat) -> Bool:
  U32.is_eq(Sysop.fmt(Stat.mode(s)), 40960)

def Stat.same_dev(a: Stat, b: Stat) -> Bool:
  match a b:
    case Stat{m, n, dh, dl, ih, il, sh, sl, bh, bl} Stat{m2, n2, dh2, dl2, ih2, il2, sh2, sl2, bh2, bl2}:
      Bool.and(U32.is_eq(dh, dh2), U32.is_eq(dl, dl2))

def Stat.same_ino(a: Stat, b: Stat) -> Bool:
  match a b:
    case Stat{m, n, dh, dl, ih, il, sh, sl, bh, bl} Stat{m2, n2, dh2, dl2, ih2, il2, sh2, sl2, bh2, bl2}:
      Bool.and(U32.is_eq(ih, ih2), U32.is_eq(il, il2))

# mountpoint -q DIR (busybox util-linux/mountpoint.c): DIR, by lstat, is a
# directory, and DIR/.. (by stat) is on another device or is the same
# inode (the root). here: lstat of DIR; up: stat of DIR/.. .
def Sysop.mountpoint(+here: Stat, +up: Stat) -> Bool:
  Bool.and(Stat.is_dir(here), Bool.or(Bool.not(Stat.same_dev(here, up)), Stat.same_ino(here, up)))

# --- du -sk DIR && find DIR -xdev | wc -l (the snapshotter's Usage;
# busybox coreutils/du.c)

# A file's device and inode.
type Inode is Data:
  Ino{dev_hi: U32, dev_lo: U32, ino_hi: U32, ino_lo: U32}

# What a walk of a tree has counted: 512-byte blocks, entries, and the
# key of each file with more than one link, whose blocks du counts once.
type Tally is Data:
  Tally{blocks: U32, count: U32, seen: List<&2, Inode>}

def Sysop.tally.new() -> Tally:
  Tally{0, 0, Nil{}}

def Sysop.seen.hit(a: Inode, b: Inode) -> Bool:
  match a b:
    case Ino{a1, a2, a3, a4} Ino{b1, b2, b3, b4}:
      Bool.and(Bool.and(U32.is_eq(a1, b1), U32.is_eq(a2, b2)), Bool.and(U32.is_eq(a3, b3), U32.is_eq(a4, b4)))

def Sysop.seen(xs: List<&2, Inode>, +k: Inode) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{x, t}:
      Bool.or(Sysop.seen.hit(x, k), Sysop.seen(t, k))

def Sysop.tally.add(linked: Bool, dup: Bool, +b: U32, +c: U32, +seen: List<&2, Inode>, +k: Inode, +blocks: U32) -> Tally:
  match linked dup:
    case False{} _:
      Tally{(b + blocks : U32), (c + 1 : U32), seen}
    case True{} False{}:
      Tally{(b + blocks : U32), (c + 1 : U32), Con{k, seen}}
    case True{} True{}:
      Tally{b, (c + 1 : U32), seen}

# One entry of the walk (its lstat): find counts it; du adds its blocks,
# but those of a file with more than one link only the first time its
# (device, inode) is met. A directory is walked once, so only other
# entries are remembered.
def Sysop.tally(t: Tally, s: Stat) -> Tally:
  match t s:
    case Tally{+b, +c, +seen} Stat{+m, +n, +dh, +dl, +ih, +il, sh, sl, bh, +bl}:
      +linked : Bool = Bool.and(U32.is_gt(n, 1), Bool.not(U32.is_eq(Sysop.fmt(m), 16384)))
      Sysop.tally.add(linked, Bool.and(linked, Sysop.seen(seen, Ino{dh, dl, ih, il})), b, c, seen, Ino{dh, dl, ih, il}, bl)

# Whether du counts s's blocks after t: not a file with more than one
# link whose inode t has met.
def Sysop.fresh(t: Tally, s: Stat) -> Bool:
  match t s:
    case Tally{b, c, seen} Stat{+m, +n, +dh, +dl, +ih, +il, sh, sl, bh, bl}:
      Bool.not(Bool.and(Bool.and(U32.is_gt(n, 1), Bool.not(U32.is_eq(Sysop.fmt(m), 16384))), Sysop.seen(seen, Ino{dh, dl, ih, il})))

def Tally.count(t: Tally) -> U32:
  match t:
    case Tally{b, c, s}:
      c

# du -k prints a tree's 512-byte blocks in KiB, a half rounded up
# (du.c print: `size++; size >>= 1`).
def Sysop.kib(+blocks: U32) -> U32:
  ((blocks / 2 : U32) + (blocks % 2 : U32) : U32)

def Tally.kib(t: Tally) -> U32:
  match t:
    case Tally{b, c, s}:
      Sysop.kib(b)

# --- The log trim (src/guest/plan.bend Plan.trim_logs: `for f in
# logs/*.log; [ -f "$f" ]; [ $(wc -c < "$f") -gt 33554432 ]; tail -c
# 8388608 "$f" > "$f.1" && : > "$f"`)

# The shell's *.log: a name that ends in .log and does not start with a
# dot.
def Sysop.is_log.go(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{c, t}:
      Bool.not(Char.is_eq(c, '.'))

def Sysop.is_log(+name: String) -> Bool:
  Bool.and(Sysop.is_log.go(name), String.ends_with(name, ".log"))

def Sysop.log_max() -> U32:
  33554432

def Sysop.log_keep() -> U32:
  8388608

# Where a trim cuts a log: nowhere, or at (hi, lo) bytes.
type Cut is Data:
  CutNone{}
  CutAt{hi: U32, lo: U32}

def Sysop.trim_at.go(big: Bool, +hi: U32, +lo: U32) -> Cut:
  match big:
    case False{}:
      CutNone{}
    case True{}:
      CutAt{(hi - Bool.pick(U32, U32.is_lt(lo, Sysop.log_keep()), 1, 0) : U32), (lo - Sysop.log_keep() : U32)}

# A log of size (hi, lo) bytes: past 32 MiB, where its last 8 MiB start
# (the range `tail -c 8388608` keeps); else nothing is cut.
def Sysop.trim_at(+hi: U32, +lo: U32) -> Cut:
  Sysop.trim_at.go(Bool.or(Bool.not(U32.is_zero(hi)), U32.is_gt(lo, Sysop.log_max())), hi, lo)

# The trim of what a log's stat (through a link, as the shell's `[ -f ]`)
# shows: only a regular file is cut.
def Sysop.trim_of.go(file: Bool, +hi: U32, +lo: U32) -> Cut:
  match file:
    case True{}:
      Sysop.trim_at(hi, lo)
    case False{}:
      CutNone{}

def Sysop.trim_of(s: Stat) -> Cut:
  match s:
    case Stat{+m, n, dh, dl, ih, il, +sh, +sl, bh, bl}:
      Sysop.trim_of.go(U32.is_eq(Sysop.fmt(m), 32768), sh, sl)

# --- hwclock -s -u (busybox util-linux/hwclock.c to_sys_clock: the RTC's
# time, read as UTC, becomes the system time with no fraction of a
# second). The kernel gives the RTC's time in seconds since 1970 in
# /sys/class/rtc/rtc0/since_epoch (Documentation/ABI/testing/sysfs-class-rtc).

def Sysop.rtc_file() -> String:
  "/sys/class/rtc/rtc0/since_epoch"

def Sysop.rtc_secs(text: String) -> Maybe<&2, U32>:
  U32.read(String.trim(text))

# --- fstrim -v (busybox util-linux/fstrim.c: "%s: %llu bytes trimmed\n")

# (hi, lo) divided by ten, by 16-bit steps: the quotient's halves and the
# remainder.
def Sysop.div10.a(+hi: U32, +lo: U32) -> U32:
  (((hi % 10 : U32) * 65536 : U32) + (lo / 65536 : U32) : U32)

def Sysop.div10.b(+hi: U32, +lo: U32) -> U32:
  (((Sysop.div10.a(hi, lo) % 10 : U32) * 65536 : U32) + (lo % 65536 : U32) : U32)

def Sysop.div10.hi(+hi: U32) -> U32:
  (hi / 10 : U32)

def Sysop.div10.lo(+hi: U32, +lo: U32) -> U32:
  (((Sysop.div10.a(hi, lo) / 10 : U32) * 65536 : U32) + (Sysop.div10.b(hi, lo) / 10 : U32) : U32)

def Sysop.div10.rem(+hi: U32, +lo: U32) -> U32:
  (Sysop.div10.b(hi, lo) % 10 : U32)

def Sysop.dec.digit(zero: Bool, +r: U32, rest: String) -> String:
  match zero:
    case True{}:
      SNil{}
    case False{}:
      SCon{Char.from_u32((48 + r : U32)), rest}

# The digits of (hi, lo), the last first (at most n).
def Sysop.dec.go(n: Nat, +hi: U32, +lo: U32) -> String:
  match n:
    case 0n:
      SNil{}
    case 1n+p:
      Sysop.dec.digit(Bool.and(U32.is_zero(hi), U32.is_zero(lo)), Sysop.div10.rem(hi, lo), Sysop.dec.go(p, Sysop.div10.hi(hi), Sysop.div10.lo(hi, lo)))

def Sysop.dec.zero(empty: Bool, +s: String) -> String:
  match empty:
    case True{}:
      "0"
    case False{}:
      s

# The 64-bit number (hi, lo) in decimal.
def Sysop.dec(+hi: U32, +lo: U32) -> String:
  +s : String = String.reverse(Sysop.dec.go(20n, hi, lo))
  Sysop.dec.zero(String.is_empty(s), s)

def Sysop.trim_line(+path: String, +hi: U32, +lo: U32) -> String:
  path ++ ": " ++ Sysop.dec(hi, lo) ++ " bytes trimmed\n"

# --- ls -1 DIR (busybox coreutils/ls.c without -a or -A): a name that
# starts with a dot is not listed.
def Sysop.listed.go(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{c, t}:
      Bool.not(Char.is_eq(c, '.'))

def Sysop.listed(name: String) -> Bool:
  Sysop.listed.go(name)
