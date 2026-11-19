# openai/math challenge `IsingFiniteness` (family 222)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 222 of the release, *Perceptron free energies and microscopic jamming*
(Probability and statistical mechanics). The family as a whole: Determines finite-temperature variational free energies for Gaussian Ising perceptrons with bounded Borel log-potentials and Gaussian spherical perceptrons with bounded continuous potentials, at every positive pattern density. A spherical extension treats bi-orthogonally invariant disorder with compact limiting singular-value distributions and no outliers. At margin $-1$, the quadratic-penalty spherical model has a sharp feasibility threshold and limiting gap and force laws, with system size, zero temperature, and critical density taken in that order.

The challenge is `IsingFiniteness`, also at `/opt/openai-math/challenges/IsingFiniteness.lean`:

```lean
import Mathlib

namespace OAI

open MeasureTheory ProbabilityTheory Filter
open scoped BigOperators Topology ENNReal

noncomputable section
namespace IsingPerceptron

def gaussianTransform (s d : ℝ) (U : ℝ → ℝ) (x : ℝ) : ℝ :=
  if d = 0 then ∫ z, U (x + Real.sqrt s * z) ∂gaussianReal 0 1
  else (Real.log (∫ z, Real.exp (d * U (x + Real.sqrt s * z))
    ∂gaussianReal 0 1)) / d

structure Partition where
  levels : ℕ
  positive : 0 < levels
  cut : Fin (levels + 1) → ℝ
  ordered : StrictMono cut
  first : cut ⟨0, Nat.zero_lt_succ levels⟩ = 0
  last : cut ⟨levels, Nat.lt_succ_self levels⟩ = 1

structure FieldStep where
  partition : Partition
  value : Fin partition.levels → ℝ
  nonneg : ∀ i, 0 ≤ value i
  ordered : Monotone value

 
def stepAt (h : FieldStep) (i : ℕ) : ℝ :=
  if hi : i < h.partition.levels then h.value ⟨i, hi⟩ else 0

 

def stepFunction (h : FieldStep) (u : ℝ) : ℝ :=
  ∑ i : Fin h.partition.levels,
    if h.partition.cut i.castSucc < u ∧ u < h.partition.cut i.succ then h.value i else 0

 
def fieldRecursion (h : FieldStep) : ℝ :=
  let k := h.partition.levels
  let increments := List.ofFn (fun i : Fin k =>
    (stepAt h i - (if i.val = 0 then 0 else stepAt h (i.val - 1)),
      h.partition.cut i.castSucc))
  increments.foldr (fun sd U => gaussianTransform sd.1 sd.2 U)
    (fun x => Real.log (Real.cosh x) - stepAt h (k - 1) / 2) 0

def pathMeasure : Measure ℝ := volume.restrict (Set.Ioo (0 : ℝ) 1)

 
structure OverlapPath where
  val : ℝ →ₘ[pathMeasure] ℝ
  admissible : ∃ q : ℝ → ℝ,
    (q =ᵐ[pathMeasure] val) ∧ MonotoneOn q (Set.Ioo 0 1) ∧
    ∀ u ∈ Set.Ioo (0 : ℝ) 1, q u ∈ Set.Icc (0 : ℝ) 1

 
def cellAverage (q : OverlapPath) (k i : ℕ) : ℝ :=
  (k : ℝ) * ∫ u in Set.Ioo ((i : ℝ) / k) (((i : ℝ) + 1) / k),
    q.val u ∂pathMeasure

 

def uniformPattern (f : ℝ → ℝ) (q : OverlapPath) (n : ℕ) : ℝ :=
  let k := n + 1
  let levelVal := fun i => if i < k then cellAverage q k i else 1
  let increments := List.ofFn (fun i : Fin (k + 1) =>
    (levelVal i - (if i.val = 0 then 0 else levelVal (i.val - 1)), (i : ℝ) / k))
  increments.foldr (fun sd U => gaussianTransform sd.1 sd.2 U) f 0

 

def patternFunctional (f : ℝ → ℝ) (q : OverlapPath) : ℝ :=
  Filter.limUnder atTop (uniformPattern f q)

 

def isingEntropy (q : OverlapPath) : EReal :=
  ⨆ h : FieldStep,
    ((fieldRecursion h + (∫ u, stepFunction h u * q.val u ∂pathMeasure) / 2 : ℝ) : EReal)

def variationalValue (α : ℝ) (f : ℝ → ℝ) : EReal :=
  ⨅ q : OverlapPath, (α * patternFunctional f q : ℝ) + isingEntropy q

theorem variationalValue_real_of_continuous {α : ℝ} (hα : 0 ≤ α)
    {f : ℝ → ℝ} (hf : Continuous f) (hbounded : ∃ K : ℝ, ∀ x, |f x| ≤ K) :
    ∃ p : ℝ, variationalValue α f = (p : EReal) := by
  sorry

end IsingPerceptron
end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/IsingFiniteness.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.IsingPerceptron.variationalValue_real_of_continuous` must keep exactly the statement shown above: same names,
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
