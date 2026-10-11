# openai/math challenge `SATComputability` (family 235)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 235 of the release, *Random-SAT thresholds, sharp variance and computability*
(Probability and statistical mechanics). The family as a whole: For random $k$-SAT with independent uniformly signed proper clauses sampled with replacement, proves finite positive limiting thresholds and hitting-time variance $\Theta_k(n)$ for every fixed $k\ge3$, and computability of the 3-SAT threshold. We credit Gaia Carenini with priority for resolving the threshold-existence conjecture in her concurrent \href{https://eccc.weizmann.ac.il/report/2026/229/}{ECCC TR26-229}, made public October 5, 2026; this family supplies another proof and the sharper variance and computability results.

The challenge is `SATComputability`, also at `/opt/openai-math/challenges/SATComputability.lean`:

```lean
import Mathlib

namespace OAI

namespace FixedClauseThreshold

abbrev Assignment (n : ℕ) := Fin n → Bool

abbrev ProperClause (n k : ℕ) :=
  { C : Fin n → Option Bool // (Finset.univ.filter fun i => (C i).isSome).card = k }

abbrev Formula (n k m : ℕ) := Fin m → ProperClause n k

def SatisfiesClause {n k : ℕ} (σ : Assignment n) (C : ProperClause n k) : Prop :=
  ∃ i : Fin n, C.val i = some (σ i)

def Satisfies {n k m : ℕ} (σ : Assignment n) (F : Formula n k m) : Prop :=
  ∀ j, SatisfiesClause σ (F j)

def Satisfiable {n k m : ℕ} (F : Formula n k m) : Prop :=
  ∃ σ : Assignment n, Satisfies σ F

noncomputable def properSATProbability (n k m : ℕ) : ℝ := by
  classical
  exact (Fintype.card { F : Formula n k m // Satisfiable F } : ℝ) /
    (Fintype.card (Formula n k m) : ℝ)
end FixedClauseThreshold

namespace FixedClauseThreshold.Computability

open Filter
open scoped Topology NNReal

def MainStatement : Prop :=
    ∃ (α : ℝ) (q : ℕ → ℚ) (c : Nat.Partrec.Code),
      0 < α ∧
      (∀ a : ℝ, 0 ≤ a → a < α →
        Tendsto (fun n : ℕ => properSATProbability n 3 ⌊a*(n : ℝ)⌋₊) atTop (nhds 1)) ∧
      (∀ a : ℝ, α < a →
        Tendsto (fun n : ℕ => properSATProbability n 3 ⌊a*(n : ℝ)⌋₊) atTop (nhds 0)) ∧
      Computable (fun r => Encodable.encode (q r)) ∧
      (∀ r, c.eval r = Part.some (Encodable.encode (q r))) ∧
      (∀ r, |(q r : ℝ)-α| ≤ (2^r : ℝ)⁻¹)

theorem main : MainStatement := by
  sorry

end FixedClauseThreshold.Computability

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/SATComputability.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.FixedClauseThreshold.Computability.main` must keep exactly the statement shown above: same names,
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
