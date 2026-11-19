# openai/math challenge `CoulombCounterexample` (family 373)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 373 of the release, *Nonattainment in three-marginal Coulomb transport*
(Partial differential equations). The family as a whole: An optimal three-particle Coulomb configuration need not be a deterministic function of the first particle, even for smooth identical spatial densities. The Monge and Kantorovich infima agree, but the Monge infimum is not attained. The same phenomenon occurs for every inverse-power Riesz exponent in each dimension at least two, with a suitable density in each case.

The challenge is `CoulombCounterexample`, also at `/opt/openai-math/challenges/CoulombCounterexample.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

open MeasureTheory
open scoped ENNReal

namespace Problem356

abbrev E3 := EuclideanSpace ℝ (Fin 3)

abbrev Triple := E3 × (E3 × E3)

def tripleFst (t : Triple) : E3 := t.1

def tripleSnd (t : Triple) : E3 := t.2.1

def tripleThd (t : Triple) : E3 := t.2.2

def invDistance (x y : E3) : ℝ≥0∞ :=
  (ENNReal.ofReal ‖x - y‖)⁻¹

def coulombCost (t : Triple) : ℝ≥0∞ :=
  invDistance (tripleFst t) (tripleSnd t) +
    invDistance (tripleFst t) (tripleThd t) +
    invDistance (tripleSnd t) (tripleThd t)

def IsThreeCoupling (mu : Measure E3) (pi : Measure Triple) : Prop :=
  IsProbabilityMeasure pi ∧
    Measure.map tripleFst pi = mu ∧
    Measure.map tripleSnd pi = mu ∧
    Measure.map tripleThd pi = mu

def densityMeasure (rho : E3 → ℝ) : Measure E3 :=
  Measure.withDensity (volume : Measure E3) (fun x => ENNReal.ofReal (rho x))

def Preserves (mu : Measure E3) (T : E3 → E3) : Prop :=
  Measurable T ∧ Measure.map T mu = mu

def graphCost (mu : Measure E3) (T2 T3 : E3 → E3) : ℝ≥0∞ :=
  ∫⁻ x, coulombCost (x, (T2 x, T3 x)) ∂mu

def kantorovichValue (mu : Measure E3) : ℝ≥0∞ :=
  ⨅ (pi : Measure Triple), ⨅ (_h : IsThreeCoupling mu pi),
    ∫⁻ t, coulombCost t ∂pi

def mongeValue (mu : Measure E3) : ℝ≥0∞ :=
  ⨅ (T2 : E3 → E3), ⨅ (T3 : E3 → E3),
    ⨅ (_h2 : Preserves mu T2), ⨅ (_h3 : Preserves mu T3),
      graphCost mu T2 T3

def IsSmoothCompactProbabilityDensity (rho : E3 → ℝ) : Prop :=
  (∀ x, 0 ≤ rho x) ∧
    ContDiff ℝ (↑(⊤ : ENat) : WithTop ENat) rho ∧
    HasCompactSupport rho ∧
    ContDiff ℝ (↑(⊤ : ENat) : WithTop ENat) (fun x : E3 => Real.sqrt (rho x)) ∧
    HasCompactSupport (fun x : E3 => Real.sqrt (rho x)) ∧
    (∫ x : E3, rho x ∂(volume : Measure E3)) = 1

def KantorovichAttained (mu : Measure E3) : Prop :=
  ∃ pi : Measure Triple,
    IsThreeCoupling mu pi ∧
      (∫⁻ t, coulombCost t ∂pi) = kantorovichValue mu

def NoMongeOptimizer (mu : Measure E3) : Prop :=
  ∀ T2 T3 : E3 → E3,
    Preserves mu T2 → Preserves mu T3 →
      kantorovichValue mu < graphCost mu T2 T3

def FiniteMongeApproximation (mu : Measure E3) : Prop :=
  ∀ epsilon : ℝ, 0 < epsilon →
    ∃ T2 T3 : E3 → E3,
      Preserves mu T2 ∧
      Preserves mu T3 ∧
      graphCost mu T2 T3 < ⊤ ∧
      graphCost mu T2 T3 ≤
        kantorovichValue mu + ENNReal.ofReal epsilon

def HasCoulombCounterexample (rho : E3 → ℝ) : Prop :=
  IsSmoothCompactProbabilityDensity rho ∧
    IsProbabilityMeasure (densityMeasure rho) ∧
    kantorovichValue (densityMeasure rho) < ⊤ ∧
    KantorovichAttained (densityMeasure rho) ∧
    NoMongeOptimizer (densityMeasure rho)

def HasFullCoulombConclusion (rho : E3 → ℝ) : Prop :=
  HasCoulombCounterexample rho ∧
    mongeValue (densityMeasure rho) =
      kantorovichValue (densityMeasure rho) ∧
    FiniteMongeApproximation (densityMeasure rho)

theorem coulomb_counterexample_and_equal_infima :
    ∃ rho : E3 → ℝ, HasFullCoulombConclusion rho := by
  sorry

end Problem356

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/CoulombCounterexample.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Problem356.coulomb_counterexample_and_equal_infima` must keep exactly the statement shown above: same names,
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
