# openai/math challenge `AuslanderReiten` (family 199)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 199 of the release, *Counterexamples to conjectures of Auslander–Reiten, Tachikawa, and Nakayama*
(Algebra). The family as a whole: Constructs finite-dimensional algebras over a characteristic-two rational-function field that disprove the Auslander–Reiten and Gorenstein-projective conjectures, and Tachikawa's second conjecture. An associated endomorphism algebra also disproves the classical, generalized and strong Nakayama conjectures, the Auslander–Gorenstein conjecture, and the Wakamatsu tilting conjecture. The counterexamples persist under every extension of the base field.

The challenge is `AuslanderReiten`, also at `/opt/openai-math/challenges/AuslanderReiten.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open CategoryTheory
open scoped TensorProduct
namespace ArExplicit.Statement
universe u v

abbrev K := FractionRing (MvPolynomial (Fin 3) (ZMod 2))

def parameters (i : Fin 3) : K :=
  algebraMap (MvPolynomial (Fin 3) (ZMod 2)) K (MvPolynomial.X i)

def TotallyAcyclicWitness (R : Type u) [Ring R]
    (Z : Type u) [AddCommGroup Z] [Module R Z] : Prop :=
  ∃ P : ChainComplex (ModuleCat.{u} R) ℤ,
    (∀ i : ℤ, Module.Finite R (P.X i) ∧ Module.Projective R (P.X i)) ∧
    (∀ i : ℤ, LinearMap.range (P.d (i+1) i).hom = LinearMap.ker (P.d i (i-1)).hom) ∧
    (∀ (Q : Type u) [AddCommGroup Q] [Module R Q] [Module.Projective R Q]
      (i : ℤ) (f : P.X i →ₗ[R] Q), f.comp (P.d (i+1) i).hom = 0 →
        ∃ g : P.X (i-1) →ₗ[R] Q, f = g.comp (P.d i (i-1)).hom) ∧
    Nonempty (Z ≃ₗ[R] (P.X 0 ⧸ LinearMap.range (P.d 1 0).hom))

def Conclusions (F R Z : Type u) [Field F] [Ring R] [Algebra F R]
    [AddCommGroup Z] [Module R Z] [Module F Z] [IsScalarTower F R Z] : Prop :=
  FiniteDimensional F R ∧
  FiniteDimensional F Z ∧
  ¬ Module.Projective R Z ∧
  TotallyAcyclicWitness R Z ∧
  (∀ i : ℕ, 0 < i →
    Subsingleton (Abelian.Ext (ModuleCat.of R Z) (ModuleCat.of R Z) i)) ∧
  (∀ i : ℕ, 0 < i →
    Subsingleton (Abelian.Ext (ModuleCat.of R Z) (ModuleCat.of R R) i)) ∧
  Nonempty ((R ⧸ Ring.jacobson R) ≃ₐ[F] (Fin 8 → F)) ∧
  (Ring.jacobson R)^4 ≠ ⊥

structure System where
  algebraCarrier : Type
  [ring : Ring algebraCarrier]
  [scalarAlgebra : Algebra K algebraCarrier]
  moduleCarrier : Type
  [additiveGroup : AddCommGroup moduleCarrier]
  [action : Module algebraCarrier moduleCarrier]
  [scalarAction : Module K moduleCarrier]
  [actionTower : IsScalarTower K algebraCarrier moduleCarrier]

attribute [instance] System.ring System.scalarAlgebra System.additiveGroup
  System.action System.scalarAction System.actionTower

def FullStatement : Prop :=
  AlgebraicIndependent (ZMod 2) parameters ∧
  ∃ s : System,
    Conclusions K s.algebraCarrier s.moduleCarrier ∧
    ∀ (E : Type v) [Field E] [Algebra K E],
      ∃ action : Module (E ⊗[K] s.algebraCarrier) (E ⊗[K] s.moduleCarrier),
      letI := action
      ∃ tower : IsScalarTower E (E ⊗[K] s.algebraCarrier) (E ⊗[K] s.moduleCarrier),
      letI := tower
      (∀ (a b : E) (r : s.algebraCarrier) (z : s.moduleCarrier),
        (a ⊗ₜ[K] r) • (b ⊗ₜ[K] z) = (a*b) ⊗ₜ[K] (r • z)) ∧
      Conclusions E (E ⊗[K] s.algebraCarrier) (E ⊗[K] s.moduleCarrier)

end ArExplicit.Statement

namespace ArExplicit.Statement
universe v

theorem main : FullStatement.{v} := by
  sorry

end ArExplicit.Statement

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/AuslanderReiten.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.ArExplicit.Statement.main` must keep exactly the statement shown above: same names,
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
