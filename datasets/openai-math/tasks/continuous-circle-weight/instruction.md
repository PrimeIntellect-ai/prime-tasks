# openai/math challenge `ContinuousCircleWeight` (family 293)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 293 of the release, *A counterexample to the hyperinvariant-subspace problem*
(Operator algebras). The family as a whole: Constructs a nonzero norm-quasinilpotent operator on every infinite-dimensional separable complex Hilbert space with no nonzero proper closed subspace invariant under every commuting operator. The construction also gives operators with no nontrivial invariant projection in the hyperfinite type $\mathrm{II}_1$ factor.

The challenge is `ContinuousCircleWeight`, also at `/opt/openai-math/challenges/ContinuousCircleWeight.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open MeasureTheory
open scoped ENNReal ComplexInnerProductSpace
namespace ContinuousCircleWeight

abbrev CircleX := AddCircle (1:ℝ)

abbrev TracialHilbert := lp (fun _ : ℤ × ℤ => ℂ) 2
abbrev Operator := TracialHilbert →L[ℂ] TracialHilbert

def circleIdentification : CircleX ≃ₜ Circle :=
  AddCircle.homeomorphCircle (by norm_num)
def circleFunction (f : C(CircleX, ℝ)) (z : ℂ) : ℂ :=
  if hz : ‖z‖ = 1 then f (circleIdentification.symm ⟨z, mem_sphere_zero_iff_norm.mpr hz⟩) else 0

def negativeLog (t : ℝ) : ℝ≥0∞ :=
  if t = 0 then ∞ else ENNReal.ofReal (-Real.log t)

structure IsTracialRotation (θ : ℝ) (U V : unitary Operator)
    (e : TracialHilbert) : Prop where
  relation : (V : Operator) * (U : Operator) =
    Complex.exp (2 * Real.pi * θ * Complex.I) • ((U : Operator) * (V : Operator))
  moments : ∀ m n : ℤ,
    inner ℂ e (((U ^ m * V ^ n : unitary Operator) : Operator) e) =
      if m = 0 ∧ n = 0 then 1 else 0
  cyclic : (Submodule.span ℂ
    (Set.range (fun mn : ℤ × ℤ =>
      ((U ^ mn.1 * V ^ mn.2 : unitary Operator) : Operator) e))).topologicalClosure = ⊤

def rotationAlgebra (U V : unitary Operator) : Set Operator :=
  Set.centralizer (Set.centralizer ({(U : Operator), (V : Operator)} : Set Operator))

def weightedRotation (U V : unitary Operator) (f : C(CircleX, ℝ)) : Operator :=
  (U : Operator) * cfc (circleFunction f) (V : Operator)

def MainStatement : Prop :=
  ∃ (θ : ℝ) (f : C(CircleX, ℝ)) (U V : unitary Operator) (e : TracialHilbert),
    0 < θ ∧ θ < 1 ∧ Irrational θ ∧
    IsTracialRotation θ U V e ∧
    (∀ x, 0 ≤ f x ∧ f x ≤ 1) ∧
    (∃ z : CircleX, ∀ x, f x = 0 ↔ x = z) ∧
    (∫⁻ x, negativeLog (f x) ∂(volume : Measure CircleX)) = ∞ ∧
    ∀ p : Operator, p ∈ rotationAlgebra U V → IsStarProjection p →
      (1 - p) * weightedRotation U V f * p = 0 → p = 0 ∨ p = 1

theorem main_theorem : MainStatement := by
  sorry

end ContinuousCircleWeight
end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/ContinuousCircleWeight.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.ContinuousCircleWeight.main_theorem` must keep exactly the statement shown above: same names,
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
