# openai/math challenge `TypeSystemNormalization` (family 245)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 245 of the release, *The $\beta$-Barendregt–Geuvers–Klop conjecture*
(Mathematical logic). The family as a whole: Proves that weak normalization implies strong normalization for every pure type system: if every legal expression in every valid context has a $\beta$-normal form, every $\beta$-reduction sequence terminates. This resolves the $\beta$-Barendregt–Geuvers–Klop conjecture, including nonfunctional rules and open contexts.

The challenge is `TypeSystemNormalization`, also at `/opt/openai-math/challenges/TypeSystemNormalization.lean`:

```lean
import Mathlib

namespace OAI

/-!
Full annotated PTS syntax, modulo alpha-renaming via de Bruijn indices.
Contexts are stored newest-first, each declaration in its prefix context.
No functionality assumptions on axioms or product rules.
-/

namespace PureTypeSystem

universe u

inductive Expr (Sorts : Type u) : Type u
  | var : Nat → Expr Sorts
  | sort : Sorts → Expr Sorts
  | app : Expr Sorts → Expr Sorts → Expr Sorts
  | lam : Expr Sorts → Expr Sorts → Expr Sorts
  | pi : Expr Sorts → Expr Sorts → Expr Sorts
  deriving DecidableEq

namespace Expr

variable {S : Type u}

def liftRen (ρ : Nat → Nat) : Nat → Nat
  | 0 => 0
  | n + 1 => ρ n + 1

def rename (ρ : Nat → Nat) : Expr S → Expr S
  | var n => var (ρ n)
  | sort s => sort s
  | app f a => app (rename ρ f) (rename ρ a)
  | lam A b => lam (rename ρ A) (rename (liftRen ρ) b)
  | pi A B => pi (rename ρ A) (rename (liftRen ρ) B)

def liftSub (σ : Nat → Expr S) : Nat → Expr S
  | 0 => var 0
  | n + 1 => rename Nat.succ (σ n)

def subst (σ : Nat → Expr S) : Expr S → Expr S
  | var n => σ n
  | sort s => sort s
  | app f a => app (subst σ f) (subst σ a)
  | lam A b => lam (subst σ A) (subst (liftSub σ) b)
  | pi A B => pi (subst σ A) (subst (liftSub σ) B)

def single (a : Expr S) : Nat → Expr S
  | 0 => a
  | n + 1 => var n

def instantiate (b a : Expr S) : Expr S := subst (single a) b

end Expr

structure Specification (S : Type u) where
  axioms : S → S → Prop
  rule : S → S → S → Prop

inductive Beta {S : Type u} : Expr S → Expr S → Prop
  | head (A b a) : Beta (.app (.lam A b) a) (b.instantiate a)
  | app_left {f f' a} : Beta f f' → Beta (.app f a) (.app f' a)
  | app_right {f a a'} : Beta a a' → Beta (.app f a) (.app f a')
  | lam_domain {A A' b} : Beta A A' → Beta (.lam A b) (.lam A' b)
  | lam_body {A b b'} : Beta b b' → Beta (.lam A b) (.lam A b')
  | pi_domain {A A' B} : Beta A A' → Beta (.pi A B) (.pi A' B)
  | pi_body {A B B'} : Beta B B' → Beta (.pi A B) (.pi A B')

def Converts {S : Type u} : Expr S → Expr S → Prop := Relation.EqvGen Beta

def Normal {S : Type u} (M : Expr S) : Prop := ∀ N, ¬ Beta M N

def WeaklyNormalizing {S : Type u} (M : Expr S) : Prop :=
  ∃ N, Relation.ReflTransGen Beta M N ∧ Normal N

/-- Accessibility for the converse of reduction: strong normalization,
including reductions in all type annotations. -/
def StronglyNormalizing {S : Type u} (M : Expr S) : Prop :=
  Acc (fun N M : Expr S => Beta M N) M

inductive HasType {S : Type u} (P : Specification S) :
    List (Expr S) → Expr S → Expr S → Prop
  | ax {s t} : P.axioms s t → HasType P [] (.sort s) (.sort t)
  | var {Γ A s} : HasType P Γ A (.sort s) →
      HasType P (A :: Γ) (.var 0) (A.rename Nat.succ)
  | weaken {Γ M B A s} : HasType P Γ M B → HasType P Γ A (.sort s) →
      HasType P (A :: Γ) (M.rename Nat.succ) (B.rename Nat.succ)
  | product {Γ A B s₁ s₂ s₃} : HasType P Γ A (.sort s₁) →
      HasType P (A :: Γ) B (.sort s₂) → P.rule s₁ s₂ s₃ →
      HasType P Γ (.pi A B) (.sort s₃)
  | abstraction {Γ A b B s} : HasType P (A :: Γ) b B →
      HasType P Γ (.pi A B) (.sort s) →
      HasType P Γ (.lam A b) (.pi A B)
  | application {Γ f a A B} : HasType P Γ f (.pi A B) →
      HasType P Γ a A → HasType P Γ (.app f a) (B.instantiate a)
  | conversion {Γ M A B s} : HasType P Γ M A → HasType P Γ B (.sort s) →
      Converts A B → HasType P Γ M B

inductive ValidContext {S : Type u} (P : Specification S) : List (Expr S) → Prop
  | nil : ValidContext P []
  | cons {Γ A s} : ValidContext P Γ → HasType P Γ A (.sort s) →
      ValidContext P (A :: Γ)

def Legal {S : Type u} (P : Specification S) (Γ : List (Expr S)) (M : Expr S) : Prop :=
  ∃ A, HasType P Γ M A ∨ HasType P Γ A M

def SystemWeaklyNormalizing {S : Type u} (P : Specification S) : Prop :=
  ∀ Γ, ValidContext P Γ → ∀ M, Legal P Γ M → WeaklyNormalizing M

def SystemStronglyNormalizing {S : Type u} (P : Specification S) : Prop :=
  ∀ Γ, ValidContext P Γ → ∀ M, Legal P Γ M → StronglyNormalizing M

/-- System-wide weak normalization implies strong normalization for every PTS,
including arbitrary sort types, nonfunctional rules and annotated terms. -/
theorem weak_implies_strong {S : Type u} (P : Specification S)
    (h : SystemWeaklyNormalizing P) : SystemStronglyNormalizing P := by
  sorry

end PureTypeSystem

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/TypeSystemNormalization.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.PureTypeSystem.weak_implies_strong` must keep exactly the statement shown above: same names,
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
