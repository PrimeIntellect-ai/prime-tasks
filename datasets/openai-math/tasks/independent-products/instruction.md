# openai/math challenge `IndependentProducts` (family 331)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 331 of the release, *Asymptotic midpoint uniform convexity without asymptotically uniformly convex renorming*
(Functional analysis). The family as a whole: Constructs a real reflexive Banach space with an asymptotically midpoint uniformly convex norm but no equivalent asymptotically uniformly convex norm, extending Baudier's separation to reflexive spaces. In the same space, depth-$k$ countably branching diamonds require distortion at least $\sqrt{1+k/12}$, so midpoint uniform convexity does not force uniformly bounded diamond distortion even under reflexivity.

The challenge is `IndependentProducts`, also at `/opt/openai-math/challenges/IndependentProducts.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

open MeasureTheory ProbabilityTheory Set Filter
open scoped ENNReal NNReal Topology

universe uX

namespace IndependentProducts

/-- The tree of finite sequences of positive integers. -/
abbrev Vertex := List ℕ+
/-- Coordinates are attached only to nonroot vertices. -/
abbrev Edge := {v : Vertex // v ≠ []}
abbrev Sample := Edge → ℝ

/-- The product law of independent copies of the multiplier. -/
def productMeasure (μ : Measure ℝ) : Measure Sample :=
  Measure.infinitePi (fun _ : Edge => μ)

/-- The nonroot prefix ending at position `j`. -/
def pathPrefix (v : Vertex) (j : Fin v.length) : Edge :=
  ⟨v.take (j.val + 1), by
    intro h
    have hl := congrArg List.length h
    simp only [List.length_take, List.length_nil] at hl
    have := j.isLt
    omega⟩

/-- Root product is the empty product 1; every other product uses the path prefixes. -/
def pathProduct (v : Vertex) (ω : Sample) : ℝ :=
  ∏ j : Fin v.length, ω (pathPrefix v j)

/-- The closed real L1 span of the path products. -/
def productSpan (μ : Measure ℝ) : Submodule ℝ (Lp ℝ 1 (productMeasure μ)) :=
  (Submodule.span ℝ {f : Lp ℝ 1 (productMeasure μ) | ∃ v : Vertex,
    (f : Sample → ℝ) =ᵐ[productMeasure μ] pathProduct v}).topologicalClosure

/-- Positivity, nonconstancy, mean one, and finite second moment of the multiplier law. -/
structure MultiplierHypotheses (μ : Measure ℝ) : Prop where
  probability : IsProbabilityMeasure μ
  positive : ∀ᵐ w ∂μ, 0 < w
  nonconstant : ∀ c : ℝ, ¬ (∀ᵐ w ∂μ, w = c)
  mean_one : ∫ w, w ∂μ = 1
  second_moment : MemLp (fun w : ℝ => w) 2 μ

variable (X : Type uX) [NormedAddCommGroup X] [NormedSpace ℝ X]

/-- Closed subspaces of finite codimension, with respect to the inherited topology. -/
def CofiniteSubspaces : Set (Submodule ℝ X) :=
  {F | IsClosed (F : Set X) ∧ FiniteDimensional ℝ (X ⧸ F)}

/-- The averaged asymptotic midpoint modulus, with directions of norm at least 1. -/
def averagedMidpointModulus (N : Seminorm ℝ X) (t : ℝ) : ℝ :=
  sInf {r | ∃ x : X, N x = 1 ∧ r =
    sSup {a | ∃ F ∈ CofiniteSubspaces X, a =
      sInf {b | ∃ y : X, y ∈ F ∧ 1 ≤ N y ∧
        b = (N (x + t • y) + N (x - t • y)) / 2 - 1}}}

/-- The usual one-sided modulus, whose directions have norm exactly 1. -/
def oneSidedModulus (N : Seminorm ℝ X) (t : ℝ) : ℝ :=
  sInf {r | ∃ x : X, N x = 1 ∧ r =
    sSup {a | ∃ F ∈ CofiniteSubspaces X, a =
      sInf {b | ∃ y : X, y ∈ F ∧ N y = 1 ∧ b = N (x + t • y) - 1}}}

/-- A seminorm with these bounds is a genuine norm equivalent to the original norm. -/
def IsEquivalentNorm (N : Seminorm ℝ X) : Prop :=
  ∃ a b : ℝ, 0 < a ∧ a ≤ b ∧ ∀ x, a * ‖x‖ ≤ N x ∧ N x ≤ b * ‖x‖

def IsAUC (N : Seminorm ℝ X) : Prop := ∀ t : ℝ, 0 < t → 0 < oneSidedModulus X N t

/-- Gaussian-tail probability, in real rather than extended-nonnegative-real notation. -/
def gaussianTail (r : ℝ) : ℝ :=
  (gaussianReal 0 1 {x : ℝ | r ≤ |x|}).toReal

/-- The Gaussian excess constant at threshold twice the parameter. -/
def excessConstant (K : ℝ) : ℝ :=
  (1 / 16 : ℝ) * ∫ x : ℝ, max (|x| - 2 * K) 0 ∂gaussianReal 0 1

/-- The density exp(-w) on the positive half-line. -/
def exponentialLaw : Measure ℝ := expMeasure 1

/-- The law of the square of a standard real Gaussian. -/
def gaussianSquareLaw : Measure ℝ := (gaussianReal 0 1).map (fun x : ℝ => x ^ 2)

theorem main_general (μ : Measure ℝ) (hμ : MultiplierHypotheses μ) :
    ¬ FiniteDimensional ℝ (productSpan μ) ∧
    ∀ N : Seminorm ℝ (productSpan μ),
      IsEquivalentNorm (productSpan μ) N → ¬ IsAUC (productSpan μ) N := by
  sorry

theorem main_exponential (t : ℝ) (ht : 0 < t) :
    (7 * t / 30) * excessConstant (10 / t) ≤
      averagedMidpointModulus (productSpan exponentialLaw)
        (normSeminorm ℝ (productSpan exponentialLaw)) t ∧
    0 < (7 * t / 30) * excessConstant (10 / t) := by
  sorry

theorem main_gaussian_24 (t : ℝ) (ht : 0 < t) :
    gaussianTail (4 * Real.sqrt 2 * (2 + Real.sqrt 2) / t) / 8 ≤
      averagedMidpointModulus (productSpan gaussianSquareLaw)
        (normSeminorm ℝ (productSpan gaussianSquareLaw)) t ∧
    0 < gaussianTail (4 * Real.sqrt 2 * (2 + Real.sqrt 2) / t) / 8 := by
  sorry

theorem main_gaussian_12 (t : ℝ) (ht : 0 < t) :
    gaussianTail (8 * Real.sqrt 6 / t) / 4 ≤
      averagedMidpointModulus (productSpan gaussianSquareLaw)
        (normSeminorm ℝ (productSpan gaussianSquareLaw)) t ∧
    0 < gaussianTail (8 * Real.sqrt 6 / t) / 4 := by
  sorry

end IndependentProducts

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/IndependentProducts.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorems `OAI.IndependentProducts.main_general`, `OAI.IndependentProducts.main_exponential`, `OAI.IndependentProducts.main_gaussian_24`, `OAI.IndependentProducts.main_gaussian_12` must keep exactly the statement shown above: same names,
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
