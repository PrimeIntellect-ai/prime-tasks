# openai/math challenge `PrimeGaps` (family 026)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 026 of the release, *Positive lower density of large prime gaps*
(Number theory). The family as a whole: For every fixed $C>0$, a positive proportion of consecutive prime gaps exceed $C\log p_n$, throughout every sufficiently large initial segment of the primes. The proportion may depend on $C$. Consequently, the indices where $p_n/n$ increases have positive lower density, answering Erd\H{o}s and Prachar.

The challenge is `PrimeGaps`, also at `/opt/openai-math/challenges/PrimeGaps.lean`:

```lean
import Mathlib

namespace OAI

namespace LargePrimeGaps

noncomputable def prime (n : ℕ) : ℕ := Nat.nth Nat.Prime (n - 1)

noncomputable def largeGapIndices (C : ℝ) (N : ℕ) : Finset ℕ := by
  classical
  exact (Finset.Icc 1 N).filter fun n =>
    C * Real.log (prime n : ℝ) < (prime (n + 1) : ℝ) - (prime n : ℝ)

end LargePrimeGaps

noncomputable section

namespace Problem344

def primeAt (n : ℕ) : ℕ :=
  Nat.nth Nat.Prime (n - 1)

def initialCount (A : Set ℕ) (N : ℕ) : ℕ := by
  classical
  exact ((Finset.Icc 1 N).filter (fun n => n ∈ A)).card

def lowerAsymptoticDensity (A : Set ℕ) : ℝ :=
  sSup {d : ℝ | ∃ N0 : ℕ, ∀ N : ℕ, N0 ≤ N →
    d ≤ (initialCount A N : ℝ) / (N : ℝ)}

def ratioIncreaseIndices : Set ℕ :=
  {n | 1 ≤ n ∧
    (primeAt n : ℝ) / (n : ℝ) <
      (primeAt (n + 1) : ℝ) / ((n + 1 : ℕ) : ℝ)}

theorem large_gaps_and_ratio_density :
    (∀ C : ℝ, 0 < C →
      ∃ c : ℝ, 0 < c ∧ ∃ N₀ : ℕ, ∀ N : ℕ, N₀ ≤ N →
        c * (N : ℝ) ≤ ((LargePrimeGaps.largeGapIndices C N).card : ℝ)) ∧
    0 < lowerAsymptoticDensity ratioIncreaseIndices := by
  sorry

end Problem344

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/PrimeGaps.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Problem344.large_gaps_and_ratio_density` must keep exactly the statement shown above: same names,
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
