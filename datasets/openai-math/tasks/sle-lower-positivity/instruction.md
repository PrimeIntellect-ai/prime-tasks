# openai/math challenge `SLELowerPositivity` (family 230)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 230 of the release, *Exact Hausdorff measure for SLE*
(Probability and statistical mechanics). The family as a whole: Resolves Schramm’s Hausdorff-measure question for chordal $\mathrm{SLE}_\kappa$, $0<\kappa<8$. The explicit gauge $r^d(\log\log(1/r))^{(2-d)/2}$, $d=1+\kappa/8$, gives almost surely positive finite measure to every trace segment $\gamma([s,t])$ with $0<s<t<\infty$, and finite expected measure to the trace in every bounded disk.

The challenge is `SLELowerPositivity`, also at `/opt/openai-math/challenges/SLELowerPositivity.lean`:

```lean
import Mathlib

namespace OAI

/-! Positivity of the explicit Hausdorff gauge on all positive-time SLE segments. -/

noncomputable section
open Set Filter MeasureTheory
open scoped Topology ENNReal NNReal
namespace SLEExactGauge
universe v_lower

noncomputable def dimension (κ : ℝ) : ℝ := 1 + κ / 8

noncomputable def codimension (κ : ℝ) : ℝ := ((2 : ℕ) : ℝ) - dimension κ

def upperHalfPlane : Set ℂ := {z | 0 < z.im}

def survivingDomain (γ : ℝ≥0 → ℂ) (t : ℝ≥0) : Set ℂ :=
  {z | z ∈ upperHalfPlane \ (γ '' Icc 0 t) ∧
    ¬ Bornology.IsBounded (connectedComponentIn (upperHalfPlane \ (γ '' Icc 0 t)) z)}

def IsCapacityTwoWitness (U : ℝ≥0 → ℝ) (γ : ℝ≥0 → ℂ)
    (G F : ℝ≥0 → ℂ → ℂ) : Prop :=
  Continuous γ ∧ γ 0 = 0 ∧ (∀ t, 0 ≤ (γ t).im) ∧
    (∀ t, DifferentiableOn ℂ (G t) (survivingDomain γ t)) ∧
    (∀ t, DifferentiableOn ℂ (F t) upperHalfPlane) ∧
    (∀ t, MapsTo (G t) (survivingDomain γ t) upperHalfPlane) ∧
    (∀ t, MapsTo (F t) upperHalfPlane (survivingDomain γ t)) ∧
    (∀ t z, z ∈ survivingDomain γ t → F t (G t z) = z) ∧
    (∀ t z, z ∈ upperHalfPlane → G t (F t z) = z) ∧
    (∀ z ∈ upperHalfPlane, G 0 z = z) ∧
    (∀ t z, z ∈ survivingDomain γ t →
      HasDerivWithinAt (fun u : ℝ => G (Real.toNNReal u) z)
        (2 / (G t z - (U t : ℂ))) (Ici 0) (t : ℝ)) ∧
    (∀ t, Tendsto (fun z : ℂ => z * (G t z - z))
      (cocompact ℂ ⊓ 𝓟 (survivingDomain γ t)) (𝓝 (2 * (t : ℂ)))) ∧
    (∀ t, Tendsto (fun y : ℝ => F t ((U t : ℂ) + (y : ℂ) * Complex.I))
      (𝓝[>] 0) (𝓝 (γ t)))

def IsCapacityTwoTrace (U : ℝ≥0 → ℝ) (γ : ℝ≥0 → ℂ) : Prop :=
  ∃ G F : ℝ≥0 → ℂ → ℂ, IsCapacityTwoWitness U γ G F

def IsOrdinaryChordalSLE {Ω : Type*} [MeasurableSpace Ω]
    (κ : ℝ) (γ : Ω → ℝ≥0 → ℂ) (P : Measure Ω) : Prop :=
  (∀ t, Measurable (fun ω => γ ω t)) ∧
  ∃ B : ℝ≥0 → Ω → ℝ, ProbabilityTheory.IsBrownianReal B P ∧
    ∀ᵐ ω ∂P, IsCapacityTwoTrace (fun t => Real.sqrt κ * B t ω) (γ ω)

structure IsGauge (h : ℝ → ℝ) : Prop where
  continuousOn : ContinuousOn h (Ici 0)
  monotoneOn : MonotoneOn h (Ici 0)
  zero : h 0 = 0
  positive : ∀ r, 0 < r → 0 < h r

noncomputable def hFormula (κ r : ℝ) : ℝ :=
  r ^ dimension κ * (Real.log (Real.log (1 / r))) ^ (codimension κ / ((2 : ℕ) : ℝ))

def HasSmallRadiusFormula (h f : ℝ → ℝ) : Prop :=
  h =ᶠ[𝓝[>] 0] f

noncomputable def extendedGauge (h : ℝ → ℝ) (r : ℝ≥0∞) : ℝ≥0∞ :=
  ENNReal.ofReal (h r.toReal)

noncomputable def hausdorffGauge (h : ℝ → ℝ) : Measure ℂ :=
  Measure.mkMetric (extendedGauge h)

def segment (γ : ℝ≥0 → ℂ) (s t : ℝ≥0) : Set ℂ := γ '' Icc s t

def SourceLowerMainTarget : Prop :=
  ∀ (Ω : Type v_lower) (_ : MeasurableSpace Ω) (P : Measure Ω), IsProbabilityMeasure P →
  ∀ κ : ℝ, 0 < κ → κ < ((8 : ℕ) : ℝ) →
  ∀ (γ : Ω → ℝ≥0 → ℂ), IsOrdinaryChordalSLE κ γ P →
  ∀ h : ℝ → ℝ, IsGauge h → HasSmallRadiusFormula h (hFormula κ) →
    ∀ᵐ ω ∂P, ∀ s t : ℝ≥0, 0 < s → s < t →
      0 < hausdorffGauge h (segment (γ ω) s t)

theorem sourceLowerMain_proved : SourceLowerMainTarget := by
  sorry

end SLEExactGauge

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/SLELowerPositivity.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.SLEExactGauge.sourceLowerMain_proved` must keep exactly the statement shown above: same names,
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
