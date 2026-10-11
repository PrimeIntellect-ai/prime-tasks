# openai/math challenge `OrdinaryElliott` (family 007)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 007 of the release, *Two-point Chowla and the corrected binary Elliott conjecture*
(Number theory). The family as a whole: Proves the ordinary two-point Chowla conjecture, with a bound $O(X/(\log X)^c)$ for Liouville correlation sums along fixed nonproportional affine forms, where $c>0$ is absolute. More generally, proves the binary corrected Elliott conjecture for complex multiplicative functions bounded by one when one factor is uniformly nonpretentious against each fixed Dirichlet character times $n^{it}$ for $|t|\le X$.

The challenge is `OrdinaryElliott`, also at `/opt/openai-math/challenges/OrdinaryElliott.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open scoped BigOperators
open Filter

namespace OrdinaryCorrelations

def OneBounded (f : ℕ → ℂ) : Prop := ∀ n, ‖f n‖ ≤ 1

def Multiplicative (f : ℕ → ℂ) : Prop :=
  ∀ m n : ℕ, 0 < m → 0 < n → m.Coprime n → f (m * n) = f m * f n

def distanceSq (f : ℕ → ℂ) {q : ℕ} (χ : DirichletCharacter ℂ q)
    (t X : ℝ) : ℝ :=
  ∑ p ∈ (Finset.Icc 2 ⌊X⌋₊).filter Nat.Prime,
    (1 - (f p * star (χ (p : ZMod q) *
      Complex.exp ((t * Real.log (p : ℝ) : ℝ) * Complex.I))).re) / (p : ℝ)

def distance (f : ℕ → ℂ) {q : ℕ} (χ : DirichletCharacter ℂ q)
    (t X : ℝ) : ℝ := Real.sqrt (distanceSq f χ t X)

def UniformlyNonpretentious (f : ℕ → ℂ) : Prop :=
  ∀ (q : ℕ), 0 < q → ∀ χ : DirichletCharacter ℂ q,
    Tendsto (fun N : ℕ => sInf ((fun t : ℝ => distance f χ t (N : ℝ)) ''
      Set.Icc (-(N : ℝ)) (N : ℝ))) atTop atTop

def shiftAverage (f₁ f₂ : ℕ → ℂ) (h₁ h₂ N : ℕ) : ℂ :=
  (N : ℂ)⁻¹ * ∑ n ∈ Finset.Icc 1 N, f₁ (n + h₁) * f₂ (n + h₂)

theorem binary_corrected_elliott
    (f₁ f₂ : ℕ → ℂ) (hf₁ : OneBounded f₁) (hf₂ : OneBounded f₂)
    (hm₁ : Multiplicative f₁) (hm₂ : Multiplicative f₂)
    (hNP : UniformlyNonpretentious f₁ ∨ UniformlyNonpretentious f₂)
    (h₁ h₂ : ℕ) (hne : h₁ ≠ h₂) :
    Tendsto (shiftAverage f₁ f₂ h₁ h₂) atTop (nhds 0) := by
  sorry

end OrdinaryCorrelations
end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/OrdinaryElliott.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.OrdinaryCorrelations.binary_corrected_elliott` must keep exactly the statement shown above: same names,
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
