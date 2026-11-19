# openai/math challenge `FiniteFactor` (family 293)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 293 of the release, *A counterexample to the hyperinvariant-subspace problem*
(Operator algebras). The family as a whole: Constructs a nonzero norm-quasinilpotent operator on every infinite-dimensional separable complex Hilbert space with no nonzero proper closed subspace invariant under every commuting operator. The construction also gives operators with no nontrivial invariant projection in the hyperfinite type $\mathrm{II}_1$ factor.

The challenge is `FiniteFactor`, also at `/opt/openai-math/challenges/FiniteFactor.lean`:

```lean
import Mathlib.Analysis.VonNeumannAlgebra.Basic
import Mathlib.Analysis.SpecialFunctions.Pow.Real

namespace OAI

namespace FiniteFactor
open Filter
open scoped Topology
universe u

variable {H : Type u} [NormedAddCommGroup H] [InnerProductSpace ℂ H] [CompleteSpace H]

/-- A concrete factor has scalar center. -/
def HasScalarCenter (M : VonNeumannAlgebra H) : Prop :=
  ∀ a ∈ M, (∀ b ∈ M, a * b = b * a) → ∃ z : ℂ, a = z • (1 : H →L[ℂ] H)

/-- Finiteness: every isometry in the algebra is unitary. -/
def IsFiniteAlgebra (M : VonNeumannAlgebra H) : Prop :=
  ∀ v ∈ M, star v * v = 1 → v * star v = 1

/-- No nonzero projection is minimal, excluding matrix factors. -/
def HasNoMinimalProjection (M : VonNeumannAlgebra H) : Prop :=
  ∀ p ∈ M, IsStarProjection p → p ≠ 0 →
    ∃ q ∈ M, IsStarProjection q ∧ q ≠ 0 ∧ q ≠ p ∧ q * p = q

/-- A separable Banach space whose dual is conjugate-linearly isometric to M. -/
def HasSeparablePredual (M : VonNeumannAlgebra H) : Prop :=
  ∃ (E : Type u) (_ : NormedAddCommGroup E) (_ : NormedSpace ℂ E)
    (_ : CompleteSpace E) (_ : TopologicalSpace.SeparableSpace E),
    Nonempty (StrongDual ℂ E ≃ₗᵢ⋆[ℂ] M.toStarSubalgebra)

def MainTarget : Prop :=
  ∃ (H : Type u) (_ : NormedAddCommGroup H) (_ : InnerProductSpace ℂ H)
    (_ : CompleteSpace H) (M : VonNeumannAlgebra H),
    HasScalarCenter M ∧ IsFiniteAlgebra M ∧ HasNoMinimalProjection M ∧
    HasSeparablePredual M ∧
    ∃ T : H →L[ℂ] H, T ∈ M ∧ T ≠ 0 ∧
      Tendsto (fun n : ℕ => ‖T ^ n‖ ^ (1 / (n : ℝ))) atTop (𝓝 0) ∧
      ∀ p ∈ M, IsStarProjection p → (1 - p) * T * p = 0 → p = 0 ∨ p = 1

theorem main_theorem : MainTarget.{0} := by
  sorry

end FiniteFactor

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/FiniteFactor.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.FiniteFactor.main_theorem` must keep exactly the statement shown above: same names,
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
