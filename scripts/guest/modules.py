#!/usr/bin/env python3
"""Resolve kernel modules and their dependencies from an extracted
linux-virt tree, decompress them into DEST/lib/modules, and write
DEST/etc/vk8s/modules: the insmod order (dependencies first).

usage: modules.py <kernel-root> <dest> <module> ...
"""
import gzip, os, sys

root, dest, wanted = sys.argv[1], sys.argv[2], sys.argv[3:]
kdir = os.path.join(root, "lib/modules", os.listdir(os.path.join(root, "lib/modules"))[0])
builtin = {os.path.basename(l.strip()).split(".")[0].replace("-", "_")
           for l in open(os.path.join(kdir, "modules.builtin"))}
dep, byname = {}, {}
for line in open(os.path.join(kdir, "modules.dep")):
    mod, _, rest = line.partition(":")
    dep[mod] = rest.split()
    byname[os.path.basename(mod).split(".")[0].replace("-", "_")] = mod

order, seen = [], set()
def visit(m):
    if m in seen: return
    seen.add(m)
    for d in dep[m]: visit(d)
    order.append(m)
missing = []
for w in wanted:
    k = w.replace("-", "_")
    if k in byname: visit(byname[k])
    elif k not in builtin: missing.append(w)
if missing: sys.exit("unknown modules: " + " ".join(missing))

os.makedirs(os.path.join(dest, "lib/modules"), exist_ok=True)
os.makedirs(os.path.join(dest, "etc/vk8s"), exist_ok=True)
names = []
for m in order:
    name = os.path.basename(m)[: -len(".gz")] if m.endswith(".gz") else os.path.basename(m)
    src = os.path.join(kdir, m)
    data = gzip.open(src).read() if m.endswith(".gz") else open(src, "rb").read()
    open(os.path.join(dest, "lib/modules", name), "wb").write(data)
    names.append("/lib/modules/" + name)
open(os.path.join(dest, "etc/vk8s/modules"), "w").write("\n".join(names) + "\n")
print(len(names), "modules", sum(os.path.getsize(os.path.join(dest, "lib/modules", os.path.basename(n))) for n in names) // 1024, "KiB")
