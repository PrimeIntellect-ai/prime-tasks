# openai/math challenge `SmoothObstruction` (family 152)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 152 of the release, *Zero entropy does not guarantee a smooth positive-volume model*
(Dynamical systems and ergodic theory). The family as a whole: Constructs a zero-entropy ergodic invertible transformation of a standard nonatomic probability space that is not measurably conjugate to any $C^\infty$ diffeomorphism preserving a strictly positive smooth probability density on a compact finite-dimensional manifold. One example rules out every finite dimension.

The challenge is `SmoothObstruction`, also at `/opt/openai-math/challenges/SmoothObstruction.lean`:

```lean
import Mathlib

namespace OAI


open MeasureTheory Set Filter
open scoped ENNReal Topology Manifold ContDiff

namespace SmoothObstruction

/-- Shannon entropy in bits; the value at mass zero is zero. -/
noncomputable def entropyTerm (p : ℝ) : ℝ := -(p * Real.log p) / Real.log 2

/-- The entropy of the length-`n` join of the partition with labels in `Fin q`. -/
noncomputable def blockEntropy {X : Type*} [MeasurableSpace X]
    (μ : Measure X) (T : X → X) {q : ℕ} (P : X → Fin q) (n : ℕ) : ℝ :=
  ∑ w : Fin n → Fin q,
    entropyTerm ((μ {x | ∀ j : Fin n, P ((T^[j.val]) x) = w j}).toReal)

/-- All finite-partition entropy rates exist and have one finite real upper
bound. This spells out `sup_P lim_n H(join_{j<n} T^{-j}P)/n < ∞` without
choosing a value for limits of nonconvergent sequences. Empty atoms are allowed. -/
def FiniteKSEntropy {X : Type*} [MeasurableSpace X]
    (μ : Measure X) (T : X → X) : Prop :=
  ∃ C : ℝ, ∀ (q : ℕ) (P : X → Fin (q + 1)), Measurable P →
    ∃ h : ℝ, h ≤ C ∧
      Tendsto (fun n : ℕ => blockEntropy μ T P n / (n : ℝ)) atTop (𝓝 h)

/-- Measure-space isomorphism after removing measurable null sets. -/
def ConullIsomorphic {X Y : Type*} [MeasurableSpace X] [MeasurableSpace Y]
    (μ : Measure X) (ν : Measure Y) : Prop :=
  ∃ (A : Set X) (B : Set Y), MeasurableSet A ∧ MeasurableSet B ∧
    μ Aᶜ = 0 ∧ ν Bᶜ = 0 ∧
    ∃ e : A ≃ᵐ B,
      MeasurePreserving e (μ.comap (Subtype.val : A → X))
        (ν.comap (Subtype.val : B → Y))

/-- Standard nonatomic in the source's explicit modulo-null-set sense. -/
def StandardNonatomic {X : Type*} [MeasurableSpace X] (μ : Measure X) : Prop :=
  ConullIsomorphic μ
    (volume.comap (Subtype.val : Set.Icc (0 : ℝ) 1 → ℝ))

/-- Measurable conjugacy on invariant conull measurable subsets, not a
continuous conjugacy and not merely a factor map. -/
def ConullConjugate {X Y : Type*} [MeasurableSpace X] [MeasurableSpace Y]
    (μ : Measure X) (T : X → X) (ν : Measure Y) (S : Y → Y) : Prop :=
  ∃ (A : Set X) (B : Set Y), MeasurableSet A ∧ MeasurableSet B ∧
    μ Aᶜ = 0 ∧ ν Bᶜ = 0 ∧ T ⁻¹' A = A ∧ S ⁻¹' B = B ∧
    ∃ e : A ≃ᵐ B,
      MeasurePreserving e (μ.comap (Subtype.val : A → X))
        (ν.comap (Subtype.val : B → Y)) ∧
      ∀ (x y : A), T x = y → (e y : Y) = S (e x)

/-- Positive smooth local coordinate densities. In a half-space chart,
`ContDiffOn` includes smoothness up to the boundary. Absolute Lebesgue density
is used; no orientation or volume form is part of the data. -/
def SmoothPositiveDensity {d : ℕ} {H : Type*} [TopologicalSpace H]
    (I : ModelWithCorners ℝ (EuclideanSpace ℝ (Fin d)) H)
    {M : Type*} [TopologicalSpace M] [ChartedSpace H M] [MeasurableSpace M]
    (ν : Measure M) : Prop :=
  ∀ x : M, ∃ f : EuclideanSpace ℝ (Fin d) → ℝ,
    ContDiffOn ℝ ∞ f (extChartAt I x).target ∧
    (∀ y ∈ (extChartAt I x).target, 0 < f y) ∧
    Measure.map (extChartAt I x) (ν.restrict (extChartAt I x).source) =
      (volume.withDensity (fun y => ENNReal.ofReal (f y))).restrict
        (extChartAt I x).target

/-- A smooth positive-volume model with a specified Euclidean or half-space
manifold model. All model dimensions will be quantified below. -/
def HasModelWith {X : Type*} [MeasurableSpace X]
    (μ : Measure X) (T : X → X) {d : ℕ} {H : Type} [TopologicalSpace H]
    (I : ModelWithCorners ℝ (EuclideanSpace ℝ (Fin d)) H) : Prop :=
  ∃ (M : Type) (_ : TopologicalSpace M) (_ : MeasurableSpace M)
      (_ : BorelSpace M) (_ : T2Space M) (_ : SecondCountableTopology M)
      (_ : CompactSpace M) (_ : ChartedSpace H M) (_ : IsManifold I ∞ M)
      (ν : Measure M) (_ : IsProbabilityMeasure ν)
      (S : Diffeomorph I I M M ∞),
    SmoothPositiveDensity I ν ∧ MeasurePreserving S ν ν ∧
      ConullConjugate μ T ν S

/-- Closed manifolds of all dimensions (including zero), and smooth manifolds
with boundary of every positive finite dimension. Nonorientable manifolds
are included: no orientability hypothesis occurs. -/
def HasSmoothPositiveVolumeModel {X : Type*} [MeasurableSpace X]
    (μ : Measure X) (T : X → X) : Prop :=
  (∃ d : ℕ, HasModelWith μ T (𝓡 d)) ∨
    (∃ d : ℕ, ∃ _ : NeZero d, HasModelWith μ T (𝓡∂ d))

/-- A finite-entropy standard nonatomic ergodic system with no smooth positive-volume model. -/
theorem main :
    ∃ (X : Type) (_ : MeasurableSpace X) (μ : Measure X)
      (_ : IsProbabilityMeasure μ) (T : X ≃ᵐ X),
      StandardNonatomic μ ∧ Ergodic T μ ∧ FiniteKSEntropy μ T ∧
        ¬ HasSmoothPositiveVolumeModel μ T := by
  sorry

end SmoothObstruction

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/SmoothObstruction.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.SmoothObstruction.main` must keep exactly the statement shown above: same names,
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
