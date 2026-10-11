# openai/math challenge `BinarySweep` (family 238)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 238 of the release, *Optimal logarithmic mixing of the Thorp shuffle*
(Probability and statistical mechanics). The family as a whole: Proves that the Thorp shuffle randomizes $N=2^d$ labeled cards in $\Theta(\log N)$ physical shuffles, settling its optimal mixing order for power-of-two deck sizes. Convergence is in total variation from the worst initial ordering and concerns the entire permutation, not just individual card positions.

The challenge is `BinarySweep`, also at `/opt/openai-math/challenges/BinarySweep.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open scoped BigOperators
namespace BinaryCoordinateSweeps

/-- The positions of a binary deck of dimension d. -/
abbrev Slot (d : ℕ) := Fin d → Bool

/-- Independent switches on the edges parallel to one coordinate. -/
def coordinateLayer (d : ℕ) (j : Fin d)
    (c : (({i : Fin d // i ≠ j} → Bool)) → Bool) : Equiv.Perm (Slot d) :=
  let e := Equiv.piSplitAt j (fun _ : Fin d => Bool)
  let sw : Equiv.Perm (Bool × ({i : Fin d // i ≠ j} → Bool)) :=
    { toFun := fun x => (x.1 ^^ c x.2, x.2)
      invFun := fun x => (x.1 ^^ c x.2, x.2)
      left_inv := fun x => by simp
      right_inv := fun x => by simp }
  e.trans (sw.trans e.symm)

abbrev SweepCoins (d : ℕ) :=
  (j : Fin d) → ({i : Fin d // i ≠ j} → Bool) → Bool

/-- The coordinate layers are applied in increasing coordinate order. -/
def binarySweep (d : ℕ) (c : SweepCoins d) : Equiv.Perm (Slot d) :=
  (List.ofFn (fun j => coordinateLayer d j (c j))).reverse.prod

def finiteLaw {Ω G : Type*} [Fintype Ω] [Fintype G] (f : Ω → G) (g : G) : ℝ := by
  classical
  exact ∑ ω, if f ω = g then (Fintype.card Ω : ℝ)⁻¹ else 0

/-- Half the unnormalized sum of absolute probability-mass differences. -/
def totalVariation {G : Type*} [Fintype G] (p q : G → ℝ) : ℝ :=
  (1 / ((2 : ℕ) : ℝ)) * ∑ g, |p g - q g|

def uniformLaw (G : Type*) [Fintype G] : G → ℝ :=
  fun _ => (Fintype.card G : ℝ)⁻¹

def binaryLaw (d : ℕ) : Equiv.Perm (Slot d) → ℝ :=
  finiteLaw (binarySweep d)

abbrev RepSpace (D : ℕ) := EuclideanSpace ℂ (Fin D)

def IsUnitaryRep {G : Type*} [Monoid G]
    {D : ℕ} (ρ : Representation ℂ G (RepSpace D)) : Prop :=
  ∀ g x, ‖ρ g x‖ = ‖x‖

def averageOperator {G : Type*} [Fintype G] [Monoid G] {D : ℕ}
    (p : G → ℝ) (ρ : Representation ℂ G (RepSpace D)) :
    RepSpace D →L[ℂ] RepSpace D :=
  LinearMap.toContinuousLinearMap (∑ g, (p g : ℂ) • ρ g)

def BinaryContractionTarget : Prop :=
  ∃ g : ℝ, 0 < g ∧ ∃ d₀ : ℕ, ∀ d ≥ d₀, ∀ D : ℕ,
    ∀ ρ : Representation ℂ (Equiv.Perm (Slot d)) (RepSpace D),
      ρ.IsIrreducible → IsUnitaryRep ρ →
      ‖averageOperator (binaryLaw d) ρ‖ ≤ (D : ℝ) ^ (-g)

def realSign {α : Type*} [Fintype α] [DecidableEq α] : Equiv.Perm α →* ℝ :=
  (Int.castRingHom ℝ).toMonoidHom.comp ((Units.coeHom ℤ).comp Equiv.Perm.sign)

section FiniteLaws
variable {G : Type*} [Fintype G] [Group G]

def convolution (p q : G → ℝ) (g : G) : ℝ := ∑ x, p x * q (x⁻¹ * g)

def pointMassOne (g : G) : ℝ := by
  classical
  exact if g = 1 then 1 else 0

/-- The law of independent repetitions, with the empty product at the identity. -/
def convolutionPower (p : G → ℝ) : ℕ → G → ℝ
  | 0 => pointMassOne
  | n + 1 => convolution p (convolutionPower p n)

end FiniteLaws

def sweepLaw (d t : ℕ) : Equiv.Perm (Slot d) → ℝ :=
  convolutionPower (binaryLaw d) t

/-- A single number of sweeps works uniformly over deterministic initial decks. -/
def UniformSweepMixingTarget : Prop :=
  ∃ w : ℕ, ∀ ε : ℝ, 0 < ε → ∃ d₀ : ℕ, ∀ d ≥ d₀,
    ∀ τ : Equiv.Perm (Slot d),
      totalVariation (fun g => sweepLaw d w (g * τ⁻¹))
        (uniformLaw (Equiv.Perm (Slot d))) ≤ ε

end BinaryCoordinateSweeps
end

open scoped BigOperators

theorem binary_sweep_contraction_and_mixing :
    BinaryCoordinateSweeps.BinaryContractionTarget ∧
    (∀ d : ℕ, 0 < d → ∑ g : Equiv.Perm (BinaryCoordinateSweeps.Slot d),
      BinaryCoordinateSweeps.binaryLaw d g * BinaryCoordinateSweeps.realSign g = 0) ∧
    BinaryCoordinateSweeps.UniformSweepMixingTarget := by
  sorry

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/BinarySweep.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.binary_sweep_contraction_and_mixing` must keep exactly the statement shown above: same names,
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
