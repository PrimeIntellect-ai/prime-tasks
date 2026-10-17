# openai/math challenge `CommutingDerivations` (family 049)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 049 of the release, *A stable-coordinate counterexample in four variables*
(Algebraic and complex geometry). The family as a whole: Constructs a polynomial in four complex variables that is not a coordinate but becomes one after adjoining a single variable, disproving the Stable Coordinate conjecture in four variables. Every fiber is affine three-space, yet none of its embeddings is rectifiable, also disproving the Abhyankar–Sathaye conjecture even when all fibers are affine spaces.

The challenge is `CommutingDerivations`, also at `/opt/openai-math/challenges/CommutingDerivations.lean`:

```lean
import Mathlib.Algebra.MvPolynomial.PDeriv
import Mathlib.Basic.Complex.Basic
import Mathlib.LinearAlgebra.LinearIndependent.Defs
import Mathlib.Logic.Equiv.Fin.Basic
import Mathlib.Logic.Function.Iterate
import Mathlib.RingTheory.Adjoin.Basic

namespace OAI

noncomputable section

namespace AbhyankarSathaye

def S {B : Type*} [CommRing B] (h u v w : B) : B :=
  2*u^3*v + 3*u^4*w + h*(v^2 - 3*u^2*w^2) + h^2*w^3

def P {B : Type*} [CommRing B] (x y s : B) : B :=
  -2*s^2*x + 3*s*y^2 - 3*s^3*y

abbrev R := MvPolynomial (Fin 4) ℂ

def h : R := MvPolynomial.X 0
def u : R := MvPolynomial.X 1
def v : R := MvPolynomial.X 2
def w : R := MvPolynomial.X 3
def x : R := u^3 + h*v
def y : R := -u^2 + h*w
def s : R := S h u v w
def p : R := P x y s
def F : R := h - p - 1

def fourInclusion {n : ℕ} (hn : 4 ≤ n) (i : Fin 4) : Fin n :=
  ⟨i.val, lt_of_lt_of_le i.isLt hn⟩

def extendedF {n : ℕ} (hn : 4 ≤ n) : MvPolynomial (Fin n) ℂ :=
  MvPolynomial.rename (fourInclusion hn) F

def blocksToAmbient {n : ℕ} (hn : 4 ≤ n) : Fin (n-4) ⊕ Fin 4 ≃ Fin n :=
  (Equiv.sumComm _ _).trans (finSumFinEquiv.trans (finCongr (by omega)))

def blocksToOutput {n : ℕ} (hn : 4 ≤ n) : Fin (n-4) ⊕ Fin 3 ≃ Fin (n-1) :=
  (Equiv.sumComm _ _).trans (finSumFinEquiv.trans (finCongr (by omega)))

namespace CommutingDerivations

variable {K A B : Type*} [CommRing K] [CommRing A] [CommRing B]
  [Algebra K A] [Algebra K B]

def LocallyNilpotent (D : Derivation K A A) : Prop :=
  ∀ a : A, ∃ n : ℕ, (D : A → A)^[n] a = 0

open MvPolynomial

theorem commuting_derivations_with_ordinary_extras (n : ℕ) (hn : 4 ≤ n) :
    ∃ d : Fin (n-1) → Derivation ℂ (MvPolynomial (Fin n) ℂ) (MvPolynomial (Fin n) ℂ),
      (∀ i, d i (extendedF hn + 1) = 0) ∧
      (∀ i j p, d i (d j p) = d j (d i p)) ∧
      (∀ i, LocallyNilpotent (d i)) ∧
      LinearIndependent (MvPolynomial (Fin n) ℂ) d ∧
      (∀ p, (∀ i, d i p = 0) ↔
        p ∈ Algebra.adjoin ℂ ({extendedF hn} : Set (MvPolynomial (Fin n) ℂ))) ∧
      (∀ g, (∀ i, d i g = 0) →
        ¬ ∃ (e : MvPolynomial (Fin n) ℂ ≃ₐ[ℂ] MvPolynomial (Fin n) ℂ) (j : Fin n),
          e (X j) = g) ∧
      (∀ i : Fin (n-4), d (blocksToOutput hn (Sum.inl i)) =
        pderiv (blocksToAmbient hn (Sum.inl i))) := by
  sorry

end CommutingDerivations

end AbhyankarSathaye

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/CommutingDerivations.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.AbhyankarSathaye.CommutingDerivations.commuting_derivations_with_ordinary_extras` must keep exactly the statement shown above: same names,
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
