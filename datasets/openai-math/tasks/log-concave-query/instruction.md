# openai/math challenge `LogConcaveQuery` (family 139)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 139 of the release, *Subpolynomial queries for log-concave sampling*
(Theoretical computer science). The family as a whole: For $C^2$ potentials with a supplied minimizer and $I\preceq\nabla^2V\preceq2I$, proves that sampling within total variation $1/10$ requires only $C_\varepsilon d^\varepsilon$ exact value-and-gradient queries for every fixed $\varepsilon>0$. The bound holds on every run, with unrestricted computation between queries. A logarithmic lower bound also holds, so the optimal power-law exponent in this oracle model is zero.

The challenge is `LogConcaveQuery`, also at `/opt/openai-math/challenges/LogConcaveQuery.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

open MeasureTheory Filter
open scoped ENNReal NNReal Topology

namespace LogConcaveSampling

abbrev Point (d : ℕ) := EuclideanSpace ℝ (Fin d)
abbrev Reply (d : ℕ) := ℝ × Point d
abbrev Transcript (d q : ℕ) := Fin q → Reply d

/-- Normalized twice continuously differentiable potentials with Hessian between the identity and twice the identity. -/
structure Admissible {d : ℕ} (V : Point d → ℝ) : Prop where
  smooth : ContDiff ℝ 2 V
  value_zero : V 0 = 0
  gradient_zero : gradient V 0 = 0
  hessian_bounds : ∀ x v : Point d,
    ‖v‖ ^ 2 ≤ inner ℝ v (fderiv ℝ (gradient V) x v) ∧
    inner ℝ v (fderiv ℝ (gradient V) x v) ≤ 2 * ‖v‖ ^ 2

/-- The unnormalized Gibbs density relative to Euclidean volume. -/
def gibbsDensity {d : ℕ} (V : Point d → ℝ) (x : Point d) : ℝ≥0∞ :=
  ENNReal.ofReal (Real.exp (-V x))

def partition {d : ℕ} (V : Point d → ℝ) : ℝ≥0∞ :=
  ∫⁻ x, gibbsDensity V x ∂volume

/-- The Gibbs probability law, normalized by its partition function. -/
def gibbs {d : ℕ} (V : Point d → ℝ) : Measure (Point d) :=
  (partition V)⁻¹ • volume.withDensity (gibbsDensity V)

def TVAtMost {E : Type*} [MeasurableSpace E]
    (μ ν : Measure E) (ε : ℝ) : Prop :=
  ∀ s : Set E, MeasurableSet s → |μ.real s - ν.real s| ≤ ε

def firstOrderReply {d : ℕ} (V : Point d → ℝ) (x : Point d) : Reply d :=
  (V x, gradient V x)

/-- Measurable adaptive queries and output, parametrized by private randomness. -/
structure OracleAlgorithm (Ω : Type*) [MeasurableSpace Ω] (d q : ℕ) where
  query : Fin q → Ω × Transcript d q → Point d
  query_measurable : ∀ i, Measurable (query i)
  output : Ω × Transcript d q → Point d
  output_measurable : Measurable output

def OracleAlgorithm.history {Ω : Type*} [MeasurableSpace Ω] {d q : ℕ}
    (A : OracleAlgorithm Ω d q) (V : Point d → ℝ) (ω : Ω) : ℕ → Transcript d q
  | 0 => 0
  | n + 1 =>
      let h := A.history V ω n
      if hn : n < q then
        Function.update h ⟨n, hn⟩ (firstOrderReply V (A.query ⟨n, hn⟩ (ω, h)))
      else h

def OracleAlgorithm.run {Ω : Type*} [MeasurableSpace Ω] {d q : ℕ}
    (A : OracleAlgorithm Ω d q) (V : Point d → ℝ) (ω : Ω) : Point d :=
  A.output (ω, A.history V ω q)

/-- A uniform sampler with a deterministic query budget on every execution and total-variation error at most one tenth. -/
def CanSample (d q : ℕ) : Prop :=
  ∃ (Ω : Type) (_ : MeasurableSpace Ω) (μ : Measure Ω)
    (_ : IsProbabilityMeasure μ) (A : OracleAlgorithm Ω d q),
    ∀ V : Point d → ℝ, Admissible V →
      Measurable (A.run V) ∧ TVAtMost (μ.map (A.run V)) (gibbs V) (1 / 10)

/-- The smallest feasible integer query budget, or infinity when no budget is feasible. -/
def queryComplexity (d : ℕ) : ℕ∞ :=
  sInf ((fun q : ℕ => (q : ℕ∞)) '' {q | CanSample d q})

/-- The quantified dimension-exponent upper bound with every positive exponent slack. -/
def ExponentBound (γ : ℝ) : Prop :=
  0 ≤ γ ∧ ∀ ε : ℝ, 0 < ε → ∃ d₀ : ℕ, ∀ d : ℕ, d₀ ≤ d →
    (queryComplexity d).toENNReal ≤ ENNReal.ofReal ((d : ℝ) ^ (γ + ε))

def gammaStar : ℝ := sInf {γ : ℝ | ExponentBound γ}

theorem exact_source_main :
    (∀ ε : ℝ, 0 < ε → ∃ C : ℝ, ∀ d : ℕ, 2 ≤ d →
      (queryComplexity d).toENNReal ≤ ENNReal.ofReal (C * (d : ℝ) ^ ε)) ∧
    (∃ c : ℝ, 0 < c ∧ ∃ d₀ : ℕ, 2 ≤ d₀ ∧ ∀ d : ℕ, d₀ ≤ d →
      ENNReal.ofReal (c * Real.log (d : ℝ)) ≤ (queryComplexity d).toENNReal) ∧
    gammaStar = 0 := by
  sorry

end LogConcaveSampling

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/LogConcaveQuery.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.LogConcaveSampling.exact_source_main` must keep exactly the statement shown above: same names,
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
