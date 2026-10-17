# openai/math challenge `StandardMapEntropy` (family 146)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 146 of the release, *Sinai's positive-entropy conjecture for the standard map*
(Dynamical systems and ergodic theory). The family as a whole: Proves that the standard sine map on the two-dimensional torus has positive metric entropy with respect to area for every sufficiently large positive parameter. This establishes Sinai's positive-parameter-measure conjecture for the original family, with the stronger conclusion of a full parameter tail.

The challenge is `StandardMapEntropy`, also at `/opt/openai-math/challenges/StandardMapEntropy.lean`:

```lean
import Mathlib

namespace OAI

open MeasureTheory Set
open scoped ENNReal BigOperators

namespace StandardMapEntropy

abbrev Circle := AddCircle (1 : ℝ)
abbrev Torus := Circle × Circle

lemma sine_periodic : Function.Periodic (fun x : ℝ => Real.sin (2 * Real.pi * x)) 1 := by
  intro x
  dsimp only
  rw [show 2 * Real.pi * (x + 1) = 2 * Real.pi * x + 2 * Real.pi by ring]
  exact Real.sin_add_two_pi _

noncomputable def sine (x : Circle) : ℝ := sine_periodic.lift x

noncomputable def standardMap (k : ℝ) (z : Torus) : Torus :=
  (z.1 + z.2 + (k * sine z.1 : ℝ), z.2 + (k * sine z.1 : ℝ))

noncomputable def area : Measure Torus :=
  (volume : Measure Circle).prod (volume : Measure Circle)

def FinitePartition (r : ℕ) := { p : Torus → Fin (r + 1) // Measurable p }

def blockAtom {r : ℕ} (f : Torus → Torus) (p : FinitePartition r)
    (n : ℕ) (w : Fin n → Fin (r + 1)) : Set Torus :=
  { z | ∀ i : Fin n, p.val (f^[i.val] z) = w i }

noncomputable def blockEntropy {r : ℕ} (μ : Measure Torus) (f : Torus → Torus)
    (p : FinitePartition r) (n : ℕ) : ℝ :=
  - ∑ w : Fin n → Fin (r + 1),
    (μ (blockAtom f p n w)).toReal * Real.log (μ (blockAtom f p n w)).toReal

noncomputable def partitionEntropy {r : ℕ} (μ : Measure Torus) (f : Torus → Torus)
    (p : FinitePartition r) : ℝ≥0∞ :=
  ⨅ n : ℕ, ENNReal.ofReal (blockEntropy μ f p (n + 1) / (n + 1 : ℝ))

noncomputable def metricEntropy (μ : Measure Torus) (f : Torus → Torus) : ℝ≥0∞ :=
  ⨆ r : ℕ, ⨆ p : FinitePartition r, partitionEntropy μ f p

def MainObligation : Prop :=
  ∃ k₀ : ℝ, 0 < k₀ ∧ ∀ k : ℝ, k₀ ≤ k → 0 < metricEntropy area (standardMap k)

theorem main_entropy : MainObligation := by
  sorry

end StandardMapEntropy

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/StandardMapEntropy.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.StandardMapEntropy.main_entropy` must keep exactly the statement shown above: same names,
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
