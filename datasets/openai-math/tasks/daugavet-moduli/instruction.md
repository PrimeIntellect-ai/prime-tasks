# openai/math challenge `DaugavetModuli` (family 331)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 331 of the release, *Asymptotic midpoint uniform convexity without asymptotically uniformly convex renorming*
(Functional analysis). The family as a whole: Constructs a real reflexive Banach space with an asymptotically midpoint uniformly convex norm but no equivalent asymptotically uniformly convex norm, extending Baudier's separation to reflexive spaces. In the same space, depth-$k$ countably branching diamonds require distortion at least $\sqrt{1+k/12}$, so midpoint uniform convexity does not force uniformly bounded diamond distortion even under reflexivity.

The challenge is `DaugavetModuli`, also at `/opt/openai-math/challenges/DaugavetModuli.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

open MeasureTheory Filter Set
open scoped ENNReal NNReal Topology

universe uX u_1

namespace ExactModuli

variable {X : Type uX} [NormedAddCommGroup X] [NormedSpace ℝ X]

/-- Closed linear subspaces of finite codimension. -/
def Cofinite (F : Submodule ℝ X) : Prop :=
  IsClosed (F : Set X) ∧ FiniteDimensional ℝ (X ⧸ F)

/-- Averaged increment for directions of norm at least one. -/
def averagedIncrement (N : Seminorm ℝ X) (x : X) (t : ℝ) (y : X) : ℝ :=
  (N (x + t • y) + N (x - t • y)) / 2 - 1

def H (N : Seminorm ℝ X) (x : X) (t : ℝ) : ℝ :=
  sSup {r | ∃ F : Submodule ℝ X, Cofinite F ∧
    r = sInf {a | ∃ y ∈ F, 1 ≤ N y ∧ a = averagedIncrement N x t y}}

def D (N : Seminorm ℝ X) (x : X) (t : ℝ) : ℝ :=
  sSup {r | ∃ F : Submodule ℝ X, Cofinite F ∧
    r = sInf {a | ∃ y ∈ F, N y = 1 ∧ a = N (x + t • y) - 1}}

def averagedModulus (N : Seminorm ℝ X) (t : ℝ) : ℝ :=
  sInf {r | ∃ x, N x = 1 ∧ r = H N x t}

def oneSidedModulus (N : Seminorm ℝ X) (t : ℝ) : ℝ :=
  sInf {r | ∃ x, N x = 1 ∧ r = D N x t}

/-- Two-sided comparison makes this seminorm a genuine norm equivalent to the original. -/
def EquivalentNorm (N : Seminorm ℝ X) : Prop :=
  ∃ a b : ℝ, 0 < a ∧ 0 < b ∧ ∀ x, a * ‖x‖ ≤ N x ∧ N x ≤ b * ‖x‖

def AUC (N : Seminorm ℝ X) : Prop :=
  ∀ t : ℝ, 0 < t → 0 < oneSidedModulus N t

/-- Every rank-one operator has the form `ell.smulRight v`. -/
def Daugavet (X : Type uX) [NormedAddCommGroup X] [NormedSpace ℝ X] : Prop :=
  ∀ (ell : X →L[ℝ] ℝ) (v : X),
    ‖ContinuousLinearMap.id ℝ X + ell.smulRight v‖ = 1 + ‖ell.smulRight v‖

variable {Ω : Type u_1} [MeasurableSpace Ω] (μ : Measure Ω)

/-- Convergence-in-measure distance on L1 equivalence classes. -/
def measureDistance (f g : Lp ℝ 1 μ) : ℝ :=
  sInf {a : ℝ | 0 < a ∧ μ.real {ω | a < |f ω - g ω|} < a}

/-- Finite covers of the entire unit ball in convergence-in-measure distance. -/
def MeasurePrecompactBall (E : Submodule ℝ (Lp ℝ 1 μ)) : Prop :=
  ∀ ε : ℝ, 0 < ε → ∃ s : Finset (Lp ℝ 1 μ),
    ∀ y : E, ‖y‖ ≤ 1 → ∃ b ∈ s, measureDistance μ (y : Lp ℝ 1 μ) b < ε

/-- Every nonempty unit-ball slice contains an almost antipodal unit vector. -/
def UnitSliceProperty (X : Type uX) [NormedAddCommGroup X] [NormedSpace ℝ X] : Prop :=
  ∀ (w : X), ‖w‖ = 1 → ∀ (ell : X →L[ℝ] ℝ) (α : ℝ),
    (∃ u : X, ‖u‖ ≤ 1 ∧ α < ell u) →
    ∀ ρ : ℝ, 0 < ρ → ∃ y : X, ‖y‖ = 1 ∧ α < ell y ∧ 2 - ρ ≤ ‖w + y‖

/-- The countable product of unit intervals. -/
abbrev KWOmega := ℕ → unitInterval

def kwMeasure : Measure KWOmega := Measure.infinitePi (fun _ : ℕ => (volume : Measure unitInterval))

theorem exact_main {Ω : Type u_1} [MeasurableSpace Ω] (μ : Measure Ω)
    [IsProbabilityMeasure μ] (E : Submodule ℝ (Lp ℝ 1 μ))
    (_hclosed : IsClosed (E : Set (Lp ℝ 1 μ))) (hdim : ¬ FiniteDimensional ℝ E)
    (hprecompact : MeasurePrecompactBall μ E) (hdaugavet : Daugavet E) :
    (∀ (x : E), ‖x‖ = 1 → ∀ t : ℝ, 0 < t →
      H (normSeminorm ℝ E) x t = max (t / 2) (t - 1) ∧
      D (normSeminorm ℝ E) x t = max 0 (t - 2)) ∧
    (∀ t : ℝ, 0 < t →
      averagedModulus (normSeminorm ℝ E) t = max (t / 2) (t - 1) ∧
      oneSidedModulus (normSeminorm ℝ E) t = max 0 (t - 2)) ∧
    (∀ N : Seminorm ℝ E, EquivalentNorm N → ¬ AUC N) := by
  sorry

theorem kadets_werner_existence :
    ∃ E : Submodule ℝ (Lp ℝ 1 kwMeasure),
      IsClosed (E : Set (Lp ℝ 1 kwMeasure)) ∧ (¬ FiniteDimensional ℝ E) ∧
      MeasurePrecompactBall kwMeasure E ∧ UnitSliceProperty E ∧ Daugavet E := by
  sorry

theorem exact_example :
    ∃ E : Submodule ℝ (Lp ℝ 1 kwMeasure),
      IsClosed (E : Set (Lp ℝ 1 kwMeasure)) ∧ (¬ FiniteDimensional ℝ E) ∧
      MeasurePrecompactBall kwMeasure E ∧ UnitSliceProperty E ∧ Daugavet E ∧
      (∀ (x : E), ‖x‖ = 1 → ∀ t : ℝ, 0 < t →
        H (normSeminorm ℝ E) x t = max (t / 2) (t - 1) ∧
        D (normSeminorm ℝ E) x t = max 0 (t - 2)) ∧
      (∀ t : ℝ, 0 < t →
        averagedModulus (normSeminorm ℝ E) t = max (t / 2) (t - 1) ∧
        oneSidedModulus (normSeminorm ℝ E) t = max 0 (t - 2)) ∧
      (∀ N : Seminorm ℝ E, EquivalentNorm N → ¬ AUC N) := by
  sorry

end ExactModuli

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/DaugavetModuli.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorems `OAI.ExactModuli.exact_main`, `OAI.ExactModuli.kadets_werner_existence`, `OAI.ExactModuli.exact_example` must keep exactly the statement shown above: same names,
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
