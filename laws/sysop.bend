import Base
import ../src/guest/sysop.bend as Y
import ../src/guest/plan.bend as P

# Proposed: the spec of src/guest/sysop.bend (docs/GOAL.md section 11,
# "Fewer shell-outs": guest hot paths stop spawning busybox). PID 1 and
# the snapshotter do themselves what they ran a busybox process for, so
# every expected value here is what that busybox applet does (busybox
# 1.37, the source file named with each group) or what the kernel's API
# says (signal(7), inode(7), sysfs-class-rtc), never this module's own
# output.

# --- Which command lines of the plans PID 1 runs itself. The plans keep
# their steps (laws/plan.bend plan.clock_sync, plan.fstrim, plan.idle_*);
# these are the argv forms of those steps, each one applet with exactly
# the options the plans pass.

# mkdir -p PATH... (coreutils/mkdir.c: every operand, parents made).
law sysop.of_mkdir:
  {Y.Sysop.of("/bin/busybox", ["mkdir", "-p", "/run/vk8s", "/var/lib/vcluster/snapshotter"]) == Y.Mkdirs{["/run/vk8s", "/var/lib/vcluster/snapshotter"]} : Y.Op}

# rm -f PATH... (coreutils/rm.c).
law sysop.of_rm:
  {Y.Sysop.of("/bin/busybox", ["rm", "-f", "/mnt/host/requests/request"]) == Y.Unlinks{["/mnt/host/requests/request"]} : Y.Op}

# hwclock -s -u (util-linux/hwclock.c: -s system time from the RTC, -u
# the RTC is in UTC): the step of plan.clock_sync.
law sysop.of_hwclock:
  {Y.Sysop.of(P.Plan.busybox(), ["hwclock", "-s", "-u"]) == Y.Clock{} : Y.Op}

# killall -STOP and -KILL (procps/kill.c; SIGSTOP is 19 and SIGKILL 9 on
# Linux arm64 and x86-64, signal(7)): the steps of plan.idle_sleep and
# plan.idle_wake.
law sysop.of_killall_stop:
  {Y.Sysop.of("/bin/busybox", ["killall", "-STOP", "kube-controller-manager"]) == Y.Signal{19, "kube-controller-manager"} : Y.Op}

law sysop.of_killall_kill:
  {Y.Sysop.of("/bin/busybox", ["killall", "-KILL", "kube-controller-manager"]) == Y.Signal{9, "kube-controller-manager"} : Y.Op}

# fstrim -v PATH (util-linux/fstrim.c): the command line of plan.fstrim.
law sysop.of_fstrim:
  {Y.Sysop.of("/bin/busybox", ["fstrim", "-v", "/var/lib/vcluster"]) == Y.Trim{"/var/lib/vcluster"} : Y.Op}

# Anything else stays a process: another program, whatever its words;
# an applet PID 1 does not do; a known applet with other options, with
# no operand, or with an operand busybox would read as an option.
law sysop.of_other_program:
  for args: +List<String>
  {Y.Sysop.of("/usr/sbin/iptables-restore", args) == Y.Exec{} : Y.Op}

law sysop.of_none:
  {Y.Sysop.of("/bin/busybox", []) == Y.Exec{} : Y.Op}

law sysop.of_exec:
  {[ Y.Sysop.of("/bin/busybox", ["sh", "-c", "echo ok > /mnt/host/ready"]),
     Y.Sysop.of("/bin/busybox", ["umount", "-a", "-r"]),
     Y.Sysop.of("/bin/busybox", ["mount", "-t", "proc", "-o", "rw", "proc", "/proc"]),
     Y.Sysop.of("/bin/busybox", ["insmod", "/lib/modules/ext4.ko"]),
     Y.Sysop.of("/bin/busybox", ["sync"]),
     Y.Sysop.of("/bin/busybox", ["mkdir", "/a"]),
     Y.Sysop.of("/bin/busybox", ["mkdir", "-p"]),
     Y.Sysop.of("/bin/busybox", ["mkdir", "-p", "-m", "700", "/a"]),
     Y.Sysop.of("/bin/busybox", ["mkdir", "-p", "/a", ""]),
     Y.Sysop.of("/bin/busybox", ["rm", "-rf", "/a"]),
     Y.Sysop.of("/bin/busybox", ["rm", "-f"]),
     Y.Sysop.of("/bin/busybox", ["hwclock", "-s"]),
     Y.Sysop.of("/bin/busybox", ["hwclock", "-w", "-u"]),
     Y.Sysop.of("/bin/busybox", ["killall", "-TERM", "kubelet"]),
     Y.Sysop.of("/bin/busybox", ["killall", "kubelet"]),
     Y.Sysop.of("/bin/busybox", ["killall", "-KILL", "-q"]),
     Y.Sysop.of("/bin/busybox", ["fstrim", "/var/lib/vcluster"]),
     Y.Sysop.of("/bin/busybox", ["fstrim", "-v", "-a"]) ]
   == [ Y.Exec{}, Y.Exec{}, Y.Exec{}, Y.Exec{}, Y.Exec{}, Y.Exec{}, Y.Exec{}, Y.Exec{}, Y.Exec{}, Y.Exec{}, Y.Exec{}, Y.Exec{},
        Y.Exec{}, Y.Exec{}, Y.Exec{}, Y.Exec{}, Y.Exec{}, Y.Exec{} ] : List<&2, Y.Op>}

