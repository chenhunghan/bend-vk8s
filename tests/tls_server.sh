#!/usr/bin/env bash
# The TLS server effects (host/effs/tls_server.c) end to end. It builds
# tests/tls_server_echo.bend natively, generates a CA, a server
# certificate, client certificates and a rogue CA with the openssl CLI,
# runs two servers (one that requires a client certificate, one that asks
# for none), and checks them with `openssl s_client` and `curl`:
# handshake and ALPN, client certificates required, verified and
# rejected, the subject reported, splice, many sequential connections,
# and no descriptor leak (/proc/<pid>/fd, Linux only).
#
# Needs bend, clang, openssl, curl. Prints PASS/FAIL lines; exits 1 on
# any FAIL.
set -uo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done
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

echo "== build"
if ! bend tests/tls_server_echo.bend -o "$tmp/echo" >"$tmp/build.log" 2>&1; then
  cat "$tmp/build.log"
  echo "FAIL build tests/tls_server_echo.bend"
  exit 1
fi
pass "build"

echo "== certificates"
ossl() { openssl "$@" >>"$tmp/openssl.log" 2>&1; }
ec="-newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes"
cd "$tmp"
# shellcheck disable=SC2086
ossl req -x509 $ec -keyout ca.key -out ca.pem -days 2 -subj "/CN=vk8s-test-ca"
# shellcheck disable=SC2086
ossl req -x509 $ec -keyout rogue.key -out rogue.pem -days 2 -subj "/CN=rogue-ca"
issue() { # issue NAME SUBJECT EXT CA
  # shellcheck disable=SC2086
  ossl req $ec -keyout "$1.key" -out "$1.csr" -subj "$2"
  printf '%b' "$3" >"$1.ext"
  ossl x509 -req -in "$1.csr" -CA "$4.pem" -CAkey "$4.key" -CAcreateserial \
    -days 2 -out "$1.pem" -extfile "$1.ext"
}
issue server "/CN=127.0.0.1" "subjectAltName=IP:127.0.0.1\nextendedKeyUsage=serverAuth" ca
issue kubelet "/O=system:masters/CN=kube-apiserver-kubelet-client" "extendedKeyUsage=clientAuth" ca
issue alice "/O=system:masters/O=dev, ops/CN=alice" "extendedKeyUsage=clientAuth" ca
issue mallory "/O=system:masters/CN=mallory" "extendedKeyUsage=clientAuth" rogue
cd - >/dev/null
if [ -s "$tmp/server.pem" ] && [ -s "$tmp/kubelet.pem" ] && [ -s "$tmp/mallory.pem" ]; then
  pass "certificates"
else
  cat "$tmp/openssl.log"; echo "FAIL certificates"; exit 1
fi

# Two servers: A requires a client certificate from ca.pem, B asks none.
base=$((20000 + RANDOM % 20000))
pa=$base
pb=$((base + 10))
start() { # start PORT CA LOG
  "$tmp/echo" "$1" "$tmp/server.pem" "$tmp/server.key" "$2" >"$3" 2>&1 &
  pids+=($!)
  for _ in $(seq 100); do
    grep -q '^ready' "$3" 2>/dev/null && return 0
    sleep 0.1
  done
  cat "$3"
  return 1
}
echo "== start"
if ! start "$pa" "$tmp/ca.pem" "$tmp/a.log"; then echo "FAIL start (client certificates)"; exit 1; fi
pid_a=${pids[0]}
if ! start "$pb" "" "$tmp/b.log"; then echo "FAIL start (no client certificates)"; exit 1; fi
pass "start"

ca=(--cacert "$tmp/ca.pem")
cert_of() { # cert_of NAME: curl's client certificate options
  echo "--cert $tmp/$1.pem --key $tmp/$1.key"
}
whoami() { # whoami PORT [curl options...]
  local port=$1; shift
  curl -sS --max-time 10 "${ca[@]}" "$@" "https://127.0.0.1:$port/whoami" 2>&1
}
# s_client -quiet reads until the server closes (stdin's end does not end
# it), so the input ends with "BYE\n", after which the echo and the
# backend close. sclient prints what came back, less that last line.
sclient_raw() { # sclient_raw PORT INPUT [s_client options...]
  local port=$1 input=$2; shift 2
  printf '%s' "$input" | timeout 10 openssl s_client -connect "127.0.0.1:$port" \
    -CAfile "$tmp/ca.pem" -verify_return_error -quiet "$@" 2>/dev/null
}
sclient() { # sclient PORT INPUT [s_client options...]
  local port=$1 input=$2 out; shift 2
  out=$(sclient_raw "$port" "$input"$'\nBYE\n' "$@")
  printf '%s' "${out%$'\n'BYE}"
}

