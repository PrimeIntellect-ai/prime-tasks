# openai/math challenge `CirculantHadamard` (family 179)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 179 of the release, *The circulant Hadamard conjecture*
(Combinatorics). The family as a whole: Proves that real circulant Hadamard matrices exist exactly in orders $1$ and $4$, resolving the circulant Hadamard conjecture. Together with classical Barker-sequence results, this shows that binary sequences whose nontrivial aperiodic autocorrelations have magnitude at most $1$ exist at lengths $n>1$ exactly when $n\in\{2,3,4,5,7,11,13\}$.

The challenge is `CirculantHadamard`, also at `/opt/openai-math/challenges/CirculantHadamard.lean`:

```lean
import Mathlib

namespace OAI

namespace CirculantHadamard

universe u

def IsSign {R : Type u} [One R] [Neg R] (x : R) : Prop :=
  x = 1 ∨ x = -1

abbrev RealMatrix (n : ℕ) := Matrix (Fin n) (Fin n) ℝ

def IsCirculant {n : ℕ} (H : RealMatrix n) : Prop :=
  ∃ h : Fin n → ℝ, ∀ i j, H i j = h (j - i)

def IsSignHadamard {n : ℕ} (H : RealMatrix n) : Prop :=
  (∀ i j, IsSign (H i j)) ∧
    H * H.transpose = (n : ℝ) • (1 : RealMatrix n)

def ExistsRealCirculantHadamard (n : ℕ) : Prop :=
  ∃ H : RealMatrix n, IsCirculant H ∧ IsSignHadamard H

theorem exists_iff_order_one_or_four (n : ℕ) (hn : 0 < n) :
    ExistsRealCirculantHadamard n ↔ n = 1 ∨ n = 4 := by
  sorry

end CirculantHadamard

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/CirculantHadamard.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.CirculantHadamard.exists_iff_order_one_or_four` must keep exactly the statement shown above: same names,
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
