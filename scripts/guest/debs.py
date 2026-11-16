#!/usr/bin/env python3
"""Fetch Debian packages for one arch (DEB_ARCH: arm64, the default, or
amd64; no dependency resolution: name every package) and merge their
files into one tar, DEST. Nothing is unpacked on
the host: macOS file systems are case-insensitive, and Debian ships names
that differ only in case (libxt_MARK.so, libxt_mark.so).

usage: debs.py <dest.tar> <package> ...      (DEBIAN_SUITE, default trixie; DEB_ARCH)
"""
import io, lzma, os, sys, tarfile, urllib.request, gzip

MIRROR = os.environ.get("DEBIAN_MIRROR", "https://deb.debian.org/debian")
SUITE = os.environ.get("DEBIAN_SUITE", "trixie")
CACHE = os.environ.get("DEB_CACHE", "out/build/debs")
ARCH = os.environ.get("DEB_ARCH", "arm64")
TRIPLET = {"arm64": "aarch64-linux-gnu", "amd64": "x86_64-linux-gnu"}[ARCH]
dest, names = sys.argv[1], sys.argv[2:]
os.makedirs(CACHE, exist_ok=True)

def fetch(url, path):
    if not os.path.exists(path):
        with urllib.request.urlopen(url) as r, open(path + ".part", "wb") as f:
            f.write(r.read())
        os.rename(path + ".part", path)
    return open(path, "rb").read()

# arm64 keeps the index name it had before amd64 (an existing cache stays valid)
idx_name = f"Packages-{SUITE}.gz" if ARCH == "arm64" else f"Packages-{SUITE}-{ARCH}.gz"
idx = fetch(f"{MIRROR}/dists/{SUITE}/main/binary-{ARCH}/Packages.gz", f"{CACHE}/{idx_name}")
pkgs = {}
for stanza in gzip.decompress(idx).decode().split("\n\n"):
    f = dict(l.split(": ", 1) for l in stanza.splitlines() if ": " in l and not l.startswith(" "))
    if "Package" in f: pkgs[f["Package"]] = f["Filename"]

def ar_members(data):
    assert data[:8] == b"!<arch>\n"
    i = 8
    while i < len(data):
        name = data[i:i+16].decode().strip().rstrip("/")
        size = int(data[i+48:i+58].decode().strip())
        yield name, data[i+60:i+60+size]
        i += 60 + size + (size & 1)

outt = tarfile.open(dest, "w")
seen = set()
for n in names:
    if n not in pkgs: sys.exit(f"no package {n} in {SUITE}")
    deb = fetch(f"{MIRROR}/{pkgs[n]}", f"{CACHE}/{os.path.basename(pkgs[n])}")
    for name, body in ar_members(deb):
        if name.startswith("data.tar"):
            mode = "r:xz" if name.endswith(".xz") else ("r:zst" if name.endswith(".zst") else "r:*")
            with tarfile.open(fileobj=io.BytesIO(body), mode=mode) as t:
                for m in t.getmembers():
                    name = m.name.lstrip("./")
                    if not name or name in seen: continue
                    if any(name.startswith(x) for x in ("usr/share/doc", "usr/share/man", "usr/share/locale",
                                                       "usr/share/i18n", f"usr/lib/{TRIPLET}/gconv")): continue
                    seen.add(name); m.name = name
                    outt.addfile(m, t.extractfile(m) if m.isfile() else None)
    print("unpacked", n)
outt.close()
