# openai/math challenge `BalancedRyser` (family 162)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 162 of the release, *Counterexamples to Ryser's covering and Gyarfas's tree-cover conjectures*
(Combinatorics). The family as a whole: Disproves Ryser's covering conjecture by constructing intersecting $(q+1)$-partite, $(q+1)$-uniform hypergraphs with covering number $q+1$, rather than the predicted bound $q$, for every sufficiently large prime $q$. A separate construction over extension fields also disproves Gyarfas's monochromatic tree-cover conjecture.

The challenge is `BalancedRyser`, also at `/opt/openai-math/challenges/BalancedRyser.lean`:

```lean
import Mathlib

namespace OAI

namespace Balanced
open scoped _root_.Balanced

structure PartiteHypergraph (r n : ℕ) where
  edges : Finset (Fin r → Fin n)

namespace PartiteHypergraph

variable {r n : ℕ}

abbrev Vertex (r n : ℕ) := Fin r × Fin n

def Covers (H : PartiteHypergraph r n) (C : Finset (Vertex r n)) : Prop :=
  ∀ e ∈ H.edges, ∃ i, (i, e i) ∈ C

def Intersecting (H : PartiteHypergraph r n) : Prop :=
  H.edges.Nonempty ∧ ∀ e ∈ H.edges, ∀ f ∈ H.edges, ∃ i, e i = f i

def Nonisolated (H : PartiteHypergraph r n) : Prop :=
  ∀ i v, ∃ e ∈ H.edges, e i = v

def HasCoverNumber (H : PartiteHypergraph r n) (k : ℕ) : Prop :=
  (∃ C : Finset (Vertex r n), H.Covers C ∧ C.card = k) ∧
    ∀ C : Finset (Vertex r n), H.Covers C → k ≤ C.card

end PartiteHypergraph

def BalancedCounterexample (q : ℕ) : Prop :=
  ∃ H : PartiteHypergraph (q + 1) (q + 1),
    H.Intersecting ∧ H.Nonisolated ∧ H.HasCoverNumber (q + 1)

def MainResult : Prop :=
  ∃ q₀ : ℕ, ∀ q : ℕ, q₀ ≤ q → q.Prime → BalancedCounterexample q

theorem main_result : MainResult := by
  sorry

end Balanced

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/BalancedRyser.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Balanced.main_result` must keep exactly the statement shown above: same names,
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
