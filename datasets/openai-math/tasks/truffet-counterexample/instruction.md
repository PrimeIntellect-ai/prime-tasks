# openai/math challenge `TruffetCounterexample` (family 104)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 104 of the release, *Quasipolynomial algorithms for mean-payoff, stochastic and parity games*
(Theoretical computer science). The family as a whole: Gives deterministic algorithms using $2^{O((\log(L+2))^2)}$ bit operations, for complete binary input length $L$, for ordinary mean-payoff games and two separate extensions. They compute exact values and optimal positional strategies in ordinary games, the nonnegative expectation-of-liminf value set in turn-based stochastic games, and the winning set for nonnegative liminf mean payoff conjoined with parity. Signed rewards, rational chance probabilities, and parity priorities are unrestricted and binary-encoded.

The challenge is `TruffetCounterexample`, also at `/opt/openai-math/challenges/TruffetCounterexample.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
namespace TruffetV4Counterexample

abbrev Coeff := WithBot ℝ

abbrev Form := Fin 3 → Coeff

abbrev Var := Fin 2

abbrev RowIndex := Fin 2

def column (j : Var) : Fin 3 := ⟨j.val, Nat.lt_trans j.isLt (by decide)⟩

def nullForm : Form := fun _ => ⊥

structure Row where
  lhs : Form
  rhs : Form

structure State where
  rows : RowIndex → Row
  cost : Form
  remaining : Var → Prop

def wellFormed (s : State) : Prop := ∀ j, ¬ s.remaining j →
  s.cost (column j) = ⊥ ∧ ∀ i,
    (s.rows i).lhs (column j) = ⊥ ∧ (s.rows i).rhs (column j) = ⊥

def eval (f : Form) (w : Fin 3 → ℝ) : Coeff :=
  max (f 0 + (w 0 : Coeff)) (max (f 1 + (w 1 : Coeff)) (f 2 + (w 2 : Coeff)))

def feasible (s : State) (w : Fin 3 → ℝ) : Prop :=
  ∀ i, eval (s.rows i).rhs w ≤ eval (s.rows i).lhs w

def lower (s : State) (i : RowIndex) (j : Var) : Prop :=
  (s.rows i).lhs (column j) ≠ ⊥ ∧
    (s.rows i).rhs (column j) < (s.rows i).lhs (column j)

def upper (s : State) (i : RowIndex) (j : Var) : Prop :=
  (s.rows i).rhs (column j) ≠ ⊥ ∧
    (s.rows i).lhs (column j) < (s.rows i).rhs (column j)

def dominating (s : State) (j : Var) : Prop :=
  s.remaining j ∧ (∃ i, lower s i j) ∧ ∃ i, upper s i j

def eligible (s : State) (i : RowIndex) (j : Var) : Prop :=
  s.remaining j ∧ lower s i j ∧ ((∃ k, dominating s k) → dominating s j)

def bounded (s : State) : Prop :=
  ∀ j, s.remaining j → (∃ i, lower s i j) ∨ ∃ i, upper s i j

def stop (s : State) : Prop := ∀ i, (s.rows i).rhs 2 ≤ (s.rows i).lhs 2

def switch (s : State) : Prop :=
  (∀ j, s.remaining j → s.cost (column j) = ⊥) ∧ ¬ stop s ∧
  (∃ j, s.remaining j) ∧
  (¬ ∃ i j, s.remaining j ∧ lower s i j) ∧
  ∃ i j, s.remaining j ∧ upper s i j

def failure (s : State) : Prop := ¬ stop s ∧
  ((¬ ∃ j, s.remaining j) ∨
   ((¬ ∃ i j, s.remaining j ∧ lower s i j) ∧
    (¬ ∃ i j, s.remaining j ∧ upper s i j)))

def lowerForm (s : State) (i : RowIndex) (j : Var) : Form := fun k =>
  if k = column j then ⊥ else
    (s.rows i).rhs k + ((-WithBot.unbotD 0 ((s.rows i).lhs (column j)) : ℝ) : Coeff)

def substitute (f : Form) (j : Var) (g : Form) : Form := fun k =>
  if k = column j then ⊥ else max (f k) (f (column j) + g k)

def cleanup (r : Row) : Row := by
  classical
  exact if ∀ k, r.rhs k ≤ r.lhs k then ⟨nullForm, nullForm⟩ else r

def advance (s : State) (i : RowIndex) (j : Var) : State where
  rows := fun r => cleanup ⟨substitute (s.rows r).lhs j (lowerForm s i j),
    substitute (s.rows r).rhs j (lowerForm s i j)⟩
  cost := substitute s.cost j (lowerForm s i j)
  remaining := fun k => s.remaining k ∧ k ≠ j

def ForcedSingletonStep (s s' : State) (i : RowIndex) (j : Var) : Prop :=
  wellFormed s ∧ wellFormed s' ∧
  bounded s ∧ ¬ stop s ∧ ¬ switch s ∧ ¬ failure s ∧
  (∀ r k, eligible s r k ↔ r = i ∧ k = j) ∧
  (∃ k, (substitute s.cost j (lowerForm s i j)) k ≠ ⊥) ∧
  s' = advance s i j

def initial : State where
  rows := ![⟨![(0 : Coeff), 0, ⊥], ![⊥, ⊥, (0 : Coeff)]⟩,
    ⟨![(0 : Coeff), ⊥, ⊥], ![⊥, (1 : Coeff), ((-2 : ℝ) : Coeff)]⟩]
  cost := ![(0 : Coeff), ⊥, ⊥]
  remaining := fun _ => True

def middle : State where
  rows := ![⟨nullForm, nullForm⟩,
    ⟨![(0 : Coeff), ⊥, ⊥], ![⊥, ⊥, (1 : Coeff)]⟩]
  cost := ![(0 : Coeff), ⊥, ⊥]
  remaining := fun j => j = 0

def finalState : State where
  rows := fun _ => ⟨nullForm, nullForm⟩
  cost := ![⊥, ⊥, (1 : Coeff)]
  remaining := fun _ => False

def crossRowRestriction (s : State) : Prop :=
  ∀ i r : RowIndex, i ≠ r → ∀ α : ℝ, ∃ w : Fin 3 → ℝ,
    eval (s.rows i).lhs w < (α : Coeff) + eval (s.rows r).rhs w

def output : Fin 3 → ℝ := ![1, 0, 0]

def better : Fin 3 → ℝ := ![0, -1, 0]

theorem finite_execution_not_optimal :
    crossRowRestriction initial ∧
    ForcedSingletonStep initial middle 0 1 ∧
    ForcedSingletonStep middle finalState 1 0 ∧
    (¬ ∃ j, finalState.remaining j) ∧ stop finalState ∧
    feasible initial output ∧ feasible initial better ∧
    output 2 = 0 ∧ better 2 = 0 ∧
    (output 1 : Coeff) = eval (lowerForm initial 0 1) output ∧
    (output 0 : Coeff) = eval (lowerForm middle 1 0) output ∧
    eval initial.cost output = eval finalState.cost output ∧
    eval initial.cost better < eval finalState.cost output := by
  sorry

end TruffetV4Counterexample
end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/TruffetCounterexample.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.TruffetV4Counterexample.finite_execution_not_optimal` must keep exactly the statement shown above: same names,
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
