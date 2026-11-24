#!/usr/bin/env bash
# The image cache on the host (host/cache/mirror.bend, `vk8s cache
# serve`) end to end on Linux, no VM. It builds tests/cache_mirror_echo.bend
# natively, serves random blobs from the TLS stub registry
# (tests/stub_registry.sh: token auth as Docker Hub asks for it), runs the
# mirror on 127.0.0.1:15001-15004 with VK8S_UPSTREAM pointing every
# registry at the stub, and pulls through it with curl as containerd
# would (by digest, ?ns=docker.io):
#
# - GET /v2/ is the OCI ping (200, {});
# - a blob the store lacks is fetched once from the registry (with a
#   token), streamed to the client and kept in the store with its
#   sidecar; asked again, it comes from the store and the registry is not
#   asked; a Range request gets 206 and those bytes;
# - three clients at once for one blob the registry sends slowly: one
#   upstream fetch, every client gets every byte (they follow the fill as
#   it grows), with the token the first blob got (the token cache: no
#   second 401);
# - a blob whose bytes do not match its digest: the client is cut off
#   before its last byte, and nothing is kept;
# - a manifest by tag is 404 UNSUPPORTED (pull-only: containerd resolves
#   tags upstream); a blob the registry lacks is 404 BLOB_UNKNOWN; a
#   Range request or a HEAD for a missing blob is 404, so containerd asks
#   the upstream itself; a HEAD for a missing manifest by digest is
#   filled (containerd resolves with it) and answered with its head;
# - a second mirror cannot start while the first listens;
# - the stop file (`vk8s cache stop` writes it) makes the mirror exit.
#
# Needs bend, clang, python3, openssl, curl, sha256sum, and the ports
# 15001-15004 and STUB_PORT (default 15443) free. Prints PASS/FAIL lines;
# exits 1 on any FAIL.
set -uo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done
  wait 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
check() { # check NAME CONDITION-COMMAND...
  local name=$1
  shift
  if "$@"; then pass "$name"; else fail "$name"; fi
}
sport=${STUB_PORT:-15443}

echo "== build"
if ! bend tests/cache_mirror_echo.bend -o "$tmp/mecho" >"$tmp/build.log" 2>&1; then
  cat "$tmp/build.log"
  echo "FAIL build tests/cache_mirror_echo.bend"
  exit 1
fi
pass "build"

echo "== blobs"
mkdir -p "$tmp/reg"
# blob N: random bytes in reg/<digest>, its digest in dN. d4's file holds
# other bytes than its digest says.
python3 -I - "$tmp" <<'PY'
import hashlib, os, sys
tmp = sys.argv[1]
for n, size in enumerate([300000, 2000000, 70000, 50000, 80000]):
    b = os.urandom(size)
    d = "sha256:" + hashlib.sha256(b).hexdigest()
    if n == 4:
        b = os.urandom(size)
    open(f"{tmp}/reg/{d}", "wb").write(b)
    open(f"{tmp}/d{n}", "w").write(d)
PY
d0=$(cat "$tmp/d0")
d1=$(cat "$tmp/d1")
d2=$(cat "$tmp/d2")
d3=$(cat "$tmp/d3")
d4=$(cat "$tmp/d4")

echo "== stub registry and mirror"
# shellcheck source=tests/stub_registry.sh
. tests/stub_registry.sh
stub_registry "$tmp" "$sport" || exit 1
pids+=("$stub_pid")
root="$tmp/store"
VK8S_UPSTREAM="https://127.0.0.1:$sport" SSL_CERT_FILE="$tmp/ca.pem" "$tmp/mecho" serve "$root" >"$tmp/mirror.log" 2>&1 &
pids+=($!)
up() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
ok=0
for _ in $(seq 100); do
  if up "$sport" && up 15001 && up 15004; then ok=1; break; fi
  sleep 0.1
done
check "the stub registry and the mirror listen" test "$ok" = 1
if [ "$ok" != 1 ]; then cat "$tmp/mirror.log" "$tmp/registry.err"; echo "== $fails failed"; exit 1; fi

base=http://127.0.0.1:15001/v2/library/busybox
get() { # get URL OUT [curl args]: prints "status size"
  local url=$1 out=$2
  shift 2
  curl -s -o "$out" -w '%{http_code} %{size_download}' "$@" "$url"
}
hex() { sha256sum "$1" | cut -d' ' -f1; }

echo "== the ping"
check "GET /v2/ is 200 {}" test "$(curl -s -w ' %{http_code}' http://127.0.0.1:15002/v2/)" = "{} 200"

echo "== a blob the store lacks, then has"
: >"$tmp/reg.log"
r=$(get "$base/blobs/$d0?ns=docker.io" "$tmp/b0")
check "the first GET is 200 with every byte ($r)" test "$r" = "200 300000"
check "the bytes are the blob's" test "sha256:$(hex "$tmp/b0")" = "$d0"
check "the registry was asked once, with a token" \
  test "$(grep -c "/blobs/$d0" "$tmp/reg.log"),$(grep -c '^/token' "$tmp/reg.log")" = 2,1
