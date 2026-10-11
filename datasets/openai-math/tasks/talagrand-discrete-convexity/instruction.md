# openai/math challenge `TalagrandDiscreteConvexity` (family 175)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 175 of the release, *Talagrand's conjectures and graph decompositions at expectation thresholds*
(Combinatorics). The family as a whole: Proves that integral and fractional expectation thresholds differ by at most a universal factor, and resolves Talagrand's discrete-convexity conjecture. An application proves the Ascoli–He–Park–Talagrand graph-decomposition conjecture: every graph's edges split into a universally bounded number of fixed pieces, each with containment threshold at most a universal constant times the original graph's integral expectation threshold. The pieces' embeddings need not agree on shared vertices.

The challenge is `TalagrandDiscreteConvexity`, also at `/opt/openai-math/challenges/TalagrandDiscreteConvexity.lean`:

```lean
import Mathlib.Data.Fintype.Powerset
import Mathlib.Data.Finset.Union
import Mathlib.Basic.Real.Basic
import Mathlib.Algebra.Order.BigOperators.Group.Finset

namespace OAI

namespace TalagrandDiscreteConvexity

open scoped BigOperators

abbrev Family (α : Type*) := Finset (Finset α)

variable {α : Type*} [Fintype α] [DecidableEq α]

noncomputable section

/-- Independent Bernoulli coordinates, including every absent coordinate. -/
def bernoulliMass (p : ℝ) (s : Finset α) : ℝ :=
  p ^ s.card * (1 - p) ^ (Finset.univ \ s).card

/-- The probability of an arbitrary family, with no monotonicity condition. -/
def familyMeasure (p : ℝ) (D : Family α) : ℝ :=
  ∑ s ∈ D, bernoulliMass p s

/-- Each distinct generator is charged once at the original density. -/
def cost (p : ℝ) (G : Family α) : ℝ := ∑ I ∈ G, p ^ I.card

/-- Every covered set contains a generator. -/
def Covers (G A : Family α) : Prop := ∀ S ∈ A, ∃ I ∈ G, I ⊆ S

/-- An actual finite containment cover with total cost at most one half. -/
def Small (p : ℝ) (A : Family α) : Prop :=
  ∃ G : Family α, Covers G A ∧ cost p G ≤ 1 / 2

/-- Exactly `k` entries, with no distinctness or disjointness restriction. -/
def unionTuple {k : ℕ} (f : Fin k → Finset α) : Finset α :=
  Finset.univ.biUnion f

/-- All subsets contained in no union of `k` members of the given family. -/
def exceptional (k : ℕ) (D : Family α) : Family α := by
  classical
  exact Finset.univ.filter (fun S =>
    ∀ f : Fin k → Finset α, (∀ j, f j ∈ D) → ¬ S ⊆ unionTuple f)

/-- Smallness at the original density for every positive ground-set size. -/
theorem talagrand_discrete_convexity (N : ℕ) (_hN : 1 ≤ N)
    (p : ℝ) (hp0 : 0 < p) (hp1 : p < 1) (D : Family (Fin N))
    (hD : 1 - 1 / (2 : ℝ) ^ 75 ≤ familyMeasure p D) :
    Small p (exceptional ((2 : ℕ) ^ 75) D) := by
  sorry

end

end TalagrandDiscreteConvexity

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/TalagrandDiscreteConvexity.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.TalagrandDiscreteConvexity.talagrand_discrete_convexity` must keep exactly the statement shown above: same names,
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
