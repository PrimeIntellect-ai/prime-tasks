# openai/math challenge `SubpolynomialLp` (family 094)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 094 of the release, *Subpolynomial dimension reduction in $L_p$*
(Convex and metric geometry). The family as a whole: For every fixed $1<p<\infty$ and distortion $D>1$, every $n$-point subset of real $L_p$ embeds into $\ell_p^d$ with distortion at most $D$ and dimension $d=n^{o(1)}$, answering Naor's sublinear-dimension question for $p\ne2$. In contrast, exact embeddings require worst-case dimension $\Theta(n^2)$ when $p\ne2$.

The challenge is `SubpolynomialLp`, also at `/opt/openai-math/challenges/SubpolynomialLp.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open MeasureTheory Filter
open scoped BigOperators Topology
universe u

namespace SubpolynomialLp

def coordinateDistance (p : ℝ) {d : ℕ} (x y : Fin d → ℝ) : ℝ :=
  (∑ a, |x a - y a| ^ p) ^ (1 / p)

/-- The universal property used in the definition of d_p(n,D). -/
def GoodDimension (p : ℝ) (n : ℕ) (D : ℝ) (d : ℕ) : Prop :=
  ∀ (Ω : Type u) (mΩ : MeasurableSpace Ω) (μ : @Measure Ω mΩ)
    (x : Fin n → @Lp Ω ℝ mΩ _ (ENNReal.ofReal p) μ),
    Function.Injective x →
    ∃ (y : Fin n → Fin d → ℝ) (s : ℝ), 0 < s ∧
      ∀ i j, s * ‖x i - x j‖ ≤ coordinateDistance p (y i) (y j) ∧
        coordinateDistance p (y i) (y j) ≤ D * s * ‖x i - x j‖

/-- The least universal coordinate dimension. The theorem also asserts that
this least dimension has the defining property, ruling out an empty infimum. -/
def dimension (p : ℝ) (n : ℕ) (D : ℝ) : ℕ :=
  sInf {d : ℕ | GoodDimension.{u} p n D d}

def gamma (p : ℝ) : ℝ := if p < 2 then 2 - p else 1 - 2 / p

/-- The universal coordinate dimension bounds and their logarithmic limits. -/
theorem source_main (p : ℝ) (hp : 1 < p) (hp2 : p ≠ 2) :
    (∀ D : ℝ, 1 < D → ∃ C : ℝ, ∀ n : ℕ, 2 ≤ n →
      GoodDimension.{u} p n D (dimension.{u} p n D) ∧
      Real.log (n : ℝ) / Real.log (1 + 2 * D) ≤ (dimension.{u} p n D : ℝ) ∧
      (dimension.{u} p n D : ℝ) ≤ Real.exp (C * Real.log (n : ℝ) ^ gamma p)) ∧
    (∀ n : ℕ, 9 ≤ n →
      GoodDimension.{u} p n 1 (dimension.{u} p n 1) ∧
      ((n - 1) / 4) ^ 2 ≤ dimension.{u} p n 1 ∧
      dimension.{u} p n 1 ≤ n.choose 2) ∧
    (∀ D : ℝ, 1 ≤ D →
      Tendsto (fun n : ℕ => Real.log (dimension.{u} p n D : ℝ) / Real.log (n : ℝ))
        atTop (𝓝 (if 1 < D then 0 else 2))) := by
  sorry

end SubpolynomialLp

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/SubpolynomialLp.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.SubpolynomialLp.source_main` must keep exactly the statement shown above: same names,
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
