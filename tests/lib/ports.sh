# Ports for test servers. Source it: . tests/lib/ports.sh  (needs python3)
#
# A test server's port must be below 32768: Linux gives client sockets
# ports from 32768-60999 (macOS from 49152), so a fixed or random port in
# that range can already be a client socket's, and the server's bind then
# fails with "Address already in use".
#
#   ports_free PORT...       a server can listen on each of them now: bind
#                            with SO_REUSEADDR and listen, on 127.0.0.1 and
#                            on 0.0.0.0, as etcd or an API server does (a
#                            listener or a client socket on the port fails
#                            it; a closed server's TIME_WAIT does not)
#   ports_pick N             prints a base whose N consecutive ports
#                            base..base+N-1 are all free; the base is random
#                            in PORTS_LO..PORTS_HI (default 11000-14999, a
#                            range no test uses with fixed ports)
#   port_listens PORT        something accepts on 127.0.0.1:PORT now
#   port_wait PORT SECONDS [PID]
#                            waits until 127.0.0.1:PORT accepts; fails after
#                            SECONDS, or at once when PID has exited
#
# Fixed ports in tests/ (keep new ones apart, and below 32768):
#   syncer_envtest.sh       20379 20380 20443  21379 21380 21443
#                           24379 24380 24443  25379 25380 25443  10269
#   syncer_load_envtest.sh  22379 22380 26443  23379 23380 27443  10279
#   layers_serve.sh, cache_mirror.sh, smoke-linux.sh  15001-15004 15443
#   nodehost_smoke.sh       16401 16402

ports_free() {
  python3 -I -c '
import socket, sys
for p in sys.argv[1:]:
    for addr in ("127.0.0.1", "0.0.0.0"):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            s.bind((addr, int(p)))
            s.listen(1)
        except OSError:
            sys.exit(1)
        finally:
            s.close()
' "$@"
}

ports_pick() {
  local n=${1:-1} lo=${PORTS_LO:-11000} hi=${PORTS_HI:-14999} base i try ports
  for ((try = 0; try < 100; try++)); do
    # two RANDOMs: one has only 15 bits
    base=$((lo + (RANDOM * 32768 + RANDOM) % (hi - lo - n + 2)))
    ports=()
    for ((i = 0; i < n; i++)); do ports+=($((base + i))); done
    if ports_free "${ports[@]}"; then echo "$base"; return 0; fi
  done
  echo "ports_pick: no $n free consecutive ports in $lo-$hi" >&2
  return 1
}

port_listens() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

port_wait() {
  local port=$1 secs=$2 pid=${3:-} i
  for ((i = 0; i < secs * 10; i++)); do
    port_listens "$port" && return 0
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then return 1; fi
    sleep 0.1
  done
  return 1
}
