#!/usr/bin/env python3
"""Copy a kernel tree (scripts/guest/kernel.sh's output) to OUT with only
the modules that MODULE... resolve to through modules.dep, at the same
paths. Image, config, build-time and the module index files
(lib/modules/<v>/modules.*) come along, and SHA256SUMS keeps only the
lines of the files OUT holds. CI uploads OUT as the kernel16k artifact:
the full tree has modules whose names differ only in case (xt_dscp.ko and
xt_DSCP.ko), which macOS's case-insensitive APFS cannot unpack side by
side. scripts/guest/build.sh and pack.sh read OUT as they read the full
tree.

usage: kernel-slim.py <kernel-root> <out> <module> ...
"""
import os, shutil, sys

root, out, wanted = sys.argv[1], sys.argv[2], sys.argv[3:]
ver = os.listdir(os.path.join(root, "lib/modules"))[0]
kdir = os.path.join(root, "lib/modules", ver)
odir = os.path.join(out, "lib/modules", ver)
builtin = {os.path.basename(l.strip()).split(".")[0].replace("-", "_")
           for l in open(os.path.join(kdir, "modules.builtin"))}
dep, byname = {}, {}
for line in open(os.path.join(kdir, "modules.dep")):
    mod, _, rest = line.partition(":")
    dep[mod] = rest.split()
    byname[os.path.basename(mod).split(".")[0].replace("-", "_")] = mod

keep = set()
def visit(m):
    if m in keep: return
    keep.add(m)
    for d in dep[m]: visit(d)
missing = []
for w in wanted:
    k = w.replace("-", "_")
    if k in byname: visit(byname[k])
    elif k not in builtin: missing.append(w)
if missing: sys.exit("unknown modules: " + " ".join(missing))

if os.path.exists(out): shutil.rmtree(out)
os.makedirs(odir)
for f in ("Image", "config", "build-time"):
    if os.path.exists(os.path.join(root, f)):
        shutil.copy2(os.path.join(root, f), os.path.join(out, f))
for f in os.listdir(kdir):
    if f.startswith("modules.") and os.path.isfile(os.path.join(kdir, f)):
        shutil.copy2(os.path.join(kdir, f), os.path.join(odir, f))
for m in sorted(keep):
    os.makedirs(os.path.dirname(os.path.join(odir, m)), exist_ok=True)
    shutil.copy2(os.path.join(kdir, m), os.path.join(odir, m))
sums = os.path.join(root, "SHA256SUMS")
if os.path.exists(sums):
    with open(os.path.join(out, "SHA256SUMS"), "w") as o:
        for line in open(sums):
            name = line.split(None, 1)[1].strip().lstrip("*")
            if os.path.isfile(os.path.join(out, name)): o.write(line)

names = [os.path.relpath(os.path.join(d, n), out) for d, ds, fs in os.walk(out) for n in ds + fs]
seen, clash = {}, []
for n in names:
    if n.lower() in seen: clash.append(seen[n.lower()] + " " + n)
    seen[n.lower()] = n
if clash: sys.exit("names that differ only in case: " + ", ".join(clash))
print(out + ":", len(keep), "of", len(dep), "modules")
