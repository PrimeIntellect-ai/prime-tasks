# openai/math challenge `HyperbolicCones` (family 095)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 095 of the release, *Hyperbolicity cones without semidefinite lifts*
(Convex and metric geometry). The family as a whole: Disproves the Projected Lax conjecture: some hyperbolicity cones are not spectrahedral shadows. The examples admit no exact finite affine semidefinite lift, regardless of the number of auxiliary variables or the real coefficients used. This also disproves the generalized Lax conjecture that every hyperbolicity cone is spectrahedral.

The challenge is `HyperbolicCones`, also at `/opt/openai-math/challenges/HyperbolicCones.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

open scoped Matrix.Norms.L2Operator

universe u

namespace Paper256

abbrev Mat (n : ℕ) (R : Type u) := Matrix (Fin n) (Fin n) R

abbrev Sym (n : ℕ) := selfAdjoint (Mat n ℝ)

instance instFiniteDimensionalSym (n : ℕ) : FiniteDimensional ℝ (Sym n) :=
  FiniteDimensional.finiteDimensional_submodule (selfAdjoint.submodule ℝ (Mat n ℝ))

abbrev Ambient := (Sym 4 × Sym 4) × (Fin 3 → ℝ)

abbrev SymIndex := {ij : Fin 4 × Fin 4 // ij.1 ≤ ij.2}

abbrev Coord := (SymIndex ⊕ SymIndex) ⊕ Fin 3

def qMatrix {R : Type u} [CommRing R] (y : Fin 3 → R) : Mat 3 R :=
  fun i j => if i = j then y i ^ 2 + y (i + 1) ^ 2 else -(y i * y j)

def phi {R : Type u} [CommRing R] (y : Fin 3 → R) (X : Mat 4 R) : Mat 4 R :=
  fun i j => Fin.cases
    (Fin.cases
      (Matrix.trace (qMatrix y * X.submatrix Fin.succ Fin.succ))
      (fun j => -(∑ k, X 0 k.succ * qMatrix y k j)) j)
    (fun i => Fin.cases
      (-(∑ k, qMatrix y i k * X k.succ 0))
      (fun j => X 0 0 * qMatrix y i j) j) i

def matrixValue {R : Type u} [CommRing R]
    (X Z : Mat 4 R) (y : Fin 3 → R) : R :=
  Matrix.det ((Matrix.det X) • Z - phi y (Matrix.adjugate X))

def symmetricCoordinates {R : Type u} (v : SymIndex → R) : Mat 4 R :=
  fun i j => if h : i ≤ j then v ⟨(i, j), h⟩
    else v ⟨(j, i), le_of_lt (lt_of_not_ge h)⟩

def polynomial : MvPolynomial Coord ℝ :=
  matrixValue
    (symmetricCoordinates fun ij => MvPolynomial.X (Sum.inl (Sum.inl ij)))
    (symmetricCoordinates fun ij => MvPolynomial.X (Sum.inl (Sum.inr ij)))
    (fun i => MvPolynomial.X (Sum.inr i))

def coordinates (x : Ambient) : Coord → ℝ :=
  Sum.elim (Sum.elim
    (fun ij => (x.1.1 : Mat 4 ℝ) ij.val.1 ij.val.2)
    (fun ij => (x.1.2 : Mat 4 ℝ) ij.val.1 ij.val.2)) x.2

def basePoint : Ambient := ((1, 1), 0)

def linePolynomial (x : Ambient) : Polynomial ℝ :=
  MvPolynomial.eval₂ Polynomial.C
    (fun i => Polynomial.C (coordinates basePoint i) * Polynomial.X -
      Polynomial.C (coordinates x i)) polynomial

def cone : Set Ambient :=
  {x | ∀ t : ℂ, (linePolynomial x).aeval t = 0 → t.im = 0 ∧ 0 ≤ t.re}

theorem main_result :
    Module.finrank ℝ Ambient = 23 ∧
    polynomial.IsHomogeneous 20 ∧
    polynomial.totalDegree = 20 ∧
    MvPolynomial.eval (coordinates basePoint) polynomial = 1 ∧
    (∀ (x : Ambient) (z : ℂ), (linePolynomial x).aeval z = 0 → z.im = 0) ∧
    ∀ (N : ℕ) (_hN : 0 < N) (L : Ambient →ₗ[ℝ] Sym N),
      cone ≠ {x | (L x : Mat N ℝ).PosSemidef} := by
  sorry

end Paper256

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/HyperbolicCones.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Paper256.main_result` must keep exactly the statement shown above: same names,
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
