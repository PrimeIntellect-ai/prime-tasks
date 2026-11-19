# openai/math challenge `LogBrunnMinkowski` (family 091)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 091 of the release, *The logarithmic Brunn–Minkowski conjecture*
(Convex and metric geometry). The family as a whole: Proves the logarithmic Brunn–Minkowski inequality for origin-symmetric convex bodies in every dimension, and the scalar-dilation B-conjecture for all even log-concave Radon measures. For Lebesgue volume it also proves the additive $L_p$ Brunn–Minkowski inequality for full-dimensional origin-symmetric convex bodies throughout $0<p<1$.

The challenge is `LogBrunnMinkowski`, also at `/opt/openai-math/challenges/LogBrunnMinkowski.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

open Set MeasureTheory
open scoped ENNReal InnerProductSpace

namespace LogBrunnMinkowski

abbrev Space (n : ℕ) := EuclideanSpace ℝ (Fin n)

def IsConvexBody {n : ℕ} (K : Set (Space n)) : Prop :=
  IsCompact K ∧ Convex ℝ K ∧ (interior K).Nonempty

def OriginSymmetric {n : ℕ} (K : Set (Space n)) : Prop :=
  ∀ x, x ∈ K ↔ -x ∈ K

def support {n : ℕ} (K : Set (Space n)) (u : Space n) : ℝ :=
  sSup ((fun x : Space n => ⟪x, u⟫_ℝ) '' K)

def wulff {n : ℕ} (f : Space n → ℝ) : Set (Space n) :=
  {x | ∀ u, ‖u‖ = 1 → ⟪x, u⟫_ℝ ≤ f u}

def logCombination {n : ℕ} (K L : Set (Space n)) (t : ℝ) :
    Set (Space n) :=
  wulff (fun u => (support K u) ^ (1 - t) * (support L u) ^ t)

theorem main (n : ℕ) (hn : 1 ≤ n) (K L : Set (Space n))
    (hK : IsConvexBody K) (hL : IsConvexBody L)
    (hsK : OriginSymmetric K) (hsL : OriginSymmetric L)
    (t : ℝ) (ht0 : 0 ≤ t) (ht1 : t ≤ 1) :
    (volume K) ^ (1 - t) * (volume L) ^ t ≤ volume (logCombination K L t) := by
  sorry

end LogBrunnMinkowski

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/LogBrunnMinkowski.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.LogBrunnMinkowski.main` must keep exactly the statement shown above: same names,
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
