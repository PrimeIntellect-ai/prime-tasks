# openai/math challenge `MetricEntropyDuality` (family 329)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 329 of the release, *A counterexample to Pietsch's metric-entropy duality conjecture*
(Functional analysis). The family as a whole: Disproves Pietsch's dimension-free duality conjecture for metric entropy. Origin-symmetric convex bodies violate every proposed choice of universal constants in the conjectured comparison between covering numbers and those of the polar bodies, even when the covering body is a cube.

The challenge is `MetricEntropyDuality`, also at `/opt/openai-math/challenges/MetricEntropyDuality.lean`:

```lean
import Mathlib.Analysis.Convex.Topology
import Mathlib.Analysis.Normed.Group.Constructions
import Mathlib.Order.Lattice.Nat
import Mathlib.Analysis.SpecialFunctions.Log.Basic

namespace OAI

universe u

noncomputable section

namespace MetricEntropyDuality

open Filter Topology
open scoped BigOperators Pointwise

abbrev RealSpace (ι : Type u) := ι → ℝ

def pairing {ι : Type u} [Fintype ι] (x y : RealSpace ι) : ℝ :=
  ∑ i, x i * y i

def cube (ι : Type u) : Set (RealSpace ι) :=
  {x | ∀ i, |x i| ≤ 1}

def polar {ι : Type u} [Fintype ι] (K : Set (RealSpace ι)) : Set (RealSpace ι) :=
  {y | ∀ x ∈ K, pairing x y ≤ 1}

def Covers {ι : Type u} {M : ℕ} (A B : Set (RealSpace ι))
    (centers : Fin M → RealSpace ι) : Prop :=
  ∀ x ∈ A, ∃ j, x - centers j ∈ B

def Coverable {ι : Type u} (A B : Set (RealSpace ι)) : Prop :=
  ∃ M : ℕ, ∃ centers : Fin M → RealSpace ι, Covers A B centers

def coveringNumber {ι : Type u} (A B : Set (RealSpace ι)) : ℕ :=
  sInf {M : ℕ | ∃ centers : Fin M → RealSpace ι, Covers A B centers}

structure IsSymmetricConvexBody {ι : Type u} [Fintype ι]
    (K : Set (RealSpace ι)) : Prop where
  isCompact : IsCompact K
  convex : Convex ℝ K
  symmetric : ∀ x, x ∈ K ↔ -x ∈ K
  interior_nonempty : (interior K).Nonempty

theorem exists_entropy_duality_counterexample_with_covers
    (a b : ℝ) (ha : 1 ≤ a) (hb : 1 ≤ b) :
    ∃ n : ℕ, 0 < n ∧ ∃ K : Set (RealSpace (Fin n)),
      IsSymmetricConvexBody K ∧
      Coverable K (cube (Fin n)) ∧
      Coverable (polar (cube (Fin n))) (a⁻¹ • polar K) ∧
      b * Real.log (coveringNumber (polar (cube (Fin n))) (a⁻¹ • polar K) : ℝ) <
        Real.log (coveringNumber K (cube (Fin n)) : ℝ) := by
  sorry

end MetricEntropyDuality

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/MetricEntropyDuality.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.MetricEntropyDuality.exists_entropy_duality_counterexample_with_covers` must keep exactly the statement shown above: same names,
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
