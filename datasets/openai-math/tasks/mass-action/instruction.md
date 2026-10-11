# openai/math challenge `MassAction` (family 149)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 149 of the release, *Permanence for weakly reversible reaction networks*
(Dynamical systems and ergodic theory). The family as a whole: Proves the permanence conjecture for every finite weakly reversible mass-action system with fixed positive rate constants. Every positive stoichiometric compatibility class, even an unbounded one, has a common compact convex forward-invariant absorbing set. All positive trajectories in that class therefore eventually share positive lower and finite upper concentration bounds.

The challenge is `MassAction`, also at `/opt/openai-math/challenges/MassAction.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

namespace Problem326

structure ReactionNetwork (d : ℕ) where
  complexes : Finset (Fin d → ℕ)
  reactions : Finset ((Fin d → ℕ) × (Fin d → ℕ))
  source_mem : ∀ e ∈ reactions, e.1 ∈ complexes
  target_mem : ∀ e ∈ reactions, e.2 ∈ complexes
  source_ne_target : ∀ e ∈ reactions, e.1 ≠ e.2

abbrev Reaction {d : ℕ} (N : ReactionNetwork d) :=
  {e : (Fin d → ℕ) × (Fin d → ℕ) // e ∈ N.reactions}

def HasReaction {d : ℕ} (N : ReactionNetwork d)
    (y z : Fin d → ℕ) : Prop :=
  (y, z) ∈ N.reactions

def WeaklyReversible {d : ℕ} (N : ReactionNetwork d) : Prop :=
  ∀ e : Reaction N,
    Relation.TransGen (HasReaction N) e.val.2 e.val.1

def monomial {d : ℕ} (x : Fin d → ℝ) (y : Fin d → ℕ) : ℝ :=
  Finset.univ.prod (fun i => x i ^ y i)

def massAction {d : ℕ} (N : ReactionNetwork d)
    (κ : Reaction N → ℝ) (x : Fin d → ℝ) : Fin d → ℝ :=
  fun i => Finset.univ.sum (fun e : Reaction N =>
    κ e * monomial x e.val.1 *
      ((e.val.2 i : ℝ) - (e.val.1 i : ℝ)))

def PositiveState {d : ℕ} (x : Fin d → ℝ) : Prop :=
  ∀ i, 0 < x i

def IsGlobalForwardSolution {d : ℕ} (N : ReactionNetwork d)
    (κ : Reaction N → ℝ) (x0 : Fin d → ℝ)
    (x : ℝ → (Fin d → ℝ)) : Prop :=
  x 0 = x0 ∧
    ∀ t : ℝ, 0 ≤ t →
      HasDerivAt x (massAction N κ (x t)) t

theorem global_bounded_persistent_solution :
    ∀ (d : ℕ) (N : ReactionNetwork d) (κ : Reaction N → ℝ),
      0 < d → WeaklyReversible N → (∀ e, 0 < κ e) →
      ∀ x0 : Fin d → ℝ, PositiveState x0 →
      ∃ ε : ℝ, 0 < ε ∧ ε < 1 ∧
        (∃ x : ℝ → (Fin d → ℝ), IsGlobalForwardSolution N κ x0 x) ∧
        ∀ x : ℝ → (Fin d → ℝ), IsGlobalForwardSolution N κ x0 x →
        ∀ t : ℝ, 0 ≤ t → ∀ i : Fin d, ε ≤ x t i ∧ x t i ≤ ε⁻¹ := by
  sorry

end Problem326

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/MassAction.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Problem326.global_bounded_persistent_solution` must keep exactly the statement shown above: same names,
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
