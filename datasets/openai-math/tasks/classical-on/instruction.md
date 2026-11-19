# openai/math challenge `ClassicalON` (family 215)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 215 of the release, *Massive continuum limits and exact mass asymptotics for planar $O(n)$ models*
(Probability and statistical mechanics). The family as a whole: Constructs the canonical continuum limit of the two-dimensional nearest-neighbor $O(3)$ model: a non-Gaussian local relativistic theory with a unique vacuum and a positive mass gap. For the square-lattice $O(4)$ model, determines the exact leading asymptotic of the full transfer gap, $m_{\mathrm{lat}}(\beta)\sim32e^{\pi/4-1/2}\sqrt\beta\,e^{-\pi\beta}$. The family also proves exponential spin-correlation decay for two-dimensional nearest-neighbor $O(n)$ models with $n\ge3$ at every positive temperature.

The challenge is `ClassicalON`, also at `/opt/openai-math/challenges/ClassicalON.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open MeasureTheory
open scoped BigOperators InnerProductSpace

namespace ClassicalON

abbrev Site := ℤ × ℤ

def PositiveNeighbor (x y : Site) : Prop :=
  (y.1 = x.1 + 1 ∧ y.2 = x.2) ∨ (y.1 = x.1 ∧ y.2 = x.2 + 1)

structure LatticeGraph where
  vertices : Finset Site
  edges : Finset (vertices × vertices)
  nearest : ∀ e ∈ edges, PositiveNeighbor e.1.val e.2.val

abbrev Spin (n : ℕ) := ↥(Metric.sphere (0 : EuclideanSpace ℝ (Fin n)) 1)
abbrev Configuration (n : ℕ) (G : LatticeGraph) := G.vertices → Spin n

def sphereProbability (n : ℕ) : Measure (Spin n) :=
  let surface := (volume : Measure (EuclideanSpace ℝ (Fin n))).toSphere
  (surface Set.univ)⁻¹ • surface

def referenceLaw (n : ℕ) (G : LatticeGraph) : Measure (Configuration n G) :=
  Measure.pi (fun _ => sphereProbability n)

def interaction (n : ℕ) (G : LatticeGraph) (b : G.edges → ℝ)
    (σ : Configuration n G) : ℝ :=
  ∑ e : G.edges, b e * ⟪(σ e.val.1).val, (σ e.val.2).val⟫_ℝ

def partition (n : ℕ) (G : LatticeGraph) (b : G.edges → ℝ) : ℝ :=
  ∫ σ, Real.exp (interaction n G b σ) ∂referenceLaw n G

def correlation (n : ℕ) (G : LatticeGraph) (b : G.edges → ℝ)
    (x y : G.vertices) : ℝ :=
  (∫ σ, ⟪(σ x).val, (σ y).val⟫_ℝ * Real.exp (interaction n G b σ)
    ∂referenceLaw n G) / partition n G b

def siteDistance (x y : Site) : ℝ :=
  Real.sqrt (((x.1 : ℝ) - (y.1 : ℝ)) ^ 2 + ((x.2 : ℝ) - (y.2 : ℝ)) ^ 2)

def ExponentialDecay : Prop :=
  ∀ (n : ℕ), 3 ≤ n → ∀ (β : ℝ), 0 < β →
    ∃ A m : ℝ, 0 < m ∧ ∀ (G : LatticeGraph) (b : G.edges → ℝ),
      (∀ e, 0 ≤ b e ∧ b e ≤ β) → ∀ x y : G.vertices,
        0 ≤ correlation n G b x y ∧
          correlation n G b x y ≤ A * Real.exp (-m * siteDistance x.val y.val)

theorem main : ExponentialDecay := by
  sorry

end ClassicalON

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/ClassicalON.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.ClassicalON.main` must keep exactly the statement shown above: same names,
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
