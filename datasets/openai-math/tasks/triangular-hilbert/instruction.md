# openai/math challenge `TriangularHilbert` (family 082)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 082 of the release, *Maximal and variational bounds for the triangular Hilbert transform*
(Real and complex analysis). The family as a whole: Proves maximal and annular $r$-variation bounds, for every $r>2$, from complex $L^3(\mathbb R^2)\times L^3(\mathbb R^2)$ to $L^{3/2}(\mathbb R^2)$. The maximal estimate controls both hard truncation endpoints and gives almost-everywhere and norm convergence. Pairing with a third input settles the triangular Hilbert transform estimate at the symmetric $L^3\times L^3\times L^3$ point.

The challenge is `TriangularHilbert`, also at `/opt/openai-math/challenges/TriangularHilbert.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

open MeasureTheory
open scoped ENNReal NNReal

namespace TriangularHilbert

abbrev Plane := ℝ × ℝ

structure Endpoints where
  lower : ℝ
  upper : ℝ
  lower_pos : 0 < lower
  lower_lt_upper : lower < upper

def annulus (ε R : ℝ) : Set ℝ := {t | ε < |t| ∧ |t| < R}

def integrand (F G : Plane → ℂ) (z : Plane) (t : ℝ) : ℂ :=
  F (z.1 + t, z.2) * G (z.1, z.2 + t) / (t : ℂ)

def truncation (F G : Plane → ℂ) (E : Endpoints) (z : Plane) : ℂ :=
  ∫ t in annulus E.lower E.upper, integrand F G z t

def GoodPoint (F G : Plane → ℂ) (z : Plane) : Prop :=
  ∀ n : ℕ, IntegrableOn (integrand F G z)
    (annulus (1 / ((n : ℝ) + 2)) ((n : ℝ) + 2))

def maximal (F G : Plane → ℂ) (z : Plane) : ℝ≥0∞ := by
  classical
  exact if GoodPoint F G z then
    ⨆ E : Endpoints, ENNReal.ofReal ‖truncation F G E z‖ else 0

def maximalNorm (F G : Plane → ℂ) : ℝ≥0∞ :=
  (∫⁻ z : Plane, maximal F G z ^ ((3 : ℝ) / 2)) ^ ((2 : ℝ) / 3)

def MainEstimate : Prop :=
  ∃ C : ℝ≥0, ∀ F G : Plane → ℂ,
    MemLp F 3 volume → MemLp G 3 volume →
    (∀ᵐ z ∂volume, GoodPoint F G z) ∧
    AEMeasurable (maximal F G) volume ∧
    maximalNorm F G ≤ (C : ℝ≥0∞) * eLpNorm F 3 volume * eLpNorm G 3 volume

open MeasureTheory Filter
open scoped ENNReal

theorem main_estimate : MainEstimate := by
  sorry

end TriangularHilbert

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/TriangularHilbert.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.TriangularHilbert.main_estimate` must keep exactly the statement shown above: same names,
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
