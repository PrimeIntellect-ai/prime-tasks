# openai/math challenge `RadialTransition` (family 228)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 228 of the release, *Continuum phase transitions for radial pair potentials*
(Probability and statistical mechanics). The family as a whole: Constructs stable distance-dependent pair interactions for three-dimensional classical particles with a first-order phase transition: the canonical free energy has a derivative jump at one inverse temperature throughout an open density interval. One potential has a divergent repulsive core; another is bounded and continuous with an integrable power-law tail, realizing the type of transition sought in Simon's continuum problem.

The challenge is `RadialTransition`, also at `/opt/openai-math/challenges/RadialTransition.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

open scoped BigOperators NNReal
open Filter MeasureTheory Set

namespace RadialTransition

abbrev Position := EuclideanSpace ℝ (Fin 3)
abbrev Potential := ℝ≥0 → ℝ

def cube (L : ℝ) : Set Position :=
  {x | ∀ k : Fin 3, 0 ≤ x k ∧ x k ≤ L}

def configurationCube (L : ℝ) (N : ℕ) : Set (Fin N → Position) :=
  {x | ∀ i : Fin N, x i ∈ cube L}

def energy (φ : Potential) {N : ℕ} (x : Fin N → Position) : ℝ :=
  ∑ i : Fin N, ∑ j : Fin N with i < j, φ (nndist (x i) (x j))

def partition (φ : Potential) (L : ℝ) (N : ℕ) (β : ℝ) : ℝ :=
  (N.factorial : ℝ)⁻¹ *
    ∫ x in configurationCube L N, Real.exp (-β * energy φ x)

def packingNumber (L : ℝ) : ℕ :=
  sSup {n : ℕ | ∃ X : Finset Position, X.card = n ∧
    (∀ x ∈ X, x ∈ cube L) ∧
    (∀ x ∈ X, ∀ y ∈ X, x ≠ y → 1 ≤ dist x y)}

def IsPackingDensity (p : ℝ) : Prop :=
  Tendsto (fun L : ℝ => (packingNumber L : ℝ) / L ^ 3) atTop (nhds p)

def IsBoundedPotential (φ : Potential) : Prop :=
  ∃ M : ℝ, 0 ≤ M ∧ ∀ r : ℝ≥0, |φ r| ≤ M

def StableWith (φ : Potential) (B : ℝ) : Prop :=
  ∀ (N : ℕ) (x : Fin N → Position), -(B * N) ≤ energy φ x

def AlgebraicDecayWith (φ : Potential) (C : ℝ) : Prop :=
  ∀ r : ℝ≥0, 1 ≤ r → |φ r| ≤ C * (r : ℝ) ^ (-(3 : ℝ) - 1 / 32)

def IsCanonicalFreeEnergy (φ : Potential) (ρ : ℝ) (f : ℝ → ℝ) : Prop :=
  ∀ β : ℝ, 0 < β →
    Tendsto (fun L : ℝ =>
      -(Real.log (partition φ L ⌊ρ * L ^ 3⌋₊ β) / (β * L ^ 3)))
      atTop (nhds (f β))

def StrictTemperatureCorner (f : ℝ → ℝ) (βc : ℝ) : Prop :=
  ∃ dLeft dRight : ℝ,
    HasDerivWithinAt f dLeft (Iic βc) βc ∧
    HasDerivWithinAt f dRight (Ici βc) βc ∧
    dRight < dLeft ∧ ¬DifferentiableAt ℝ f βc

theorem main :
    ∃ (p : ℝ) (φ : Potential) (B C : ℝ) (f : ℝ → ℝ) (βc : ℝ),
      0 < p ∧ IsPackingDensity p ∧
      IsBoundedPotential φ ∧ Continuous φ ∧
      0 < B ∧ 0 < C ∧ StableWith φ B ∧ AlgebraicDecayWith φ C ∧
      IsCanonicalFreeEnergy φ (5*p/3) f ∧
      βc ∈ Icc (7/8:ℝ) (9/8) ∧ StrictTemperatureCorner f βc := by
  sorry

end RadialTransition

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/RadialTransition.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.RadialTransition.main` must keep exactly the statement shown above: same names,
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
