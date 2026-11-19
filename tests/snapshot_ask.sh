#!/usr/bin/env bash
# The node snapshotter's ask to the host's layer filler
# (host/snapshot_ask.bend, work item W6 of
# docs/ref/explore-layers-autofill.md) end to end, against a fake
# filler. It builds tests/snapshot_ask_echo.bend natively and runs it
# against a small TCP server (python3, test glue only) that records the
# ask's line and answers as each case says:
#
#   published  "ok published\n"
#   no         "no store full\n"
#   junk       a line that is not a reply
#   split      "ok present\n" in three writes
#   silent     reads the ask, answers nothing, closes after 3 s
#   refused    nothing listens on the port
#
# Every case but the two replies must come back as "no reply", which the
# snapshotter treats as a "no": it probes the store again and unpacks on
# the node, so a pull never fails because of the ask.
#
# Needs bend, clang, python3. Prints PASS/FAIL lines; exits 1 on any FAIL.
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

echo "== build"
if ! bend tests/snapshot_ask_echo.bend -o "$tmp/echo" >"$tmp/build.log" 2>&1; then
  cat "$tmp/build.log"
  echo "FAIL build tests/snapshot_ask_echo.bend"
  exit 1
fi
pass "build"

echo "== no arguments"
out=$("$tmp/echo" 2>&1)
if grep -qx 'PASS snapshot_ask_echo: a refused ask comes back as no reply' <<<"$out"; then
  pass "native lane: a refused ask comes back as no reply"
else
  fail "native lane: a refused ask: $out"
fi

cat >"$tmp/filler.py" <<'EOF'
import socket, sys, time
mode, portfile, linefile = sys.argv[1], sys.argv[2], sys.argv[3]
srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", 0))
srv.listen(4)
with open(portfile + ".tmp", "w") as f:
    f.write(str(srv.getsockname()[1]))
import os
os.rename(portfile + ".tmp", portfile)
c, _ = srv.accept()
buf = b""
while not buf.endswith(b"\n") and len(buf) < 1024:
    b = c.recv(1024)
    if not b:
        break
    buf += b
with open(linefile, "wb") as f:
    f.write(buf)
if mode == "published":
    c.sendall(b"ok published\n")
elif mode == "no":
    c.sendall(b"no store full\n")
elif mode == "junk":
    c.sendall(b"HTTP/1.0 400 Bad Request\n")
elif mode == "split":
    for part in (b"ok ", b"pres", b"ent\n"):
        c.sendall(part)
        time.sleep(0.2)
elif mode == "silent":
    time.sleep(3)
time.sleep(0.2)
c.close()
EOF

want_line="ask docker.io library/nginx sha256:e6693c20186f837fc393390135d8a598a96a833917917789d63766cab6c59582 sha256:9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0 sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1"

# run MODE MS WANT: a fake filler in MODE, the ask with a wait of MS ms;
# the program must print WANT and the filler must have read the ask.
run() {
  local mode=$1 ms=$2 want=$3
  rm -f "$tmp/port" "$tmp/line"
  python3 "$tmp/filler.py" "$mode" "$tmp/port" "$tmp/line" &
  pids+=($!)
  for _ in $(seq 1 100); do [ -s "$tmp/port" ] && break; sleep 0.05; done
  local port t0 t1 got
  port=$(cat "$tmp/port")
  t0=$(date +%s%N)
  got=$(timeout 30 "$tmp/echo" 127.0.0.1 "$port" "$ms" 2>&1)
  t1=$(date +%s%N)
  if [ "$got" = "said: $want" ]; then pass "$mode: said: $want"; else fail "$mode: got '$got', want 'said: $want'"; fi
  if [ "$(cat "$tmp/line" 2>/dev/null)" = "$want_line" ]; then
    pass "$mode: the filler read the ask's line"
  else
    fail "$mode: the filler read '$(cat "$tmp/line" 2>/dev/null)'"
  fi
  echo "   ($mode: $(((t1 - t0) / 1000000)) ms)"
}

echo "== replies"
run published 10000 "ok published"
run no 10000 "no store full"
run split 10000 "ok present"

echo "== no reply"
run junk 10000 "no reply: the filler's answer is not a reply line"
run silent 1000 "no reply: no reply within 1000 ms"

echo "== refused"
# A port that was just free: bind, read it, close.
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
got=$(timeout 30 "$tmp/echo" 127.0.0.1 "$port" 10000 2>&1)
case "$got" in
  "said: no reply: connecting to the filler: "*) pass "refused: $got" ;;
  *) fail "refused: got '$got'" ;;
esac

echo
if [ "$fails" = 0 ]; then echo "ALL PASS"; else echo "$fails FAILED"; exit 1; fi
