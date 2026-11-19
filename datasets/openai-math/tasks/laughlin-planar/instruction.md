# openai/math challenge `LaughlinPlanar` (family 269)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 269 of the release, *The Laughlin gap and stability under scalar disorder*
(Mathematical physics). The family as a whole: Proves the fermionic Laughlin spectral-gap conjecture for the full $V_1$ interaction at filling $1/3$ on the round sphere. The unique ground state remains uniformly gapped under sufficiently weak bounded real scalar one-body potentials projected to the lowest Landau level. Both the gap and disorder threshold are uniform over all sufficiently large particle numbers and all normalized potential profiles.

The challenge is `LaughlinPlanar`, also at `/opt/openai-math/challenges/LaughlinPlanar.lean`:

```lean
import Mathlib

namespace OAI

namespace Laughlin
open scoped BigOperators Matrix ENNReal

noncomputable def gammaStar : ℝ := 4616733319001 / 10^14

noncomputable def pairLimitCoefficient (p x y : ℕ) : ℝ :=
  if x+y = p+1 then
    ((x : ℝ)-(y : ℝ)) * Real.sqrt ((p.factorial : ℝ) /
      (((2 : ℕ) : ℝ)^p * (x.factorial : ℝ) * (y.factorial : ℝ))) / Real.sqrt (2 : ℕ)
  else 0

namespace Fock

abbrev Orbital (Q : ℕ) := Fin (Q+1) → ℂ
abbrev Space (Q : ℕ) := ExteriorAlgebra ℂ (Orbital Q)

noncomputable def annihilate {Q : ℕ} (i : Fin (Q+1)) : Module.End ℂ (Space Q) :=
  CliffordAlgebra.contractLeft (Q := (0 : QuadraticForm ℂ (Orbital Q))) (LinearMap.proj i)

noncomputable def occupationBasis (Q : ℕ) :
    Module.Basis (Finset (Fin (Q+1))) ℂ (Space Q) :=
  (Pi.basisFun ℂ (Fin (Q+1))).ExteriorAlgebra

def OccupationBidegree (Q n w : ℕ) (x : Space Q) : Prop :=
  ∀ A : Finset (Fin (Q+1)), (A.card ≠ n ∨ (∑ i ∈ A, i.val) ≠ w) →
    (occupationBasis Q).repr x A = 0

end Fock

namespace Planar
open Fock

abbrev Occupations (L : ℕ) := Finset (Fin (L+1))

noncomputable def pairMatrix (L : ℕ) (c : Fin (L+1) → Fin (L+1) → ℂ) :
    Matrix (Occupations L) (Occupations L) ℂ := fun A B =>
  ∑ i, ∑ j, c i j * (occupationBasis L).repr
    (annihilate j (annihilate i (occupationBasis L B))) A

noncomputable def planarCoefficient (p i j : ℕ) : ℂ :=
  ((pairLimitCoefficient p i j / Real.sqrt (2 : ℕ) : ℝ) : ℂ)

noncomputable def planarPairMatrix (L p : ℕ) : Matrix (Occupations L) (Occupations L) ℂ :=
  pairMatrix L (fun i j => planarCoefficient p i.val j.val)

noncomputable def planarHamiltonian (L : ℕ) : Matrix (Occupations L) (Occupations L) ℂ :=
  ∑ p ∈ Finset.range (2*L+1), (planarPairMatrix L p)ᴴ * planarPairMatrix L p

noncomputable def pairEnergy (L : ℕ)
    (P : ℕ → Matrix (Occupations L) (Occupations L) ℂ) (x : Occupations L → ℂ) : ℝ :=
  ∑ p ∈ Finset.range (2*L+1), ∑ A, ‖(P p *ᵥ x) A‖^2

noncomputable def squareNorm (L : ℕ) (H : Matrix (Occupations L) (Occupations L) ℂ)
    (x : Occupations L → ℂ) : ℝ := ∑ A, ‖(H *ᵥ x) A‖^2

/-- Occupation coefficients with fixed particle number in every homogeneous degree. -/
structure HomogeneousState (N : ℕ) where
  block : (L : ℕ) → Space L
  homogeneous : ∀ L, OccupationBidegree L N L (block L)

noncomputable def fullEnergy {N : ℕ} (ψ : HomogeneousState N) : ℝ≥0∞ :=
  ∑' L, ENNReal.ofReal (pairEnergy L (planarPairMatrix L)
    (fun A => (occupationBasis L).repr (ψ.block L) A))

noncomputable def fullSquareNorm {N : ℕ} (ψ : HomogeneousState N) : ℝ≥0∞ :=
  ∑' L, ENNReal.ofReal (squareNorm L (planarHamiltonian L)
    (fun A => (occupationBasis L).repr (ψ.block L) A))

end Planar

/-- The planar endpoint inequality in the homogeneous occupation representation. -/
theorem planar_gap {N : ℕ} (ψ : Planar.HomogeneousState N) :
    ENNReal.ofReal gammaStar * Planar.fullEnergy ψ ≤ Planar.fullSquareNorm ψ := by
  sorry

end Laughlin

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/LaughlinPlanar.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Laughlin.planar_gap` must keep exactly the statement shown above: same names,
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
