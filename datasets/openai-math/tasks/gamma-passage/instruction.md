# openai/math challenge `GammaPassage` (family 212)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 212 of the release, *No bigeodesics and smooth limit shapes in planar first-passage percolation*
(Probability and statistical mechanics). The family as a whole: Proves that planar first-passage percolation has no doubly infinite geodesic for iid nonnegative nonatomic edge weights when the minimum of four weights has finite second moment. For exponential weights, the limit shape is strictly convex with $C^1$ boundary. Differentiability also holds for every Gamma law with positive shape and rate.

The challenge is `GammaPassage`, also at `/opt/openai-math/challenges/GammaPassage.lean`:

```lean
import Mathlib.Algebra.BigOperators.Group.List.Basic
import Mathlib.Algebra.Group.Prod
import Mathlib.Analysis.Calculus.ContDiff.Defs
import Mathlib.Analysis.Calculus.Deriv.Basic
import Mathlib.Analysis.Calculus.FDeriv.Basic
import Mathlib.Analysis.InnerProductSpace.PiL2
import Mathlib.Probability.Distributions.Gamma
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

def IsTimeConstant {Ω : Type*} [MeasurableSpace Ω]
    (P : Measure Ω) (τ : Edge → Ω → ℝ) (μ : Plane → ℝ) : Prop :=
  ∀ v : Plane, ∀ᵐ ω ∂P,
    Tendsto (fun t : ℝ => passageTime (fun e => τ e ω) (0, 0)
      (latticeFloor (t • v)) / t) atTop (𝓝 (μ v))

def DifferentiableAwayFromOrigin (μ : Plane → ℝ) : Prop :=
  ∀ v : Plane, v ≠ 0 → ∃ ℓ : Plane →L[ℝ] ℝ, HasFDerivAt μ ℓ v

end PlanarFPP

namespace GammaFPP

open Set MeasureTheory ProbabilityTheory PlanarFPP

structure IidEnvironment {Ω : Type*} [MeasurableSpace Ω]
    (ν : Measure ℝ) (P : Measure Ω) (τ : PlanarFPP.Edge → Ω → ℝ) : Prop where
  probability : IsProbabilityMeasure P
  measurable : ∀ e, Measurable (τ e)
  independent : iIndepFun τ P
  marginal : ∀ e, Measure.map (τ e) P = ν


abbrev GammaEnvironment {Ω : Type*} [MeasurableSpace Ω]
    (shape rate : ℝ) (P : Measure Ω) (τ : PlanarFPP.Edge → Ω → ℝ) :=
  IidEnvironment (gammaMeasure shape rate) P τ


/-- A regular C¹ parametrization of the curve near a point, with a continuous inverse. -/
def HasC1CurveChart (S : Set Plane) (v : Plane) : Prop :=
  ∃ U : Set Plane, IsOpen U ∧ v ∈ U ∧ v ∈ S ∧ ∃ γ : ℝ → Plane, ∃ θ : Plane → ℝ,
    ContDiff ℝ 1 γ ∧ ContinuousOn θ U ∧
    (∀ t, γ t ∈ S ∩ U) ∧ (∀ t, θ (γ t)=t) ∧
    (∀ z ∈ S ∩ U, γ (θ z)=z) ∧
    (∀ t, ∃ d : Plane, HasDerivAt γ d t ∧ d ≠ 0)

/-- The Gamma theorem: an actual deterministic passage-time limit norm exists
for every positive shape and rate and every iid environment with that law.
Its Frechet differentiability and literal unit-ball boundary charts are
conclusions. No shape theorem, norm, or no-corner hypothesis is supplied. -/
def GammaDifferentiabilityTarget : Prop :=
  ∀ (shape rate : ℝ), 0 < shape → 0 < rate →
    ∀ (Ω : Type) [MeasurableSpace Ω] (P : Measure Ω)
      (τ : PlanarFPP.Edge → Ω → ℝ),
      GammaEnvironment shape rate P τ →
        ∃ μ : Plane → ℝ,
          TimeConstantNorm μ ∧ IsTimeConstant P τ μ ∧
          DifferentiableAwayFromOrigin μ ∧
          ∀ v ∈ frontier {z : Plane | μ z ≤ 1},
            HasC1CurveChart (frontier {z : Plane | μ z ≤ 1}) v

theorem gamma_differentiability : GammaDifferentiabilityTarget := by
  sorry

end GammaFPP

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/GammaPassage.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.GammaFPP.gamma_differentiability` must keep exactly the statement shown above: same names,
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
