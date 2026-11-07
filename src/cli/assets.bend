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

# One archive, strictly (security review F7): downloaded into this run's
# own staging directory, checked against its SHA-256, then listed: it must
# hold exactly one regular file, named as the archive without ".tgz",
# before it is unpacked.
def Assets.fetch_one_strict(+base: String, +ver: String, f: AssetFile) -> String:
  match f:
    case AssetFile{+name, sum}:
      +member = String.take(name, Nat.sub(String.length(name), 4n))
      "curl -fL --retry 3 --progress-bar -o \"$t/" ++ name ++ "\" " ++ P.Plan.sh_quote(Assets.url(base, ver, name))
        ++ " && echo " ++ P.Plan.sh_quote(sum ++ "  " ++ name) ++ " | (cd \"$t\" && shasum -a 256 -c -s)"
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
