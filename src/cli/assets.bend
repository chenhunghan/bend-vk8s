import Base
import ../guest/plan.bend as P

# Where vk8s finds its guest assets (kernel, initramfs, the read-only
# assets disk, the data disk template), and how it fetches them: from the
# GitHub release named by the manifest's version, each archive checked
# against its pinned SHA-256 before it is unpacked. VK8S_ASSETS (a local
# build) bypasses all of it.

# An archive of a release and the SHA-256 it must have.
type AssetFile is Data:
  AssetFile{name: String, sum: String}

def Assets.default_base() -> String:
  "https://github.com/chenhunghan/bend-vk8s/releases/download"

def Assets.dir(+home: String, +ver: String) -> String:
  home ++ "/.vk8s/assets/" ++ ver

def Assets.url(+base: String, +ver: String, +file: String) -> String:
  base ++ "/" ++ ver ++ "/" ++ file

# The four files a cluster needs, as `test -f` arguments.
def Assets.have_sh(+dir: String) -> String:
  "test -f " ++ P.Plan.sh_quote(dir ++ "/Image") ++ " -a -f " ++ P.Plan.sh_quote(dir ++ "/vk8s.cpio")
    ++ " -a -f " ++ P.Plan.sh_quote(dir ++ "/assets.img") ++ " -a -f " ++ P.Plan.sh_quote(dir ++ "/data.img")

def Assets.fetch_one(+base: String, +ver: String, f: AssetFile) -> String:
  match f:
    case AssetFile{+name, sum}:
      "curl -fL --retry 3 --progress-bar -o \"$t/" ++ name ++ "\" " ++ P.Plan.sh_quote(Assets.url(base, ver, name))
        ++ " && echo " ++ P.Plan.sh_quote(sum ++ "  " ++ name) ++ " | (cd \"$t\" && shasum -a 256 -c -s)"
        ++ " || { echo " ++ P.Plan.sh_quote("vk8s: " ++ name ++ ": download failed or SHA-256 mismatch") ++ " >&2; rm -rf \"$t\"; exit 1; }"
        ++ "; tar -xzSf \"$t/" ++ name ++ "\" -C \"$t\" && rm -f \"$t/" ++ name ++ "\" || { rm -rf \"$t\"; exit 1; }; "

# A SHA-256 check of "SUM  NAME" lines on stdin (docs/ref/explore-linux-
# hosts.md, Phase 1): shasum where present (macOS, as before), else GNU
# coreutils' sha256sum for Linux hosts without Perl's shasum.
def Assets.sha256_check() -> String:
  "if command -v shasum >/dev/null 2>&1; then shasum -a 256 -c -s; else sha256sum -c --status; fi"

# One archive, strictly (security review F7): downloaded into this run's
# own staging directory, checked against its SHA-256, then listed: it must
# hold exactly one regular file, named as the archive without ".tgz",
# before it is unpacked.
def Assets.fetch_one_strict(+base: String, +ver: String, f: AssetFile) -> String:
  match f:
    case AssetFile{+name, sum}:
      +member = String.take(name, Nat.sub(String.length(name), 4n))
      "curl -fL --retry 3 --progress-bar -o \"$t/" ++ name ++ "\" " ++ P.Plan.sh_quote(Assets.url(base, ver, name))
        ++ " && echo " ++ P.Plan.sh_quote(sum ++ "  " ++ name) ++ " | (cd \"$t\" && " ++ Assets.sha256_check() ++ ")"
        ++ " || { echo " ++ P.Plan.sh_quote("vk8s: " ++ name ++ ": download failed or SHA-256 mismatch") ++ " >&2; rm -rf \"$t\"; exit 1; }"
        ++ "; l=$(tar -tvzf \"$t/" ++ name ++ "\") && [ \"$(printf '%s\\n' \"$l\" | wc -l | tr -d ' ')\" = 1 ] && case \"$l\" in -*\" " ++ member ++ "\") ;; *) false ;; esac"
        ++ " || { echo " ++ P.Plan.sh_quote("vk8s: " ++ name ++ ": unexpected archive members") ++ " >&2; rm -rf \"$t\"; exit 1; }"
        ++ "; tar -xzSf \"$t/" ++ name ++ "\" -C \"$t\" " ++ P.Plan.sh_quote(member) ++ " && rm -f \"$t/" ++ name ++ "\" || { rm -rf \"$t\"; exit 1; }; "

