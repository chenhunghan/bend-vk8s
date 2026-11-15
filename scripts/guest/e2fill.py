#!/usr/bin/env python3
"""Write a tar's tree into an ext4 image under DEST, with debugfs.

Nothing is unpacked into a host directory under its own name: macOS file
systems are case-insensitive, and the Debian root has names that differ
only in case (libxt_MARK.so, libxt_mark.so). Each file goes through a
numbered temporary file instead. Owners become root; modes come from the
tar. Fails on any debugfs error.

usage: e2fill.py <debugfs> <image.ext4> <tree.tar> <dest>
"""
import os, subprocess, sys, tarfile, tempfile

debugfs, img, tarf, dest = sys.argv[1], sys.argv[2], sys.argv[3], "/" + sys.argv[4].strip("/")

def q(s):
    if any(c in s for c in ' \t\n"\\'): sys.exit("e2fill: unsupported path " + repr(s))
    return s

with tempfile.TemporaryDirectory() as tmp, tarfile.open(tarf) as t:
    cmds, dirs = [], set()
    def mkdir(d):
        if d in dirs or d == "/": return
        mkdir(os.path.dirname(d))
        dirs.add(d)
        cmds.append("mkdir " + q(d))
        cmds.append("sif %s uid 0" % q(d)); cmds.append("sif %s gid 0" % q(d))
    mkdir(dest)
    n = 0
    for m in t.getmembers():
        p = dest + "/" + m.name.strip("/")
        if m.isdir():
            mkdir(p); continue
        mkdir(os.path.dirname(p))
        if m.issym():
            cmds.append("symlink %s %s" % (q(p), q(m.linkname)))
        elif m.isfile():
            n += 1
            f = os.path.join(tmp, str(n))
            with open(f, "wb") as o: o.write(t.extractfile(m).read())
            # write links its name into the current directory as given
            cmds.append("cd " + q(os.path.dirname(p)))
            cmds.append("write %s %s" % (f, q(os.path.basename(p))))
            cmds.append("sif %s mode 0%o" % (q(p), 0o100000 | (m.mode & 0o7777)))
            cmds.append("sif %s uid 0" % q(p)); cmds.append("sif %s gid 0" % q(p))
        else:
            sys.exit("e2fill: unsupported member " + m.name)
    script = os.path.join(tmp, "cmds")
    open(script, "w").write("\n".join(cmds) + "\n")
    r = subprocess.run([debugfs, "-w", "-f", script, img], capture_output=True, text=True)
    errs = [l for l in r.stderr.splitlines() if l.strip() and not l.startswith("debugfs ")]
    if r.returncode != 0 or errs:
        sys.exit("e2fill: debugfs failed:\n" + "\n".join(errs[:20]))
print("e2fill:", n, "files,", len(dirs), "directories into", img + ":" + dest)
