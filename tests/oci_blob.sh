#!/usr/bin/env bash
# The OCI blob effects (host/oci/effs/oci_blob.c) end to end. It builds
# tests/oci_blob_echo.bend natively, makes a sparse source file of
# OCI_BLOB_GIB GiB (default 5, so sizes and offsets pass 2^32) with
# random bytes at its start, across 4 GiB and at its end, and a TLS
# server certificate with the openssl CLI. Then, against the program:
#
# - fetch: the source goes up a plain socket (bash /dev/tcp) and a TLS one
#   (openssl s_client); the program writes it with OciBlob.fetch and
#   answers OciBlob.commit's digest, which must match sha256sum's, and
#   the file it wrote must match the source (cmp) with mode 0600;
# - send: the whole source comes back over a plain socket (sendfile) and
#   a TLS one, and a range across 4 GiB over a plain one, checked with
#   cmp;
# - a stream that ends early fails the fetch (ECONNRESET);
# - peak RSS (VmHWM, Linux only) grows by less than 64 MiB.
#
# It prints the throughput of each transfer (client and server on one
# machine, so the client's cost is in it). Needs bend, clang, openssl,
# perl, sha256sum (or shasum). Prints PASS/FAIL lines; exits 1 on any
# FAIL.
set -uo pipefail
cd "$(dirname "$0")/.."

