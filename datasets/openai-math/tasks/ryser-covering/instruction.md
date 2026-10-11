# openai/math challenge `RyserCovering` (family 162)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 162 of the release, *Counterexamples to Ryser's covering and Gyarfas's tree-cover conjectures*
(Combinatorics). The family as a whole: Disproves Ryser's covering conjecture by constructing intersecting $(q+1)$-partite, $(q+1)$-uniform hypergraphs with covering number $q+1$, rather than the predicted bound $q$, for every sufficiently large prime $q$. A separate construction over extension fields also disproves Gyarfas's monochromatic tree-cover conjecture.

The challenge is `RyserCovering`, also at `/opt/openai-math/challenges/RyserCovering.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

namespace RyserCoveringCounterexample

abbrev Hypergraph (V : Type*) := Finset (Finset V)

section

variable {V : Type*} [DecidableEq V]

def IsCover (H : Hypergraph V) (C : Finset V) : Prop :=
  ∀ e ∈ H, ∃ v ∈ C, v ∈ e

def Intersecting (H : Hypergraph V) : Prop :=
  ∀ e ∈ H, ∀ f ∈ H, e ≠ f → (e ∩ f).Nonempty

attribute [-instance] instDecidablePairwiseCoeFinsetOfDecidableEqOfDecidableRel in
def matchings (H : Hypergraph V) : Finset (Hypergraph V) := by
  classical
  exact H.powerset.filter fun M => (M : Set (Finset V)).Pairwise Disjoint

def matchingNumber (H : Hypergraph V) : ℕ := (matchings H).sup Finset.card

def coverCardinalities (H : Hypergraph V) : Set ℕ :=
  {n | ∃ C : Finset V, IsCover H C ∧ C.card = n}

def coverNumber (H : Hypergraph V) : ℕ := sInf (coverCardinalities H)

def PartiteUniform {I : Type*} (part : V → I) (H : Hypergraph V) : Prop :=
  ∀ e ∈ H, ∀ i : I, ∃! v : V, v ∈ e ∧ part v = i

def RPartiteUniform (r : ℕ) (H : Hypergraph V) : Prop :=
  ∃ part : V → Fin r, PartiteUniform part H

end

def CounterexampleRank (r : ℕ) : Prop :=
  ∃ (V : Type) (fin : Fintype V) (dec : DecidableEq V),
    letI : Fintype V := fin
    letI : DecidableEq V := dec
    ∃ H : Hypergraph V,
      0 < r ∧ H.Nonempty ∧ RPartiteUniform r H ∧ Intersecting H ∧
        (∃ C : Finset V, IsCover H C) ∧ matchingNumber H = 1 ∧ coverNumber H = r

theorem exists_prime_eventually_counterexampleRank :
    ∃ p : ℕ, p.Prime ∧ 5 < p ∧ p % 3 = 2 ∧
      ∃ N : ℕ, ∀ n : ℕ, N ≤ n → n.Prime → 2 < n →
        CounterexampleRank (p ^ n + 1) := by
  sorry

end RyserCoveringCounterexample

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/RyserCovering.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.RyserCoveringCounterexample.exists_prime_eventually_counterexampleRank` must keep exactly the statement shown above: same names,
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