# --- mkdir -p (libbb/make_directory.c bb_make_directory with
# FILEUTILS_RECUR): the path is cut before the first character after each
# run of "/", and mkdir(2) is called on each cut, then on the whole path.
law sysop.prefixes_absolute:
  {Y.Sysop.prefixes("/a/b") == ["/", "/a/", "/a/b"] : +List<String>}

law sysop.prefixes_relative:
  {Y.Sysop.prefixes("a/b/c") == ["a/", "a/b/", "a/b/c"] : +List<String>}

law sysop.prefixes_slashes:
  {Y.Sysop.prefixes("/var/lib//x/") == ["/", "/var/", "/var/lib//", "/var/lib//x/"] : +List<String>}

law sysop.prefixes_one:
  {Y.Sysop.prefixes("x") == ["x"] : +List<String>}

# A mkdir(2) that fails goes on only for EEXIST (17) or EISDIR (21), and
# then only if stat shows a directory; EACCES (13), ENOTDIR (20), EROFS
# (30) and ENOSPC (28) fail.
law sysop.made:
  {[Y.Sysop.made(0), Y.Sysop.made(17), Y.Sysop.made(21), Y.Sysop.made(13), Y.Sysop.made(20), Y.Sysop.made(30), Y.Sysop.made(28)]
   == [Y.MadeOk{}, Y.MadeStat{}, Y.MadeStat{}, Y.MadeFail{}, Y.MadeFail{}, Y.MadeFail{}, Y.MadeFail{}] : List<&2, Y.Made>}

# rm -f (libbb/remove_file.c, FILEUTILS_FORCE): ENOENT (2) is no error;
# a directory (EISDIR 21, EPERM 1), EACCES (13) and EROFS (30) are.
law sysop.unlinked:
  {[Y.Sysop.unlinked(0), Y.Sysop.unlinked(2), Y.Sysop.unlinked(21), Y.Sysop.unlinked(1), Y.Sysop.unlinked(13), Y.Sysop.unlinked(30)]
   == [True{}, True{}, False{}, False{}, False{}, False{}] : List<&2, Bool>}

# --- stat: the file type is st_mode & 0170000 (inode(7)): 040755 is a
# directory, 0100644 a regular file, 0120777 a symbolic link, 0140755 a
# socket.
law sysop.stat_words:
  {Y.Sysop.stat([16877, 2, 0, 2049, 0, 12, 0, 4096, 0, 8]) == Some{Y.Stat{16877, 2, 0, 2049, 0, 12, 0, 4096, 0, 8}} : Maybe<&2, Y.Stat>}

law sysop.stat_short:
  {Y.Sysop.stat([16877, 2, 0, 2049]) == None{} : Maybe<&2, Y.Stat>}

law sysop.kinds:
  {[ Y.Stat.is_dir(Y.Stat{16877, 2, 0, 1, 0, 2, 0, 0, 0, 0}), Y.Stat.is_file(Y.Stat{16877, 2, 0, 1, 0, 2, 0, 0, 0, 0}),
     Y.Stat.is_file(Y.Stat{33188, 1, 0, 1, 0, 3, 0, 0, 0, 0}), Y.Stat.is_dir(Y.Stat{33188, 1, 0, 1, 0, 3, 0, 0, 0, 0}),
     Y.Stat.is_link(Y.Stat{41471, 1, 0, 1, 0, 4, 0, 0, 0, 0}), Y.Stat.is_file(Y.Stat{41471, 1, 0, 1, 0, 4, 0, 0, 0, 0}),
     Y.Stat.is_file(Y.Stat{49645, 1, 0, 1, 0, 5, 0, 0, 0, 0}), Y.Stat.is_dir(Y.Stat{49645, 1, 0, 1, 0, 5, 0, 0, 0, 0}) ]
   == [True{}, False{}, True{}, False{}, True{}, False{}, False{}, False{}] : List<&2, Bool>}

