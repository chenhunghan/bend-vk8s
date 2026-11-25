#!/usr/bin/env bash
# A VM node's extras for a host-integrated workload (vk8s create --mount,
# --host-socket, --node-setup; src/cli/extras.bend, src/guest/extras.bend,
# host/host_socket.bend), on macOS in VM mode, against one real cluster:
#
#   - a read-only mount of a folder and a writable mount of a sub-folder,
#     at the same absolute paths in the node; pods use them as hostPath
#     volumes, as this user's uid, as root and as another uid
#   - a static Linux binary (busybox) runs from the read-only mount
#   - a Unix socket of the node that reaches a stand-in server on the Mac
#     (a socket under a path with a space), mounted into a pod as hostPath
#     type Socket: a line and its echo, a client that half-closes, 1 MiB,
#     three connections at once, and the server sees each one close
#   - a setup script from the mount: a marker under /etc, a directory and
#     a link under /var/lib, a shim in /usr/local/bin and a containerd
#     drop-in for the runtime handler `extra`; a RuntimeClass extra pod runs
#   - all of it again after vk8s pause and resume, and after create
#     --upgrade (the script ran again)
#   - delete leaves no process and no cluster directory (so no vsock
#     socket or link), and the host's own socket stays
#
# usage: tests/node_extras.sh
# Environment: VK8S (default out/vk8s), VK8S_ASSETS (a local guest build),
# NAME (default nx-<pid>), BUSYBOX (a static Linux busybox for this arch,
# default out/build/busybox). Needs kubectl, python3 and zig (the test's
# socket client is built for Linux). Its files stay under out/nx and are
# removed at the end; the cluster lives in the real ~/.vk8s.
# Prints PASS/FAIL lines; exits 1 on any FAIL.
set -uo pipefail
cd "$(dirname "$0")/.."
[ "$(uname -s)" = Darwin ] || { echo "SKIP tests/node_extras.sh runs on macOS (VM mode)"; exit 0; }
vk8s=${VK8S:-$PWD/out/vk8s}
case $vk8s in /*) ;; *) vk8s=$PWD/$vk8s ;; esac
name=${NAME:-nx-$$}
bb=${BUSYBOX:-out/build/busybox}
for t in kubectl python3 zig; do command -v $t >/dev/null || { echo "FAIL $t is missing"; exit 1; }; done
[ -x "$vk8s" ] || { echo "FAIL $vk8s is missing (scripts/build-mac.sh out/vk8s)"; exit 1; }
[ -f "$bb" ] || { echo "FAIL $bb is missing (a static Linux busybox; scripts/guest/build.sh fetches one)"; exit 1; }

work=$PWD/out/nx
root=$work/home            # the read-only mount
rw=$root/work              # the writable mount, inside it
app="$work/app support"    # the host socket's directory: a space in it
sock="$app/x.sock"
uid=$(id -u) gid=$(id -g)
gsock=/run/user/$uid/x.sock
dir=$HOME/.vk8s/clusters/$name
kc=$dir/kubeconfig.yaml
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
t() { local what=$1; shift; if "$@" >/dev/null 2>&1; then pass "$what"; else fail "$what"; fi; }
k() { kubectl --kubeconfig "$kc" --request-timeout=60s "$@"; }

srv=
cleanup() {
  "$vk8s" delete "$name" >/dev/null 2>&1
  [ -n "$srv" ] && kill "$srv" 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT
rm -rf "$work"
mkdir -p "$root/bin" "$rw" "$app"
echo "hello from the host" > "$root/hello.txt"
cp "$bb" "$root/bin/busybox"

# The socket client, for Linux: sockc PATH line|half|big TEXT
#   line: sends TEXT and a newline, prints the one line that comes back
#   half: sends TEXT and a newline, shuts its write side down, prints
#         everything up to the end
#   big:  sends TEXT bytes (a number), shuts its write side down, prints
#         everything up to the end
cat > "$work/sockc.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
static int put(int fd, const char* p, size_t n) {
  while (n > 0) { ssize_t w = write(fd, p, n); if (w <= 0) return -1; p += w; n -= (size_t)w; }
  return 0;
}
int main(int argc, char** argv) {
  if (argc != 4) return 2;
  struct sockaddr_un a; memset(&a, 0, sizeof a); a.sun_family = AF_UNIX;
  strncpy(a.sun_path, argv[1], sizeof a.sun_path - 1);
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0 || connect(fd, (struct sockaddr*)&a, sizeof a) != 0) { perror("connect"); return 1; }
  char buf[65536];
  if (strcmp(argv[2], "big") == 0) {
    long n = atol(argv[3]);
    memset(buf, 'x', sizeof buf);
    while (n > 0) { size_t m = n > (long)sizeof buf ? sizeof buf : (size_t)n; if (put(fd, buf, m) != 0) { perror("write"); return 1; } n -= (long)m; }
  } else {
    if (put(fd, argv[3], strlen(argv[3])) != 0 || put(fd, "\n", 1) != 0) { perror("write"); return 1; }
  }
  if (strcmp(argv[2], "line") != 0) shutdown(fd, SHUT_WR);
  for (;;) {
    ssize_t r = read(fd, buf, sizeof buf);
    if (r < 0) { perror("read"); return 1; }
    if (r == 0) break;
    fwrite(buf, 1, (size_t)r, stdout);
    if (strcmp(argv[2], "line") == 0 && memchr(buf, '\n', (size_t)r)) break;
  }
  fflush(stdout);
  close(fd);
  return 0;
}
EOF
zig cc -target aarch64-linux-musl -static -O2 -s "$work/sockc.c" -o "$root/bin/sockc" 2>"$work/zig.log" \
  || { cat "$work/zig.log"; echo "FAIL could not build the socket client"; exit 1; }

# The stand-in for the host's server: each line comes back with a prefix;
# at the client's end-of-file it answers with the bytes it read, then
# closes. It logs every open and close.
cat > "$work/server.py" <<'EOF'
import os, socket, sys, threading
d, logf = sys.argv[1], sys.argv[2]
os.chdir(d)                      # bind by a short name: the path may be long
try:
    os.unlink("x.sock")
except FileNotFoundError:
    pass
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind("x.sock")
s.listen(64)
lock = threading.Lock()
def log(m):
    with lock:
        with open(logf, "a") as f:
            f.write(m + "\n")
def serve(c):
    log("open")
    n, pend = 0, b""
    try:
        while True:
            b = c.recv(65536)
            if not b:
                break
            n += len(b)
            pend += b
            while b"\n" in pend:
                line, pend = pend.split(b"\n", 1)
                log("line " + line.decode("utf-8", "replace"))
                c.sendall(b"echo: " + line + b"\n")
            if len(pend) > 4096:
                pend = b""
        c.sendall(b"eof: %d\n" % n)
    except OSError:
        pass
    c.close()
    log("close")
log("ready")
while True:
    c, _ = s.accept()
    threading.Thread(target=serve, args=(c,), daemon=True).start()
EOF
python3 "$work/server.py" "$app" "$work/server.log" &
srv=$!
for i in $(seq 50); do [ -S "$sock" ] && break; sleep 0.1; done
t "the stand-in server listens on a path with a space" test -S "$sock"

# The setup script, in the read-only mount. It runs as root in the node
# at every boot, before containerd starts.
cat > "$root/setup.sh" <<EOF
#!/bin/sh
set -e
echo "node setup as uid \$(id -u)"
echo marker > /etc/node-extras-marker
mkdir -p /var/lib/extra/data
ln -sfn /var/lib/extra/data /var/lib/extra/link
echo data > /var/lib/extra/link/file
cp /var/lib/vcluster/bin/containerd-shim-runc-v2 /usr/local/bin/containerd-shim-extra-v2
cat > /etc/containerd/conf.d/extra.toml <<TOML
version = 3
[plugins."io.containerd.cri.v1.runtime".containerd.runtimes.extra]
  runtime_type = "io.containerd.extra.v2"
  pod_annotations = ["example.run/*"]
TOML
# root in the node reaches the host's socket too
$root/bin/sockc $gsock line "setup as \$(id -u)"
date +%s >> $rw/boots
EOF

echo "== create"
"$vk8s" create "$name" --connect=false --idle-sleep 0 --mount "$root" --mount "$rw:rw" \
  --host-socket "$gsock=$sock" --node-setup "$root/setup.sh" 2>&1 | tee "$work/create.log"
t "create succeeded" grep -q "Successfully created" "$work/create.log"
t "create printed no setup warning" bash -c "! grep -q 'node setup script' '$work/create.log'"
t "cluster.env records the read-only mount" grep -qx "MOUNT_0=ro:$root" "$dir/cluster.env"
t "cluster.env records the writable mount" grep -qx "MOUNT_1=rw:$rw" "$dir/cluster.env"
t "cluster.env records the host socket" grep -qx "HOST_SOCKET_0=$gsock=$sock" "$dir/cluster.env"
t "cluster.env records the setup script" grep -qx "NODE_SETUP=$root/setup.sh" "$dir/cluster.env"
t "the vsock link points at the host socket" test "$(readlink "$dir/vsock_100")" = "$sock"
t "the setup script's exit code is 0 in the share" grep -qx 0 "$dir/share/node-setup.exit"
t "the setup script's output is in the node's logs" grep -q "node setup as uid 0" "$dir/share/logs/node-setup.log"
t "root in the node reached the host socket" grep -q "echo: setup as 0" "$dir/share/logs/node-setup.log"

k wait --for=condition=Ready node --all --timeout=240s >/dev/null 2>&1
for i in $(seq 60); do k get serviceaccount default >/dev/null 2>&1 && break; sleep 2; done
k apply -f - >/dev/null <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: extra
handler: extra
EOF

# pod NAME USER SCRIPT [RUNTIMECLASS]: a pod of the node's own pause image
# (no pull) whose command is the busybox of the read-only mount. USER is
# "uid:gid" (the pause image's own user is 65535). Both mounts, the socket, /etc and /var/lib are
# hostPath volumes.
pod() {
  local pname=$1 user=$2 script=$3 rc=${4:-} sc="" rcl=""
  sc="securityContext: {runAsUser: ${user%:*}, runAsGroup: ${user#*:}}"
  [ -n "$rc" ] && rcl="runtimeClassName: $rc"
  k apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $pname
  annotations:
    example.run/kind: test
spec:
  restartPolicy: Never
  terminationGracePeriodSeconds: 1
  $rcl
  $sc
  containers:
  - name: c
    image: registry.k8s.io/pause:3.10.2
    imagePullPolicy: Never
    command: ["$root/bin/busybox", "sh", "-c", $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$script")]
    volumeMounts:
    - {name: ro, mountPath: "$root"}
    - {name: rw, mountPath: "$rw"}
    - {name: sock, mountPath: /sock/x.sock}
    - {name: etc, mountPath: /node-etc/marker}
    - {name: varlib, mountPath: /node-var}
  volumes:
  - name: ro
    hostPath: {path: "$root", type: Directory}
  - name: rw
    hostPath: {path: "$rw", type: Directory}
  - name: sock
    hostPath: {path: "$gsock", type: Socket}
  - name: etc
    hostPath: {path: /etc/node-extras-marker, type: File}
  - name: varlib
    hostPath: {path: /var/lib/extra, type: Directory}
EOF
}
# done_pod NAME: wait until the pod has finished; its log is in $work/NAME.log
done_pod() {
  local pname=$1 ph=""
  for i in $(seq 90); do
    ph=$(k get pod "$pname" -o jsonpath='{.status.phase}' 2>/dev/null)
    [ "$ph" = Succeeded ] || [ "$ph" = Failed ] && break
    sleep 1
  done
  k logs "$pname" > "$work/$pname.log" 2>&1
  # NX_DEBUG=FILE: every pod's log, and what kubectl says of one that failed
  if [ -n "${NX_DEBUG:-}" ]; then
    { echo "--- pod $pname: $ph"; cat "$work/$pname.log"; [ "$ph" = Succeeded ] || k describe pod "$pname" | tail -n 15; } >> "$NX_DEBUG" 2>&1
  fi
  [ "$ph" = Succeeded ]
}
has() { grep -qF -- "$2" "$work/$1.log"; }
closed() { [ "$(grep -c '^open$' "$work/server.log")" = "$(grep -c '^close$' "$work/server.log")" ]; }

# round TAG: every check against the running cluster. The pause image has
# no shell of its own: B is the busybox of the read-only mount.
round() {
  local r=$1 B=$root/bin/busybox
  echo "== round: $r"
  rm -f "$rw/from-pod-$r.txt" "$rw/from-root-$r.txt" "$rw/from-other-$r.txt" "$rw"/p[123]

  pod "m-$r" "$uid:$gid" "$B cat $root/hello.txt; (echo x > $root/ro-probe) 2>/dev/null && echo RO-WRITTEN || echo RO-REFUSED; echo \"pod $r as \$($B id -u):\$($B id -g)\" > $rw/from-pod-$r.txt && echo RW-WRITTEN; $B ls -ln $rw/from-pod-$r.txt; $B chmod 640 $rw/from-pod-$r.txt && $B ls -ln $rw/from-pod-$r.txt; echo exec-ok"
  t "$r: the mounts pod (uid $uid) finished" done_pod "m-$r"
  t "$r: the pod reads the host's file at the same path" has "m-$r" "hello from the host"
  t "$r: the pod cannot write the read-only mount" has "m-$r" "RO-REFUSED"
  t "$r: nothing was written to the read-only folder" test ! -e "$root/ro-probe"
  t "$r: the pod wrote the writable mount as uid $uid" has "m-$r" "RW-WRITTEN"
  t "$r: the file is on the Mac with the right content" test "$(cat "$rw/from-pod-$r.txt" 2>/dev/null)" = "pod $r as $uid:$gid"
  t "$r: the pod sees its file as owned by $uid:$gid" grep -qE " $uid +$gid " "$work/m-$r.log"
  t "$r: the pod's chmod reaches the Mac" test "$(stat -f %Lp "$rw/from-pod-$r.txt" 2>/dev/null)" = 640
  t "$r: a static Linux binary runs from the read-only mount" has "m-$r" "exec-ok"

  pod "o-$r" "0:0" "echo \"root $r\" > $rw/from-root-$r.txt && echo ROOT-WRITTEN; $B ls -ln $rw/from-root-$r.txt; (echo x > $root/ro-probe) 2>/dev/null && echo RO-WRITTEN || echo RO-REFUSED; $B cat /node-etc/marker; $B cat /node-var/data/file; $B readlink /node-var/link; $root/bin/sockc /sock/x.sock line 'root $r'"
  t "$r: the root pod finished" done_pod "o-$r"
  t "$r: root in a pod writes the writable mount" test "$(cat "$rw/from-root-$r.txt" 2>/dev/null)" = "root $r"
  t "$r: root's file belongs to $uid:$gid too (the Mac user owns everything)" grep -qE " $uid +$gid " "$work/o-$r.log"
  t "$r: root in a pod cannot write the read-only mount" has "o-$r" "RO-REFUSED"
  t "$r: the setup script's marker is under /etc" has "o-$r" "marker"
  t "$r: the setup script's directory and link are under /var/lib" bash -c "grep -qx data '$work/o-$r.log' && grep -qx /var/lib/extra/data '$work/o-$r.log'"
  t "$r: root in a pod gets the server's reply" has "o-$r" "echo: root $r"

  # another uid is "other" to the Mac user's files (mode 755 and 644)
  pod "x-$r" "1234:1234" "$B cat $root/hello.txt; (echo x > $rw/from-other-$r.txt) 2>/dev/null && echo OTHER-WRITTEN || echo OTHER-REFUSED"
  t "$r: the other-uid pod finished" done_pod "x-$r"
  t "$r: another uid reads what the mode lets others read" has "x-$r" "hello from the host"
  t "$r: another uid cannot write the Mac user's folder" has "x-$r" "OTHER-REFUSED"

  pod "s-$r" "$uid:$gid" "S=$root/bin/sockc; \$S /sock/x.sock line 'one $r'; \$S /sock/x.sock half 'half $r'; \$S /sock/x.sock big 1048576; for i in 1 2 3; do \$S /sock/x.sock half \"par \$i $r\" > $rw/p\$i & done; wait; $B cat $rw/p1 $rw/p2 $rw/p3"
  t "$r: the socket pod (uid $uid) finished" done_pod "s-$r"
  t "$r: a line through the socket comes back from the Mac" has "s-$r" "echo: one $r"
  t "$r: a client that shut its write side down still gets the reply" bash -c "grep -qF 'echo: half $r' '$work/s-$r.log' && grep -qx 'eof: $((6 + ${#r}))' '$work/s-$r.log'"
  t "$r: 1 MiB arrives whole" has "s-$r" "eof: 1048576"
  t "$r: three connections at once all answer" bash -c "[ \"\$(grep -c 'echo: par [123] $r' '$work/s-$r.log')\" = 3 ]"
  for i in $(seq 30); do closed && break; sleep 0.2; done
  t "$r: the server saw every connection close" closed

  pod "r-$r" "0:0" "echo rc-ok" extra
  t "$r: a RuntimeClass extra pod runs" done_pod "r-$r"
  t "$r: its container ran" has "r-$r" "rc-ok"
  k delete pod "m-$r" "o-$r" "x-$r" "s-$r" "r-$r" --wait=false >/dev/null 2>&1
}

round first
t "the setup script ran once" test "$(wc -l < "$rw/boots" | tr -d ' ')" = 1

echo "== pause, resume"
"$vk8s" pause "$name" >/dev/null 2>&1
sleep 3
"$vk8s" resume "$name" >/dev/null 2>&1
k wait --for=condition=Ready node --all --timeout=120s >/dev/null 2>&1
round resumed
t "the setup script did not run again for a resume" test "$(wc -l < "$rw/boots" | tr -d ' ')" = 1

echo "== create --upgrade"
"$vk8s" create "$name" --upgrade --connect=false --idle-sleep 0 2>&1 | tee "$work/upgrade.log"
t "the upgrade succeeded" grep -q "Successfully upgraded" "$work/upgrade.log"
t "the upgrade kept the mounts" grep -qx "MOUNT_1=rw:$rw" "$dir/cluster.env"
t "the upgrade kept the host socket" grep -qx "HOST_SOCKET_0=$gsock=$sock" "$dir/cluster.env"
t "the upgrade kept the setup script" grep -qx "NODE_SETUP=$root/setup.sh" "$dir/cluster.env"
t "the setup script ran again after the upgrade's reboot" test "$(wc -l < "$rw/boots" | tr -d ' ')" = 2
k wait --for=condition=Ready node --all --timeout=240s >/dev/null 2>&1
for i in $(seq 60); do k get serviceaccount default >/dev/null 2>&1 && break; sleep 2; done
round upgraded

echo "== delete"
pid=$(cat "$dir/vmm.pid" 2>/dev/null)
"$vk8s" delete "$name" 2>&1 | tail -n 1
t "the VM's process is gone" bash -c "! kill -0 '$pid' 2>/dev/null"
t "no process names the cluster's directory" bash -c "! pgrep -f '$dir/' >/dev/null"
t "the cluster's directory is gone (no vsock socket, no link)" test ! -e "$dir"
t "the host's own socket is still there" test -S "$sock"
t "the host's folder kept its files" test -f "$root/hello.txt"

if [ $fails = 0 ]; then echo "node_extras: all passed"; else echo "node_extras: $fails FAILED"; fi
[ $fails = 0 ]
