# openai/math challenge `SnakyConditional` (family 187)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 187 of the release, *Snaky in 21 Maker moves*
(Combinatorics). The family as a whole: Settles the Snaky achievement problem: Maker can force the six-cell Snaky shape within 21 of its own moves on the initially empty infinite square board. Maker moves first, each player claims one free cell per turn, and translations, rotations and reflections count as wins.

The challenge is `SnakyConditional`, also at `/opt/openai-math/challenges/SnakyConditional.lean`:

```lean
import Mathlib

namespace OAI.SnakyConditional

abbrev Cell := ℤ × ℤ
def snaky : Finset Cell := {(0, 0), (1, 0), (2, 0), (3, 0), (3, 1), (4, 1)}
def orient (r : Fin 8) (p : Cell) : Cell :=
  match r.val with
  | 0 => (p.1, p.2)
  | 1 => (p.2, p.1)
  | 2 => (p.1, -p.2)
  | 3 => (-p.2, p.1)
  | 4 => (-p.1, p.2)
  | 5 => (p.2, -p.1)
  | 6 => (-p.1, -p.2)
  | _ => (-p.2, -p.1)
def placement (r : Fin 8) (t p : Cell) : Cell := orient r p + t
def HasSnaky (M : Finset Cell) : Prop :=
  ∃ (r : Fin 8) (t : Cell), snaky.image (placement r t) ⊆ M

namespace OrdinaryStrategy

variable {α : Type*} [DecidableEq α]

abbrev Policy (α : Type*) := ℕ → Finset α → Finset α → α
def playState (σ : Policy α) (N : ℕ) (β : ℕ → α) (M₀ B₀ : Finset α) :
    ℕ → Finset α × Finset α
  | 0 => (M₀, B₀)
  | k + 1 =>
      let state := playState σ N β M₀ B₀ k
      (insert (σ (N - k) state.1 state.2) state.1, insert (β k) state.2)
def makerAt (σ : Policy α) (N : ℕ) (β : ℕ → α) (M₀ B₀ : Finset α) (k : ℕ) : α :=
  let state := playState σ N β M₀ B₀ k
  σ (N - k) state.1 state.2
def LegalRepliesBeforeFinal (σ : Policy α) (N : ℕ) (β : ℕ → α)
    (M₀ B₀ : Finset α) : Prop :=
  ∀ k, k + 1 < N →
    β k ∉ insert (makerAt σ N β M₀ B₀ k) (playState σ N β M₀ B₀ k).1 ∧
    β k ∉ (playState σ N β M₀ B₀ k).2
end OrdinaryStrategy

open OrdinaryStrategy

theorem snaky_winning_strategy_with_legal_states :
    ∃ σ : Policy Cell,
      (∀ r M B, σ r M B ∉ M ∧ σ r M B ∉ B) ∧
      ∀ β : ℕ → Cell, LegalRepliesBeforeFinal σ 35 β ∅ ∅ →
        HasSnaky (playState σ 35 β ∅ ∅ 35).1 ∧
        (playState σ 35 β ∅ ∅ 35).1.card = 35 ∧
        Disjoint (playState σ 35 β ∅ ∅ 35).1 (playState σ 35 β ∅ ∅ 34).2 ∧
        ∀ k, k < 35 →
          Disjoint (playState σ 35 β ∅ ∅ k).1 (playState σ 35 β ∅ ∅ k).2 ∧
          (playState σ 35 β ∅ ∅ k).2.card = k := by
  sorry

end OAI.SnakyConditional
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/SnakyConditional.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.SnakyConditional.snaky_winning_strategy_with_legal_states` must keep exactly the statement shown above: same names,
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
