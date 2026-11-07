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

def Assets.fetch_all(+base: String, +ver: String, fs: List<&2, AssetFile>) -> String:
  match fs:
    case Nil{}:
      ""
    case Con{f, rest}:
      Assets.fetch_one(base, ver, f) ++ Assets.fetch_all(base, ver, rest)

# Download into a temporary directory beside the target, verify, unpack,
# then rename it into place: an interrupted fetch never leaves a partial
# asset set where vk8s looks for one.
def Assets.fetch_sh(+dir: String, +base: String, +ver: String, fs: List<&2, AssetFile>) -> String:
  "set -e; mkdir -p \"$(dirname " ++ P.Plan.sh_quote(dir) ++ ")\"; t=" ++ P.Plan.sh_quote(dir ++ ".part") ++ "; rm -rf \"$t\"; mkdir -p \"$t\"; set +e; "
    ++ Assets.fetch_all(base, ver, fs) ++ "rm -rf " ++ P.Plan.sh_quote(dir) ++ " && mv \"$t\" " ++ P.Plan.sh_quote(dir)
