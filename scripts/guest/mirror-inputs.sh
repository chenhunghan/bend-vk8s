#!/usr/bin/env bash
# Uploads the pinned files of the guest build to our mirror release, the
# GitHub release $INPUTS_TAG of $INPUTS_REPO (scripts/guest/pins.sh), so a
# build of any commit still finds them after their origin stops serving
# them. Each download tries its origin first and falls back to this
# release, under the same SHA-256 (pin_get of pins.sh, debs.py). The files
# and their names there:
#   <arch>-<file>.apk    the Alpine packages of pins.sh (linux-virt,
#                        busybox-static; aarch64, x86_64). Alpine keeps
#                        only the newest build of a package in a branch.
#   cacert-<date>.pem    the CA bundle of pins.sh (curl.se)
#   deb-<pool file>      every Debian package of debs.lock (arm64, amd64),
#                        with ~ and + as _ (debs.py --pins prints them).
#                        deb.debian.org drops a package at a point release.
#   kubernetes-<ver>-<arch>-full.tar.gz, gvisor-<ver>-<arch>.tar.bz2,
#   kube-router_<ver>_linux_<arch>.tar.gz
#                        the archives of fetch-assets.sh (arm64, amd64),
#                        each from one third-party GitHub release
#
# Run it with every pin bump, in the same change. It is idempotent: a name
# the release already holds is left alone (and reported when GitHub's
# digest of it is not the pin), only a missing one is fetched (through the
# build's own download, so its SHA-256 is checked) and uploaded. Older
# files stay, so an older commit still builds. The release is created
# when it is not there: a pre-release, never "latest", so it does not pass
# for a vk8s release. Its text (the licenses and sources below) is set on
# every run.
#
# usage: mirror-inputs.sh [--check]
#   --check   upload nothing; exit 1 when a pinned file is missing
# Needs gh (logged in; to upload, with write access to the repository),
# curl and python3.
set -euo pipefail
cd "$(dirname "$0")/../.."
. scripts/guest/pins.sh
check=0
case ${1:-} in
  "") ;;
  --check) check=1 ;;
  *) sed -n 's/^# usage: //p' "$0"; exit 2 ;;
esac

