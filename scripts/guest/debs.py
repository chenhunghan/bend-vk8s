#!/usr/bin/env python3
"""Fetch Debian packages for one arch (DEB_ARCH: arm64, the default, or
amd64; no dependency resolution: name every package) and merge their
files into one tar, DEST. Nothing is unpacked on
the host: macOS file systems are case-insensitive, and Debian ships names
that differ only in case (libxt_MARK.so, libxt_mark.so).

Every package is pinned (docs/ref/review-bend-vk8s-pr-48.md #2): LOCK
(scripts/guest/debs.lock) names its version, pool file and SHA-256, and a
.deb whose SHA-256 differs is refused, also from the cache. The pool file
comes from DEBIAN_MIRROR, else (a point release removed it) from our
mirror release (VK8S_INPUTS_MIRROR, the INPUTS_MIRROR of pins.sh; the file
is there as mirror_name says, scripts/guest/mirror-inputs.sh uploads it),
else from snapshot.debian.org, which keeps every file Debian published.
The next source is tried only when one does not answer: a source that
answers with other bytes fails the build (a finding, not an outage). So a
build always gets the same bytes.

--lock writes LOCK anew from the signed index of DEBIAN_SUITE: InRelease,
checked by gpgv against DEBIAN_KEYRING (Debian's archive keyring), gives
the SHA-256 of each arch's Packages.xz, and that index gives the SHA-256
of each package. Run it to move to newer packages, and review the diff.

--fetch only downloads the named packages of DEB_ARCH into DEB_CACHE.
--pins prints "<arch> <package> <pool file name> <mirror name> <sha256>"
for every line of LOCK and fetches nothing (mirror-inputs.sh reads it).

usage: debs.py <dest.tar> <package> ...      (DEB_ARCH; LOCK)
       debs.py --lock <package> ...           (DEBIAN_SUITE, default trixie)
       debs.py --fetch <package> ...          (DEB_ARCH; LOCK; DEB_CACHE)
       debs.py --pins                         (LOCK)
"""
import hashlib, io, json, lzma, os, re, subprocess, sys, tarfile, tempfile, urllib.request

MIRROR = os.environ.get("DEBIAN_MIRROR", "https://deb.debian.org/debian")
SNAPSHOT = os.environ.get("DEBIAN_SNAPSHOT", "https://snapshot.debian.org")
# the default is pins.sh's INPUTS_MIRROR (build.sh passes that one)
INPUTS = os.environ.get("VK8S_INPUTS_MIRROR", "https://github.com/chenhunghan/bend-vk8s/releases/download/guest-inputs")
SUITE = os.environ.get("DEBIAN_SUITE", "trixie")
CACHE = os.environ.get("DEB_CACHE", "out/build/debs")
ARCH = os.environ.get("DEB_ARCH", "arm64")
LOCK = os.environ.get("LOCK", os.path.join(os.path.dirname(os.path.abspath(__file__)), "debs.lock"))
KEYRING = os.environ.get("DEBIAN_KEYRING", "/usr/share/keyrings/debian-archive-keyring.gpg")
ARCHES = ("arm64", "amd64")

def get(url):
    with urllib.request.urlopen(url, timeout=120) as r:
        return r.read()

def sha256(b):
    return hashlib.sha256(b).hexdigest()

def stanzas(text):
    for stanza in text.split("\n\n"):
        f = dict(l.split(": ", 1) for l in stanza.splitlines() if ": " in l and not l.startswith(" "))
        if "Package" in f: yield f

def lock():
    """Write LOCK from the gpgv-verified InRelease and its Packages.xz."""
    names = sys.argv[2:]
    if not names: sys.exit("debs.py --lock: name the packages")
    rel = get(f"{MIRROR}/dists/{SUITE}/InRelease")
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "InRelease")
        open(p, "wb").write(rel)
        out = os.path.join(d, "Release")
        # gpgv writes the signed text only when a good signature from the
        # keyring covers it
        subprocess.run(["gpgv", "--keyring", KEYRING, "--output", out, p], check=True)
        signed = open(out).read()
    sums, section = {}, False
    for l in signed.splitlines():
        if not l.startswith(" "): section = l == "SHA256:"; continue
        if section:
            s, _, n = l.split()
            sums[n] = s
    lines = [f"# scripts/guest/debs.py --lock {' '.join(names)}",
             f"# {SUITE}, InRelease of {MIRROR} checked by gpgv against {os.path.basename(KEYRING)}",
             "# arch package version pool-file sha256"]
    for arch in ARCHES:
        n = f"main/binary-{arch}/Packages.xz"
        idx = get(f"{MIRROR}/dists/{SUITE}/{n}")
        if sha256(idx) != sums.get(n): sys.exit(f"{n}: SHA-256 differs from the signed InRelease")
        pkgs = {f["Package"]: f for f in stanzas(lzma.decompress(idx).decode())}
        for name in names:
            if name not in pkgs: sys.exit(f"no package {name} in {SUITE} {arch}")
            f = pkgs[name]
            lines.append(f"{arch} {name} {f['Version']} {f['Filename']} {f['SHA256']}")
    open(LOCK, "w").write("\n".join(lines) + "\n")
    print("wrote", LOCK)

