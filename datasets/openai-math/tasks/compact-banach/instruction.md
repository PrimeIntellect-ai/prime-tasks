# openai/math challenge `CompactBanach` (family 098)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 098 of the release, *A negative answer to the Lang–Plaut problem*
(Convex and metric geometry). The family as a whole: Every infinite-dimensional real Banach space contains a compact doubling set that admits no bi-Lipschitz embedding into any finite-dimensional normed space. The doubling constant is universal. This answers the Lang–Plaut problem negatively, even for compact subsets of Hilbert space.

The challenge is `CompactBanach`, also at `/opt/openai-math/challenges/CompactBanach.lean`:

```lean
import Mathlib

namespace OAI

                                                                                
                                                                              
                                                                                
                                                     

universe u v
namespace CompactBanach

def DoublingAtMost {B : Type*} [MetricSpace B] (K : Set B) (bound : ℕ) : Prop :=
  ∀ x : K, ∀ r : ℝ, 0 < r →
    ∃ centers : Finset K, centers.card ≤ bound ∧
      ∀ y : K, dist y x < r → ∃ c ∈ centers, dist y c < r / ((2 : ℕ) : ℝ)

def AdmitsBiLipschitzEmbedding {B : Type*} [MetricSpace B] (K : Set B)
    (E : Type*) [MetricSpace E] : Prop :=
  ∃ f : K → E, ∃ a : ℝ, 0 < a ∧ ∃ D : ℝ, 1 ≤ D ∧
    ∀ x y : K, a * dist x y ≤ dist (f x) (f y) ∧
      dist (f x) (f y) ≤ D * a * dist x y

                                                                       
theorem main : ∃ Λ : ℕ, ∀ (B : Type u) [NormedAddCommGroup B] [NormedSpace ℝ B]
    [CompleteSpace B], ¬ FiniteDimensional ℝ B →
    ∃ K : Set B, IsCompact K ∧ DoublingAtMost K Λ ∧
      ∀ (E : Type v) [NormedAddCommGroup E] [NormedSpace ℝ E]
        [FiniteDimensional ℝ E], ¬ AdmitsBiLipschitzEmbedding K E := by
  sorry

end CompactBanach

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/CompactBanach.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.CompactBanach.main` must keep exactly the statement shown above: same names,
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
