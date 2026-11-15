#!/usr/bin/env python3
"""Resolve kernel modules and their dependencies from an extracted
linux-virt tree, decompress them into KO_DIR, and write LIST: the insmod
order (dependencies first), each module as GUEST_DIR/<name>.ko, the path
the guest reads it from. With --after EARLIER, the modules EARLIER lists
(an earlier stage's list) are already loaded: they are neither copied nor
listed.

usage: modules.py <kernel-root> <ko-dir> <guest-dir> <list> [--after <earlier-list>] <module> ...
"""
import gzip, os, sys

root, kodir, gdir, listf, wanted = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5:]
loaded = set()
if wanted[:1] == ["--after"]:
    loaded = {os.path.basename(l.strip()) for l in open(wanted[1]) if l.strip()}
    wanted = wanted[2:]
kdir = os.path.join(root, "lib/modules", os.listdir(os.path.join(root, "lib/modules"))[0])
builtin = {os.path.basename(l.strip()).split(".")[0].replace("-", "_")
           for l in open(os.path.join(kdir, "modules.builtin"))}
dep, byname = {}, {}
for line in open(os.path.join(kdir, "modules.dep")):
    mod, _, rest = line.partition(":")
    dep[mod] = rest.split()
    byname[os.path.basename(mod).split(".")[0].replace("-", "_")] = mod

def ko(m):
    return os.path.basename(m)[: -len(".gz")] if m.endswith(".gz") else os.path.basename(m)

order, seen = [], {m for m in dep if ko(m) in loaded}
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

os.makedirs(kodir, exist_ok=True)
os.makedirs(os.path.dirname(listf) or ".", exist_ok=True)
for m in order:
    src = os.path.join(kdir, m)
    data = gzip.open(src).read() if m.endswith(".gz") else open(src, "rb").read()
    open(os.path.join(kodir, ko(m)), "wb").write(data)
open(listf, "w").write("".join(gdir.rstrip("/") + "/" + ko(m) + "\n" for m in order))
print(listf + ":", len(order), "modules", sum(os.path.getsize(os.path.join(kodir, ko(m))) for m in order) // 1024, "KiB")