def lock_lines():
    """LOCK's entries: (arch, package, version, pool file, sha256)."""
    for l in open(LOCK):
        w = l.split()
        if not w or w[0].startswith("#"): continue
        if len(w) != 5 or len(w[4]) != 64: sys.exit(f"{LOCK}: bad line: {l.strip()}")
        yield w

def pins():
    """LOCK's entries of ARCH: package -> (version, pool file, sha256)."""
    return {w[1]: (w[2], w[3], w[4]) for w in lock_lines() if w[0] == ARCH}

def mirror_name(pool):
    """The pool file's name in our mirror release: deb-<its file name>,
    which says the package, the version and the arch, with every character
    a GitHub release would rewrite (~ and + of Debian versions) as _."""
    return "deb-" + re.sub(r"[^A-Za-z0-9._-]", "_", os.path.basename(pool))

def snapshot_url(name, version, pool):
    """The pool file on snapshot.debian.org, by its package and version."""
    info = json.loads(get(f"{SNAPSHOT}/mr/binary/{name}/{version}/binfiles?fileinfo=1"))
    base = os.path.basename(pool)
    for b in info.get("result", []):
        for fi in info.get("fileinfo", {}).get(b["hash"], []):
            if fi.get("name") == base: return f"{SNAPSHOT}/file/{b['hash']}"
    raise LookupError(f"{base} not on snapshot.debian.org")

def fetch(name, version, pool, want):
    """The .deb, checked against its pinned SHA-256 (also a cached one)."""
    path = os.path.join(CACHE, os.path.basename(pool))
    if os.path.exists(path):
        b = open(path, "rb").read()
        if sha256(b) == want: return b
        os.remove(path)
    errs = []
    for url in (lambda: f"{MIRROR}/{pool}", lambda: f"{INPUTS}/{mirror_name(pool)}",
                lambda: snapshot_url(name, version, pool)):
        try:
            u = url()
            b = get(u)
        except Exception as e:
            errs.append(str(e)); continue
        # no other source is tried then, as pin_get of pins.sh
        if sha256(b) != want: sys.exit(f"SHA-256 mismatch: {u} has {sha256(b)} (want {want})")
        if errs: print(f"debs.py: {os.path.basename(pool)} from {u} ({'; '.join(errs)})", file=sys.stderr)
        open(path + ".part", "wb").write(b)
        os.rename(path + ".part", path)
        return b
    sys.exit(f"{pool}: no download ({'; '.join(errs)})")

def ar_members(data):
    assert data[:8] == b"!<arch>\n"
    i = 8
    while i < len(data):
        name = data[i:i+16].decode().strip().rstrip("/")
        size = int(data[i+48:i+58].decode().strip())
        yield name, data[i+60:i+60+size]
        i += 60 + size + (size & 1)

def build():
    dest, names = sys.argv[1], sys.argv[2:]
    triplet = {"arm64": "aarch64-linux-gnu", "amd64": "x86_64-linux-gnu"}[ARCH]
    os.makedirs(CACHE, exist_ok=True)
    pinned = pins()
    outt = tarfile.open(dest, "w")
    seen = set()
    for n in names:
        if n not in pinned: sys.exit(f"{n} ({ARCH}) has no pin in {LOCK} (scripts/guest/debs.py --lock)")
        version, pool, want = pinned[n]
        deb = fetch(n, version, pool, want)
        for name, body in ar_members(deb):
            if name.startswith("data.tar"):
                mode = "r:xz" if name.endswith(".xz") else ("r:zst" if name.endswith(".zst") else "r:*")
                with tarfile.open(fileobj=io.BytesIO(body), mode=mode) as t:
                    for m in t.getmembers():
                        name = m.name.lstrip("./")
                        if not name or name in seen: continue
                        if any(name.startswith(x) for x in ("usr/share/doc", "usr/share/man", "usr/share/locale",
                                                           "usr/share/i18n", f"usr/lib/{triplet}/gconv")): continue
                        seen.add(name); m.name = name
                        outt.addfile(m, t.extractfile(m) if m.isfile() else None)
        print("unpacked", n, version)
    outt.close()

def fetch_only():
    os.makedirs(CACHE, exist_ok=True)
    pinned = pins()
    for n in sys.argv[2:]:
        if n not in pinned: sys.exit(f"{n} ({ARCH}) has no pin in {LOCK} (scripts/guest/debs.py --lock)")
        fetch(n, *pinned[n])

if len(sys.argv) >= 2 and sys.argv[1] == "--lock":
    lock()
elif len(sys.argv) >= 3 and sys.argv[1] == "--fetch":
    fetch_only()
elif len(sys.argv) == 2 and sys.argv[1] == "--pins":
    for arch, name, version, pool, want in lock_lines():
        print(arch, name, os.path.basename(pool), mirror_name(pool), want)
elif len(sys.argv) >= 2:
    build()
else:
    sys.exit(__doc__)
