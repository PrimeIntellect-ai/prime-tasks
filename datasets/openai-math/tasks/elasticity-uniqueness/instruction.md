# openai/math challenge `ElasticityUniqueness` (family 372)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 372 of the release, *Global uniqueness in smooth isotropic elasticity*
(Partial differential equations). The family as a whole: Proves that full static boundary displacement-to-traction data determine both smooth real Lame moduli on every bounded connected smooth domain in $\mathbb R^3$, provided $\mu>0$ and $3\lambda+2\mu>0$ on the closure. Neither analyticity, proximity to constant coefficients nor prior knowledge near the boundary is required.

The challenge is `ElasticityUniqueness`, also at `/opt/openai-math/challenges/ElasticityUniqueness.lean`:

```lean
import Mathlib

namespace OAI

/-!
# Global uniqueness for smooth isotropic elasticity

The physical Dirichlet-to-Neumann pairing acts on the variational trace
quotient. Its quotient norm is not identified here with boundary-chart
fractional Sobolev norms.
-/

noncomputable section
open MeasureTheory Set
open scoped BigOperators

namespace Elasticity

abbrev X := EuclideanSpace ℝ (Fin 3)
abbrev V := X

def coordVector (i : Fin 3) : X := EuclideanSpace.single i 1

def SmoothBoundary (Ω : Set X) : Prop :=
  ∀ x ∈ frontier Ω, ∃ e : OpenPartialHomeomorph X X,
    x ∈ e.source ∧
    ContDiffOn ℝ (⊤ : ℕ∞) e e.source ∧
    ContDiffOn ℝ (⊤ : ℕ∞) e.symm e.target ∧
    e x 0 = 0 ∧
    ∀ y ∈ e.source, y ∈ Ω ↔ 0 < e y 0

def Domain (Ω : Set X) : Prop :=
  IsOpen Ω ∧ IsConnected Ω ∧ Bornology.IsBounded Ω ∧ SmoothBoundary Ω

def SmoothUpTo (Ω : Set X) (f : X → ℝ) : Prop :=
  ∃ U : Set X, IsOpen U ∧ closure Ω ⊆ U ∧ ContDiffOn ℝ (⊤ : ℕ∞) f U

def Admissible (Ω : Set X) (lam mu : X → ℝ) : Prop :=
  SmoothUpTo Ω lam ∧ SmoothUpTo Ω mu ∧
    ∀ x ∈ closure Ω, 0 < mu x ∧ 0 < 3 * lam x + 2 * mu x

abbrev Ambient (Ω : Set X) :=
  Lp V 2 (volume.restrict Ω) × (Fin 3 → Lp V 2 (volume.restrict Ω))

def coordDeriv (f : X → V) (i : Fin 3) (x : X) : V :=
  fderiv ℝ f x (coordVector i)

def SmoothJets (Ω : Set X) : Set (Ambient Ω) :=
  {j | ∃ (f : X → V) (hf : MemLp f 2 (volume.restrict Ω))
      (hd : ∀ i, MemLp (coordDeriv f i) 2 (volume.restrict Ω)),
    ContDiff ℝ (⊤ : ℕ∞) f ∧
    j.1 = hf.toLp f ∧ j.2 = fun i => (hd i).toLp (coordDeriv f i)}

def TestJets (Ω : Set X) : Set (Ambient Ω) :=
  {j | ∃ (f : X → V) (hf : MemLp f 2 (volume.restrict Ω))
      (hd : ∀ i, MemLp (coordDeriv f i) 2 (volume.restrict Ω)),
    ContDiff ℝ (⊤ : ℕ∞) f ∧ HasCompactSupport f ∧ tsupport f ⊆ Ω ∧
    j.1 = hf.toLp f ∧ j.2 = fun i => (hd i).toLp (coordDeriv f i)}

abbrev H1 (Ω : Set X) := {j : Ambient Ω // j ∈ closure (SmoothJets Ω)}

def HasZeroTrace (Ω : Set X) (u : H1 Ω) : Prop :=
  u.val ∈ closure (TestJets Ω)

def SameTrace (Ω : Set X) (u v : H1 Ω) : Prop :=
  u.val - v.val ∈ closure (TestJets Ω)

abbrev BoundaryData (Ω : Set X) := Quot (SameTrace Ω)

def trace (Ω : Set X) (u : H1 Ω) : BoundaryData Ω := Quot.mk _ u

def div (Ω : Set X) (u : H1 Ω) (x : X) : ℝ :=
  ∑ i, (u.val.2 i x) i

def strain (Ω : Set X) (u : H1 Ω) (x : X) (i j : Fin 3) : ℝ :=
  ((u.val.2 j x) i + (u.val.2 i x) j) / 2

def energy (Ω : Set X) (lam mu : X → ℝ) (u v : H1 Ω) : ℝ :=
  ∫ x, (lam x * div Ω u x * div Ω v x +
    2 * mu x * ∑ i, ∑ j, strain Ω u x i j * strain Ω v x i j)
    ∂(volume.restrict Ω)

def WeakSolution (Ω : Set X) (lam mu : X → ℝ) (u : H1 Ω) : Prop :=
  ∀ v : H1 Ω, HasZeroTrace Ω v → energy Ω lam mu u v = 0

def dirichletSolution (Ω : Set X) (lam mu : X → ℝ)
    (f : BoundaryData Ω) : H1 Ω := by
  classical
  exact if h : ∃ u : H1 Ω, trace Ω u = f ∧ WeakSolution Ω lam mu u
  then Classical.choose h
  else f.out

def DN (Ω : Set X) (lam mu : X → ℝ) : BoundaryData Ω → BoundaryData Ω → ℝ :=
  fun f g => energy Ω lam mu (dirichletSolution Ω lam mu f) g.out

def MainClaim : Prop :=
  ∀ (Ω : Set X), Domain Ω →
  ∀ (lam₁ mu₁ lam₂ mu₂ : X → ℝ),
    Admissible Ω lam₁ mu₁ → Admissible Ω lam₂ mu₂ →
    DN Ω lam₁ mu₁ = DN Ω lam₂ mu₂ →
    (∀ x ∈ Ω, lam₁ x = lam₂ x) ∧ (∀ x ∈ Ω, mu₁ x = mu₂ x)

theorem global_uniqueness : MainClaim := by
  sorry

end Elasticity

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/ElasticityUniqueness.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Elasticity.global_uniqueness` must keep exactly the statement shown above: same names,
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
