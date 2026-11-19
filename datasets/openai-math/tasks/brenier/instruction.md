# openai/math challenge `Brenier` (family 374)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 374 of the release, *Sharp one-third stability of optimal transport maps*
(Partial differential equations). The family as a whole: For uniform source measure $\rho$ on a compact convex body with interior in dimension at least two, quadratic optimal transport maps satisfy $\|T_\mu-T_\nu\|_{L^2(\rho)}\le C W_2(\mu,\nu)^{1/3}$ uniformly over targets in a fixed compact set. The exponent is sharp, even for three-atom targets, disproving Letrouit's conjectured square-root bound.

The challenge is `Brenier`, also at `/opt/openai-math/challenges/Brenier.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

open MeasureTheory
open scoped BigOperators ENNReal

namespace Problem358

abbrev E (dimension : ℕ) := EuclideanSpace ℝ (Fin dimension)

def uniformMeasure {dimension : ℕ} (source : Set (E dimension)) : Measure (E dimension) :=
  (volume source)⁻¹ • volume.restrict source

def IsSupported {dimension : ℕ} (measure : Measure (E dimension))
    (container : Set (E dimension)) : Prop :=
  measure (containerᶜ) = 0

def IsCoupling {dimension : ℕ} (source target : Measure (E dimension))
    (plan : Measure (E dimension × E dimension)) : Prop :=
  IsProbabilityMeasure plan ∧
    Measure.map Prod.fst plan = source ∧
    Measure.map Prod.snd plan = target

def quadraticPlanCost {dimension : ℕ} (plan : Measure (E dimension × E dimension)) :
    ℝ≥0∞ :=
  ∫⁻ pair, ENNReal.ofReal (‖pair.1 - pair.2‖ ^ 2) ∂plan

def wasserstein2 {dimension : ℕ} (source target : Measure (E dimension)) : ℝ :=
  Real.sqrt
    (ENNReal.toReal
      (sInf {cost : ℝ≥0∞ |
        ∃ plan : Measure (E dimension × E dimension),
          IsCoupling source target plan ∧ quadraticPlanCost plan = cost}))

def graphPlan {dimension : ℕ} (source : Measure (E dimension))
    (transport : E dimension → E dimension) : Measure (E dimension × E dimension) :=
  Measure.map (fun point => (point, transport point)) source

def IsQuadraticOptimalMap {dimension : ℕ} (source target : Measure (E dimension))
    (transport : E dimension → E dimension) : Prop :=
  Measurable transport ∧
    Measure.map transport source = target ∧
    ∀ plan : Measure (E dimension × E dimension),
      IsCoupling source target plan →
        quadraticPlanCost (graphPlan source transport) ≤ quadraticPlanCost plan

def IsUniqueQuadraticOptimalMap {dimension : ℕ} (source target : Measure (E dimension))
    (transport : E dimension → E dimension) : Prop :=
  IsQuadraticOptimalMap source target transport ∧
    ∀ plan : Measure (E dimension × E dimension),
      IsCoupling source target plan →
        quadraticPlanCost plan ≤ quadraticPlanCost (graphPlan source transport) →
          plan = graphPlan source transport

def mapL2Dist {dimension : ℕ} (source : Measure (E dimension))
    (first second : E dimension → E dimension) : ℝ :=
  Real.sqrt (∫ point, ‖first point - second point‖ ^ 2 ∂source)

def cube (dimension : ℕ) : Set (E dimension) :=
  {point | ∀ index, |point index| ≤ 1}

def HasExactlyThreeAtoms {dimension : ℕ} (measure : Measure (E dimension))
    (container : Set (E dimension)) : Prop :=
  ∃ atoms : Fin 3 → E dimension, Function.Injective atoms ∧
    (∀ index, atoms index ∈ container) ∧
    ∃ weights : Fin 3 → ℝ≥0∞, (∀ index, 0 < weights index) ∧
      (∑ index, weights index) = 1 ∧
      measure = ∑ index, weights index • Measure.dirac (atoms index)

theorem one_third_stability :
    ∀ (dimension : ℕ) (source container : Set (E dimension)),
      2 ≤ dimension → IsCompact source → Convex ℝ source → (interior source).Nonempty →
      IsCompact container → container.Nonempty →
      ∃ constant : ℝ, 0 ≤ constant ∧
        ∀ (first second : Measure (E dimension)),
          IsProbabilityMeasure first → IsProbabilityMeasure second →
          IsSupported first container → IsSupported second container →
          ∃ firstMap secondMap : E dimension → E dimension,
            IsUniqueQuadraticOptimalMap (uniformMeasure source) first firstMap ∧
            IsUniqueQuadraticOptimalMap (uniformMeasure source) second secondMap ∧
            mapL2Dist (uniformMeasure source) firstMap secondMap ≤
              constant * Real.rpow (wasserstein2 first second) (1 / 3 : ℝ) := by
  sorry

theorem one_third_exponent_is_sharp :
    ∀ (dimension : ℕ), 2 ≤ dimension → ∀ exponent : ℝ, (1 / 3 : ℝ) < exponent →
      ∀ constant : ℝ, 0 < constant →
        ∃ (first second : Measure (E dimension)) (firstMap secondMap : E dimension → E dimension),
          IsProbabilityMeasure first ∧ IsProbabilityMeasure second ∧
          IsSupported first (cube dimension) ∧ IsSupported second (cube dimension) ∧
          HasExactlyThreeAtoms first (cube dimension) ∧
          HasExactlyThreeAtoms second (cube dimension) ∧
          first ≠ second ∧
          IsUniqueQuadraticOptimalMap (uniformMeasure (cube dimension)) first firstMap ∧
          IsUniqueQuadraticOptimalMap (uniformMeasure (cube dimension)) second secondMap ∧
          0 < wasserstein2 first second ∧
          constant * Real.rpow (wasserstein2 first second) exponent <
            mapL2Dist (uniformMeasure (cube dimension)) firstMap secondMap := by
  sorry

end Problem358

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/Brenier.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorems `OAI.Problem358.one_third_stability`, `OAI.Problem358.one_third_exponent_is_sharp` must keep exactly the statement shown above: same names,
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
