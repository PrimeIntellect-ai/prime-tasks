# openai/math challenge `SymmetricDomains` (family 058)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 058 of the release, *The Kollar–Pardon universal-cover conjecture*
(Algebraic and complex geometry). The family as a whole: Proves the Kollar–Pardon conjecture: the semialgebraic universal covers of connected normal projective complex varieties are exactly products $D\times\mathbb C^m\times F$, with $D$ bounded symmetric and $F$ simply connected, normal, and projective. A universal cover is quasi-projective exactly when the bounded symmetric factor is absent. In particular, a smooth projective variety covered by $\mathbb C^n$ has a finite \textnormal{étale} cover by an abelian variety.

The challenge is `SymmetricDomains`, also at `/opt/openai-math/challenges/SymmetricDomains.lean`:

```lean
import Mathlib

namespace OAI

namespace Release061

abbrev Affine (n : ℕ) := Fin n → ℂ

def realCoordinates {n : ℕ} (z : Affine n) : Fin n ⊕ Fin n → ℝ :=
  Sum.elim (fun j => (z j).re) (fun j => (z j).im)

def IsAffineAlgebraic {n : ℕ} (V : Set (Affine n)) : Prop :=
  ∃ P : Set (MvPolynomial (Fin n) ℂ),
    V = {z | ∀ p ∈ P, MvPolynomial.eval z p = 0}

inductive IsSemialgebraic {n : ℕ} : Set (Affine n) → Prop
  | zero (p : MvPolynomial (Fin n ⊕ Fin n) ℝ) :
      IsSemialgebraic {z | MvPolynomial.eval (realCoordinates z) p = 0}
  | positive (p : MvPolynomial (Fin n ⊕ Fin n) ℝ) :
      IsSemialgebraic {z | 0 < MvPolynomial.eval (realCoordinates z) p}
  | compl {S : Set (Affine n)} : IsSemialgebraic S → IsSemialgebraic Sᶜ
  | union {S T : Set (Affine n)} :
      IsSemialgebraic S → IsSemialgebraic T → IsSemialgebraic (S ∪ T)

def HolomorphicOnSubset {n m : ℕ} (S : Set (Affine n)) (f : S → Affine m) : Prop :=
  ∀ p : S, ∃ W : Set (Affine n), IsOpen W ∧ (p : Affine n) ∈ W ∧
    ∃ F : Affine n → Affine m, AnalyticOnNhd ℂ F W ∧
      ∀ q : S, (q : Affine n) ∈ W → F q = f q

structure Biholomorph {n m : ℕ} (S : Set (Affine n)) (T : Set (Affine m)) where
  toHomeomorph : S ≃ₜ T
  holomorphic_toFun : HolomorphicOnSubset S (fun p => (toHomeomorph p : Affine m))
  holomorphic_invFun : HolomorphicOnSubset T (fun q => (toHomeomorph.symm q : Affine n))

def IsSmooth {n : ℕ} (S : Set (Affine n)) : Prop :=
  ∀ p : S, ∃ (m : ℕ) (W : Set (Affine n)), W ⊆ S ∧
    IsOpen ((Subtype.val : S → Affine n) ⁻¹' W) ∧ (p : Affine n) ∈ W ∧
    ∃ D : Set (Affine m), IsOpen D ∧ Nonempty (Biholomorph W D)

def IsBoundedSymmetricDomain {n : ℕ} (D : Set (Affine n)) : Prop :=
  IsOpen D ∧ IsConnected D ∧ Bornology.IsBounded D ∧
    ∀ p : D, ∃ σ : Biholomorph D D,
      Function.Involutive σ.toHomeomorph ∧ σ.toHomeomorph p = p ∧
      ∃ W : Set D, IsOpen W ∧ p ∈ W ∧
        ∀ q ∈ W, σ.toHomeomorph q = q → q = p

theorem main {n : ℕ} (V U : Set (Affine n))
    (hV : IsAffineAlgebraic V) (hUV : U ⊆ V)
    (hopen : IsOpen ((Subtype.val : V → Affine n) ⁻¹' U))
    (hconn : IsConnected U) (hsa : IsSemialgebraic U)
    (hbounded : Bornology.IsBounded U)
    (Γ : Type*) [Group Γ] [TopologicalSpace Γ] [DiscreteTopology Γ]
    [MulAction Γ U] [ProperSMul Γ U]
    [CompactSpace (Quotient (MulAction.orbitRel Γ U))]
    (hhol : ∀ γ : Γ, HolomorphicOnSubset U (fun p => (γ • p : U).val)) :
    IsSmooth U ∧ ∃ (m : ℕ) (D : Set (Affine m)),
      IsBoundedSymmetricDomain D ∧ Nonempty (Biholomorph U D) := by
  sorry

end Release061

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/SymmetricDomains.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Release061.main` must keep exactly the statement shown above: same names,
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
