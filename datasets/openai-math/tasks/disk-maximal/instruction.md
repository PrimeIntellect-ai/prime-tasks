# openai/math challenge `DiskMaximal` (family 085)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 085 of the release, *Endpoint regularity of the planar centered maximal function*
(Real and complex analysis). The family as a whole: Resolves the planar centered-disk case of the Haj{\l}asz–Onninen maximal-function regularity problem. For every real $f\in W^{1,1}(\mathbb R^2)$, the centered disk maximal function satisfies $\|\nabla Mf\|_1\le C\|\nabla f\|_1$ with an absolute constant. It belongs locally to $W^{1,1}$ and has a globally integrable weak gradient.

The challenge is `DiskMaximal`, also at `/opt/openai-math/challenges/DiskMaximal.lean`:

```lean
import Mathlib

namespace OAI

open MeasureTheory Set
open scoped ENNReal NNReal Topology ContDiff

noncomputable section
namespace CenteredDiskEndpoint

/-- The Euclidean plane, not the product space with its max norm. -/
abbrev Plane := EuclideanSpace ℝ (Fin 2)

/-- Absolute disk average, retaining possible infinite values. -/
def absoluteDiskAverage (f : Plane → ℝ) (x : Plane) (r : ℝ) : ℝ≥0∞ :=
  (∫⁻ y in Metric.ball x r, ENNReal.ofReal |f y|) /
    ENNReal.ofReal (Real.pi * r ^ 2)

/-- The actual centered disk maximal function, over every positive real radius. -/
def maximal (f : Plane → ℝ) (x : Plane) : ℝ≥0∞ :=
  ⨆ (r : ℝ) (_ : 0 < r), absoluteDiskAverage f x r

/-- Real representative; the endpoint also asserts that `maximal f` is finite a.e. -/
def maximalReal (f : Plane → ℝ) (x : Plane) : ℝ := (maximal f x).toReal

/-- The i-th coordinate derivative of a smooth test function. -/
def testPartial (φ : Plane → ℝ) (i : Fin 2) (x : Plane) : ℝ :=
  fderiv ℝ φ x (EuclideanSpace.single i 1)

/-- Distributional first derivatives represented by a vector-valued function. -/
def HasWeakGradient (f : Plane → ℝ) (g : Plane → Plane) : Prop :=
  ∀ (φ : Plane → ℝ), ContDiff ℝ ∞ φ → HasCompactSupport φ →
    ∀ i : Fin 2, (∫ x, f x * testPartial φ i x) = -∫ x, g x i * φ x

/-- Local W^(1,1), expressed using the same distributional gradient convention. -/
def InW11Loc (f : Plane → ℝ) : Prop :=
  LocallyIntegrable f ∧
    ∃ g : Plane → Plane, LocallyIntegrable g ∧ HasWeakGradient f g

/-- The gradient L1 norm in Euclidean norm. -/
def gradientNorm (g : Plane → Plane) : ℝ := ∫ x, ‖g x‖

/-- Exact endpoint, including finiteness before passing to the real representative.
Quantifying the input gradient makes the norm bound independent of a choice of
representative of its weak derivatives. -/
def EndpointStatement : Prop :=
  ∃ C : ℝ, 0 ≤ C ∧
    ∀ (f : Plane → ℝ) (g : Plane → Plane),
      Integrable f → Integrable g → HasWeakGradient f g →
      (∀ᵐ x, maximal f x ≠ ⊤) ∧
      LocallyIntegrable (maximalReal f) ∧
      InW11Loc (maximalReal f) ∧
      ∃ G : Plane → Plane, Integrable G ∧
        HasWeakGradient (maximalReal f) G ∧ gradientNorm G ≤ C * gradientNorm g

theorem main_endpoint : EndpointStatement := by
  sorry

end CenteredDiskEndpoint

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/DiskMaximal.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.CenteredDiskEndpoint.main_endpoint` must keep exactly the statement shown above: same names,
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
