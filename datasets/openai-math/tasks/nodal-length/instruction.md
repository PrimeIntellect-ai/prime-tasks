# openai/math challenge `NodalLength` (family 350)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 350 of the release, *Yau's nodal conjecture: surfaces and counterexamples*
(Differential geometry). The family as a whole: Proves the sharp $C\sqrt\lambda$ upper bound for nodal length on every fixed smooth closed surface, completing Yau's conjecture there. The upper bound fails for fixed smooth metrics in dimensions three and four, including metrics on $S^3$ arbitrarily close to round. In dimension five, nodal measure can grow faster than $\lambda^{1/2+\varepsilon_0}$ for some fixed $\varepsilon_0>0$, ruling out even arbitrarily small power losses.

The challenge is `NodalLength`, also at `/opt/openai-math/challenges/NodalLength.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

open scoped ContDiff Bundle ENNReal
open Bundle Manifold MeasureTheory

namespace SharpNodal

abbrev Plane := EuclideanSpace ℝ (Fin 2)

variable {M : Type*} [MetricSpace M] [ChartedSpace Plane M]
  [IsManifold 𝓘(ℝ, Plane) ∞ M]
  [RiemannianBundle (fun x : M => TangentSpace 𝓘(ℝ, Plane) x)]

def coordinateMetric (x : M) (y : Plane) : Matrix (Fin 2) (Fin 2) ℝ :=
  fun i j => inner ℝ
    (mfderiv 𝓘(ℝ, Plane) 𝓘(ℝ, Plane) (chartAt Plane x).symm y
      (EuclideanSpace.single i 1))
    (mfderiv 𝓘(ℝ, Plane) 𝓘(ℝ, Plane) (chartAt Plane x).symm y
      (EuclideanSpace.single j 1))

def coordinateDensity (x : M) (y : Plane) : ℝ :=
  Real.sqrt (coordinateMetric x y).det

def coordPartial (f : Plane → ℝ) (i : Fin 2) (y : Plane) : ℝ :=
  fderiv ℝ f y (EuclideanSpace.single i 1)

def laplaceBeltrami (u : M → ℝ) (x : M) : ℝ :=
  (coordinateDensity x (chartAt Plane x x))⁻¹ *
    ∑ i : Fin 2, coordPartial (fun y => coordinateDensity x y *
      ∑ j : Fin 2, ((coordinateMetric x y)⁻¹ i j) *
        coordPartial (u ∘ (chartAt Plane x).symm) j y) i (chartAt Plane x x)

def nodalSet (u : M → ℝ) : Set M := {x | u x = 0}

def nodalLength (u : M → ℝ) : ℝ≥0∞ :=
  letI : MeasurableSpace M := borel M
  letI : BorelSpace M := ⟨rfl⟩
  Measure.hausdorffMeasure 1 (nodalSet u)

def MainStatement (M : Type*) [MetricSpace M] [ChartedSpace Plane M]
    [IsManifold 𝓘(ℝ, Plane) ∞ M]
    [RiemannianBundle (fun x : M => TangentSpace 𝓘(ℝ, Plane) x)] : Prop :=
  ∃ C : ℝ, 0 ≤ C ∧ ∀ (lam : ℝ), 0 < lam → ∀ (u : M → ℝ),
    ContMDiff 𝓘(ℝ, Plane) 𝓘(ℝ) ∞ u → u ≠ 0 →
    (∀ x, -laplaceBeltrami u x = lam * u x) →
    nodalLength u ≤ ENNReal.ofReal (C * Real.sqrt lam)

theorem Main [CompactSpace M] [ConnectedSpace M]
    [IsContMDiffRiemannianBundle 𝓘(ℝ,Plane) ∞ Plane
      (fun x:M=>TangentSpace 𝓘(ℝ,Plane) x)]
    [IsRiemannianManifold 𝓘(ℝ,Plane) M] : MainStatement M := by
  sorry

end SharpNodal

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/NodalLength.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.SharpNodal.Main` must keep exactly the statement shown above: same names,
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
