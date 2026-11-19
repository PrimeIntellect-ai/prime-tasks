# openai/math challenge `Conductivity` (family 365)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 365 of the release, *Joint metric and connection recovery from one boundary patch*
(Partial differential equations). The family as a whole: Zero-frequency measurements on any nonempty open boundary patch determine a smooth metric and smooth unitary connection on a trivial Hermitian rank-two bundle over a compact connected manifold of dimension at least three, up to diffeomorphism and gauge fixed on that patch. Inputs and observations use the same patch. In contrast, distinct uniformly positive bounded measurable scalar conductivities on a three-dimensional ball can have identical full-boundary data.

The challenge is `Conductivity`, also at `/opt/openai-math/challenges/Conductivity.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open MeasureTheory
open scoped ENNReal

namespace ScalarConductivity

abbrev R3 := EuclideanSpace ℝ (Fin 3)
abbrev JetFiber := EuclideanSpace ℝ (Fin 4)
def ball : Set R3 := Metric.ball 0 3
def ballMeasure : Measure R3 := volume.restrict ball
abbrev JetSpace := Lp JetFiber 2 ballMeasure

def smoothJet (f : R3 → ℝ) (x : R3) : JetFiber :=
  WithLp.toLp 2 (Fin.cases (f x) (fun i => gradient f x i))

def smoothJets : Set JetSpace :=
  { z | ∃ (f : R3 → ℝ) (_ : ContDiff ℝ (↑(⊤ : ℕ∞)) f)
      (hf : MemLp (smoothJet f) 2 ballMeasure), z = hf.toLp (smoothJet f) }

def compactSmoothJets : Set JetSpace :=
  { z | ∃ (f : R3 → ℝ) (_ : ContDiff ℝ (↑(⊤ : ℕ∞)) f)
      (_ : HasCompactSupport f) (_ : tsupport f ⊆ ball)
      (hf : MemLp (smoothJet f) 2 ballMeasure), z = hf.toLp (smoothJet f) }

def H1Space : Submodule ℝ JetSpace :=
  (Submodule.span ℝ smoothJets).topologicalClosure
abbrev H1 := H1Space

def zeroTraceAmbient : Submodule ℝ JetSpace :=
  (Submodule.span ℝ compactSmoothJets).topologicalClosure

def H10 : Submodule ℝ H1 := zeroTraceAmbient.comap H1Space.subtype

instance H10_isClosed : IsClosed (H10 : Set H1) := by
  exact (Submodule.isClosed_topologicalClosure
    (Submodule.span ℝ compactSmoothJets)).preimage continuous_subtype_val

abbrev TraceSpace := H1 ⧸ H10
abbrev TraceDual := TraceSpace →L[ℝ] ℝ
abbrev DNOperator := TraceSpace →L[ℝ] TraceDual

def trace (u : H1) : TraceSpace := H10.mkQ u

def weakGradient (u : H1) (x : R3) : R3 :=
  WithLp.toLp 2 (fun i => (u.val x) i.succ)

def energy (γ : R3 → ℝ) (u v : H1) : ℝ :=
  ∫ x, γ x * inner ℝ (weakGradient u x) (weakGradient v x) ∂ballMeasure

def Harmonic (γ : R3 → ℝ) (u : H1) : Prop :=
  ∀ h : H1, h ∈ H10 → energy γ u h = 0

def IsDirichletToNeumann (γ : R3 → ℝ) (Λ : DNOperator) : Prop :=
  ∀ f : TraceSpace, ∃ u : H1,
    trace u = f ∧ Harmonic γ u ∧
    (∀ u' : H1, trace u' = f → Harmonic γ u' → u' = u) ∧
    ∀ v : H1, Λ f (trace v) = energy γ u v

def EqualOneNearBoundary (γ : R3 → ℝ) : Prop :=
  ∃ r : ℝ, 0 < r ∧ r < 3 ∧ ∀ᵐ x ∂ballMeasure, r < ‖x‖ → γ x = 1

def MainStatement : Prop :=
  ∃ (γ₀ γ₁ : R3 → ℝ) (c C : ℝ) (Λ : DNOperator),
    0 < c ∧ c < C ∧
    Measurable γ₀ ∧ Measurable γ₁ ∧
    MemLp γ₀ ∞ ballMeasure ∧ MemLp γ₁ ∞ ballMeasure ∧
    (∀ᵐ x ∂ballMeasure, c ≤ γ₀ x ∧ γ₀ x ≤ C) ∧
    (∀ᵐ x ∂ballMeasure, c ≤ γ₁ x ∧ γ₁ x ≤ C) ∧
    EqualOneNearBoundary γ₀ ∧ EqualOneNearBoundary γ₁ ∧
    0 < ballMeasure {x | γ₀ x ≠ γ₁ x} ∧
    IsDirichletToNeumann γ₀ Λ ∧ IsDirichletToNeumann γ₁ Λ

theorem main_nonuniqueness : MainStatement := by
  sorry

end ScalarConductivity
end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/Conductivity.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.ScalarConductivity.main_nonuniqueness` must keep exactly the statement shown above: same names,
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
