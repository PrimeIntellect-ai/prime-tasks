# openai/math challenge `HotSpots` (family 369)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 369 of the release, *The hot spots conjecture for simply connected planar domains*
(Partial differential equations). The family as a whole: Proves a strict form of Burdzy's simply connected hot spots conjecture. On every smooth bounded simply connected planar domain, each nonzero eigenfunction for the first positive Neumann eigenvalue has no interior critical point, so all global extrema lie on the boundary. Eigenvalue multiplicity is allowed.

The challenge is `HotSpots`, also at `/opt/openai-math/challenges/HotSpots.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open Set MeasureTheory
open scoped ContDiff

namespace StrictHotSpots

abbrev Plane := EuclideanSpace ℝ (Fin 2)

def SmoothBoundary (Ω : Set Plane) : Prop :=
  ∀ p ∈ frontier Ω, ∃ (U : Set Plane) (ρ : Plane → ℝ),
    IsOpen U ∧ p ∈ U ∧ ContDiffOn ℝ ∞ ρ U ∧
    fderiv ℝ ρ p ≠ 0 ∧ ρ p = 0 ∧
    Ω ∩ U = {x | ρ x < 0} ∩ U

def AdmissibleDomain (Ω : Set Plane) : Prop :=
  Ω.Nonempty ∧ IsOpen Ω ∧ Bornology.IsBounded Ω ∧
    IsSimplyConnected Ω ∧ SmoothBoundary Ω

def HasH1Gradient (Ω : Set Plane) (v : Plane → ℝ) (g : Plane → Plane) : Prop :=
  MemLp v 2 (volume.restrict Ω) ∧ MemLp g 2 (volume.restrict Ω) ∧
  ∀ φ : Plane → ℝ, ContDiff ℝ ∞ φ → HasCompactSupport φ → tsupport φ ⊆ Ω →
    ∀ e : Plane,
      (∫ x in Ω, v x * (fderiv ℝ φ x) e) =
        -(∫ x in Ω, (inner ℝ (g x) e) * φ x)

def rayleighValues (Ω : Set Plane) : Set ℝ :=
  {r | ∃ (v : Plane → ℝ) (g : Plane → Plane),
    HasH1Gradient Ω v g ∧ (∫ x in Ω, v x) = 0 ∧
    0 < (∫ x in Ω, (v x) ^ 2) ∧
    r = (∫ x in Ω, ‖g x‖ ^ 2) / (∫ x in Ω, (v x) ^ 2)}

def firstPositiveNeumannValue (Ω : Set Plane) : ℝ := sInf (rayleighValues Ω)

def InFirstNeumannEigenspace (Ω : Set Plane) (u : Plane → ℝ) : Prop :=
  ContDiffOn ℝ ∞ u (closure Ω) ∧ HasH1Gradient Ω u (gradient u) ∧
    (∫ x in Ω, u x) = 0 ∧
    ∀ (v : Plane → ℝ) (g : Plane → Plane), HasH1Gradient Ω v g →
      (∫ x in Ω, inner ℝ (gradient u x) (g x)) =
        firstPositiveNeumannValue Ω * (∫ x in Ω, u x * v x)

def MainConclusion (Ω : Set Plane) (u : Plane → ℝ) : Prop :=
  (∀ x ∈ Ω, gradient u x ≠ 0) ∧
    ∀ x ∈ Ω, sInf (u '' frontier Ω) < u x ∧ u x < sSup (u '' frontier Ω)

theorem main_theorem (Ω : Set Plane) (hΩ : AdmissibleDomain Ω)
    (u : Plane → ℝ) (hu : InFirstNeumannEigenspace Ω u)
    (hne : ∃ x ∈ Ω, u x ≠ 0) : MainConclusion Ω u := by
  sorry

end StrictHotSpots
end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/HotSpots.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.StrictHotSpots.main_theorem` must keep exactly the statement shown above: same names,
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
