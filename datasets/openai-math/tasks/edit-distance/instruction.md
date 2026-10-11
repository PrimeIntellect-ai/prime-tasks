# openai/math challenge `EditDistance` (family 099)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 099 of the release, *The sharp distortion of edit distance into $\ell_1$*
(Convex and metric geometry). The family as a whole: Determines the least distortion of embedding edit distance on words of length at most $d$ into real $\ell_1$: it is $\exp(\Theta(\sqrt{\log d\,\log\log d}))$. Insertions, deletions and substitutions have unit cost. The constants are uniform over all finite alphabets with at least two symbols, even when the alphabet grows with $d$; binary words already force the lower bound.

The challenge is `EditDistance`, also at `/opt/openai-math/challenges/EditDistance.lean`:

```lean
import Mathlib

namespace OAI

namespace EditDistortion

universe u

/-- A single unit-cost insertion, deletion, or (when enabled) substitution. -/
inductive Step (substitutions : Bool) {Alpha : Type u} : List Alpha → List Alpha → Prop
  | insert (p q : List Alpha) (a : Alpha) : Step substitutions (p ++ q) (p ++ a :: q)
  | delete (p q : List Alpha) (a : Alpha) : Step substitutions (p ++ a :: q) (p ++ q)
  | substitute (h : substitutions = true) (p q : List Alpha) (a b : Alpha) :
      Step substitutions (p ++ a :: q) (p ++ b :: q)

/-- An unrestricted script of exactly n unit edits. -/
inductive Script (substitutions : Bool) {Alpha : Type u} : ℕ → List Alpha → List Alpha → Prop
  | nil (x : List Alpha) : Script substitutions 0 x x
  | cons {n : ℕ} {x y z : List Alpha} (first : Step substitutions x y)
      (rest : Script substitutions n y z) : Script substitutions (n + 1) x z

/-- Minimum script length. Scripts always exist (delete x and insert y). -/
noncomputable def edit {Alpha : Type u} (x y : List Alpha) : ℕ :=
  sInf {n | Script true n x y}

abbrev L1 := lp (fun _ : ℕ => ℝ) 1

/-- The product of the two maximal distance ratios. -/
noncomputable def distortion {X : Type u} (ρ : X → X → ℝ) (f : X ↪ L1) : ℝ :=
  sSup {r : ℝ | ∃ x y : X, x ≠ y ∧ r = ‖f x - f y‖ / ρ x y} *
    sSup {r : ℝ | ∃ x y : X, x ≠ y ∧ r = ρ x y / ‖f x - f y‖}

/-- The infimum over injective maps to real absolutely summable sequences. -/
noncomputable def leastDistortion {X : Type u} (ρ : X → X → ℝ) : ℝ :=
  sInf (Set.range (distortion ρ))

abbrev Words (Alpha : Type u) (d : ℕ) := {x : List Alpha // x.length ≤ d}

noncomputable def E (Alpha : Type u) (d : ℕ) : ℝ :=
  leastDistortion (fun x y : Words Alpha d => (edit x.val y.val : ℝ))

noncomputable def exponentScale (c : ℝ) (d : ℕ) : ℝ :=
  Real.exp (c * Real.sqrt (Real.log (d : ℝ) * Real.log (Real.log (d : ℝ))))

/-- Supremum over finite alphabet cardinalities. -/
noncomputable def alphabetSup (d : ℕ) : ℝ :=
  sSup {r : ℝ | ∃ n : ℕ, 2 ≤ n ∧ r = E (Fin n) d}

/-- A finite nonempty subset of binary words of one common length. -/
def BinaryWitness (c : ℝ) (d : ℕ) : Prop :=
  ∃ n : ℕ, n ≤ d ∧ ∃ S : Set (List Bool), S.Finite ∧ S.Nonempty ∧
    (∀ w ∈ S, w.length = n) ∧
    exponentScale c d ≤ leastDistortion (fun x y : S => (edit x.val y.val : ℝ))

/-- Uniform two-sided bounds with common positive constants and threshold. -/
def MainClaim : Prop :=
  ∃ c C : ℝ, 0 < c ∧ 0 < C ∧ ∃ d₀ : ℕ, ∀ d : ℕ, d₀ ≤ d →
    (∀ (Alpha : Type u) [Fintype Alpha], 2 ≤ Fintype.card Alpha →
      exponentScale c d ≤ E Alpha d ∧ E Alpha d ≤ exponentScale C d) ∧
    BinaryWitness c d ∧
    exponentScale c d ≤ alphabetSup d ∧ alphabetSup d ≤ exponentScale C d

end EditDistortion

universe u

theorem edit_distance_main : EditDistortion.MainClaim.{u} := by
  sorry

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/EditDistance.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.edit_distance_main` must keep exactly the statement shown above: same names,
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
