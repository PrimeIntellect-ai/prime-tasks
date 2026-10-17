# openai/math challenge `CoveringDensity` (family 092)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 092 of the release, *The optimal order of convex-body covering density*
(Convex and metric geometry). The family as a whole: Determines the optimal worst-case covering density as $\Theta(n\log n)$, for both lattice and unrestricted translative coverings. Every convex body in $\mathbb R^n$, $n\ge2$, admits a lattice covering of density at most $Cn\log n$; centrally symmetric examples in every sufficiently large dimension require at least $cn\log n$ even without the lattice restriction, for absolute $c,C>0$.

The challenge is `CoveringDensity`, also at `/opt/openai-math/challenges/CoveringDensity.lean`:

```lean
import Mathlib

namespace OAI

namespace CoveringOrder
open Set MeasureTheory
open scoped ENNReal

abbrev Space (n : ℕ) := EuclideanSpace ℝ (Fin n)

/-- Actual discrete full-rank lattice coverings; no assumed density theorem. -/
structure LatticeCover {n : ℕ} (K : Set (Space n)) where
  lattice : Submodule ℤ (Space n)
  discrete : DiscreteTopology lattice
  fullrank : IsZLattice ℝ lattice
  covers : ∀ y, ∃ l : lattice, y - l.val ∈ K

noncomputable def euclideanVolume (n : ℕ) :
    @Measure (EuclideanSpace ℝ (Fin n))
      (@WithLp.measurableSpace 2 (Fin n → ℝ)
        (@MeasurableSpace.pi (Fin n) (fun _ => ℝ) (fun _ => Real.measurableSpace))) :=
  @Measure.map (Fin n → ℝ) (EuclideanSpace ℝ (Fin n))
    (@MeasurableSpace.pi (Fin n) (fun _ => ℝ) (fun _ => Real.measurableSpace))
    (@WithLp.measurableSpace 2 (Fin n → ℝ)
      (@MeasurableSpace.pi (Fin n) (fun _ => ℝ) (fun _ => Real.measurableSpace)))
    (@WithLp.toLp 2 (Fin n → ℝ))
    (Measure.pi (fun _ : Fin n => @volume ℝ Real.measureSpace))

noncomputable def euclideanCovolume {n : ℕ}
    (lattice : Submodule ℤ (EuclideanSpace ℝ (Fin n))) : ℝ≥0∞ :=
  addCovolume lattice (EuclideanSpace ℝ (Fin n)) (euclideanVolume n)

noncomputable def latticeDensity {n : ℕ} {K : Set (Space n)}
    (cover : LatticeCover K) : ℝ≥0∞ :=
  euclideanVolume n K / euclideanCovolume cover.lattice

noncomputable def thetaL {n : ℕ} (K : Set (EuclideanSpace ℝ (Fin n))) : ℝ≥0∞ :=
  ⨅ cover : LatticeCover K, latticeDensity cover

end CoveringOrder

namespace TranslativeCovering

open Set Filter MeasureTheory
open scoped ENNReal

abbrev Space (n : ℕ) := EuclideanSpace ℝ (Fin n)

def cube (n : ℕ) (R : ℝ) : Set (Space n) :=
  {x | ∀ i, -R ≤ x i ∧ x i ≤ R}

def LocallyFiniteCenters {n : ℕ} (X : Set (Space n)) : Prop :=
  ∀ B : Set (Space n), Bornology.IsBounded B → (X ∩ B).Finite

def Covers {n : ℕ} (K X : Set (Space n)) : Prop :=
  ∀ y, ∃ x ∈ X, y - x ∈ K

def ConvexBody {n : ℕ} (K : Set (Space n)) : Prop :=
  IsCompact K ∧ Convex ℝ K ∧ (interior K).Nonempty

def CentrallySymmetric {n : ℕ} (K : Set (Space n)) : Prop :=
  ∃ z, ∀ x, x ∈ K ↔ (2 : ℝ) • z - x ∈ K

noncomputable def upperCenterIntensity {n : ℕ} (X : Set (Space n)) : ℝ≥0∞ :=
  Filter.limsup (fun R : ℝ =>
    (↑(X ∩ cube n R).ncard : ℝ≥0∞) / ENNReal.ofReal ((2 * R) ^ n)) atTop

noncomputable def thetaT {n : ℕ} (K : Set (Space n)) : ℝ≥0∞ :=
  ⨅ X : {X : Set (Space n) // LocallyFiniteCenters X ∧ Covers K X},
    volume K * upperCenterIntensity X.val

end TranslativeCovering

namespace CoveringOrder
open Set MeasureTheory
open scoped ENNReal

abbrev Body (n : ℕ) := {K : Set (Space n) // TranslativeCovering.ConvexBody K}
abbrev SymmetricBody (n : ℕ) :=
  {K : Body n // TranslativeCovering.CentrallySymmetric K.val}

noncomputable def translativeSup (n : ℕ) : ℝ≥0∞ :=
  ⨆ K : Body n, TranslativeCovering.thetaT K.val

noncomputable def symmetricTranslativeSup (n : ℕ) : ℝ≥0∞ :=
  ⨆ K : SymmetricBody n, TranslativeCovering.thetaT K.val.val

noncomputable def latticeSup (n : ℕ) : ℝ≥0∞ :=
  ⨆ K : Body n, thetaL K.val

noncomputable def symmetricLatticeSup (n : ℕ) : ℝ≥0∞ :=
  ⨆ K : SymmetricBody n, thetaL K.val.val

/-- The finite real comparison scale, viewed in extended nonnegative reals. -/
def orderBounds (c C : ℝ) (n : ℕ) (a : ℝ≥0∞) : Prop :=
  ENNReal.ofReal (c * (n : ℝ) * Real.log (n : ℝ)) ≤ a ∧
    a ≤ ENNReal.ofReal (C * (n : ℝ) * Real.log (n : ℝ))

/-- All four extremal quantities have common
absolute positive comparison constants. ENNReal bounds imply finiteness rather
than mapping a potentially infinite density to zero through `toReal`. -/
def OptimalOrder : Prop :=
  ∃ c C : ℝ, 0 < c ∧ 0 < C ∧ ∃ n₀ : ℕ, ∀ n : ℕ, n₀ ≤ n →
    orderBounds c C n (translativeSup n) ∧
    orderBounds c C n (symmetricTranslativeSup n) ∧
    orderBounds c C n (latticeSup n) ∧
    orderBounds c C n (symmetricLatticeSup n)

end CoveringOrder

/-- Translative and lattice covering densities over all convex bodies and over
centrally symmetric convex bodies have the same asymptotic order. -/
theorem CoveringOrder.optimal_order : CoveringOrder.OptimalOrder := by
  sorry

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/CoveringDensity.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.CoveringOrder.optimal_order` must keep exactly the statement shown above: same names,
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