# --- mountpoint -q (util-linux/mountpoint.c): lstat of DIR must show a
# directory; with stat of DIR/.., it is a mount point when the devices
# differ, or when both are the same inode (the root). The first argument
# is DIR, the second DIR/.. .
law sysop.mountpoint_plain_dir:
  {Y.Sysop.mountpoint(Y.Stat{16877, 2, 0, 2049, 0, 40, 0, 0, 0, 0}, Y.Stat{16877, 5, 0, 2049, 0, 12, 0, 0, 0, 0}) == False{} : Bool}

law sysop.mountpoint_other_device:
  {Y.Sysop.mountpoint(Y.Stat{16877, 2, 0, 1792, 0, 1, 0, 0, 0, 0}, Y.Stat{16877, 5, 0, 2049, 0, 12, 0, 0, 0, 0}) == True{} : Bool}

law sysop.mountpoint_root:
  {Y.Sysop.mountpoint(Y.Stat{16877, 20, 0, 2049, 0, 2, 0, 0, 0, 0}, Y.Stat{16877, 20, 0, 2049, 0, 2, 0, 0, 0, 0}) == True{} : Bool}

law sysop.mountpoint_not_dir:
  {Y.Sysop.mountpoint(Y.Stat{33188, 1, 0, 1792, 0, 9, 0, 0, 0, 0}, Y.Stat{16877, 5, 0, 2049, 0, 12, 0, 0, 0, 0}) == False{} : Bool}

# The high words count: device 1:2049 is not device 0:2049.
law sysop.mountpoint_high_word:
  {Y.Sysop.mountpoint(Y.Stat{16877, 2, 1, 2049, 0, 40, 0, 0, 0, 0}, Y.Stat{16877, 5, 0, 2049, 0, 12, 0, 0, 0, 0}) == True{} : Bool}

# --- du -sk DIR && find DIR -xdev | wc -l (coreutils/du.c; the
# snapshotter's Usage, laws/layers_pb.bend's measure_args). find prints
# one line per entry, the directory itself included. du sums st_blocks
# (512 bytes each) and counts an inode with more than one link once; -k
# prints the sum halved, a half rounded up (`size++; size >>= 1`).
# A directory (8 blocks), a file (16), a file with two links (8) and its
# second name: 4 entries, 32 blocks, 16 KiB.
law sysop.tally_links_once:
  {Y.Sysop.tally(Y.Sysop.tally(Y.Sysop.tally(Y.Sysop.tally(Y.Sysop.tally.new(),
      Y.Stat{16877, 2, 0, 2049, 0, 40, 0, 4096, 0, 8}),
      Y.Stat{33188, 1, 0, 2049, 0, 41, 0, 7000, 0, 16}),
      Y.Stat{33188, 2, 0, 2049, 0, 42, 0, 100, 0, 8}),
      Y.Stat{33188, 2, 0, 2049, 0, 42, 0, 100, 0, 8})
   == Y.Tally{32, 4, [Y.Ino{0, 2049, 0, 42}]} : Y.Tally}

# Two directories with two links each (their own "." entry) are two
# inodes, both counted.
law sysop.tally_dirs:
  {Y.Sysop.tally(Y.Sysop.tally(Y.Sysop.tally.new(), Y.Stat{16877, 2, 0, 2049, 0, 40, 0, 4096, 0, 8}), Y.Stat{16877, 2, 0, 2049, 0, 50, 0, 4096, 0, 8})
   == Y.Tally{16, 2, []} : Y.Tally}

# The same inode number on another device is another file.
law sysop.tally_other_device:
  {Y.Sysop.tally(Y.Sysop.tally(Y.Sysop.tally.new(), Y.Stat{33188, 2, 0, 2049, 0, 42, 0, 100, 0, 8}), Y.Stat{33188, 2, 0, 2050, 0, 42, 0, 100, 0, 8})
   == Y.Tally{16, 2, [Y.Ino{0, 2050, 0, 42}, Y.Ino{0, 2049, 0, 42}]} : Y.Tally}

law sysop.fresh:
  {[ Y.Sysop.fresh(Y.Tally{8, 1, [Y.Ino{0, 2049, 0, 42}]}, Y.Stat{33188, 2, 0, 2049, 0, 42, 0, 100, 0, 8}),
     Y.Sysop.fresh(Y.Tally{8, 1, [Y.Ino{0, 2049, 0, 42}]}, Y.Stat{33188, 2, 0, 2049, 0, 43, 0, 100, 0, 8}),
     Y.Sysop.fresh(Y.Tally{8, 1, [Y.Ino{0, 2049, 0, 42}]}, Y.Stat{33188, 1, 0, 2049, 0, 42, 0, 100, 0, 8}) ]
   == [False{}, True{}, True{}] : List<&2, Bool>}

