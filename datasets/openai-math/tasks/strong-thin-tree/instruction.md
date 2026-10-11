# openai/math challenge `StrongThinTree` (family 174)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 174 of the release, *Deterministic construction of strong thin spanning trees*
(Combinatorics). The family as a whole: Resolves the strong thin-tree conjecture constructively. Every finite loopless $k$-edge-connected multigraph on at least two vertices has a spanning tree containing at most a universal $C/k$ fraction of the edges of every cut. Such a tree can be found deterministically in polynomial time, even with binary-encoded parallel-edge multiplicities.

The challenge is `StrongThinTree`, also at `/opt/openai-math/challenges/StrongThinTree.lean`:

```lean
import Mathlib

namespace OAI

namespace StrongThinTree

structure MultiGraph (n m : ℕ) where
  left : Fin m → Fin n
  right : Fin m → Fin n
  loopless : ∀ e, left e ≠ right e

namespace MultiGraph

def cut {n m : ℕ} (G : MultiGraph n m) (T : Finset (Fin m))
    (S : Finset (Fin n)) : Finset (Fin m) :=
  T.filter fun e => (G.left e ∈ S ∧ G.right e ∉ S) ∨
    (G.right e ∈ S ∧ G.left e ∉ S)

def Connected {n m : ℕ} (G : MultiGraph n m) (T : Finset (Fin m)) : Prop :=
  ∀ S : Finset (Fin n), S.Nonempty → S ≠ Finset.univ → (G.cut T S).Nonempty

def SpanningTree {n m : ℕ} (G : MultiGraph n m) (T : Finset (Fin m)) : Prop :=
  G.Connected T ∧ ∀ e ∈ T, ¬ G.Connected (T.erase e)

def EdgeConnected {n m : ℕ} (G : MultiGraph n m) (k : ℕ) : Prop :=
  ∀ S : Finset (Fin n), S.Nonempty → S ≠ Finset.univ →
    k ≤ (G.cut Finset.univ S).card

end MultiGraph

def MainStatement : Prop :=
  ∃ C : ℝ, 0 < C ∧ ∀ (k : ℕ), 1 ≤ k → ∀ (n m : ℕ), 2 ≤ n →
    ∀ G : MultiGraph n m, G.EdgeConnected k →
      ∃ T : Finset (Fin m), G.SpanningTree T ∧
        ∀ S : Finset (Fin n), S.Nonempty → S ≠ Finset.univ →
          ((G.cut T S).card : ℝ) ≤ (C / (k : ℝ)) * (G.cut Finset.univ S).card

theorem strongThinTree : MainStatement := by
  sorry

end StrongThinTree

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/StrongThinTree.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.StrongThinTree.strongThinTree` must keep exactly the statement shown above: same names,
  namespaces, binders and types. Every definition the statements use must stay exactly as written.
  Change nothing except the proofs.
- **Standard axioms only.** Proofs may use only `propext`, `Quot.sound` and `Classical.choice`.
  `sorry`, `admit`, new `axiom`s and `native_decide` (it introduces an axiom of its own) are rejected.
- **Keep the challenge's declarations as they are.** Put new lemmas and instances *after* the
  definitions the statements use, or in a separate `Submission/*.lean` module. A declaration added
  before them can change how they elaborate, and then they no longer match the challenge.
- **Kernel-checked.** The proofs are re-checked by the Lean kernel, not just the elaborator.

Long proofs can be split into modules under `/workspace/Submission/` (module names
`Submission.Foo`, `Submission.Foo.Bar`) imported from `Submission.lean`. Only `.lean` files at
those two paths are graded.

## Environment

- Lean `v4.34.1` and Mathlib at commit `d13f23b` are installed and prebuilt; `/workspace` is a
  Lake project.
- The sandbox has 4 CPUs and 8 GB of memory; `LEAN_NUM_THREADS=3` keeps `lake build` to three
  parallel jobs. Check your work with `cd /workspace && lake build Submission`. Add `#print axioms <name>` to see
  which axioms a proof uses.
- There is no internet access. OpenAI's own proofs are not installed.

## Grading

When you finish, `Submission.lean` and `Submission/**.lean` are copied to a fresh machine and
checked with [Comparator](https://github.com/leanprover/comparator), the Lean FRO's proof checker.
The reward is 1 if Comparator accepts the proof and 0 otherwise. A partial proof scores 0.
