#!/usr/bin/env python3
"""Streams the assets disk's tree as one tar (GNU format) to OUT ('-' is
stdout), for sqfstar (scripts/guest/mksqfs.sh):
  - BIN_DIR's tree at the root: the Kubernetes binaries, which PID 1 mounts
    at /var/lib/vcluster/bin;
  - GUEST_TAR's tree under guest/ (pack.sh's guest root), when given.

Nothing is unpacked into a host directory: macOS file systems are
case-insensitive, and the Debian root has names that differ only in case
(libxt_MARK.so, libxt_mark.so). Owners become root, times 0, so the disk
is the same bytes on every build. Regular files of BIN_DIR are 0755 when
executable, else 0644; GUEST_TAR keeps its modes.

usage: disktar.py OUT BIN_DIR [GUEST_TAR]
"""
import os, sys, tarfile

if len(sys.argv) not in (3, 4): sys.exit(__doc__.rsplit("usage: ", 1)[1].strip())
out, bin_dir = sys.argv[1], sys.argv[2]
guest = sys.argv[3] if len(sys.argv) == 4 else None
f = sys.stdout.buffer if out == "-" else open(out, "wb")
t = tarfile.open(fileobj=f, mode="w|", format=tarfile.GNU_FORMAT)
dirs = set()

def info(name, kind, mode, size=0, target=""):
    m = tarfile.TarInfo(name)
    m.type, m.mode, m.size, m.linkname = kind, mode, size, target
    m.uid = m.gid = 0; m.uname = m.gname = "root"; m.mtime = 0
    return m

def mkdir(d):
    if not d or d in dirs: return
    mkdir(os.path.dirname(d))
    dirs.add(d)
    t.addfile(info(d, tarfile.DIRTYPE, 0o755))

def walk(top, rel=""):
    for n in sorted(os.listdir(os.path.join(top, rel))):
        r = os.path.join(rel, n)
        yield r
        p = os.path.join(top, r)
        if os.path.isdir(p) and not os.path.islink(p): yield from walk(top, r)

for r in walk(bin_dir):
    p = os.path.join(bin_dir, r)
    mkdir(os.path.dirname(r))
    if os.path.islink(p):
        t.addfile(info(r, tarfile.SYMTYPE, 0o777, target=os.readlink(p)))
    elif os.path.isdir(p):
        mkdir(r)
    elif os.path.isfile(p):
        with open(p, "rb") as src:
            t.addfile(info(r, tarfile.REGTYPE, 0o755 if os.access(p, os.X_OK) else 0o644, os.path.getsize(p)), src)
    else:
        sys.exit("disktar: unsupported file " + p)

if guest:
    with tarfile.open(guest) as g:
        for m in g.getmembers():
            r = "guest/" + m.name.strip("/")
            mkdir(os.path.dirname(r))
            if m.isdir():
                mkdir(r)
            elif m.issym():
                t.addfile(info(r, tarfile.SYMTYPE, 0o777, target=m.linkname))
            elif m.isfile():
                t.addfile(info(r, tarfile.REGTYPE, m.mode & 0o7777, m.size), g.extractfile(m))
            else:
                sys.exit("disktar: unsupported member " + m.name)
t.close()
f.flush()
