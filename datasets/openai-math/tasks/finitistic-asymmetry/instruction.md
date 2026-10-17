# openai/math challenge `FinitisticAsymmetry` (family 198)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 198 of the release, *A counterexample to the little finitistic-dimension conjecture*
(Algebra). The family as a whole: Constructs a finite-dimensional complex algebra whose finite-dimensional modules have unbounded finite projective dimensions. This disproves the little finitistic-dimension conjecture.

The challenge is `FinitisticAsymmetry`, also at `/opt/openai-math/challenges/FinitisticAsymmetry.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open CategoryTheory

namespace LittleFinitistic
universe u
variable (A : Type u) [Ring A]

attribute [-instance] CompletePartialOrder.toSupSet in
def littleFinitisticDimension : WithBot ℕ∞ :=
  ⨆ (M : ModuleCat.{u} A) (_ : Module.Finite A M) (_ : projectiveDimension M < ⊤),
    projectiveDimension M

def bigFinitisticDimension : WithBot ℕ∞ :=
  ⨆ (M : ModuleCat.{u} A) (_ : projectiveDimension M < ⊤), projectiveDimension M

def InjectivesGenerate : Prop :=
  letI := HasDerivedCategory.standard (ModuleCat.{u} A)
  ∀ (P : ObjectProperty (DerivedCategory (ModuleCat.{u} A))),
    P.IsClosedUnderIsomorphisms → P.IsTriangulated →
    (∀ I : Type u, P.IsClosedUnderColimitsOfShape (Discrete I)) →
    (∀ (M : ModuleCat.{u} A), Injective M →
      P ((DerivedCategory.singleFunctor (ModuleCat.{u} A) 0).obj M)) →
    ∀ X, P X

theorem extreme_left_right_asymmetry :
    ∃ (Λ : Type) (_ : Ring Λ) (_ : Algebra ℂ Λ),
      FiniteDimensional ℂ Λ ∧
      littleFinitisticDimension Λ = ⊤ ∧ bigFinitisticDimension Λ = ⊤ ∧
      littleFinitisticDimension Λᵐᵒᵖ = 0 ∧ bigFinitisticDimension Λᵐᵒᵖ = 0 ∧
      ¬ InjectivesGenerate Λ ∧ InjectivesGenerate Λᵐᵒᵖ := by
  sorry

end LittleFinitistic

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/FinitisticAsymmetry.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.LittleFinitistic.extreme_left_right_asymmetry` must keep exactly the statement shown above: same names,
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
