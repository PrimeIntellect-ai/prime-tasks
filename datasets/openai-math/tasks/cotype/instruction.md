# openai/math challenge `Cotype` (family 326)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 326 of the release, *The cotype–cotype conjecture under the approximation property*
(Functional analysis). The family as a whole: Resolves the cotype–cotype conjecture for real Banach spaces with the approximation property. Such a nonzero space is $K$-convex if and only if both it and its dual have finite Rademacher cotype, with possibly different exponents. Equivalently, these cotype assumptions force nontrivial Rademacher type.

The challenge is `Cotype`, also at `/opt/openai-math/challenges/Cotype.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

open scoped BigOperators
universe u v

namespace Cotype

abbrev Cube (n : ℕ) := Fin n → Bool

def sign (b : Bool) : ℝ := if b then -1 else 1

def average {ι : Type u} [Fintype ι] {E : Type v} [AddCommMonoid E] [Module ℝ E]
    (f : ι → E) : E := (Fintype.card ι : ℝ)⁻¹ • ∑ i, f i

variable (E : Type u) [NormedAddCommGroup E] [NormedSpace ℝ E]

def cubeL2 {n : ℕ} (f : Cube n → E) : ℝ :=
  Real.sqrt (average (fun ε => ‖f ε‖ ^ 2))

def rademacherSum {n : ℕ} (x : Fin n → E) (ε : Cube n) : E :=
  ∑ i, sign (ε i) • x i

def moment {n : ℕ} (f : Cube n → E) (i : Fin n) : E :=
  average (fun ε => sign (ε i) • f ε)

def radProjection {n : ℕ} (f : Cube n → E) : Cube n → E :=
  rademacherSum E (moment E f)

def KConvex : Prop := ∃ K : ℝ, 0 ≤ K ∧ ∀ (n : ℕ) (f : Cube n → E),
  cubeL2 E (radProjection E f) ≤ K * cubeL2 E f

def HasCotype (q : ℝ) : Prop := 2 ≤ q ∧ ∃ C : ℝ, 0 ≤ C ∧
  ∀ (n : ℕ) (x : Fin n → E),
    (∑ i, ‖x i‖ ^ q) ^ (1 / q) ≤ C * cubeL2 E (rademacherSum E x)

def FiniteCotype : Prop := ∃ q : ℝ, HasCotype E q

def ApproximationProperty : Prop := ∀ (M : Set E), IsCompact M →
  ∀ δ : ℝ, 0 < δ → ∃ S : E →L[ℝ] E,
    FiniteDimensional ℝ (LinearMap.range S.toLinearMap) ∧
    ∀ x ∈ M, ‖S x - x‖ < δ

def MainTarget [CompleteSpace E] [Nontrivial E] : Prop :=
  ApproximationProperty E →
    (KConvex E ↔ FiniteCotype E ∧ FiniteCotype (E →L[ℝ] ℝ))

variable {X : Type u} [NormedAddCommGroup X] [NormedSpace ℝ X] [CompleteSpace X]

theorem mainTarget_proved [Nontrivial X] : MainTarget X := by
  sorry

end Cotype

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/Cotype.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Cotype.mainTarget_proved` must keep exactly the statement shown above: same names,
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