def Assets.fetch_all(+base: String, +ver: String, fs: List<&2, AssetFile>) -> String:
  match fs:
    case Nil{}:
      ""
    case Con{f, rest}:
      Assets.fetch_one_strict(base, ver, f) ++ Assets.fetch_all(base, ver, rest)

# Download into a fresh, private staging directory beside the target
# (mktemp, mode 0700, unique per run), verify, unpack, then rename it into
# place unless another run finished first: no run deletes another's work,
# and vk8s never sees a partial asset set.
def Assets.fetch_sh(+dir: String, +base: String, +ver: String, fs: List<&2, AssetFile>) -> String:
  "umask 077; mkdir -p \"$(dirname " ++ P.Plan.sh_quote(dir) ++ ")\" && t=$(mktemp -d \"$(dirname " ++ P.Plan.sh_quote(dir) ++ ")/.fetch.XXXXXX\") || exit 1; "
    ++ Assets.fetch_all(base, ver, fs) ++ "chmod 755 \"$t\"; if [ -e " ++ P.Plan.sh_quote(dir) ++ " ]; then rm -rf \"$t\"; else mv \"$t\" " ++ P.Plan.sh_quote(dir) ++ "; fi"

# Whether every archive is pinned by a 64-character SHA-256 hex digest.
def Assets.pinned(fs: List<&2, AssetFile>) -> Bool:
  match fs:
    case Nil{}:
      True{}
    case Con{AssetFile{n, +sum}, t}:
      Bool.and(Nat.is_eq(String.length(sum), 64n), Assets.pinned(t))

# --- Per-role asset sets (docs/GOAL.md section 9; docs/ref/footprint-
# decisions.md D1). Every VM boots the base files (Image, vk8s.cpio,
# base.img, data.img); each attaches one read-only squashfs disk per set of
# its role, <set>.img, which a release pins as <set>.img.tgz.

# A role set's archive.
type SetFile is Data:
  SetFile{set: String, file: AssetFile}

