# openai/math challenge `TalagrandExpectationThreshold` (family 175)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 175 of the release, *Talagrand's conjectures and graph decompositions at expectation thresholds*
(Combinatorics). The family as a whole: Proves that integral and fractional expectation thresholds differ by at most a universal factor, and resolves Talagrand's discrete-convexity conjecture. An application proves the Ascoli–He–Park–Talagrand graph-decomposition conjecture: every graph's edges split into a universally bounded number of fixed pieces, each with containment threshold at most a universal constant times the original graph's integral expectation threshold. The pieces' embeddings need not agree on shared vertices.

The challenge is `TalagrandExpectationThreshold`, also at `/opt/openai-math/challenges/TalagrandExpectationThreshold.lean`:

```lean
import Mathlib.Data.Fintype.Powerset
import Mathlib.Data.Finset.Union
import Mathlib.Basic.Real.Basic
import Mathlib.Algebra.Order.Archimedean.Real.Basic
import Mathlib.Algebra.Order.BigOperators.Group.Finset
import Mathlib.Algebra.BigOperators.Group.Finset.Piecewise

namespace OAI

namespace TalagrandThreshold

open scoped BigOperators

abbrev Family (α : Type*) := Finset (Finset α)

variable {α : Type*} [Fintype α] [DecidableEq α]

noncomputable section

def cost (p : ℝ) (G : Family α) : ℝ := ∑ S ∈ G, p ^ S.card

def Covers (G F : Family α) : Prop := ∀ H ∈ F, ∃ S ∈ G, S ⊆ H

def Small (p : ℝ) (F : Family α) : Prop :=
  ∃ G : Family α, Covers G F ∧ cost p G ≤ 1 / 2

def fracCost (p : ℝ) (g : Finset α → ℝ) : ℝ :=
  ∑ S : Finset α, g S * p ^ S.card

def FractionalCover (F : Family α) (g : Finset α → ℝ) : Prop :=
  (∀ S, 0 ≤ g S ∧ g S ≤ 1) ∧
    ∀ H ∈ F, 1 ≤ ∑ S ∈ H.powerset, g S

def FractionalSmall (p : ℝ) (F : Family α) : Prop :=
  ∃ g : Finset α → ℝ, FractionalCover F g ∧ fracCost p g ≤ 1 / 2

def Increasing (F : Family α) : Prop :=
  ∀ H ∈ F, ∀ K : Finset α, H ⊆ K → K ∈ F

def integralFeasible (F : Family α) : Set ℝ :=
  {p | 0 ≤ p ∧ p ≤ 1 ∧ Small p F}

def fractionalFeasible (F : Family α) : Set ℝ :=
  {p | 0 ≤ p ∧ p ≤ 1 ∧ FractionalSmall p F}

def q (F : Family α) : ℝ := sSup (integralFeasible F)

def qf (F : Family α) : ℝ := sSup (fractionalFeasible F)

end

theorem talagrand_expectation_threshold_equivalence [Nonempty α]
    (F : Family α) (_hF : F.Nonempty) (hproper : F ≠ Finset.univ)
    (hIncreasing : Increasing F) :
    qf F ≤ ((25 : ℝ) * (512 : ℝ) ^ 4) * q F := by
  sorry

end TalagrandThreshold

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/TalagrandExpectationThreshold.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.TalagrandThreshold.talagrand_expectation_threshold_equivalence` must keep exactly the statement shown above: same names,
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
