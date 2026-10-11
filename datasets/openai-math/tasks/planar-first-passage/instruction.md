# openai/math challenge `PlanarFirstPassage` (family 212)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 212 of the release, *No bigeodesics and smooth limit shapes in planar first-passage percolation*
(Probability and statistical mechanics). The family as a whole: Proves that planar first-passage percolation has no doubly infinite geodesic for iid nonnegative nonatomic edge weights when the minimum of four weights has finite second moment. For exponential weights, the limit shape is strictly convex with $C^1$ boundary. Differentiability also holds for every Gamma law with positive shape and rate.

The challenge is `PlanarFirstPassage`, also at `/opt/openai-math/challenges/PlanarFirstPassage.lean`:

```lean
import Mathlib.Algebra.BigOperators.Group.List.Basic
import Mathlib.Algebra.Group.Prod
import Mathlib.Analysis.Calculus.ContDiff.Defs
import Mathlib.Analysis.Calculus.Deriv.Basic
import Mathlib.Analysis.Calculus.FDeriv.Basic
import Mathlib.Analysis.InnerProductSpace.PiL2
import Mathlib.Analysis.LocallyConvex.WithSeminorms
import Mathlib.Probability.Distributions.Exponential
import Mathlib.Probability.Independence.Basic

namespace OAI

namespace PlanarFPP

open Set MeasureTheory ProbabilityTheory Filter
open scoped Topology

abbrev Vertex := ℤ × ℤ

abbrev Edge := Vertex × Bool

inductive Step where
  | east | west | north | south
  deriving DecidableEq

def Step.delta : Step → Vertex
  | .east => (1, 0)
  | .west => (-1, 0)
  | .north => (0, 1)
  | .south => (0, -1)

def Step.edge (p : Vertex) : Step → Edge
  | .east => (p, false)
  | .west => (p + (-1, 0), false)
  | .north => (p, true)
  | .south => (p + (0, -1), true)

def displacement (ds : List Step) : Vertex := (ds.map Step.delta).sum

def pathCost (τ : Edge → ℝ) (p : Vertex) : List Step → ℝ
  | [] => 0
  | d :: ds => τ (d.edge p) + pathCost τ (p + d.delta) ds

abbrev Plane := EuclideanSpace ℝ (Fin 2)

noncomputable def latticeFloor (v : Plane) : Vertex := (⌊v 0⌋, ⌊v 1⌋)

noncomputable def passageTime (τ : Edge → ℝ) (p q : Vertex) : ℝ :=
  sInf {t | ∃ ds : List Step, p + displacement ds = q ∧ pathCost τ p ds = t}

structure TimeConstantNorm (μ : Plane → ℝ) : Prop where
  nonneg : ∀ v, 0 ≤ μ v
  zero_iff : ∀ v, μ v = 0 ↔ v = 0
  triangle : ∀ v w, μ (v + w) ≤ μ v + μ w
  homogeneous : ∀ (a : ℝ) v, μ (a • v) = |a| * μ v

structure ExponentialEnvironment {Ω : Type*} [MeasurableSpace Ω]
    (P : Measure Ω) (τ : Edge → Ω → ℝ) : Prop where
  probability : IsProbabilityMeasure P
  measurable : ∀ e, Measurable (τ e)
  independent : iIndepFun τ P
  marginal : ∀ e, Measure.map (τ e) P = expMeasure 1

def IsTimeConstant {Ω : Type*} [MeasurableSpace Ω]
    (P : Measure Ω) (τ : Edge → Ω → ℝ) (μ : Plane → ℝ) : Prop :=
  ∀ v : Plane, ∀ᵐ ω ∂P,
    Tendsto (fun t : ℝ => passageTime (fun e => τ e ω) (0, 0)
      (latticeFloor (t • v)) / t) atTop (𝓝 (μ v))

def DifferentiableAwayFromOrigin (μ : Plane → ℝ) : Prop :=
  ∀ v : Plane, v ≠ 0 → ∃ ℓ : Plane →L[ℝ] ℝ, HasFDerivAt μ ℓ v

def UniqueNormalizedSupports (μ : Plane → ℝ) : Prop :=
  ∀ v : Plane, μ v = 1 → ∃! ℓ : Plane →L[ℝ] ℝ,
    ℓ v = 1 ∧ ∀ w, ℓ w ≤ μ w

def C1UnitSphere (μ : Plane → ℝ) : Prop :=
  ∀ v : Plane, μ v = 1 → ∃ U : Set Plane, IsOpen U ∧ v ∈ U ∧
    ∃ g : Plane → ℝ, ContDiffOn ℝ 1 g U ∧
      (∀ w ∈ U, μ w = 1 ↔ g w = 0) ∧
      ∀ w ∈ U, g w = 0 → ∃ ℓ : Plane →L[ℝ] ℝ,
        HasFDerivAt g ℓ w ∧ ℓ ≠ 0

def HasC1CurveChart (S : Set Plane) (v : Plane) : Prop :=
  ∃ U : Set Plane, IsOpen U ∧ v ∈ U ∧ v ∈ S ∧ ∃ γ : ℝ → Plane, ∃ θ : Plane → ℝ,
    ContDiff ℝ 1 γ ∧ ContinuousOn θ U ∧
    (∀ t, γ t ∈ S ∩ U) ∧ (∀ t, θ (γ t)=t) ∧
    (∀ z ∈ S ∩ U, γ (θ z)=z) ∧
    (∀ t, ∃ d : Plane, HasDerivAt γ d t ∧ d ≠ 0)

theorem manuscriptMain (Ω : Type) [MeasurableSpace Ω] (P : Measure Ω) (τ : Edge → Ω → ℝ)
    (henv : ExponentialEnvironment P τ) :
    ∃ μ : Plane → ℝ, TimeConstantNorm μ ∧ IsTimeConstant P τ μ ∧
      DifferentiableAwayFromOrigin μ ∧ UniqueNormalizedSupports μ ∧ C1UnitSphere μ ∧
      (∀ v ∈ frontier {z | μ z ≤ 1}, ∃! L : Set Plane,
        ∃ g : Plane →L[ℝ] ℝ, g ≠ 0 ∧ (∀ z, μ z ≤ 1 → g z ≤ g v) ∧ L={z | g z=g v}) ∧
      (∀ v ∈ frontier {z | μ z ≤ 1}, HasC1CurveChart (frontier {z | μ z ≤ 1}) v) := by
  sorry

end PlanarFPP

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/PlanarFirstPassage.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.PlanarFPP.manuscriptMain` must keep exactly the statement shown above: same names,
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