notes() {
  cat <<'EOF'
This is not a vk8s release. It holds copies of third-party files that the
guest build pins, so that a build of any commit still finds them after
their origin stops serving them.

Each file is unchanged, as its origin served it. The build tries the
origin first and falls back to this release, and it accepts a file from
either only when its SHA-256 is the one pinned in the repository
([pins.sh](https://github.com/chenhunghan/bend-vk8s/blob/main/scripts/guest/pins.sh),
[debs.lock](https://github.com/chenhunghan/bend-vk8s/blob/main/scripts/guest/debs.lock),
[fetch-assets.sh](https://github.com/chenhunghan/bend-vk8s/blob/main/scripts/guest/fetch-assets.sh)).
[mirror-inputs.sh](https://github.com/chenhunghan/bend-vk8s/blob/main/scripts/guest/mirror-inputs.sh)
uploads them.

## Licenses and sources

### Alpine Linux packages (`<arch>-<file>.apk`)

- `linux-virt-*.apk` is Alpine's build of the Linux kernel, GPL-2.0-only.
  Its source is kernel.org's `linux-<base>.tar.xz` with
  `patch-<version>.xz`
  (https://cdn.kernel.org/pub/linux/kernel/v6.x/), built with the
  APKBUILD, patches and configs of `main/linux-lts` in
  [Alpine's aports](https://gitlab.alpinelinux.org/alpine/aports) at the
  commit "main/linux-lts: upgrade to <version>" of the release branch.
  [scripts/guest/kernel.sh](https://github.com/chenhunghan/bend-vk8s/blob/main/scripts/guest/kernel.sh)
  at the commit that pins a version names that aports commit and pins the
  kernel.org tarball and patch by SHA-512.
- `busybox-static-*.apk` is Alpine's build of BusyBox, GPL-2.0-only.
  Its source is https://busybox.net/downloads/ with `main/busybox` of
  aports (the commit is in the package's `.PKGINFO`).

Each package carries Alpine's signature and its `.PKGINFO` (version,
aports commit, build date).

### CA bundle (`cacert-<date>.pem`)

Mozilla's CA root certificates as curl publishes them
(https://curl.se/docs/caextract.html), MPL-2.0. Its source is Mozilla's
`certdata.txt`, converted by curl's `mk-ca-bundle`.

### Debian packages (`deb-<package>_<version>_<arch>.deb`)

Binary packages of Debian 13 (trixie), from https://deb.debian.org/debian
(`pool/main/`), for arm64 and amd64. In a file name here, `_` stands for
the `~` or `+` of the Debian version. Each package holds its full
copyright and license text in `usr/share/doc/<package>/copyright`; in
short, by source package:

| Source package | Binary packages here | License |
|---|---|---|
| glibc | libc6, libc-bin | LGPL-2.1-or-later (parts GPL-2.0-or-later) |
| iptables | iptables, libxtables12, libip4tc2, libip6tc2 | GPL-2.0-or-later |
| libnftnl | libnftnl11 | GPL-2.0-or-later |
| libmnl | libmnl0 | LGPL-2.1-or-later |
| libnetfilter-conntrack | libnetfilter-conntrack3 | GPL-2.0-or-later |
| libnfnetlink | libnfnetlink0 | GPL-2.0 |
| conntrack-tools | conntrack | GPL-2.0-or-later |
| ipset | ipset, libipset13t64 | GPL-2.0-only |
| iproute2 | iproute2 | GPL-2.0-or-later |
| busybox | busybox-static | GPL-2.0-only |
| cpio | cpio | GPL-3.0-or-later |
| elfutils | libelf1t64 | LGPL-3.0-or-later or GPL-2.0-or-later |
| libbpf | libbpf1 | LGPL-2.1-only or BSD-2-Clause |
| libcap2 | libcap2 | BSD-3-Clause or GPL-2.0-only |
| libzstd | libzstd1 | BSD-3-Clause or GPL-2.0-only |
| openssl | libssl3t64 | Apache-2.0 |
| zlib | zlib1g | Zlib |
| pcre2 | libpcre2-8-0 | BSD-3-Clause |
| libbsd | libbsd0 | BSD-3-Clause and other BSD licenses |
| libmd | libmd0 | BSD-3-Clause, BSD-2-Clause, ISC, public domain |
| libselinux | libselinux1 | public domain |

Corresponding source, for the GPL and LGPL packages and every other one:
Debian's own source package of the same version, which
snapshot.debian.org keeps:
`https://snapshot.debian.org/package/<source package>/<version>/` (the
`.dsc`, the `.orig.tar.*` and the `.debian.tar.*`). The version is the one
in the file name, without a trailing `+b<n>` (a rebuild of the same
source), and
[debs.lock](https://github.com/chenhunghan/bend-vk8s/blob/main/scripts/guest/debs.lock)
lists it with its epoch.

### Kubernetes binaries (`kubernetes-<version>-<arch>-full.tar.gz`)

The release bundle of https://github.com/loft-sh/kubernetes (Apache-2.0)
of that version, unchanged. It holds builds of Kubernetes
(https://github.com/kubernetes/kubernetes), etcd
(https://github.com/etcd-io/etcd), kine (https://github.com/loft-sh/kine),
konnectivity (https://github.com/kubernetes-sigs/apiserver-network-proxy),
containerd (https://github.com/containerd/containerd), runc
(https://github.com/opencontainers/runc), the CNI plugins
(https://github.com/containernetworking/plugins), Helm
(https://github.com/helm/helm) and crictl
(https://github.com/kubernetes-sigs/cri-tools), all Apache-2.0. The
bundle's release notes
(`https://github.com/loft-sh/kubernetes/releases/tag/<version>`) name the
version of each.

### gVisor (`gvisor-<release>-<arch>.tar.bz2`)

`gvisor-<arch>.tar.bz2` of the release `release-<release>` of
https://github.com/google/gvisor, Apache-2.0.

### kube-router (`kube-router_<version>_linux_<arch>.tar.gz`)

The release archive of https://github.com/cloudnativelabs/kube-router of
that version, Apache-2.0 (its `LICENSE` is in the archive).
EOF
}

# items: "<name in the release> <sha256> <kind> <what fetch needs>" of
# every pinned file
items() {
  local arch pkg pin out
  for arch in aarch64 x86_64; do
    for pkg in linux-virt busybox-static; do
      pin=$(alpine_pin "$arch" "$pkg") || return 1
      echo "$arch-${pin% *} ${pin#* } apk $arch $pkg"
    done
  done
  echo "$CACERT_FILE $CACERT_SHA256 cacert"
  out=$(python3 -I scripts/guest/debs.py --pins) || return 1
  awk '{ print $4, $5, "deb", $1, $2, $3 }' <<<"$out"
  for arch in arm64 amd64; do
    out=$(ARCH=$arch scripts/guest/fetch-assets.sh --pins) || return 1
    awk -v a="$arch" '{ print $1, $2, "asset", a, $3 }' <<<"$out"
  done
}

# fetch NAME SHA256 KIND ARGS...: the file as $t/NAME, by the build's own
# download of it (so from its origin, checked against the pin)
fetch() {
  local name=$1 sum=$2 kind=$3; shift 3
  case $kind in
    apk) alpine_get "$1" "$2" "$t/$name" ;;
    cacert) pin_get "${CACERT_URL:-https://curl.se/ca}/$name" "$t/$name" "$sum" ;;
    deb) DEB_ARCH=$1 DEB_CACHE=$t/debs python3 -I scripts/guest/debs.py --fetch "$2" && mv "$t/debs/$3" "$t/$name" ;;
    asset) ARCH=$1 scripts/guest/fetch-assets.sh --download >/dev/null && { ln -f "$2" "$t/$name" 2>/dev/null || cp "$2" "$t/$name"; } ;;
    *) echo "mirror-inputs: unknown kind $kind" >&2; return 1 ;;
  esac
  pin_ok "$sum" "$t/$name"
}

list=$(items) || { echo "mirror-inputs: cannot list the pinned files" >&2; exit 1; }
dup=$(cut -d' ' -f1 <<<"$list" | sort | uniq -d)
[ -z "$dup" ] || { echo "mirror-inputs: two pins share a name: $dup" >&2; exit 1; }

if ! gh release view "$INPUTS_TAG" -R "$INPUTS_REPO" >/dev/null 2>&1; then
  [ $check = 0 ] || { echo "mirror-inputs: no release $INPUTS_TAG in $INPUTS_REPO" >&2; exit 1; }
  notes | gh release create "$INPUTS_TAG" -R "$INPUTS_REPO" --prerelease --latest=false \
    --title "Pinned guest build inputs (mirror)" --notes-file -
elif [ $check = 0 ]; then
  notes | gh release edit "$INPUTS_TAG" -R "$INPUTS_REPO" --notes-file - >/dev/null
fi

have=$(gh release view "$INPUTS_TAG" -R "$INPUTS_REPO" --json assets \
  --jq '.assets[] | "\(.name) \(.digest // "")"')
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
bad=0 there=0 n=0
while read -r name sum kind args; do
  n=$((n + 1))
  if line=$(grep -F -- "$name " <<<"$have" | grep -m1 "^$name "); then
    digest=${line#* }
    if [ -n "$digest" ] && [ "$digest" != "sha256:$sum" ]; then
      echo "mirror-inputs: $name is there with $digest, the pin is sha256:$sum" >&2; bad=1
    else
      there=$((there + 1))
    fi
  elif [ $check = 1 ]; then
    echo "mirror-inputs: missing: $name" >&2; bad=1
  else
    # shellcheck disable=SC2086 # the kind's arguments are words
    fetch "$name" "$sum" "$kind" $args </dev/null
    gh release upload "$INPUTS_TAG" -R "$INPUTS_REPO" "$t/$name" </dev/null
    echo "uploaded: $name $(wc -c <"$t/$name" | tr -d ' ') bytes sha256 $sum"
    rm -f "$t/$name"
  fi
done <<<"$list"
echo "mirror-inputs: $there of $n pinned files were already in $INPUTS_REPO release $INPUTS_TAG"
exit $bad
