# openai/math challenge `TwoWayDeterminization` (family 129)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 129 of the release, *Exponential state costs for two-way automata*
(Theoretical computer science). The family as a whole: Proves exponential lower bounds both for complementing two-way nondeterministic finite automata and for simulating one-way nondeterministic automata by two-way deterministic ones. The latter resolves the Sakoda–Sipser state-succinctness conjecture over growing finite alphabets; both results rule out polynomial state bounds independent of alphabet size.

The challenge is `TwoWayDeterminization`, also at `/opt/openai-math/challenges/TwoWayDeterminization.lean`:

```lean
import Mathlib

namespace OAI

namespace TwoWayComplementation

open scoped SetRel

/-- Reflexive transitive closure, including the empty path. -/
def relStar {α : Type*} (R : SetRel α α) : SetRel α α :=
  {(x, y) | Relation.ReflTransGen (fun a b => (a, b) ∈ R) x y}

/-- A read-only 2NFA. The two endmarkers are `Sum.inl 0` and `Sum.inl 1`.
    Move codes 0, 1, 2 mean left, stay, right. -/
structure TwoNFA (Sigma Q : Type*) where
  /-- The state in which the machine starts on the left endmarker. -/
  initial : Q
  /-- States whose occurrence on a finite run constitutes acceptance. -/
  accepting : Set Q
  /-- Allowed next-state and move pairs, determined by the state and scanned symbol. -/
  transition : Q → (Fin 2 ⊕ Sigma) → Set (Q × Fin 3)

/-- Tape lookup includes two distinct endmarkers, even on empty input. -/
def tapeSymbol {Sigma : Type*} (w : List Sigma) (p : Fin (w.length + 2)) : Fin 2 ⊕ Sigma :=
  if hleft : p.val = 0 then .inl 0
  else if hright : p.val = w.length + 1 then .inl 1
  else .inr (w[p.val - 1]'(by omega))

namespace TwoNFA

/-- One legal step: both head positions stay within the marked input. -/
def step {Sigma Q : Type*} (A : TwoNFA Sigma Q) (w : List Sigma) :
    SetRel (Q × Fin (w.length + 2)) (Q × Fin (w.length + 2)) :=
  {(c, d) | ∃ move : Fin 3,
    (d.1, move) ∈ A.transition c.1 (tapeSymbol w c.2) ∧
    (d.2.val : ℤ) = (c.2.val : ℤ) + (move.val : ℤ) - 1}

/-- Existential finite-run acceptance, allowing a run of length zero. -/
def language {Sigma Q : Type*} (A : TwoNFA Sigma Q) : Set (List Sigma) :=
  {w | ∃ c, c.1 ∈ A.accepting ∧
    ((A.initial, ⟨0, by omega⟩), c) ∈ relStar (A.step w)}

end TwoNFA

/-- At most one next-state/move pair at every state and scanned symbol. -/
def TwoNFA.Deterministic {Sigma Q : Type*} (A : TwoNFA Sigma Q) : Prop :=
  ∀ q symbol, (A.transition q symbol).Subsingleton

/-- Relation product for an input word; the empty product is the identity. -/
def relationProduct {H : Type*} (w : List (SetRel H H)) : SetRel H H :=
  w.foldr SetRel.comp SetRel.id

/-- The source language consists of the words with nonempty relation product. -/
def sourceLanguage (H : Type*) : Set (List (SetRel H H)) :=
  {w | (relationProduct w).Nonempty}

/-- Both lower bounds hold for the same n-state liveness witness. -/
theorem explicit_family_main (n : ℕ) (hn : 4 ≤ n) :
    ∃ A : TwoNFA (SetRel (Fin (n - 2)) (Fin (n - 2))) (Fin n),
      A.language = sourceLanguage (Fin (n - 2)) ∧
      (∀ (Q : Type*) [Fintype Q],
        ∀ B : TwoNFA (SetRel (Fin (n - 2)) (Fin (n - 2))) Q,
        B.language = A.languageᶜ →
          (1 / 2 : ℝ) * 2 ^ ((n - 4) / 127) - 1 ≤ (Fintype.card Q : ℝ)) ∧
      (131 ≤ n → ∀ (Q : Type*) [Fintype Q],
        ∀ D : TwoNFA (SetRel (Fin (n - 2)) (Fin (n - 2))) Q,
        D.Deterministic → D.language = A.language →
          (1 / 2 : ℝ) * 2 ^ ((n - 4) / 127) ≤ (Fintype.card Q : ℝ)) := by
  sorry

end TwoWayComplementation

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/TwoWayDeterminization.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.TwoWayComplementation.explicit_family_main` must keep exactly the statement shown above: same names,
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
