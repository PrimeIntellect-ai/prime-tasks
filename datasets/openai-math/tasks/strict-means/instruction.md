# openai/math challenge `StrictMeans` (family 072)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 072 of the release, *Brennan's conjecture and a counterexample to Kraetzer's prediction*
(Real and complex analysis). The family as a whole: Proves Brennan's conjecture: for every conformal bijection $\phi$ from a simply connected plane domain onto the disk, $|\phi'|^s$ is area-integrable for $4/3<s<4$. The sharp universal integral-means identity is $B_{\mathcal S}(t)=|t|-1$ for $t\le-2$. A strict bound $B_b(-1)<1/4$ for bounded univalent functions disproves Kraetzer's prediction at that parameter.

The challenge is `StrictMeans`, also at `/opt/openai-math/challenges/StrictMeans.lean`:

```lean
import Mathlib

namespace OAI

open Set Filter MeasureTheory
open scoped Topology

namespace StrictInverseFirstPower

def disk : Set ℂ := Metric.ball 0 1

def NormalizedUnivalent (f : ℂ → ℂ) : Prop :=
  DifferentiableOn ℂ f disk ∧ Set.InjOn f disk ∧ f 0 = 0 ∧ deriv f 0 = 1

def BoundedNormalizedUnivalent (f : ℂ → ℂ) : Prop :=
  NormalizedUnivalent f ∧ ∃ R : ℝ, ∀ z ∈ disk, ‖f z‖ ≤ R

noncomputable def integralMean (p : ℝ) (f : ℂ → ℂ) (r : ℝ) : ℝ :=
  (2 * Real.pi)⁻¹ * ∫ θ in -Real.pi..Real.pi,
    ‖deriv f ((r : ℂ) * Complex.exp ((θ : ℂ) * Complex.I))‖ ^ p

noncomputable def growthExponent (p : ℝ) (f : ℂ → ℂ) : EReal :=
  Filter.limsup (fun r : ℝ =>
    ((Real.log (integralMean p f r) / Real.log (1 / (1 - r)) : ℝ) : EReal))
    (𝓝[<] (1 : ℝ))

noncomputable def boundedSpectrum (p : ℝ) : EReal :=
  ⨆ (f : ℂ → ℂ) (_ : BoundedNormalizedUnivalent f), growthExponent p f

noncomputable def kraetzerPrediction (p : ℝ) : EReal :=
  if |p| ≤ 2 then ((p ^ (2 : ℕ) / 4 : ℝ) : EReal)
  else ((|p| - 1 : ℝ) : EReal)

theorem main :
    (∃ ε C : ℝ, 0 < ε ∧ ε < 1 / 4 ∧
      ∀ (f : ℂ → ℂ), NormalizedUnivalent f →
        ∀ r : ℝ, 1 / 2 ≤ r → r < 1 →
          integralMean (-1) f r ≤ C * (1 - r) ^ (-(1 / 4 : ℝ) + ε)) ∧
    boundedSpectrum (-1) < (1 / 4 : EReal) ∧
    (¬ ∀ p : ℝ, boundedSpectrum p = kraetzerPrediction p) := by
  sorry

end StrictInverseFirstPower

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/StrictMeans.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.StrictInverseFirstPower.main` must keep exactly the statement shown above: same names,
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
