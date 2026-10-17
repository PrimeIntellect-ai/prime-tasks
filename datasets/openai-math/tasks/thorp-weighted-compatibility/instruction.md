# openai/math challenge `ThorpWeightedCompatibility` (family 238)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 238 of the release, *Optimal logarithmic mixing of the Thorp shuffle*
(Probability and statistical mechanics). The family as a whole: Proves that the Thorp shuffle randomizes $N=2^d$ labeled cards in $\Theta(\log N)$ physical shuffles, settling its optimal mixing order for power-of-two deck sizes. Convergence is in total variation from the worst initial ordering and concerns the entire permutation, not just individual card positions.

The challenge is `ThorpWeightedCompatibility`, also at `/opt/openai-math/challenges/ThorpWeightedCompatibility.lean`:

```lean
import Mathlib

namespace OAI

open scoped Classical
namespace ThorpCompatibility
open Finset

abbrev Rows (A D : ℕ) := Fin A → Equiv.Perm (Fin D)
abbrev Cols (A D : ℕ) := Fin D → Equiv.Perm (Fin A)

def Compatible {A D : ℕ} (r : Rows A D) (c : Cols A D) : Prop :=
  ∀ j : Fin D, Function.Injective (fun i : Fin A => c (r i j) i)

noncomputable def uniformMean {α : Type*} [Fintype α] (f : α → ℝ) : ℝ :=
  (∑ x, f x) / Fintype.card α

noncomputable def marginalFactor {α : Type*} [Fintype α]
    (θ : ℝ) (w : α → ℝ) : ℝ :=
  (uniformMean (fun x => Real.rpow (w x) (1 / θ))) ^ θ

noncomputable def weightedCompatibility (A D : ℕ)
    (w : Fin A → Equiv.Perm (Fin D) → ℝ)
    (v : Fin D → Equiv.Perm (Fin A) → ℝ) : ℝ := by
  classical
  exact (Nat.factorial (A * D) : ℝ) /
    ((Nat.factorial D : ℝ) ^ A * (Nat.factorial A : ℝ) ^ D) *
    uniformMean (fun rc : Rows A D × Cols A D =>
      if Compatible rc.1 rc.2 then (∏ i, w i (rc.1 i)) * (∏ k, v k (rc.2 k)) else 0)

def WeightedCompatibilityTheorem : Prop :=
  ∃ L C₀ m₀ : ℝ, 0 < L ∧ 0 < C₀ ∧ 0 < m₀ ∧
    ∀ A D : ℕ,
    let n : ℝ := A * D
    let m := Real.sqrt n
    let θ := 1 - L / Real.log m
    m₀ ≤ m → 0 < θ → m / ((2 : ℕ) : ℝ) ≤ A → (A : ℝ) ≤ ((2 : ℕ) : ℝ) * m →
    m / ((2 : ℕ) : ℝ) ≤ D → (D : ℝ) ≤ ((2 : ℕ) : ℝ) * m →
    ∀ (w : Fin A → Equiv.Perm (Fin D) → ℝ)
      (v : Fin D → Equiv.Perm (Fin A) → ℝ),
    (∀ i σ, 0 ≤ w i σ) → (∀ k σ, 0 ≤ v k σ) →
    weightedCompatibility A D w v ≤
      Real.exp (C₀ * n ^ (((54 : ℕ) : ℝ) / ((100 : ℕ) : ℝ))) *
        (∏ i, marginalFactor θ (w i)) * (∏ k, marginalFactor θ (v k))


theorem weightedCompatibility_main : WeightedCompatibilityTheorem := by
  sorry

end ThorpCompatibility

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/ThorpWeightedCompatibility.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.ThorpCompatibility.weightedCompatibility_main` must keep exactly the statement shown above: same names,
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