echo "== handshake"
out=$(printf 'Q\n' | timeout 10 openssl s_client -connect "127.0.0.1:$pb" -CAfile "$tmp/ca.pem" \
  -verify_return_error -alpn http/1.1 2>&1)
check "handshake verifies the server certificate" grep -q 'Verify return code: 0 (ok)' <<<"$out"
check "ALPN selects http/1.1" grep -q 'ALPN protocol: http/1.1' <<<"$out"
refused() { ! printf 'Q\n' | timeout 10 openssl s_client -connect "127.0.0.1:$pb" \
  -CAfile "$tmp/ca.pem" -tls1_1 >/dev/null 2>&1; }
check "TLS 1.1 refused" refused

echo "== echo"
out=$(sclient "$pb" "hello over tls")
check "s_client echo" test "$out" = "hello over tls"
out=$(sclient "$pa" "hello with a certificate" -cert "$tmp/kubelet.pem" -key "$tmp/kubelet.key")
check "s_client echo with a client certificate" test "$out" = "hello with a certificate"

echo "== client certificates"
# shellcheck disable=SC2046
out=$(whoami "$pa" $(cert_of kubelet))
check "curl with a verified client certificate" grep -q '^cn=kube-apiserver-kubelet-client$' <<<"$out"
check "subject reported (RFC 4514)" grep -qx 'subject=CN=kube-apiserver-kubelet-client,O=system:masters' <<<"$out"
check "groups reported" grep -qx 'o=system:masters' <<<"$out"
# shellcheck disable=SC2046
out=$(whoami "$pa" $(cert_of alice))
check "escaped subject reported" grep -qx 'subject=CN=alice,O=dev\\, ops,O=system:masters' <<<"$out"
check "groups in certificate order" test "$(grep '^o=' <<<"$out" | tr '\n' ';')" = "o=system:masters;o=dev, ops;"
out=$(sclient_raw "$pa" $'GET /whoami HTTP/1.0\r\n\r\n' -cert "$tmp/kubelet.pem" -key "$tmp/kubelet.key")
check "s_client subject reported" grep -q '^cn=kube-apiserver-kubelet-client' <<<"$out"
out=$(whoami "$pa")
check "no client certificate: rejected" bash -c '! grep -q "^cn=" <<<"$1"' _ "$out"
# shellcheck disable=SC2046
out=$(whoami "$pa" $(cert_of mallory))
check "client certificate from another CA: rejected" bash -c '! grep -q "^cn=" <<<"$1"' _ "$out"
check "rejections logged" grep -q 'handshake: .*(errno 13)' "$tmp/a.log"
out=$(whoami "$pb")
check "no client certificate asked: peer reports none" grep -q '^no client certificate' <<<"$out"

echo "== splice"
out=$(sclient $((pb + 1)) "spliced bytes")
check "splice TLS to plain and back" test "$out" = "SPLICED BYTES"
big=$(head -c 300000 /dev/zero | tr '\0' 'x')
out=$(sclient $((pb + 1)) "$big")
check "splice 300000 bytes" test "$out" = "$(tr x X <<<"$big")"
out=$(sclient $((pa + 1)) "with a certificate" -cert "$tmp/kubelet.pem" -key "$tmp/kubelet.key")
check "splice behind a client certificate" test "$out" = "WITH A CERTIFICATE"

echo "== many sequential connections"
fds() { ls "/proc/$pid_a/fd" 2>/dev/null | wc -l; }
before=$(fds)
ok=0
n=40
for i in $(seq $n); do
  # shellcheck disable=SC2046
  o1=$(whoami "$pa" $(cert_of kubelet))
  o2=$(sclient "$pa" "ping $i" -cert "$tmp/kubelet.pem" -key "$tmp/kubelet.key")
  o3=$(sclient $((pa + 1)) "splice $i" -cert "$tmp/kubelet.pem" -key "$tmp/kubelet.key")
  whoami "$pa" >/dev/null # rejected
  if grep -q '^cn=kube-apiserver-kubelet-client$' <<<"$o1" && [ "$o2" = "ping $i" ] && [ "$o3" = "SPLICE $i" ]; then
    ok=$((ok + 1))
  fi
done
check "$n rounds of whoami, echo, splice and a rejection ($ok ok)" test "$ok" = "$n"
check "server A still running" kill -0 "$pid_a"
if [ -d "/proc/$pid_a/fd" ]; then
  sleep 0.5
  after=$(fds)
  check "no descriptor leak ($before open before, $after after)" test "$after" -le "$before"
else
  echo "skip: no /proc, no descriptor count"
fi

if [ "$fails" -ne 0 ]; then
  echo "== server A log"; tail -20 "$tmp/a.log"
  echo "== server B log"; tail -20 "$tmp/b.log"
  echo "$fails FAILED"
  exit 1
fi
echo "ALL PASS"
