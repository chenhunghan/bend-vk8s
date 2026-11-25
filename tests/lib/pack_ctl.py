#!/usr/bin/env python3
"""A stand-in for a VM's control socket with a pack, for tests of the layer
filler's pack and drop lines (host/layers/serve.bend; tests/layers_serve.sh).

    pack_ctl.py SOCKET LOG IMAGE

Listens on the Unix socket SOCKET as bend-vmm's --control does: one line in,
one answer, close. Each line is appended to LOG. Answers, as bend-vmm
0x2324e729258ea5021b37b97947af4c3f words them (src/disk/pack.bend):
  pack add IMAGE     1048576 4096
  pack add other     error: cannot open other (errno 2)
  pack list          the pack's table on one line. Before the first add of
                     IMAGE: another file live at 0. After it: IMAGE also
                     live at 1048576 and at 3145728, and dropped at 2097152
  pack drop N        dropped
"""
import json
import os
import socket
import sys

path, log, image = sys.argv[1:4]
if os.path.exists(path):
    os.unlink(path)
srv = socket.socket(socket.AF_UNIX)
srv.bind(path)
srv.listen(16)
other = {"offset": 0, "length": 4096, "path": "/somewhere/else.sqfs", "live": True}
mine = [{"offset": 1048576, "length": 4096, "path": image, "live": True},
        {"offset": 2097152, "length": 4096, "path": image, "live": False},
        {"offset": 3145728, "length": 4096, "path": image, "live": True}]
added = False
while True:
    conn, _ = srv.accept()
    data = b""
    while not data.endswith(b"\n"):
        chunk = conn.recv(4096)
        if not chunk:
            break
        data += chunk
    line = data.decode().strip()
    if not line:
        # a peer that only connects (bend-vmm's client looks first)
        conn.close()
        continue
    with open(log, "a") as f:
        f.write(line + "\n")
    if line == "pack add " + image:
        answer = "1048576 4096"
        added = True
    elif line.startswith("pack add "):
        answer = "error: cannot open " + line[9:] + " (errno 2)"
    elif line == "pack list":
        table = {"name": "layers", "size": 4194304, "entries": [other] + (mine if added else [])}
        answer = json.dumps(table, separators=(",", ":"))
    elif line.startswith("pack drop "):
        answer = "dropped"
    else:
        answer = "error: unknown command"
    try:
        conn.sendall((answer + "\n").encode())
    except OSError:
        pass
    conn.close()
