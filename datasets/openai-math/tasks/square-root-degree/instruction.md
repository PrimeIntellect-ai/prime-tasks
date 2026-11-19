# openai/math challenge `SquareRootDegree` (family 192)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 192 of the release, *A counterexample to the Gopalan–Servedio conjecture*
(Combinatorics). The family as a whole: Disproves the proposed square-root bound relating a Boolean function's linear Fourier coefficients to its polynomial degree. For every $C>0$, there is a sign-valued Boolean function $f$ with $\sum_i\widehat f(\{i\})>C\sqrt{\deg(f)}$. Thus its total signed correlation with individual input bits can exceed the proposed bound by an arbitrary factor.

The challenge is `SquareRootDegree`, also at `/opt/openai-math/challenges/SquareRootDegree.lean`:

```lean
import Mathlib

namespace OAI

/-!
Bool encodes a sign: false is +1 and true is -1. The average is uniform,
and degree is ordinary real Fourier degree, not F₂ degree or threshold degree.
-/

open scoped BigOperators

noncomputable section

namespace SquareRootDegree

abbrev Cube (ι : Type*) := ι → Bool

def sign (b : Bool) : ℝ := if b then -1 else 1

def average {α : Type*} [Fintype α] (f : α → ℝ) : ℝ :=
  (Fintype.card α : ℝ)⁻¹ * ∑ x, f x

def character {ι : Type*} (s : Finset ι) (x : Cube ι) : ℝ :=
  ∏ i ∈ s, sign (x i)

def fourierCoeff {ι : Type*} [Fintype ι] (f : Cube ι → ℝ) (s : Finset ι) : ℝ := by
  classical
  exact average (fun x => f x * character s x)

def fourierDegree {ι : Type*} [Fintype ι] (f : Cube ι → ℝ) : ℕ := by
  classical
  exact (Finset.univ.filter (fun s : Finset ι => fourierCoeff f s ≠ 0)).sup Finset.card

def IsBoolean {α : Type*} (f : α → ℝ) : Prop :=
  ∀ x, f x = -1 ∨ f x = 1

def Nonconstant {α : Type*} (f : α → ℝ) : Prop :=
  ∃ x y, f x ≠ f y

def singletonSum {ι : Type*} [Fintype ι] (f : Cube ι → ℝ) : ℝ :=
  ∑ i, fourierCoeff f {i}

def absoluteSingletonSum {ι : Type*} [Fintype ι] (f : Cube ι → ℝ) : ℝ :=
  ∑ i, |fourierCoeff f {i}|

def SignedViolations : Prop :=
  ∀ C : ℝ, 0 < C → ∃ n : ℕ, 0 < n ∧ ∃ f : Cube (Fin n) → ℝ,
    IsBoolean f ∧ Nonconstant f ∧ C * Real.sqrt (fourierDegree f) < singletonSum f

def AbsoluteRatios : Set ℝ :=
  {r | ∃ n : ℕ, 0 < n ∧ ∃ f : Cube (Fin n) → ℝ,
    IsBoolean f ∧ 0 < fourierDegree f ∧
      r = absoluteSingletonSum f / Real.sqrt (fourierDegree f)}

/-- The two clauses of the literal main theorem. Unboundedness above is the
real-valued formulation of the displayed supremum being positive infinity. -/
theorem main : SignedViolations ∧ ¬ BddAbove AbsoluteRatios := by
  sorry

end SquareRootDegree

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/SquareRootDegree.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.SquareRootDegree.main` must keep exactly the statement shown above: same names,
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
