# openai/math challenge `SeparableQuotientNegative` (family 323)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 323 of the release, *Relative independence of the separable quotient problem*
(Functional analysis). The family as a whole: Establishes, relative to the consistency of a measurable cardinal, that the separable quotient problem is independent of ZFC. The assertion that every infinite-dimensional Banach space has a separable infinite-dimensional quotient can hold for all real and complex Banach spaces, whereas the continuum hypothesis yields counterexamples over both fields.

The challenge is `SeparableQuotientNegative`, also at `/opt/openai-math/challenges/SeparableQuotientNegative.lean`:

```lean
import Mathlib

namespace OAI

namespace SeparableQuotient

open MeasureTheory Cardinal

universe u

/-- The continuum hypothesis. -/
def CH : Prop := Cardinal.mk ℝ = Cardinal.aleph 1

/-- A bounded linear surjection onto an infinite-dimensional separable Banach space. -/
def HasSeparableQuotient (𝕜 : Type) [RCLike 𝕜]
    (X : Type u) [NormedAddCommGroup X] [NormedSpace 𝕜 X] : Prop :=
  ∃ (Y : Type u) (_ : NormedAddCommGroup Y) (_ : NormedSpace 𝕜 Y),
    CompleteSpace Y ∧ TopologicalSpace.SeparableSpace Y ∧
      (¬ FiniteDimensional 𝕜 Y) ∧ ∃ T : X →L[𝕜] Y, Function.Surjective T

/-- The separable quotient assertion at an arbitrary ambient universe. -/
def SQ (𝕜 : Type) [RCLike 𝕜] : Prop :=
  ∀ (X : Type u) [NormedAddCommGroup X] [NormedSpace 𝕜 X] [CompleteSpace X],
    (¬ FiniteDimensional 𝕜 X) → HasSeparableQuotient 𝕜 X

theorem negative_main (hCH : CH) : ¬ SQ.{u} ℝ ∧ ¬ SQ.{u} ℂ := by
  sorry

end SeparableQuotient

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/SeparableQuotientNegative.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.SeparableQuotient.negative_main` must keep exactly the statement shown above: same names,
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