def Assets.has(xs: +List<String>, +x: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{y, t}:
      String.eq(x, y) || Assets.has(t, x)

# images (the preloaded add-on tars) only where the image cache does not
# run: with it, kubelet pulls the add-ons through the cache (A3).
def Assets.images_unless(cached: Bool) -> +List<String>:
  match cached:
    case True{}:
      Nil{}
    case False{}:
      ["images"]

def Assets.role_sets.pick(sa: Bool, cl: Bool, wk: Bool, ca: Bool, cached: Bool) -> +List<String>:
  match sa cl wk ca:
    case True{} _ _ _:
      Con{"node", Con{"control-plane", Assets.images_unless(cached)}}
    case False{} True{} _ _:
      ["node", "control-plane", "classic"]
    case False{} False{} True{} _:
      Con{"node", Assets.images_unless(cached)}
    case False{} False{} False{} True{}:
      ["cache"]
    case False{} False{} False{} False{}:
      Nil{}

# The sets a VM of this role mounts, in disk order: a standalone control
# plane (also a node) node and control-plane; a classic one (its pods run
# on the host cluster; kubeadm, in node, makes its PKI) node, control-plane
# and classic; a worker node; the image cache cache. images joins the
# standalone control plane and the worker unless the cache runs (cached).
def Assets.role_sets(+role: String, cached: Bool) -> +List<String>:
  Assets.role_sets.pick(String.eq(role, "standalone"), String.eq(role, "classic"), String.eq(role, "worker"),
    String.eq(role, "cache"), cached)

def Assets.set_files.keep(hit: Bool, f: AssetFile, rest: List<&2, AssetFile>) -> List<&2, AssetFile>:
  match hit:
    case True{}:
      Con{f, rest}
    case False{}:
      rest

# The archives of these sets, in the manifest's order.
def Assets.set_files(+sets: +List<String>, fs: List<&2, SetFile>) -> List<&2, AssetFile>:
  match fs:
    case Nil{}:
      Nil{}
    case Con{SetFile{+s, f}, t}:
      Assets.set_files.keep(Assets.has(sets, s), f, Assets.set_files(sets, t))

def Assets.files_of(fs: List<&2, SetFile>) -> List<&2, AssetFile>:
  match fs:
    case Nil{}:
      Nil{}
    case Con{SetFile{s, f}, t}:
      Con{f, Assets.files_of(t)}

# Whether each set's archive is named <set>.img.tgz (the host looks for
# <set>.img in the assets dir).
def Assets.sets_named(fs: List<&2, SetFile>) -> Bool:
  match fs:
    case Nil{}:
      True{}
    case Con{SetFile{s, AssetFile{n, sum}}, t}:
      Bool.and(String.eq(n, s ++ ".img.tgz"), Assets.sets_named(t))

# The disk files of these sets in an assets dir.
def Assets.set_paths(+dir: String, sets: +List<String>) -> +List<String>:
  match sets:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      Con{dir ++ "/" ++ s ++ ".img", Assets.set_paths(dir, t)}

# The files these archives unpack to (each holds one, named as the
# archive without ".tgz").
def Assets.file_paths(+dir: String, fs: List<&2, AssetFile>) -> +List<String>:
  match fs:
    case Nil{}:
      Nil{}
    case Con{AssetFile{+name, sum}, t}:
      Con{dir ++ "/" ++ String.take(name, Nat.sub(String.length(name), 4n)), Assets.file_paths(dir, t)}

def Assets.fetch_missing(+dir: String, +base: String, +ver: String, fs: List<&2, AssetFile>) -> String:
  match fs:
    case Nil{}:
      ""
    case Con{AssetFile{+name, +sum}, rest}:
      "if [ ! -f " ++ P.Plan.sh_quote(dir ++ "/" ++ String.take(name, Nat.sub(String.length(name), 4n))) ++ " ]; then "
        ++ Assets.fetch_one_strict(base, ver, AssetFile{name, sum}) ++ "fi; " ++ Assets.fetch_missing(dir, base, ver, rest)

# Fetch the archives whose file the assets dir lacks into a fresh,
# private staging dir inside it (Assets.fetch_one_strict: checksum, one
# member), then move each file into place unless another run placed it
# first: the base files' dir gains a set without being replaced.
def Assets.fetch_into_sh(+dir: String, +base: String, +ver: String, fs: List<&2, AssetFile>) -> String:
  +d = P.Plan.sh_quote(dir)
  "umask 077; mkdir -p " ++ d ++ " && t=$(mktemp -d " ++ d ++ "/.fetch.XXXXXX) || exit 1; "
    ++ Assets.fetch_missing(dir, base, ver, fs)
    ++ "for f in \"$t\"/*; do [ -f \"$f\" ] || continue; n=${f##*/}; [ -e " ++ d ++ "/\"$n\" ] || mv \"$f\" " ++ d ++ "/\"$n\"; done; rm -rf \"$t\""

# --- Optional sets (docs/ref/review-bend-vk8s-pr-48.md #3). The build
# makes images only after scripts/guest/images.sh ran, and a release pins
# only the sets it has; the image cache is not fatal either. So images and
# cache are optional: a VM boots without them (kubelet then pulls the
# add-ons from the registries; the cache VM does not start, and containerd
# pulls directly). Every other set is required.
def Assets.optional(+s: String) -> Bool:
  String.eq(s, "images") || String.eq(s, "cache")

def Assets.sets_with.keep(keep: Bool, +s: String, +rest: +List<String>) -> +List<String>:
  match keep:
    case True{}:
      s <> rest
    case False{}:
      rest

# The sets whose disk the assets dir holds; have holds one Bool per set,
# in the same order (Vk8s.have_each of Assets.set_paths).
def Assets.present(sets: +List<String>, have: +List<Bool>) -> +List<String>:
  match sets have:
    case Nil{} _:
      Nil{}
    case Con{s, t} Nil{}:
      Nil{}
    case Con{+s, t} Con{h, u}:
      Assets.sets_with.keep(h, s, Assets.present(t, u))

# The sets whose disk the assets dir lacks.
def Assets.absent(sets: +List<String>, have: +List<Bool>) -> +List<String>:
  match sets have:
    case Nil{} _:
      Nil{}
    case Con{+s, t} Nil{}:
      s <> Assets.absent(t, Nil{})
    case Con{+s, t} Con{h, u}:
      Assets.sets_with.keep(Bool.not(h), s, Assets.absent(t, u))

# The absent sets a VM cannot boot without: vk8s stops with an error.
def Assets.missing_required.go(+s: String) -> Bool:
  Bool.not(Assets.optional(s))

def Assets.missing_required.pick(sets: +List<String>) -> +List<String>:
  match sets:
    case Nil{}:
      Nil{}
    case Con{+s, t}:
      Assets.sets_with.keep(Assets.missing_required.go(s), s, Assets.missing_required.pick(t))

def Assets.missing_required(sets: +List<String>, have: +List<Bool>) -> +List<String>:
  Assets.missing_required.pick(Assets.absent(sets, have))

# The absent optional sets: vk8s warns and goes on without them.
def Assets.missing_optional.pick(sets: +List<String>) -> +List<String>:
  match sets:
    case Nil{}:
      Nil{}
    case Con{+s, t}:
      Assets.sets_with.keep(Assets.optional(s), s, Assets.missing_optional.pick(t))

def Assets.missing_optional(sets: +List<String>, have: +List<Bool>) -> +List<String>:
  Assets.missing_optional.pick(Assets.absent(sets, have))

# --- Optional sets fetched on demand (docs/GOAL.md section 11). gvisor
# (runsc, its containerd shim, gvisor-bin/) and etcd (etcd, etcdutl) left
# node and control-plane for sets of their own (scripts/guest/sets.txt):
# a VM attaches gvisor only when its cluster was made with --gvisor, and
# etcd only when it was made with --backing-store etcd. Once asked for,
# they are required (Assets.optional stays False for them).

# The sets split off node and control-plane.
def Assets.split(+s: String) -> Bool:
  String.eq(s, "gvisor") || String.eq(s, "etcd")

def Assets.gvisor_if(on: Bool) -> +List<String>:
  match on:
    case True{}:
      ["gvisor"]
    case False{}:
      Nil{}

def Assets.etcd_if(on: Bool) -> +List<String>:
  match on:
    case True{}:
      ["etcd"]
    case False{}:
      Nil{}

# The optional sets of a role: gvisor on a node (a standalone control
# plane, a worker) with gVisor on, etcd on a control plane (standalone or
# classic) with the etcd backing store. Off, none, whatever the role.
def Assets.extra_sets(gvisor: Bool, etcd: Bool, +role: String) -> +List<String>:
  match gvisor etcd:
    case False{} False{}:
      Nil{}
    case _ _:
      List.append(&2, String,
        Assets.etcd_if(etcd && (String.eq(role, "standalone") || String.eq(role, "classic"))),
        Assets.gvisor_if(gvisor && (String.eq(role, "standalone") || String.eq(role, "worker"))))

# xs, then ys (xs itself when ys is empty).
def Assets.add_sets(xs: +List<String>, ys: +List<String>) -> +List<String>:
  match ys:
    case Nil{}:
      xs
    case Con{+y, +t}:
      List.append(&2, String, xs, Con{y, t})

# Assets.role_sets with the optional sets after the role's own, in disk
# order: etcd, then gvisor.
def Assets.role_sets.v2(+role: String, cached: Bool, gvisor: Bool, etcd: Bool) -> +List<String>:
  Assets.add_sets(Assets.role_sets(role, cached), Assets.extra_sets(gvisor, etcd, role))

# Whether a release pins this set.
def Assets.pins_set(+s: String, fs: List<&2, SetFile>) -> Bool:
  Bool.not(List.is_empty(&2, AssetFile, Assets.set_files([s], fs)))

def Assets.unsplit.keep(drop: Bool, +s: String, +rest: +List<String>) -> +List<String>:
  match drop:
    case True{}:
      rest
    case False{}:
      s <> rest

# A release made before the split pins no gvisor or etcd set: its node and
# control-plane sets hold runsc and etcd. From that release's assets dir
# (released), a split set it does not pin is left out: the VM finds the
# binaries in node and control-plane. A local build (VK8S_ASSETS) keeps
# every set: there, a split set is required.
def Assets.unsplit(sets: +List<String>, +fs: List<&2, SetFile>, +released: Bool) -> +List<String>:
  match sets:
    case Nil{}:
      Nil{}
    case Con{+s, t}:
      Assets.unsplit.keep(released && Assets.split(s) && Bool.not(Assets.pins_set(s, fs)), s,
        Assets.unsplit(t, fs, released))

# The sets of want that have does not hold.
def Assets.not_in(want: +List<String>, +have: +List<String>) -> +List<String>:
  match want:
    case Nil{}:
      Nil{}
    case Con{+s, t}:
      Assets.sets_with.keep(Bool.not(Assets.has(have, s)), s, Assets.not_in(t, have))
