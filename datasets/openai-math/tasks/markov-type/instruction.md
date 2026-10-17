# openai/math challenge `MarkovType` (family 327)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 327 of the release, *Markov type characterizes superreflexivity*
(Functional analysis). The family as a whole: Proves that every real Banach space with Markov type $p$ for some $p>1$ admits an equivalent uniformly convex norm, answering Naor's renorming question. Together with the known converse, this characterizes superreflexivity by nontrivial Markov type.

The challenge is `MarkovType`, also at `/opt/openai-math/challenges/MarkovType.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

open scoped BigOperators

namespace MarkovSuperreflexivity

structure FiniteReversibleChain (S : Type*) [Fintype S] where
  π : S → ℝ
  P : S → S → ℝ
  π_nonneg : ∀ s, 0 ≤ π s
  sum_π : ∑ s, π s = 1
  P_nonneg : ∀ s t, 0 ≤ P s t
  sum_P : ∀ s, ∑ t, P s t = 1
  balance : ∀ s t, π s * P s t = π t * P t s

abbrev StatePath (S : Type*) (n : ℕ) := Fin (n + 1) → S

def pathWeight {S : Type*} [Fintype S]
    (C : FiniteReversibleChain S) (n : ℕ) (ω : StatePath S n) : ℝ :=
  C.π (ω 0) * ∏ i : Fin n, C.P (ω i.castSucc) (ω i.succ)

def stateCost {S X : Type*} [Fintype S] [NormedAddCommGroup X]
    (C : FiniteReversibleChain S) (f : S → X) (p : ℝ) (n : ℕ) : ℝ :=
  ∑ ω : StatePath S n,
    pathWeight C n ω * Real.rpow (‖f (ω (Fin.last n)) - f (ω 0)‖) p

def MarkovTypeWith (p K : ℝ) (X : Type*) [NormedAddCommGroup X] : Prop :=
  0 < p ∧ 0 < K ∧
    ∀ (m : ℕ) (C : FiniteReversibleChain (Fin m)) (f : Fin m → X) (n : ℕ),
      1 ≤ n → stateCost C f p n ≤ Real.rpow K p * (n : ℝ) * stateCost C f p 1

def HasMarkovType (p : ℝ) (X : Type*) [NormedAddCommGroup X] : Prop :=
  ∃ K : ℝ, MarkovTypeWith p K X

def HasNontrivialMarkovType (X : Type*) [NormedAddCommGroup X] : Prop :=
  ∃ p : ℝ, 1 < p ∧ HasMarkovType p X

section

universe u

variable (X : Type u) [NormedAddCommGroup X] [NormedSpace ℝ X]

structure EquivalentNorm where
  p : Seminorm ℝ X
  lower : ℝ
  upper : ℝ
  lower_pos : 0 < lower
  upper_pos : 0 < upper
  lower_bound : ∀ x, lower * ‖x‖ ≤ p x
  upper_bound : ∀ x, p x ≤ upper * ‖x‖

variable {X}

def UniformConvex (p : Seminorm ℝ X) : Prop :=
  ∀ ε : ℝ, 0 < ε → ε ≤ 2 → ∃ δ : ℝ, 0 < δ ∧
    ∀ x y : X, p x ≤ 1 → p y ≤ 1 → ε ≤ p (x - y) →
      p ((1 / 2 : ℝ) • (x + y)) ≤ 1 - δ

def HasEquivalentUCNorm (X : Type u) [NormedAddCommGroup X] [NormedSpace ℝ X] : Prop :=
  ∃ N : EquivalentNorm X, UniformConvex N.p

end

variable {X : Type*} [NormedAddCommGroup X] [NormedSpace ℝ X]

theorem hasNontrivialMarkovType_iff_hasEquivalentUCNorm [CompleteSpace X] :
    HasNontrivialMarkovType X ↔ HasEquivalentUCNorm X := by
  sorry

end MarkovSuperreflexivity

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/MarkovType.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.MarkovSuperreflexivity.hasNontrivialMarkovType_iff_hasEquivalentUCNorm` must keep exactly the statement shown above: same names,
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