gib=${OCI_BLOB_GIB:-5}
tmp=$(mktemp -d)
pid=
cleanup() {
  [ -n "$pid" ] && kill "$pid" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
check() { # check NAME CONDITION-COMMAND...
  local name=$1; shift
  if "$@"; then pass "$name"; else fail "$name"; fi
}
sha() { # sha FILE: its SHA-256, in hex
  if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}
mode() { # mode FILE: its permission bits, in octal
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}
size() { # size FILE: its size in bytes
  wc -c <"$1" | tr -d ' '
}
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
rate() { # rate BYTES START END: MiB/s
  awk -v b="$1" -v s="$2" -v e="$3" 'BEGIN { d = e - s; if (d <= 0) d = 0.001; printf "%.0f MiB/s (%.1f s)", b / 1048576 / d, d }'
}
hwm() { # the program's peak RSS in KiB (Linux), or nothing
  awk '/^VmHWM:/ { print $2 }' "/proc/$pid/status" 2>/dev/null
}
saw() { # saw PATTERN: wait up to 30 s for a line of the program's output
  for _ in $(seq 1 300); do
    grep -q "$1" "$tmp/out.log" && return 0
    sleep 0.1
  done
  return 1
}

echo "== build"
if ! bend tests/oci_blob_echo.bend -o "$tmp/echo" >"$tmp/build.log" 2>&1; then
  cat "$tmp/build.log"
  echo "FAIL build tests/oci_blob_echo.bend"
  exit 1
fi
pass "build"

echo "== no arguments"
out=$("$tmp/echo" 2>&1)
check "native lane: OciBlob.open of a missing file answers ENOENT" \
  grep -qx 'PASS oci_blob_echo: OciBlob.open answers ENOENT (native lane)' <<<"$out"

echo "== certificate"
ossl() { openssl "$@" >>"$tmp/openssl.log" 2>&1; }
ec="-newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes"
# shellcheck disable=SC2086
ossl req -x509 $ec -keyout "$tmp/ca.key" -out "$tmp/ca.pem" -days 2 -subj "/CN=oci-blob-test-ca"
# shellcheck disable=SC2086
ossl req $ec -keyout "$tmp/server.key" -out "$tmp/server.csr" -subj "/CN=127.0.0.1"
printf 'subjectAltName=IP:127.0.0.1\nextendedKeyUsage=serverAuth\n' >"$tmp/server.ext"
ossl x509 -req -in "$tmp/server.csr" -CA "$tmp/ca.pem" -CAkey "$tmp/ca.key" -CAcreateserial \
  -days 2 -out "$tmp/server.pem" -extfile "$tmp/server.ext"
if [ -s "$tmp/server.pem" ]; then pass "certificate"; else cat "$tmp/openssl.log"; fail "certificate"; exit 1; fi

echo "== source ($gib GiB, sparse)"
half=524288
total=$((gib * 1073741824))
four=4294967296
src="$tmp/src.bin"
dd if=/dev/zero of="$src" bs=1 count=0 seek="$total" 2>/dev/null
put() { dd if=/dev/urandom of="$src" bs="$half" count="$2" seek="$1" conv=notrunc 2>/dev/null; }
put 0 2
if [ "$total" -gt "$four" ]; then
  put $((four / half - 1)) 2
  off=$((four - 1048576 - 7))
else
  off=$((total / 2 - 7))
fi
put $((total / half - 1)) 1
len=$((2097152 + 13))
check "the source is $total bytes" test "$(size "$src")" = "$total"
want=$(sha "$src")
echo "sha256 $want"

echo "== serve"
mkdir "$tmp/d"
port=$((20000 + RANDOM % 20000))
"$tmp/echo" "$port" "$tmp/d" "$src" "$tmp/server.pem" "$tmp/server.key" \
  $((total >> 32)) $((total & 4294967295)) $((off >> 32)) $((off & 4294967295)) \
  $((len >> 32)) $((len & 4294967295)) >"$tmp/out.log" 2>"$tmp/err.log" &
pid=$!
if ! saw '^ready$'; then
  cat "$tmp/out.log" "$tmp/err.log"
  fail "the program listens"
  exit 1
fi
pass "the program listens"
rss0=$(hwm)

echo "== fetch, plain"
t0=$(now)
got=$(
  exec 3<>"/dev/tcp/127.0.0.1/$port"
  cat "$src" >&3
  head -n 1 <&3
)
t1=$(now)
echo "INFO fetch plain: $(rate "$total" "$t0" "$t1")"
check "plain fetch: OciBlob.commit's digest is sha256sum's (got '$got')" test "$got" = "$want"
check "plain.blob matches the source" cmp -s "$src" "$tmp/d/plain.blob"
check "plain.blob has mode 600" test "$(mode "$tmp/d/plain.blob")" = 600
rm -f "$tmp/d/plain.blob"

echo "== fetch, TLS"
t0=$(now)
got=$(openssl s_client -connect "127.0.0.1:$((port + 1))" -quiet -CAfile "$tmp/ca.pem" \
  <"$src" 2>>"$tmp/s_client.log" | head -n 1)
t1=$(now)
echo "INFO fetch TLS: $(rate "$total" "$t0" "$t1")"
check "TLS fetch: OciBlob.commit's digest is sha256sum's (got '$got')" test "$got" = "$want"
check "tls.blob matches the source" cmp -s "$src" "$tmp/d/tls.blob"
rm -f "$tmp/d/tls.blob"

echo "== send, plain (sendfile on Linux)"
t0=$(now)
check "plain send: the whole file arrives" cmp -s "$src" - <"/dev/tcp/127.0.0.1/$((port + 2))"
t1=$(now)
echo "INFO send plain: $(rate "$total" "$t0" "$t1")"

echo "== send, TLS"
t0=$(now)
openssl s_client -connect "127.0.0.1:$((port + 3))" -quiet -CAfile "$tmp/ca.pem" \
  </dev/null 2>>"$tmp/s_client.log" | cmp -s "$src" -
st=$?
t1=$(now)
check "TLS send: the whole file arrives" test "$st" = 0
echo "INFO send TLS: $(rate "$total" "$t0" "$t1")"

echo "== send, a range from $off ($len bytes)"
tail -c +$((off + 1)) "$src" | head -c "$len" >"$tmp/range.want"
check "range send: the bytes arrive" cmp -s "$tmp/range.want" - <"/dev/tcp/127.0.0.1/$((port + 4))"

echo "== a stream that ends early"
(
  exec 3<>"/dev/tcp/127.0.0.1/$port"
  head -c 100000 "$src" >&3
)
check "a short stream fails the fetch with ECONNRESET" saw "^fetch failed: OciBlob: the peer closed before the blob's end"

echo "== the program's answers"
check "two fetches" test "$(grep -c '^fetched ' "$tmp/out.log")" = 2
check "three sends" test "$(grep -c '^sent$' "$tmp/out.log")" = 3
check "no other failure" test "$(grep -c 'failed' "$tmp/out.log")" = 1
if [ "$fails" -ne 0 ]; then cat "$tmp/out.log" "$tmp/err.log"; fi

rss1=$(hwm)
if [ -n "$rss1" ] && [ -n "$rss0" ]; then
  echo "INFO peak RSS: $rss0 KiB at start, $rss1 KiB at the end"
  check "peak RSS grows by less than 64 MiB" test $((rss1 - rss0)) -lt 65536
else
  echo "INFO peak RSS: not measured (no /proc)"
fi

if [ "$fails" -ne 0 ]; then
  echo "$fails FAILED"
  exit 1
fi
echo "ALL PASS"
