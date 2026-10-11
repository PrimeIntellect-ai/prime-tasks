# openai/math challenge `FourRowPermanent` (family 238)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 238 of the release, *Optimal logarithmic mixing of the Thorp shuffle*
(Probability and statistical mechanics). The family as a whole: Proves that the Thorp shuffle randomizes $N=2^d$ labeled cards in $\Theta(\log N)$ physical shuffles, settling its optimal mixing order for power-of-two deck sizes. Convergence is in total variation from the worst initial ordering and concerns the entire permutation, not just individual card positions.

The challenge is `FourRowPermanent`, also at `/opt/openai-math/challenges/FourRowPermanent.lean`:

```lean
import Mathlib

namespace OAI

/-!
# A robust four-row permanent inequality

`Fin 4` labels four sites. A law is represented by real probability masses;
`IsProbability` asserts nonnegativity and total mass one. All row norms use
the uniform counting normalization.
-/

noncomputable section
namespace FourRow
open scoped BigOperators

abbrev Site := Fin 4
abbrev Perm := Equiv.Perm Site
abbrev Law := Perm → ℝ
abbrev Functions := Site → Site → ℝ

def IsProbability (ν : Law) : Prop :=
  (∀ π, 0 ≤ ν π) ∧ ∑ π, ν π = 1

def UniformMarginals (ν : Law) : Prop :=
  ∀ i j : Site, ∑ π, (if π i = j then ν π else 0) = 1 / 4

def totalVariation (ν : Law) : ℝ :=
  (∑ π, |ν π - 1 / 24|) / 2

def lpNorm (p : ℝ) (f : Site → ℝ) : ℝ :=
  ((∑ j, (f j) ^ p) / 4) ^ (1 / p)

def permanentExpectation (ν : Law) (f : Functions) : ℝ :=
  ∑ π, ν π * ∏ i, f i (π i)

theorem robust_permanent :
  ∃ p₀ : ℝ, 4 / 3 < p₀ ∧ p₀ < 2 ∧
    ∃ ε : ℝ, 0 < ε ∧ ∀ ν : Law,
      IsProbability ν → totalVariation ν < ε → UniformMarginals ν →
      ∀ f : Functions, (∀ i j, 0 ≤ f i j) →
        permanentExpectation ν f ≤ ∏ i, lpNorm p₀ (f i) := by
  sorry

end FourRow
end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/FourRowPermanent.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.FourRow.robust_permanent` must keep exactly the statement shown above: same names,
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
