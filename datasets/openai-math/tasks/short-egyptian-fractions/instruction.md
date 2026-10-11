# openai/math challenge `ShortEgyptianFractions` (family 025)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 025 of the release, *Erd\H{o}s’s short Egyptian-fraction conjecture*
(Number theory). The family as a whole: Every rational $a/b$ with $1\le a<b$ is a sum of $O(\log\log b)$ distinct positive unit fractions. The worst-case minimum number of terms has the same order, resolving Erd\H{o}s’s conjecture on short Egyptian fractions.

The challenge is `ShortEgyptianFractions`, also at `/opt/openai-math/challenges/ShortEgyptianFractions.lean`:

```lean
import Mathlib

namespace OAI

namespace ShortEgyptian

def IsExpansion (a b : ℕ) (ns : List ℕ) : Prop :=
  ns.Pairwise (· < ·) ∧ (∀ n ∈ ns, 2 ≤ n) ∧
    (ns.map (fun n => (1 : ℚ) / (n : ℚ))).sum = (a : ℚ) / (b : ℚ)

noncomputable def minLength (a b : ℕ) : ℕ :=
  sInf {k : ℕ | ∃ ns : List ℕ, IsExpansion a b ns ∧ ns.length = k}

noncomputable def maxMinLength (b : ℕ) : ℕ :=
  (Finset.Ico 1 b).sup (fun a => minLength a b)

theorem main :
    (∀ a b : ℕ, 1 ≤ a → a < b → ∃ ns : List ℕ, IsExpansion a b ns) ∧
    ∃ c₁ c₂ : ℝ, 0 < c₁ ∧ 0 < c₂ ∧ ∃ b₀ : ℕ, 2 ≤ b₀ ∧
      ∀ b : ℕ, b₀ ≤ b →
        c₁ * Real.log (Real.log (b : ℝ)) ≤ (maxMinLength b : ℝ) ∧
        (maxMinLength b : ℝ) ≤ c₂ * Real.log (Real.log (b : ℝ)) := by
  sorry

end ShortEgyptian

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/ShortEgyptianFractions.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.ShortEgyptian.main` must keep exactly the statement shown above: same names,
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
