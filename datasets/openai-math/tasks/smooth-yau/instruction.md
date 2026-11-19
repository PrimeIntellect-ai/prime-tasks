# openai/math challenge `SmoothYau` (family 350)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 350 of the release, *Yau's nodal conjecture: surfaces and counterexamples*
(Differential geometry). The family as a whole: Proves the sharp $C\sqrt\lambda$ upper bound for nodal length on every fixed smooth closed surface, completing Yau's conjecture there. The upper bound fails for fixed smooth metrics in dimensions three and four, including metrics on $S^3$ arbitrarily close to round. In dimension five, nodal measure can grow faster than $\lambda^{1/2+\varepsilon_0}$ for some fixed $\varepsilon_0>0$, ruling out even arbitrarily small power losses.

The challenge is `SmoothYau`, also at `/opt/openai-math/challenges/SmoothYau.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
namespace YauCounterexamples
section
open Set Filter Manifold Bundle MeasureTheory
open scoped Topology ContDiff ENNReal


abbrev Euclidean (n : ℕ) := EuclideanSpace ℝ (Fin n)
abbrev Sphere (n : ℕ) := Metric.sphere (0 : Euclidean (n + 1)) 1
abbrev FourManifold := Sphere 2 × (Circle × Circle)
abbrev FourModel := Euclidean 2 × (Euclidean 1 × Euclidean 1)

instance torusChartedSpace : ChartedSpace (Euclidean 1 × Euclidean 1) (Circle × Circle) :=
  prodChartedSpace (Euclidean 1) Circle (Euclidean 1) Circle

instance torusIsManifold : IsManifold 𝓘(ℝ, Euclidean 1 × Euclidean 1) ∞ (Circle × Circle) := by
  rw [modelWithCornersSelf_prod]
  exact IsManifold.prod Circle Circle

instance fourChartedSpace : ChartedSpace FourModel FourManifold :=
  prodChartedSpace (Euclidean 2) (Sphere 2) (Euclidean 1 × Euclidean 1) (Circle × Circle)

instance fourIsManifold : IsManifold 𝓘(ℝ, FourModel) ∞ FourManifold := by
  rw [show 𝓘(ℝ, FourModel) = 𝓘(ℝ, Euclidean 2).prod
    𝓘(ℝ, Euclidean 1 × Euclidean 1) from modelWithCornersSelf_prod]
  exact IsManifold.prod (Sphere 2) (Circle × Circle)

section Definitions
variable {E : Type*} [NormedAddCommGroup E] [NormedSpace ℝ E]
  [FiniteDimensional ℝ E]
variable {M : Type*} [TopologicalSpace M] [ChartedSpace E M]
  [IsManifold 𝓘(ℝ, E) ∞ M]

/-- Ordinary smooth positive-definite Riemannian metrics, with the existing tangent topology. -/
abbrev SmoothMetric (E : Type*) [NormedAddCommGroup E] [NormedSpace ℝ E]
    (M : Type*) [TopologicalSpace M] [ChartedSpace E M] [IsManifold 𝓘(ℝ, E) ∞ M] :=
  ContMDiffRiemannianMetric 𝓘(ℝ, E) ∞ E (fun x : M => TangentSpace 𝓘(ℝ, E) x)

abbrev CoordIndex (E : Type*) [NormedAddCommGroup E] [NormedSpace ℝ E]
    [FiniteDimensional ℝ E] := Fin (Module.finrank ℝ E)

/-- A coordinate vector, pushed from a chart back into the tangent bundle. -/
def coordinateVector (p : M) (y : E) (i : CoordIndex E) :
    TangentSpace 𝓘(ℝ, E) ((chartAt E p).symm y) :=
  mfderiv 𝓘(ℝ, E) 𝓘(ℝ, E) (chartAt E p).symm y (Module.finBasis ℝ E i)

/-- Metric coefficients in a chart. Only values in the chart target are used. -/
def metricCoefficients (g : SmoothMetric E M) (p : M) (y : E) :
    Matrix (CoordIndex E) (CoordIndex E) ℝ :=
  fun i j => g.inner ((chartAt E p).symm y)
    (coordinateVector p y i) (coordinateVector p y j)

/-- The local coordinate formula det(g)^(-1/2) d_i(det(g)^(1/2) g^{ij} d_j u).
The chart at the evaluation point is used, so all derivatives are taken in
its open target. -/
def laplaceBeltrami (g : SmoothMetric E M) (u : M → ℝ) (x : M) : ℝ :=
  let c := chartAt E x
  let a := metricCoefficients g x
  let density := fun y => Real.sqrt (Matrix.det (a y))
  let u' := u ∘ c.symm
  (density (c x))⁻¹ * ∑ i, fderiv ℝ
    (fun y => density y * ∑ j, (a y)⁻¹ i j *
      fderiv ℝ u' y (Module.finBasis ℝ E j))
    (c x) (Module.finBasis ℝ E i)

/-- One compact-chart seminorm test for the usual smooth topology of metrics. -/
structure CoordinateTest (E : Type*) [NormedAddCommGroup E] [NormedSpace ℝ E]
    [FiniteDimensional ℝ E] (M : Type*) [TopologicalSpace M] [ChartedSpace E M] where
  center : M
  compactSet : Set E
  isCompact : IsCompact compactSet
  inTarget : compactSet ⊆ (chartAt E center).target
  order : ℕ
  row : CoordIndex E
  column : CoordIndex E

/-- The finite compact-chart derivative tests defining a C∞ neighborhood.
A single positive tolerance suffices for the finitely many tests. -/
def IsSmoothNeighborhood (g₀ : SmoothMetric E M) (N : Set (SmoothMetric E M)) : Prop :=
  ∃ tests : List (CoordinateTest E M), ∃ ε : ℝ, 0 < ε ∧
    ∀ g : SmoothMetric E M,
      (∀ t ∈ tests, ∀ y ∈ t.compactSet,
        ‖iteratedFDeriv ℝ t.order
          (fun z => metricCoefficients g t.center z t.row t.column -
            metricCoefficients g₀ t.center z t.row t.column) y‖ < ε) → g ∈ N

/-- Hausdorff measure for the path distance of the actual Riemannian metric,
not the metric inherited from any ambient embedding. -/
def nodalMeasure [T3Space M] (g : SmoothMetric E M) (d : ℝ) (u : M → ℝ) : ℝ≥0∞ :=
  letI : RiemannianBundle (fun x : M => TangentSpace 𝓘(ℝ, E) x) :=
    ⟨g.toRiemannianMetric⟩
  letI : IsContinuousRiemannianBundle E (fun x : M => TangentSpace 𝓘(ℝ, E) x) :=
    ⟨⟨g.inner, g.contMDiff.continuous, fun _ _ _ => rfl⟩⟩
  letI : EMetricSpace M := EMetricSpace.ofRiemannianMetric 𝓘(ℝ, E) M
  letI : MeasurableSpace M := borel M
  letI : BorelSpace M := ⟨rfl⟩
  Measure.hausdorffMeasure d {x | u x = 0}

/-- The eigensequence belongs to one fixed metric and has finite nodal measure. -/
def HasUnboundedNodalRatio [T3Space M] (g : SmoothMetric E M) (d : ℕ) : Prop :=
  ∃ (u : ℕ → M → ℝ) (eigenvalue : ℕ → ℝ),
    (∀ j, ContMDiff 𝓘(ℝ, E) 𝓘(ℝ, ℝ) ∞ (u j) ∧ u j ≠ 0 ∧ 0 < eigenvalue j ∧
      (∀ x, -laplaceBeltrami g (u j) x = eigenvalue j * u j x) ∧
      nodalMeasure g (d - 1 : ℕ) (u j) ≠ (∞ : ℝ≥0∞)) ∧
    Tendsto eigenvalue atTop atTop ∧
    Tendsto (fun j => (nodalMeasure g (d - 1 : ℕ) (u j)).toReal / Real.sqrt (eigenvalue j))
      atTop atTop

end Definitions

/-- The round metric is the pullback of the Euclidean scalar product under
inclusion of the unit sphere. This predicate specifies exactly that tensor. -/
def IsRound (g : SmoothMetric (Euclidean 3) (Sphere 3)) : Prop :=
  ∀ (x : Sphere 3) (v w : TangentSpace 𝓘(ℝ, Euclidean 3) x),
    g.inner x v w = inner ℝ
      (mfderiv 𝓘(ℝ, Euclidean 3) 𝓘(ℝ, Euclidean 4)
        (fun y : Sphere 3 => (y : Euclidean 4)) x v)
      (mfderiv 𝓘(ℝ, Euclidean 3) 𝓘(ℝ, Euclidean 4)
        (fun y : Sphere 3 => (y : Euclidean 4)) x w)


end

open Set Filter Manifold Bundle MeasureTheory
open scoped Topology ContDiff ENNReal


theorem sphere_three (gRound : SmoothMetric (Euclidean 3) (Sphere 3))
    (hRound : IsRound gRound) :
    ∀ N : Set (SmoothMetric (Euclidean 3) (Sphere 3)),
      IsSmoothNeighborhood gRound N →
      ∃ g ∈ N, HasUnboundedNodalRatio g 3 := by
  sorry

theorem sphere_two_torus_two :
    ∃ g : SmoothMetric FourModel FourManifold,
      HasUnboundedNodalRatio g 4 := by
  sorry



end YauCounterexamples
end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/SmoothYau.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorems `OAI.YauCounterexamples.sphere_three`, `OAI.YauCounterexamples.sphere_two_torus_two` must keep exactly the statement shown above: same names,
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
