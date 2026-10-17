# openai/math challenge `PerceptronFreeEnergy` (family 222)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 222 of the release, *Perceptron free energies and microscopic jamming*
(Probability and statistical mechanics). The family as a whole: Determines finite-temperature variational free energies for Gaussian Ising perceptrons with bounded Borel log-potentials and Gaussian spherical perceptrons with bounded continuous potentials, at every positive pattern density. A spherical extension treats bi-orthogonally invariant disorder with compact limiting singular-value distributions and no outliers. At margin $-1$, the quadratic-penalty spherical model has a sharp feasibility threshold and limiting gap and force laws, with system size, zero temperature, and critical density taken in that order.

The challenge is `PerceptronFreeEnergy`, also at `/opt/openai-math/challenges/PerceptronFreeEnergy.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open MeasureTheory ProbabilityTheory Filter Set
open scoped ENNReal NNReal Topology BigOperators BoundedContinuousFunction

namespace SphericalPerceptronFreeEnergy

abbrev Time := unitInterval
abbrev BrownianPath := C(ℝ≥0, ℝ)

instance : MeasurableSpace BrownianPath := borel BrownianPath
instance : BorelSpace BrownianPath := ⟨rfl⟩

abbrev Spin (N : ℕ) := EuclideanSpace ℝ (Fin N)

def patternCount (α : ℝ) (N : ℕ) : ℕ := ⌊α * (N : ℝ)⌋₊
abbrev Patterns (α : ℝ) (N : ℕ) := Fin (patternCount α N) → Fin N → ℝ

def patternLaw (α : ℝ) (N : ℕ) : Measure (Patterns α N) :=
  Measure.pi fun _ => Measure.pi fun _ => gaussianReal 0 1

def unitSphereLaw (N : ℕ) : Measure (Metric.sphere (0 : Spin N) 1) :=
  let s := (volume : Measure (Spin N)).toSphere
  (s Set.univ)⁻¹ • s

def sphereLaw (N : ℕ) : Measure (Spin N) :=
  (unitSphereLaw N).map fun x => Real.sqrt (N : ℝ) • x.val

def patternField {α : ℝ} {N : ℕ} (g : Patterns α N)
    (a : Fin (patternCount α N)) (x : Spin N) : ℝ :=
  (∑ i : Fin N, g a i * x i) / Real.sqrt (N : ℝ)

def hamiltonian (α : ℝ) (φ : ℝ →ᵇ ℝ) (N : ℕ) (g : Patterns α N)
    (x : Spin N) : ℝ :=
  ∑ a : Fin (patternCount α N), φ (patternField g a x)

def pressure (α β : ℝ) (φ : ℝ →ᵇ ℝ) (N : ℕ) (g : Patterns α N) : ℝ :=
  Real.log (∫ x, Real.exp (β * hamiltonian α φ N g x) ∂sphereLaw N) / (N : ℝ)

def expectedPressure (α β : ℝ) (φ : ℝ →ᵇ ℝ) (N : ℕ) : ℝ :=
  ∫ g, pressure α β φ N g ∂patternLaw α N

structure Trial where
  toFun : Time → ℝ
  monotone : Monotone toFun
  measurable : Measurable toFun
  nonneg : ∀ t, 0 ≤ toFun t
  le_one : ∀ t, toFun t ≤ 1

instance : CoeFun Trial (fun _ => Time → ℝ) := ⟨Trial.toFun⟩

def timeLaw : Measure Time := Measure.comap Subtype.val volume

def tailIntegral (m : Trial) (t : Time) : ℝ :=
  ∫ s in Set.Ici t, m s ∂timeLaw

def entropy (m : Trial) : ℝ≥0∞ :=
  (∫⁻ t, (ENNReal.ofReal (tailIntegral m t))⁻¹ -
    (ENNReal.ofReal (1 - (t : ℝ)))⁻¹ ∂timeLaw) / 2

def brownianEval (t : ℝ≥0) (ω : BrownianPath) : ℝ := ω t

@[instance_reducible] def nullSigma (P : Measure BrownianPath) : MeasurableSpace BrownianPath :=
  MeasurableSpace.generateFrom {s | P s = 0}

@[instance_reducible] def usualBrownianSigma (P : Measure BrownianPath) (t : Time) :
    MeasurableSpace BrownianPath :=
  ⨅ s : {s : ℝ≥0 // (t : ℝ) < s},
    (⨆ r : {r : ℝ≥0 // r ≤ s.val},
      MeasurableSpace.comap (brownianEval r.val) (borel ℝ)) ⊔ nullSigma P

def Progressive (P : Measure BrownianPath) (v : Time → BrownianPath → ℝ) : Prop :=
  ∀ t : Time,
    @Measurable (Set.Iic t × BrownianPath) ℝ
      (MeasurableSpace.prod inferInstance (usualBrownianSigma P t)) (borel ℝ)
      (fun p => v p.1.val p.2)

def controlCost (P : Measure BrownianPath) (m : Trial)
    (v : Time → BrownianPath → ℝ) : ℝ≥0∞ :=
  ∫⁻ ω, ∫⁻ t, ENNReal.ofReal (m t * v t ω ^ 2) ∂timeLaw ∂P

def controlPayoff (P : Measure BrownianPath) (f : ℝ →ᵇ ℝ) (m : Trial)
    (v : Time → BrownianPath → ℝ) : ℝ :=
  (∫ ω, f (brownianEval 1 ω + ∫ t, m t * v t ω ∂timeLaw) ∂P) -
    (controlCost P m v).toReal / 2

def controlValue (P : Measure BrownianPath) (f : ℝ →ᵇ ℝ) (m : Trial) : ℝ :=
  sSup {a | ∃ v : Time → BrownianPath → ℝ,
    Progressive P v ∧ controlCost P m v < ∞ ∧ a = controlPayoff P f m v}

def variationalValue (P : Measure BrownianPath) (α β : ℝ) (φ : ℝ →ᵇ ℝ) : EReal :=
  ⨅ m : Trial, ((α * controlValue P (β • φ) m : ℝ) : EReal) + (entropy m).toEReal

theorem main (P : Measure BrownianPath) [IsProbabilityMeasure P]
    (hB : IsBrownianReal brownianEval P)
    (α β : ℝ) (hα : 0 < α) (hβ : 0 < β) (φ : ℝ →ᵇ ℝ) :
    ∃ p : ℝ, variationalValue P α β φ = (p : EReal) ∧
      Tendsto (fun N : ℕ => expectedPressure α β φ (N + 1)) atTop (𝓝 p) ∧
      ∀ ε : ℝ, 0 < ε →
        Tendsto (fun N : ℕ => patternLaw α (N + 1)
          {g | ε < |pressure α β φ (N + 1) g - p|}) atTop (𝓝 0) := by
  sorry

end SphericalPerceptronFreeEnergy

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/PerceptronFreeEnergy.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.SphericalPerceptronFreeEnergy.main` must keep exactly the statement shown above: same names,
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
