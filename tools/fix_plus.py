#!/usr/bin/env python3
"""Runs `bend FILE --check-only` and, while it reports a variable "consumed
more than once", marks that binder reusable (`+x`) at the reported line, in
a def's parameter list or a pattern. Stops at any other error, which it
prints. Usage: tools/fix_plus.py FILE [MAX]"""
import re
import subprocess
import sys


def check(path):
    r = subprocess.run(["bend", path, "--check-only"], capture_output=True, text=True)
    return r.stdout + r.stderr


def main(path, limit):
    for _ in range(limit):
        out = check(path)
        m = re.search(r"observed : (\S+) \(consumed more than once\)", out)
        loc = re.search(r"Location: (\S+)\n(?:.*\n)*?\s*(\d+)>\|", out)
        if not m or not loc:
            print(out.strip().splitlines()[-1] if "ALL PROOFS CHECK" in out else out)
            return
        var, line = m.group(1), int(loc.group(2))
        lines = open(path).read().split("\n")
        src = lines[line - 1]
        pat = re.compile(r"(?<![\w.+\-~])" + re.escape(var) + r"(?=\s*[:,}\)])")
        new, n = pat.subn("+" + var, src, count=1)
        if n == 0:
            print("cannot place +%s on line %d:\n%s\n%s" % (var, line, src, out))
            return
        lines[line - 1] = new
        open(path, "w").write("\n".join(lines))
        print("+%s at %s:%d" % (var, path, line))
    print("stopped after", limit, "fixes")


if __name__ == "__main__":
    main(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 40)
