# openai/math challenge `GaussianPropeller` (family 096)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 096 of the release, *The Gaussian propeller conjecture*
(Convex and metric geometry). The family as a whole: Proves that the sum of squared Gaussian first moments of any finite measurable partition is at most $9/(8\pi)$. In dimension at least two, three planar sectors of angle $2\pi/3$, extended orthogonally, attain the bound. Combined with the separate Unique Games theorem, this proves NP-hardness of improving the loss factor $(8\pi/9)(1-1/k)$ for identity-target kernel clustering with fixed $k\ge3$ on rational centered positive semidefinite inputs.

The challenge is `GaussianPropeller`, also at `/opt/openai-math/challenges/GaussianPropeller.lean`:

```lean
import Mathlib

namespace OAI

open MeasureTheory ProbabilityTheory
open scoped ENNReal

namespace GaussianPropeller

abbrev Space (d : ℕ) := EuclideanSpace ℝ (Fin d)

noncomputable def gaussian (d : ℕ) : Measure (Space d) := stdGaussian (Space d)

def IsPartition {d k : ℕ} (A : Fin k → Set (Space d)) : Prop :=
  (∀ i, MeasurableSet (A i)) ∧ ∀ᵐ x ∂gaussian d, ∃! i, x ∈ A i

noncomputable def centroid {d : ℕ} (A : Set (Space d)) : Space d :=
  ∫ x in A, x ∂gaussian d

noncomputable def value {d k : ℕ} (A : Fin k → Set (Space d)) : ℝ :=
  ∑ i, ‖centroid (A i)‖ ^ 2

def coord {d : ℕ} (j : ℕ) (x : Space d) : ℝ :=
  if h : j < d then x ⟨j, h⟩ else 0

noncomputable def propeller (d k : ℕ) (i : Fin k) : Set (Space d) :=
  if i.val = 0 then {x | |coord 1 x| ≤ Real.sqrt 3 * coord 0 x}
  else if i.val = 1 then {x | 0 ≤ coord 1 x ∧ Real.sqrt 3 * coord 0 x ≤ coord 1 x}
  else if i.val = 2 then {x | coord 1 x ≤ 0 ∧ Real.sqrt 3 * coord 0 x ≤ -coord 1 x}
  else ∅

def AllPartitions : Prop :=
  (∀ (d k : ℕ), 0 < d → 0 < k → ∀ A : Fin k → Set (Space d),
    IsPartition A → value A ≤ 9 / (8 * Real.pi)) ∧
  (∀ (d k : ℕ), 2 ≤ d → 3 ≤ k →
    IsPartition (propeller d k) ∧ value (propeller d k) = 9 / (8 * Real.pi))

theorem all_partitions : AllPartitions := by
  sorry

end GaussianPropeller

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/GaussianPropeller.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.GaussianPropeller.all_partitions` must keep exactly the statement shown above: same names,
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
