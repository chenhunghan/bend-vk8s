#!/usr/bin/env python3
"""Make the initramfs point into the guest root on the assets disk.

For each entry of GUEST_TAR (the tree disktar.py puts under guest/ on the disk),
ROOT gets a symlink to MOUNT/<path>, the path where stage 0 mounts it:
  - in bin, sbin, usr/bin and usr/sbin, one link per file, since busybox
    installs its applets beside them (a file busybox also has wins, as it
    did when these files were in the initramfs);
  - in usr and etc, one link per child (usr/lib, usr/share, etc/ssl, ...),
    except a child ROOT already has (etc/vk8s stays in the initramfs);
  - any other top-level entry as a whole.
/lib is usr/lib, as on Debian: the glibc loader /lib/ld-linux-aarch64.so.1
and the module paths /lib/modules/<name>.ko resolve on the disk. On amd64
/lib64 is usr/lib64 the same way: the loader is /lib64/ld-linux-x86-64.so.2.

usage: links.py <guest.tar> <root> <mount>
"""
import os, sys, tarfile

tarf, root, mount = sys.argv[1], sys.argv[2], sys.argv[3].rstrip("/")
PER_FILE = {"bin", "sbin", "usr/bin", "usr/sbin"}
SPLIT = {"usr", "etc"}
links = set()
with tarfile.open(tarf) as t:
    for m in t.getmembers():
        parts = m.name.strip("/").split("/")
        if len(parts) >= 2 and "/".join(parts[:2]) in PER_FILE and len(parts) >= 3:
            links.add("/".join(parts[:3]))
        elif parts[0] in PER_FILE and len(parts) >= 2:
            links.add("/".join(parts[:2]))
        elif parts[0] in SPLIT and len(parts) >= 2 and "/".join(parts[:2]) not in PER_FILE:
            links.add("/".join(parts[:2]))
        elif parts[0] not in SPLIT and parts[0] not in PER_FILE:
            links.add(parts[0])
n = 0
for g in sorted(links):
    p = os.path.join(root, g)
    if os.path.lexists(p): continue
    os.makedirs(os.path.dirname(p), exist_ok=True)
    os.symlink(mount + "/" + g, p)
    n += 1
for d in ("lib", "lib64"):
    if "usr/" + d in links and not os.path.lexists(os.path.join(root, d)):
        os.symlink("usr/" + d, os.path.join(root, d))
print(n, "links into", mount)