f0="$root/docker.io/blobs/sha256/${d0:7:2}/${d0#sha256:}"
check "the store keeps the blob" cmp -s "$f0" "$tmp/b0"
check "and its sidecar (media type, size, last use)" grep -q '^size 300000$' "$f0.meta"
: >"$tmp/reg.log"
r=$(get "$base/blobs/$d0" "$tmp/b0b")
check "the second GET is 200 from the store ($r)" test "$r" = "200 300000"
check "the registry is not asked again" test ! -s "$tmp/reg.log"
r=$(get "$base/blobs/$d0" "$tmp/b0r" -r 1000-1999)
check "a Range GET is 206 with 1000 bytes ($r)" test "$r" = "206 1000"
check "those are bytes 1000-1999" cmp -s "$tmp/b0r" <(tail -c +1001 "$tmp/b0" | head -c 1000)

echo "== three clients at once, a slow registry"
: >"$tmp/reg.log"
printf '65536' >"$tmp/drip"
ws=()
for i in 1 2 3; do
  get "$base/blobs/$d1" "$tmp/b1.$i" >"$tmp/r1.$i" &
  ws+=($!)
  sleep 0.1
done
wait "${ws[@]}"
rm -f "$tmp/drip"
check "each client got 200 and every byte ($(cat "$tmp"/r1.[123] | tr '\n' ' '))" \
  test "$(cat "$tmp"/r1.1 "$tmp"/r1.2 "$tmp"/r1.3 | tr -d '\n')" = "200 2000000200 2000000200 2000000"
check "each client's bytes are the blob's" \
  test "$(hex "$tmp/b1.1") $(hex "$tmp/b1.2") $(hex "$tmp/b1.3")" = "${d1#sha256:} ${d1#sha256:} ${d1#sha256:}"
# one request: the token the first blob got is cached (Auth.cache) and
# sent at once, so no 401 and no second token request
check "one fetch from the registry for the three, with the cached token" \
  test "$(grep -c "/blobs/$d1" "$tmp/reg.log"),$(grep -c '^/token' "$tmp/reg.log")" = 1,0

echo "== a blob that does not match its digest"
r=$(get "$base/blobs/$d4" "$tmp/b4")
check "the client is cut off before the last byte ($r)" test "${r#200 }" -lt 80000
check "nothing is kept" test ! -e "$root/docker.io/blobs/sha256/${d4:7:2}/${d4#sha256:}"

echo "== what the mirror does not serve"
check "a manifest by tag is 404 UNSUPPORTED" \
  grep -q '"code":"UNSUPPORTED"' <(curl -s "$base/manifests/latest")
missing="sha256:$(printf '1%.0s' $(seq 64))"
check "a blob the registry lacks is 404 BLOB_UNKNOWN" \
  test "$(curl -s -o "$tmp/m" -w '%{http_code}' "$base/blobs/$missing"),$(grep -c BLOB_UNKNOWN "$tmp/m")" = 404,1
check "a Range GET of a blob the store lacks is 404" test "$(curl -s -o /dev/null -w '%{http_code}' -r 0-9 "$base/blobs/$d2")" = 404
check "a HEAD of a blob the store lacks is 404" test "$(curl -s -o /dev/null -w '%{http_code}' -I "$base/blobs/$d2")" = 404
check "neither cached it" test ! -e "$root/docker.io/blobs/sha256/${d2:7:2}/${d2#sha256:}"

echo "== a HEAD of a manifest the store lacks"
# containerd resolves an image with HEAD manifests/<digest> on the mirror
# first; a 404 would send it to the registry itself (Serve.miss.fills)
r=$(curl -s -o /dev/null -D "$tmp/h3" -w '%{http_code}' -I "$base/manifests/$d3")
check "is filled: 200 with its length ($r)" test "$r,$(grep -ci '^content-length: 50000' "$tmp/h3")" = "200,1"
kept=0
for _ in $(seq 40); do
  if test -e "$root/docker.io/blobs/sha256/${d3:7:2}/${d3#sha256:}"; then kept=1; break; fi
  sleep 0.1
done
check "and the store keeps it" test "$kept" = 1

echo "== a second mirror"
"$tmp/mecho" serve "$tmp/store2" >"$tmp/mirror2.log" 2>&1
check "cannot start while the first listens" test "$?" != 0

echo "== stop"
touch "$root.stop"
gone=0
for _ in $(seq 40); do
  if ! up 15001; then gone=1; break; fi
  sleep 0.1
done
check "the file ROOT.stop makes the mirror exit (vk8s cache stop)" test "$gone" = 1
check "and the mirror removed it" test ! -e "$root.stop"

echo "== the mirror's log"
cat "$tmp/mirror.log"
check "the mirror logs each object it cached (two blobs, a manifest)" test "$(grep -c ' cached (' "$tmp/mirror.log")" = 3

echo "== $fails failed"
[ "$fails" = 0 ]
