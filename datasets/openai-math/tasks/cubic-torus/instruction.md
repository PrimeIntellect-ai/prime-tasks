# openai/math challenge `CubicTorus` (family 354)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 354 of the release, *Isoperimetric regions in the cubic three-torus*
(Differential geometry). The family as a whole: Determines the isoperimetric profile of the unit cubic flat three-torus and classifies every finite-perimeter minimizer: balls, circular tubes around shortest closed geodesics, coordinate slabs, and their complements. The transition volumes are $4\pi/81$ and $1/\pi$, with exactly the adjacent two types minimizing at each transition.

The challenge is `CubicTorus`, also at `/opt/openai-math/challenges/CubicTorus.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open MeasureTheory Set
open scoped ENNReal

namespace CubicTorus

abbrev Cover := EuclideanSpace ℝ (Fin 3)
abbrev Torus := PiLp 2 (fun _ : Fin 3 => AddCircle (1 : ℝ))

/-- The quotient R³ → R³/Z³ in orthonormal coordinates. -/
def quotientMap (x : Cover) : Torus :=
  WithLp.toLp 2 (fun i => (x i : AddCircle (1 : ℝ)))

/-- One unit-volume fundamental domain; its boundary is immaterial to integration. -/
def fundamentalCube : Set Cover := {x | ∀ i, 0 ≤ x i ∧ x i < 1}

/-- The Riemannian volume measure of the unit flat torus. -/
def torusVolume : Measure Torus :=
  Measure.map quotientMap (volume.restrict fundamentalCube)

/-- An integer lattice vector in the Euclidean cover. -/
def latticeVector (n : Fin 3 → ℤ) : Cover := WithLp.toLp 2 (fun i => (n i : ℝ))

/-- The smooth vector fields on the flat torus with pointwise length at most one,
expressed as Z³-periodic fields on its Euclidean cover. The explicit ℕ∞ index
is C^∞; top of WithTop ℕ∞ would instead mean analytic in this Mathlib. -/
def AdmissibleField (F : Cover → Cover) : Prop :=
  ContDiff ℝ (⊤ : ℕ∞) F ∧
  (∀ (n : Fin 3 → ℤ) (x : Cover), F (x + latticeVector n) = F x) ∧
  ∀ x, ‖F x‖ ≤ 1

/-- Euclidean divergence in the orthonormal coordinate frame. -/
def divergence (F : Cover → Cover) (x : Cover) : ℝ :=
  ∑ i : Fin 3, (fderiv ℝ F x (EuclideanSpace.single i 1)) i

/-- De Giorgi perimeter, allowed to be infinite; no regularity of E is imposed. -/
def perimeter (E : Set Torus) : ℝ≥0∞ :=
  ⨆ (F : Cover → Cover) (_ : AdmissibleField F),
    ENNReal.ofReal (∫ x in fundamentalCube ∩ quotientMap ⁻¹' E, divergence F x)

/-- Finite-perimeter measurable regions, including all null-set modifications. -/
def FinitePerimeter (E : Set Torus) : Prop :=
  NullMeasurableSet E torusVolume ∧ perimeter E < ⊤

/-- A global perimeter minimizer under the prescribed volume constraint. -/
def IsMinimizerAt (V : ℝ) (E : Set Torus) : Prop :=
  FinitePerimeter E ∧ torusVolume E = ENNReal.ofReal V ∧
  ∀ F : Set Torus, FinitePerimeter F → torusVolume F = ENNReal.ofReal V →
    perimeter E ≤ perimeter F

/-- The candidate unit-torus isoperimetric profile. -/
def candidateProfile (V : ℝ) : ℝ :=
  let v := min V (1 - V)
  min ((36 * Real.pi) ^ (1 / 3 : ℝ) * v ^ (2 / 3 : ℝ))
    (min (2 * Real.sqrt (Real.pi * v)) 2)

/-- Canonical centered ball. Its radius on the listed branch is below 1/2. -/
def canonicalBall (V : ℝ) : Set Torus :=
  Metric.ball 0 ((3 * V / (4 * Real.pi)) ^ (1 / 3 : ℝ))

/-- Canonical tube around the shortest closed geodesic in coordinate direction 0. -/
def canonicalTube (V : ℝ) : Set Torus :=
  {x | ‖x 1‖ ^ 2 + ‖x 2‖ ^ 2 < (Real.sqrt (V / Real.pi)) ^ 2}

/-- Canonical slab of width V between two parallel coordinate tori. -/
def canonicalSlab (V : ℝ) : Set Torus := {x | ‖x 0‖ < V / 2}

/-- Equality of regions up to ambient flat isometry and a null set. -/
def CongruentAE (E F : Set Torus) : Prop :=
  ∃ φ : Torus ≃ᵢ Torus, E =ᵐ[torusVolume] (φ '' F)

/-- Exactly the closed phase ranges, so adjacent types are BOTH included at ties. -/
def SmallStandardRegion (V : ℝ) (E : Set Torus) : Prop :=
  (V ≤ 4 * Real.pi / 81 ∧ CongruentAE E (canonicalBall V)) ∨
  (4 * Real.pi / 81 ≤ V ∧ V ≤ 1 / Real.pi ∧ CongruentAE E (canonicalTube V)) ∨
  (1 / Real.pi ≤ V ∧ CongruentAE E (canonicalSlab V))

/-- The equality class at every interior volume, including complementation. -/
def StandardRegionAt (V : ℝ) (E : Set Torus) : Prop :=
  if V ≤ 1 / 2 then SmallStandardRegion V E
  else SmallStandardRegion (1 - V) Eᶜ

/-- Attainment, the sharp profile, and all equality cases at interior volumes. -/
theorem unit_cubic_isoperimetric (V : ℝ) (hV : V ∈ Ioo 0 1) :
    (∃ E : Set Torus, IsMinimizerAt V E) ∧
    (∀ E : Set Torus, IsMinimizerAt V E →
      perimeter E = ENNReal.ofReal (candidateProfile V)) ∧
    (∀ E : Set Torus, IsMinimizerAt V E ↔ StandardRegionAt V E) := by
  sorry

end CubicTorus
end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/CubicTorus.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.CubicTorus.unit_cubic_isoperimetric` must keep exactly the statement shown above: same names,
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
