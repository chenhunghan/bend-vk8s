#!/usr/bin/env bash
# The push gate: `bend PROOF.bend`, scripts/check.sh, and the kernel's
# verdict (`bend --verdict`, what CI's verdict job runs over every module)
# on the modules whose laws or proofs differ from origin/main. The verdict
# on all modules takes too long for every push; a law that the checker
# accepts but the kernel runs out of fuel on is nearly always a new one.
#
#   scripts/gate.sh            prints GATE PASS, or GATE FAIL and why
#   BASE=<ref> scripts/gate.sh compare against another ref
#
# Logs go to out/gate-*.log. The verdict needs Lean (~/.elan); without it
# the step is skipped and the last line says so.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.bend/bin:$HOME/.elan/bin:/opt/homebrew/opt/e2fsprogs/sbin:$PATH"
mkdir -p out
base=${BASE:-origin/main}

bend PROOF.bend > out/gate-proof.log 2>&1; p=$?
grep -q '^ALL PROOFS CHECK' out/gate-proof.log || { echo "GATE FAIL: PROOF (exit $p)"; tail -15 out/gate-proof.log; exit 1; }

scripts/check.sh > out/gate-check.log 2>&1; c=$?
{ [ $c = 0 ] && grep -q 'CHECK OK' out/gate-check.log; } || { echo "GATE FAIL: check.sh (exit $c)"; grep -v 'ok\|done:\|compiles' out/gate-check.log | tail -25; exit 1; }

# modules touched: committed since the base, staged, unstaged and untracked
mods=$( { git diff --name-only "$base" -- laws proofs 2>/dev/null
          git ls-files --others --exclude-standard -- laws proofs; } |
        sed -nE 's#^(laws|proofs)/([^/]*)\.bend$#\2#p' | sort -u)
note=""
if [ -n "$mods" ]; then
  if command -v lean >/dev/null 2>&1; then
    : > out/gate-verdict.log
    for m in $mods; do
      [ -f "proofs/$m.bend" ] || continue
      out=$(bend "proofs/$m.bend" --verdict 2>&1)
      echo "== $m"$'\n'"$out" >> out/gate-verdict.log
      grep -q '^ALL PROOFS CHECK' <<<"$out" || { echo "GATE FAIL: verdict of proofs/$m.bend"; echo "$out" | tail -15; exit 1; }
    done
    note=" (verdict: $(echo $mods))"
  else
    note=" (verdict SKIPPED, no lean on PATH: $(echo $mods))"
  fi
fi
echo "GATE PASS$note"
