# openai/math challenge `BinaryEditLower` (family 099)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 099 of the release, *The sharp distortion of edit distance into $\ell_1$*
(Convex and metric geometry). The family as a whole: Determines the least distortion of embedding edit distance on words of length at most $d$ into real $\ell_1$: it is $\exp(\Theta(\sqrt{\log d\,\log\log d}))$. Insertions, deletions and substitutions have unit cost. The constants are uniform over all finite alphabets with at least two symbols, even when the alphabet grows with $d$; binary words already force the lower bound.

The challenge is `BinaryEditLower`, also at `/opt/openai-math/challenges/BinaryEditLower.lean`:

```lean
import Mathlib

namespace OAI

namespace TreeEdit

universe u

/-- A single unit-cost insertion, deletion, or substitution at any position. -/
inductive EditStep {α : Type u} : List α → List α → Prop
  | insert (p q : List α) (a : α) : EditStep (p ++ q) (p ++ a :: q)
  | delete (p q : List α) (a : α) : EditStep (p ++ a :: q) (p ++ q)
  | substitute (p q : List α) (a b : α) : EditStep (p ++ a :: q) (p ++ b :: q)

/-- An edit script with no restriction on intermediate word lengths. -/
inductive EditScript {α : Type u} : List α → List α → ℕ → Prop
  | nil (x : List α) : EditScript x x 0
  | cons {x y z : List α} {n : ℕ} :
      EditStep x y → EditScript y z n → EditScript x z (n + 1)

noncomputable def ed {α : Type u} (x y : List α) : ℕ :=
  sInf {n | EditScript x y n}

abbrev RealL1 := lp (fun _ : ℕ => ℝ) 1
abbrev Word (α : Type u) (n : ℕ) := {x : List α // x.length = n}

namespace BinaryLower

/-- The product of the two maximal pairwise distance ratios. -/
noncomputable def distortion {X : Type u} (ρ : X → X → ℝ) (f : X → RealL1) : ℝ :=
  sSup {r : ℝ | ∃ x y : X, x ≠ y ∧ r = ‖f x - f y‖ / ρ x y} *
  sSup {r : ℝ | ∃ x y : X, x ≠ y ∧ r = ρ x y / ‖f x - f y‖}

/-- The infimum over every injective map into the full real sequence space ℓ₁. -/
noncomputable def c1 (X : Type u) (ρ : X → X → ℝ) : ℝ :=
  sInf {D : ℝ | ∃ f : X → RealL1, Function.Injective f ∧ D = distortion ρ f}

noncomputable def binarySetDistortion {n : ℕ} (W : Finset (Word Bool n)) : ℝ :=
  c1 {x : Word Bool n // x ∈ W}
    (fun x y => (ed x.val.val y.val.val : ℝ))

noncomputable def growth (c : ℝ) (d : ℕ) : ℝ :=
  Real.exp (c * Real.sqrt (Real.log (d : ℝ) * Real.log (Real.log (d : ℝ))))

end BinaryLower

open BinaryLower

/-- The binary lower-bound theorem of OpenAI's September 27, 2026 tree-constructions
manuscript: finite equal-length witnesses for every sufficiently large length cap. -/
theorem binary_lower_bound :
    ∃ c : ℝ, 0 < c ∧ ∃ d₀ : ℕ, ∀ d : ℕ, d₀ ≤ d →
      ∃ n : ℕ, 1 ≤ n ∧ n ≤ d ∧
        ∃ W : Finset (Word Bool n), 2 ≤ W.card ∧
          growth c d ≤ binarySetDistortion W := by
  sorry

end TreeEdit

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/BinaryEditLower.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.TreeEdit.binary_lower_bound` must keep exactly the statement shown above: same names,
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
