# openai/math challenge `YauCounterexample` (family 350)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 350 of the release, *Yau's nodal conjecture: surfaces and counterexamples*
(Differential geometry). The family as a whole: Proves the sharp $C\sqrt\lambda$ upper bound for nodal length on every fixed smooth closed surface, completing Yau's conjecture there. The upper bound fails for fixed smooth metrics in dimensions three and four, including metrics on $S^3$ arbitrarily close to round. In dimension five, nodal measure can grow faster than $\lambda^{1/2+\varepsilon_0}$ for some fixed $\varepsilon_0>0$, ruling out even arbitrarily small power losses.

The challenge is `YauCounterexample`, also at `/opt/openai-math/challenges/YauCounterexample.lean`:

```lean
import Mathlib

namespace OAI

namespace Yau
namespace Target
open Bundle Manifold Matrix Filter
open scoped ContDiff Topology ENNReal
noncomputable section

abbrev Base := Metric.sphere (0 : EuclideanSpace ℝ (Fin 5)) 1

abbrev Manifold5 := Base × Circle

abbrev Model := EuclideanSpace ℝ (Fin 4) × EuclideanSpace ℝ (Fin 1)

abbrev modelWithCorners := (𝓡 4).prod (𝓡 1)

abbrev SmoothMetric := ContMDiffRiemannianMetric modelWithCorners ∞ Model
  (fun x : Manifold5 ↦ TangentSpace modelWithCorners x)

abbrev Index := Fin (Module.finrank ℝ Model)

def frame : Module.Basis Index ℝ Model := Module.finBasis ℝ Model

def metricMatrix (g : SmoothMetric) (c : PartialEquiv Manifold5 Model)
    (y : Model) : Matrix Index Index ℝ := fun i j ↦
  g.inner (c.symm y)
    (mfderiv 𝓘(ℝ, Model) modelWithCorners c.symm y (frame i))
    (mfderiv 𝓘(ℝ, Model) modelWithCorners c.symm y (frame j))

def volumeFactor (g : SmoothMetric) (c : PartialEquiv Manifold5 Model)
    (y : Model) : ℝ := Real.sqrt (metricMatrix g c y).det

def chartLaplacian (g : SmoothMetric) (c : PartialEquiv Manifold5 Model)
    (u : Manifold5 → ℝ) (y : Model) : ℝ :=
  (volumeFactor g c y)⁻¹ * ∑ i, fderiv ℝ
    (fun z ↦ volumeFactor g c z * ∑ j,
      (metricMatrix g c z)⁻¹ i j * fderiv ℝ (u ∘ c.symm) z (frame j)) y (frame i)

def nodalMeasure (g : SmoothMetric) (u : Manifold5 → ℝ) : ℝ≥0∞ :=
  letI : RiemannianBundle (fun x : Manifold5 ↦ TangentSpace modelWithCorners x) :=
    ⟨g.toRiemannianMetric⟩
  letI : IsContMDiffRiemannianBundle modelWithCorners ∞ Model
      (fun x : Manifold5 ↦ TangentSpace modelWithCorners x) := inferInstance
  letI : MeasurableSpace Manifold5 := borel Manifold5
  letI : BorelSpace Manifold5 := ⟨rfl⟩
  letI : IsContinuousRiemannianBundle Model
      (fun x : Manifold5 ↦ TangentSpace modelWithCorners x) :=
    ⟨g.inner, g.toContinuousRiemannianMetric.continuous, fun _ _ _ ↦ rfl⟩
  letI : EMetricSpace Manifold5 := EMetricSpace.ofRiemannianMetric modelWithCorners Manifold5
  MeasureTheory.Measure.hausdorffMeasure (4 : ℝ) {x | u x = 0}

def MainTarget : Prop :=
  ∃ (g : SmoothMetric) (lam : ℕ → ℝ) (u : ℕ → Manifold5 → ℝ),
    (∀ k, 0 < lam k) ∧
    (∀ k, u k ≠ 0) ∧
    (∀ k, ContMDiff modelWithCorners 𝓘(ℝ, ℝ) ∞ (u k)) ∧
    (∀ k x, -chartLaplacian g (extChartAt modelWithCorners x) (u k) ((extChartAt modelWithCorners x) x) =
      lam k * u k x) ∧
    Tendsto lam atTop atTop ∧
    Tendsto (fun k ↦ nodalMeasure g (u k) / ENNReal.ofReal (Real.sqrt (lam k)))
      atTop (𝓝 ⊤)

theorem yau_nodal_set_upper_bound_counterexample : MainTarget := by
  sorry

end
end Target
end Yau

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/YauCounterexample.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Yau.Target.yau_nodal_set_upper_bound_counterexample` must keep exactly the statement shown above: same names,
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
