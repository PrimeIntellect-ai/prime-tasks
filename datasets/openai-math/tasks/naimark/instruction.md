# openai/math challenge `Naimark` (family 297)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 297 of the release, *A ZFC counterexample to Naimark's problem*
(Operator algebras). The family as a whole: Gives an alternative to \href{https://arxiv.org/abs/2609.26930v1}{Tanaka's ZFC construction} of a unital infinite-dimensional simple complex $C^*$-algebra with a faithful tracial state and exactly one nonzero irreducible representation up to unitary equivalence. Thus the unrestricted compact-operator characterization fails without additional set-theoretic assumptions; the counterexample is nonseparable.

The challenge is `Naimark`, also at `/opt/openai-math/challenges/Naimark.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

universe u v w

namespace NaimarkZFC

def IsSimpleCStar (A : Type u) [CStarAlgebra A] : Prop :=
  Nontrivial A ∧ ∀ I : TwoSidedIdeal A, IsClosed (I : Set A) → I = ⊥ ∨ I = ⊤

def IsState {A : Type u} [CStarAlgebra A] (f : A →L[ℂ] ℂ) : Prop :=
  ‖f‖ = 1 ∧ ∀ a : A, (f (star a * a)).im = 0 ∧ 0 ≤ (f (star a * a)).re

def IsFaithfulTracialState {A : Type u} [CStarAlgebra A] (f : A →L[ℂ] ℂ) : Prop :=
  IsState f ∧ (∀ a b : A, f (a * b) = f (b * a)) ∧
    ∀ a : A, a ≠ 0 → 0 < (f (star a * a)).re

def IsIrreducible {A : Type u} [CStarAlgebra A]
    {H : Type v} [NormedAddCommGroup H] [InnerProductSpace ℂ H] [CompleteSpace H]
    (π : A →⋆ₙₐ[ℂ] (H →L[ℂ] H)) : Prop :=
  π ≠ 0 ∧ ∀ M : Submodule ℂ H, IsClosed (M : Set H) →
    (∀ a : A, ∀ x ∈ M, π a x ∈ M) → M = ⊥ ∨ M = ⊤

def UnitarilyEquivalent {A : Type u} [CStarAlgebra A]
    {H : Type v} [NormedAddCommGroup H] [InnerProductSpace ℂ H] [CompleteSpace H]
    {K : Type w} [NormedAddCommGroup K] [InnerProductSpace ℂ K] [CompleteSpace K]
    (π : A →⋆ₙₐ[ℂ] (H →L[ℂ] H)) (ρ : A →⋆ₙₐ[ℂ] (K →L[ℂ] K)) : Prop :=
  ∃ U : H ≃ₗᵢ[ℂ] K, ∀ a : A, ∀ x : H, U (π a x) = ρ a (U x)

def HasUniqueIrreducibleRepresentation (A : Type u) [CStarAlgebra A] : Prop :=
  ∀ (H : Type v) [NormedAddCommGroup H] [InnerProductSpace ℂ H] [CompleteSpace H]
    (K : Type w) [NormedAddCommGroup K] [InnerProductSpace ℂ K] [CompleteSpace K]
    (π : A →⋆ₙₐ[ℂ] (H →L[ℂ] H)) (ρ : A →⋆ₙₐ[ℂ] (K →L[ℂ] K)),
    IsIrreducible π → IsIrreducible ρ → UnitarilyEquivalent π ρ

def IsIsomorphicToCompacts (A : Type u) [CStarAlgebra A]
    (H : Type v) [NormedAddCommGroup H] [InnerProductSpace ℂ H] [CompleteSpace H] : Prop :=
  ∃ φ : A →⋆ₙₐ[ℂ] (H →L[ℂ] H), Function.Injective φ ∧
    ∀ T : H →L[ℂ] H, (∃ a : A, φ a = T) ↔ IsCompactOperator T

theorem main :
    ∃ (A : Type u) (_ : CStarAlgebra A),
      IsSimpleCStar A ∧ ¬ FiniteDimensional ℂ A ∧
      (∃ τ : A →L[ℂ] ℂ, IsFaithfulTracialState τ) ∧
      HasUniqueIrreducibleRepresentation.{u, v, w} A ∧
      ∀ (H : Type v) [NormedAddCommGroup H] [InnerProductSpace ℂ H] [CompleteSpace H],
        ¬ IsIsomorphicToCompacts A H := by
  sorry

end NaimarkZFC

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/Naimark.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.NaimarkZFC.main` must keep exactly the statement shown above: same names,
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
