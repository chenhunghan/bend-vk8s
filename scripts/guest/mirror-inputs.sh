#!/usr/bin/env bash
# Uploads the Alpine packages scripts/guest/pins.sh pins (linux-virt and
# busybox-static, aarch64 and x86_64) to our mirror release, the GitHub
# release $INPUTS_TAG of $INPUTS_REPO, each as <arch>-<file>.apk. Alpine
# keeps only the newest build of a package in a branch, so a pinned file
# leaves its mirrors; alpine_get (pins.sh) then takes it from this release,
# under the same SHA-256.
#
# Run it with every pin bump, in the same change. It is idempotent: a name
# the release already holds is left alone (and reported when GitHub's
# digest of it is not the pin), only a missing one is fetched (alpine_get:
# the SHA-256 is checked) and uploaded. Older files stay, so an older
# commit still builds. The release is created when it is not there: a
# pre-release, never "latest", so it does not pass for a vk8s release.
#
# usage: mirror-inputs.sh [--check]
#   --check   upload nothing; exit 1 when a pinned file is missing
# Needs gh (logged in, with write access to the repository) and curl.
set -euo pipefail
cd "$(dirname "$0")/../.."
. scripts/guest/pins.sh
check=0
case ${1:-} in
  "") ;;
  --check) check=1 ;;
  *) sed -n 's/^# usage: //p' "$0"; exit 2 ;;
esac

if ! gh release view "$INPUTS_TAG" -R "$INPUTS_REPO" >/dev/null 2>&1; then
  [ $check = 0 ] || { echo "mirror-inputs: no release $INPUTS_TAG in $INPUTS_REPO" >&2; exit 1; }
  gh release create "$INPUTS_TAG" -R "$INPUTS_REPO" --prerelease --latest=false \
    --title "Pinned guest build inputs (mirror)" --notes-file - <<'EOF'
This is not a vk8s release. It holds copies of third-party files that the
guest build pins, so that a build of any commit still finds them after
their origin stops serving them.

Each file is `<arch>-<name>` of an Alpine Linux package, unchanged, as
Alpine's mirrors served it. The build
([scripts/guest/pins.sh](https://github.com/chenhunghan/bend-vk8s/blob/main/scripts/guest/pins.sh))
tries Alpine first and falls back to this release, and it accepts a file
from either only when its SHA-256 is the one pinned in `pins.sh`.
`scripts/guest/mirror-inputs.sh` uploads them.

Licenses and source:

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
EOF
fi

have=$(gh release view "$INPUTS_TAG" -R "$INPUTS_REPO" --json assets \
  --jq '.assets[] | "\(.name) \(.digest // "")"')
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
bad=0
for arch in aarch64 x86_64; do
  for pkg in linux-virt busybox-static; do
    read -r apk sum <<<"$(alpine_pin "$arch" "$pkg")"
    name=$arch-$apk
    if line=$(grep "^$name " <<<"$have"); then
      digest=${line#* }
      if [ -n "$digest" ] && [ "$digest" != "sha256:$sum" ]; then
        echo "mirror-inputs: $name is there with $digest, the pin is sha256:$sum" >&2; bad=1
      else
        echo "there:    $name"
      fi
    elif [ $check = 1 ]; then
      echo "mirror-inputs: missing: $name" >&2; bad=1
    else
      alpine_get "$arch" "$pkg" "$t/$name"
      gh release upload "$INPUTS_TAG" -R "$INPUTS_REPO" "$t/$name"
      rm -f "$t/$name"
      echo "uploaded: $name sha256 $sum"
    fi
  done
done
exit $bad
