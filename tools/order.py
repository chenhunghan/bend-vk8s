#!/usr/bin/env python3
"""Reorders a Bend file's top-level blocks so every def comes after the defs
it calls (Bend binds defs in order). Imports, types and laws keep their
places; defs fill the def slots in dependency order, each with the comment
lines above it. Ties keep the file's order. Usage: tools/order.py FILE..."""
import re
import sys

HEAD = re.compile(r"^(@unsafe def|def|type|law|import) ")
NAME = re.compile(r"^(?:@unsafe )?(?:def|type|law) ([A-Za-z0-9_.?]+)")
WORD = re.compile(r"[A-Za-z_][A-Za-z0-9_.?]*")
STR = re.compile(r'"(?:[^"\\]|\\.)*"')


def blocks(text):
    out, pend, cur = [], [], None
    for line in text.splitlines():
        if HEAD.match(line):
            if cur is not None:
                out.append(cur)
            cur = pend + [line]
            pend = []
        elif line.startswith("#") or line == "":
            if cur is not None and line == "" or cur is None:
                pend.append(line)
            else:
                pend.append(line)
        else:
            if cur is None:
                pend.append(line)
            else:
                cur.extend(pend + [line])
                pend = []
    if cur is not None:
        out.append(cur)
    return out, pend


def head(b):
    for line in b:
        if HEAD.match(line):
            return line
    return ""


def main(path):
    text = open(path).read()
    bs, tail = blocks(text)
    imports = [b for b in bs if head(b).startswith("import ")]
    types = [b for b in bs if re.match(r"^(type|law) ", head(b))]
    defs = [b for b in bs if b not in imports and b not in types]
    names = {}
    for i, b in enumerate(defs):
        m = NAME.match(head(b))
        names[m.group(1)] = i
    deps = []
    for i, b in enumerate(defs):
        body = "\n".join(l for l in b if not l.lstrip().startswith("#"))
        body = STR.sub('""', body)
        ds = set()
        for w in WORD.findall(body):
            for cand in (w, w.rstrip(".")):
                j = names.get(cand)
                if j is not None and j != i:
                    ds.add(j)
        deps.append(ds)
    done, order = set(), []

    def visit(i, stack):
        if i in done:
            return
        if i in stack:
            sys.exit("cycle through " + head(defs[i]))
        stack.add(i)
        for j in sorted(deps[i]):
            visit(j, stack)
        stack.discard(i)
        done.add(i)
        order.append(i)

    for i in range(len(defs)):
        visit(i, set())
    it = iter(order)
    parts = [defs[next(it)] if b in defs else b for b in bs]
    res = ""
    for i, b in enumerate(parts):
        both = i > 0 and head(b).startswith("import ") and head(parts[i - 1]).startswith("import ")
        text = "\n".join(b).strip("\n") + "\n" if both else "\n".join(b).rstrip("\n") + "\n"
        res += ("" if i == 0 or both else "\n") + text
    res = re.sub(r"\n{3,}", "\n\n", res)
    open(path, "w").write(res.rstrip("\n") + "\n" + "\n".join(tail).rstrip())


if __name__ == "__main__":
    for p in sys.argv[1:]:
        main(p)
