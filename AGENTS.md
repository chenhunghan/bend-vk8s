When using Bend:
- run `bend guide` to learn it
- use `LAWS.bend` to keep important rules
- run `bend PROOF.bend` before committing
- parallelize the code whenever possible

# bend-vk8s

A rewrite of loft-sh/vcluster in Bend that runs virtual Kubernetes clusters
in bend-vmm microVMs (not Docker). Read docs/DESIGN.md before your first
change. `vcluster/` (git-ignored; `git clone --depth 1
https://github.com/loft-sh/vcluster`) is the reference: match its behavior
and quote its tests, but not its Go structure.

## Layout

- `src/`: pure Bend, every decision, no IO.
- `host/`: IO: processes, files, sockets, TLS server effects, and the
  bend-kube-runtime client.
- `laws/<module>.bend`: the spec of each module, as Bend laws.
- `proofs/<module>.bend`: one proof per law, `def L.<law>`.
- `LAWS.bend`, `PROOF.bend`: gather every laws/proofs file.
- `tests/<name>.bend`: executable tests; each prints PASS/FAIL lines.
- `laws/done/<module>`: marker that the module's laws all prove.
- `scripts/check.sh`: the gate (typing, ratchet, tests). CI runs it.

## Rules

1. Laws are the spec and the architect owns them. Never edit, weaken or
   delete an existing law in `laws/`. You may add new laws under a
   `# Proposed:` comment at the end of a file; say so in the PR.
2. Test files headed `FROZEN SPEC` are spec too. Do not edit them.
3. A contract in `src/` (types, def names and signatures that a law or a
   frozen test uses) is fixed. Fill the `?TODO` bodies, and add as many
   helper defs as you like. If a contract is wrong, stop and say why in the
   PR instead of working around it.
4. Prove every law of your module in `proofs/<module>.bend`. When it prints
   ALL PROOFS CHECK, add `laws/done/<module>` in the same PR. If a general
   law resists a real attempt, leave it open, skip the marker, and explain
   in the PR what blocks it.
5. `scripts/check.sh` must pass before you push.
6. Never use `@unsafe` (or `?`-suffixed defs) in `src/`. Only `host/` may.
7. Parallelize where the work splits evenly (independent objects,
   resources, list halves) with a parallel let, keeping both sides balanced.
8. Expected values in concrete laws come from vcluster's Go code or tests
   (run the Go if needed). Never derive them from your own Bend code.

## Bend facts that bite (2.0.40)

- No hex literals, no U64, no U8. Bytes are `+List<U32>`.
- Variables are affine. Write `+x` to reuse a Data value.
- `match` takes only parameters or pattern-bound variables. Branch on a
  computed value through a helper def.
- Defs are declared before use, with no mutual recursion. Recursion must
  shrink an argument (left to right). Loops over outside data take `Nat`
  fuel first.
- Operators need a type: `(a + b : U32)`.
- `for s: T where P` binds s to a pair. For a hypothesis, use a separate
  `for h: {P}` parameter.
- See ~/bend-vmm/AGENTS.md and ~/bend-kube for more patterns. bend-kube
  (BendHub `bend-kube-runtime`) is our Kubernetes client.
