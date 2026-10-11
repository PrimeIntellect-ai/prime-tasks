# openai/math challenge `EntangledGames` (family 277)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 277 of the release, *Threshold repetition for entangled games*
(Mathematical physics). The family as a whole: Proves exponential threshold repetition for every finite two-player one-round game: if its entangled value is $v<1$, the probability of winning at least a fraction $v+\delta$ of $k$ independent repetitions decays exponentially in $k$, for $0<\delta<1-v$. Arbitrary joint finite-dimensional entangled strategies and correlated question distributions are allowed.

The challenge is `EntangledGames`, also at `/opt/openai-math/challenges/EntangledGames.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open scoped BigOperators ComplexOrder

namespace ThresholdParallelRepetition

structure Game (x y a b : ℕ) where
  questionProb : Fin (x + 1) × Fin (y + 1) → ℝ
  questionProb_nonneg : ∀ z, 0 ≤ questionProb z
  questionProb_sum : ∑ z, questionProb z = 1
  accepts : Fin (x + 1) → Fin (y + 1) → Fin (a + 1) → Fin (b + 1) → Bool

structure Strategy (X Y A B : Type) [Fintype A] [Fintype B] where
  dimA : ℕ
  dimB : ℕ
  state : Fin (dimA + 1) × Fin (dimB + 1) → ℂ
  state_unit : ∑ i, Complex.normSq (state i) = 1
  alice : X → A → Matrix (Fin (dimA + 1)) (Fin (dimA + 1)) ℂ
  bob : Y → B → Matrix (Fin (dimB + 1)) (Fin (dimB + 1)) ℂ
  alice_pos : ∀ x a, (alice x a).PosSemidef
  bob_pos : ∀ y b, (bob y b).PosSemidef
  alice_total : ∀ x, ∑ a, alice x a = 1
  bob_total : ∀ y, ∑ b, bob y b = 1

def Strategy.born {X Y A B : Type} [Fintype A] [Fintype B]
    (S : Strategy X Y A B) (x : X) (y : Y) (a : A) (b : B) : ℝ :=
  ∑ i, ∑ j, (star (S.state i) *
    (S.alice x a i.1 j.1 * S.bob y b i.2 j.2) * S.state j).re

abbrev SingleStrategy (x y a b : ℕ) :=
  Strategy (Fin (x + 1)) (Fin (y + 1)) (Fin (a + 1)) (Fin (b + 1))

def successProbability {x y a b : ℕ} (G : Game x y a b) (S : SingleStrategy x y a b) : ℝ :=
  ∑ z : Fin (x + 1) × Fin (y + 1), G.questionProb z *
    ∑ w : Fin (a + 1) × Fin (b + 1),
      if G.accepts z.1 z.2 w.1 w.2 then S.born z.1 z.2 w.1 w.2 else 0

def entangledValue {x y a b : ℕ} (G : Game x y a b) : ℝ :=
  sSup (Set.range (successProbability G))

abbrev RepeatedStrategy (x y a b k : ℕ) :=
  Strategy (Fin k → Fin (x + 1)) (Fin k → Fin (y + 1))
    (Fin k → Fin (a + 1)) (Fin k → Fin (b + 1))

def wins {x y a b k : ℕ} (G : Game x y a b)
    (xs : Fin k → Fin (x + 1)) (ys : Fin k → Fin (y + 1))
    (as : Fin k → Fin (a + 1)) (bs : Fin k → Fin (b + 1)) : ℕ :=
  ∑ i, if G.accepts (xs i) (ys i) (as i) (bs i) then 1 else 0

def thresholdProbability {x y a b k : ℕ} (G : Game x y a b) (δ : ℝ)
    (S : RepeatedStrategy x y a b k) : ℝ :=
  ∑ xs : Fin k → Fin (x + 1), ∑ ys : Fin k → Fin (y + 1),
    (∏ i, G.questionProb (xs i, ys i)) *
      ∑ as : Fin k → Fin (a + 1), ∑ bs : Fin k → Fin (b + 1),
        if ⌈(entangledValue G + δ) * (k : ℝ)⌉₊ ≤ wins G xs ys as bs
        then S.born xs ys as bs else 0

def thresholdValue {x y a b k : ℕ} (G : Game x y a b) (δ : ℝ) : ℝ :=
  sSup (Set.range (thresholdProbability (k := k) G δ))

theorem threshold_parallel_repetition :
    ∃ κ₀ : ℝ, 0 < κ₀ ∧
      ∀ (x y a b : ℕ) (G : Game x y a b), entangledValue G < 1 →
      ∀ (δ : ℝ), 0 < δ → δ < 1 - entangledValue G →
      ∀ (k : ℕ), 1 ≤ k →
        (∀ S : RepeatedStrategy x y a b k,
          thresholdProbability G δ S ≤
            Real.exp (-κ₀ * δ ^ 13 / (1 + Real.log (((a + 1) * (b + 1) : ℕ) : ℝ)) * k)) ∧
        thresholdValue (k := k) G δ ≤
          Real.exp (-κ₀ * δ ^ 13 / (1 + Real.log (((a + 1) * (b + 1) : ℕ) : ℝ)) * k) := by
  sorry

end ThresholdParallelRepetition

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/EntangledGames.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.ThresholdParallelRepetition.threshold_parallel_repetition` must keep exactly the statement shown above: same names,
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
