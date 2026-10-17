# openai/math challenge `BorsukNine` (family 156)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 156 of the release, *Borsuk's conjecture fails in dimension nine*
(Combinatorics). The family as a whole: Constructs a compact subset of $\mathbb R^9$ that cannot be covered by ten sets of strictly smaller diameter, disproving Borsuk's covering assertion already in dimension nine. The example consists of rank-one orthogonal projectors onto lines in $\mathbb R^4$, with the Frobenius metric.

The challenge is `BorsukNine`, also at `/opt/openai-math/challenges/BorsukNine.lean`:

```lean
import Mathlib

namespace OAI

namespace BorsukNine

abbrev Vector4 := EuclideanSpace ℝ (Fin 4)
abbrev Matrix4 := EuclideanSpace ℝ (Fin 4 × Fin 4)

def projector (u : Vector4) : Matrix4 :=
  WithLp.toLp 2 (fun ij => u ij.1 * u ij.2)

def projectorSet : Set Matrix4 :=
  projector '' {u : Vector4 | ‖u‖ = 1}

def traceOneSymmetric : Set Matrix4 :=
  {A | (∀ i j : Fin 4, A (i, j) = A (j, i)) ∧ ∑ i : Fin 4, A (i, i) = 1}

def HasTenSmallCover : Prop :=
  ∃ C : Fin 10 → Set Matrix4,
    (∀ i, C i ⊆ projectorSet) ∧
    projectorSet ⊆ ⋃ i, C i ∧
    ∀ i, Metric.diam (C i) < Real.sqrt 2

theorem main_theorem :
    IsCompact projectorSet ∧
    projectorSet ⊆ traceOneSymmetric ∧
    Metric.diam projectorSet = Real.sqrt 2 ∧
    ¬ HasTenSmallCover := by
  sorry

end BorsukNine

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/BorsukNine.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.BorsukNine.main_theorem` must keep exactly the statement shown above: same names,
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