law sysop.kib:
  {[Y.Sysop.kib(0), Y.Sysop.kib(1), Y.Sysop.kib(8), Y.Sysop.kib(17), Y.Sysop.kib(4294967295)] == [0, 1, 4, 9, 2147483648] : List<&2, U32>}

law sysop.tally_kib_count:
  {[Y.Tally.kib(Y.Tally{17, 3, []}), Y.Tally.count(Y.Tally{17, 3, []})] == [9, 3] : List<&2, U32>}

# --- The log trim (laws/plan.bend plan.trim_logs: `for f in
# logs/*.log; [ -f "$f" ]; [ $(wc -c < "$f") -gt 33554432 ]; tail -c
# 8388608 "$f" > "$f.1" && : > "$f"`). The shell's *.log matches a name
# that ends in .log and does not start with a dot.
law sysop.is_log:
  {[Y.Sysop.is_log("kubelet.log"), Y.Sysop.is_log("kube-apiserver.log"), Y.Sysop.is_log("kubelet.log.1"), Y.Sysop.is_log(".kubelet.log"),
    Y.Sysop.is_log(".log"), Y.Sysop.is_log("log"), Y.Sysop.is_log("")]
   == [True{}, True{}, False{}, False{}, False{}, False{}, False{}] : List<&2, Bool>}

# -gt 33554432: a log of exactly 32 MiB stays; one byte more keeps its
# last 8388608 bytes, which start at size - 8388608.
law sysop.trim_at:
  {[Y.Sysop.trim_at(0, 0), Y.Sysop.trim_at(0, 33554432), Y.Sysop.trim_at(0, 33554433), Y.Sysop.trim_at(0, 4294967295), Y.Sysop.trim_at(1, 0),
    Y.Sysop.trim_at(1, 8388608)]
   == [Y.CutNone{}, Y.CutNone{}, Y.CutAt{0, 25165825}, Y.CutAt{0, 4286578687}, Y.CutAt{0, 4286578688}, Y.CutAt{1, 0}] : List<&2, Y.Cut>}

# [ -f ]: only a regular file is cut (a 64 MiB one here; a directory of
# that size is not).
law sysop.trim_of:
  {[Y.Sysop.trim_of(Y.Stat{33188, 1, 0, 40, 0, 7, 0, 67108864, 0, 131072}), Y.Sysop.trim_of(Y.Stat{16877, 2, 0, 40, 0, 7, 0, 67108864, 0, 131072}),
    Y.Sysop.trim_of(Y.Stat{33188, 1, 0, 40, 0, 7, 0, 1024, 0, 8})]
   == [Y.CutAt{0, 58720256}, Y.CutNone{}, Y.CutNone{}] : List<&2, Y.Cut>}

# --- hwclock -s -u (util-linux/hwclock.c): the kernel shows the RTC's
# time as decimal seconds since 1970 and a newline in
# /sys/class/rtc/rtc0/since_epoch (Documentation/ABI/testing/sysfs-class-rtc).
law sysop.rtc_file:
  {Y.Sysop.rtc_file() == "/sys/class/rtc/rtc0/since_epoch" : String}

law sysop.rtc_secs:
  {[Y.Sysop.rtc_secs("1764108000\n"), Y.Sysop.rtc_secs("0\n"), Y.Sysop.rtc_secs(""), Y.Sysop.rtc_secs("unknown\n")]
   == [Some{1764108000}, Some{0}, None{}, None{}] : List<&2, Maybe<&2, U32>>}

# --- fstrim -v (util-linux/fstrim.c prints "%s: %llu bytes trimmed\n").
# The count is 64 bits: (0, 2416758784) is the run docs/STATUS.md
# records, (1, 0) is 2^32, and (4294967295, 4294967295) is 2^64 - 1.
law sysop.dec:
  {[Y.Sysop.dec(0, 0), Y.Sysop.dec(0, 7), Y.Sysop.dec(0, 2416758784), Y.Sysop.dec(1, 0), Y.Sysop.dec(2, 1410065408), Y.Sysop.dec(4294967295, 4294967295)]
   == ["0", "7", "2416758784", "4294967296", "10000000000", "18446744073709551615"] : List<&2, String>}

law sysop.trim_line:
  {Y.Sysop.trim_line("/var/lib/vcluster", 0, 2416758784) == "/var/lib/vcluster: 2416758784 bytes trimmed\n" : String}

# --- ls -1 (coreutils/ls.c without -a): a name that starts with a dot is
# not listed.
law sysop.listed:
  {[Y.Sysop.listed("12"), Y.Sysop.listed(".tmp"), Y.Sysop.listed(""), Y.Sysop.listed("a.b")] == [True{}, False{}, False{}, True{}] : List<&2, Bool>}
