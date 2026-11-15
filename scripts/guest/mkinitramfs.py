#!/usr/bin/env python3
"""Packs directories into a newc cpio initramfs, adding /dev/console.
Symlinks stay symlinks. An output named *.tar gets the same tree as a tar
instead (no /dev/console, no empty top-level directories): the guest root
that scripts/guest/e2fill.py writes onto the assets disk.

usage: mkinitramfs.py <out.cpio|out.tar> <dir|file.tar>... [<host-file>:<guest-path> ...]
Later directories override earlier ones. Directories become 0755; files
keep their executable bit.
"""
import io, os, sys, tarfile

ino = [1]
def entry(name, mode, data=b"", rdev=(0, 0)):
    ino[0] += 1
    hdr = "070701" + "".join("%08X" % v for v in [
        ino[0], mode, 0, 0, 1, 0, len(data), 0, 0, rdev[0], rdev[1], len(name) + 1, 0])
    out = hdr.encode() + name.encode() + b"\0"
    out += b"\0" * (-len(out) % 4)
    return out + data + b"\0" * (-len(data) % 4)

out = sys.argv[1]
files, links = {}, {}
blobs = {}   # guest path -> (bytes, executable), from tars
for arg in sys.argv[2:]:
    if arg.endswith(".tar"):
        with tarfile.open(arg) as t:
            for m in t.getmembers():
                if m.issym():
                    links[m.name] = m.linkname; files.pop(m.name, None); blobs.pop(m.name, None)
                elif m.isfile():
                    blobs[m.name] = (t.extractfile(m).read(), bool(m.mode & 0o111)); links.pop(m.name, None)
        continue
    if ":" in arg:
        host, guest = arg.split(":", 1)
        files[guest.lstrip("/")] = host
        continue
    for d, dirnames, names in os.walk(arg):
        for n in names + [x for x in dirnames if os.path.islink(os.path.join(d, x))]:
            p = os.path.join(d, n)
            g = os.path.relpath(p, arg)
            if os.path.islink(p):
                links[g] = os.readlink(p); files.pop(g, None)
            else:
                files[g] = p; links.pop(g, None)
as_tar = out.endswith(".tar")
dirs = set() if as_tar else {"dev", "proc", "sys", "tmp", "bin", "mnt"}
for g in list(files) + list(links) + list(blobs):
    parts = g.split("/")[:-1]
    for i in range(1, len(parts) + 1):
        dirs.add("/".join(parts[:i]))
dirs -= set(links)
if as_tar:
    t = tarfile.open(out, "w", format=tarfile.GNU_FORMAT)
    def add(name, kind, mode, data=b"", target=""):
        m = tarfile.TarInfo(name); m.type = kind; m.mode = mode; m.size = len(data); m.linkname = target
        t.addfile(m, io.BytesIO(data) if data else None)
    for d in sorted(dirs): add(d, tarfile.DIRTYPE, 0o755)
    for g in sorted(links): add(g, tarfile.SYMTYPE, 0o777, target=links[g])
    for g in sorted(blobs):
        if g in files: continue
        data, x = blobs[g]
        add(g, tarfile.REGTYPE, 0o755 if x else 0o644, data)
    for g in sorted(files):
        add(g, tarfile.REGTYPE, 0o755 if os.access(files[g], os.X_OK) or g == "sbin/vk8s-init" else 0o644,
            open(files[g], "rb").read())
    t.close()
    sys.exit(0)
blob = b"".join(entry(d, 0o040755) for d in sorted(dirs))
blob += entry("dev/console", 0o020600, rdev=(5, 1))
for g in sorted(links):
    blob += entry(g, 0o120777, links[g].encode())
for g in sorted(blobs):
    if g in files: continue
    data, x = blobs[g]
    blob += entry(g, 0o100755 if x else 0o100644, data)
for g in sorted(files):
    data = open(files[g], "rb").read()
    mode = 0o100755 if os.access(files[g], os.X_OK) or g in ("init", "sbin/vk8s-init") else 0o100644
    blob += entry(g, mode, data)
blob += entry("TRAILER!!!", 0)
blob += b"\0" * (-len(blob) % 512)
open(out, "wb").write(blob)
