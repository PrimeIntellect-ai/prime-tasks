# openai/math challenge `RyserOddExtensions` (family 162)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 162 of the release, *Counterexamples to Ryser's covering and Gyarfas's tree-cover conjectures*
(Combinatorics). The family as a whole: Disproves Ryser's covering conjecture by constructing intersecting $(q+1)$-partite, $(q+1)$-uniform hypergraphs with covering number $q+1$, rather than the predicted bound $q$, for every sufficiently large prime $q$. A separate construction over extension fields also disproves Gyarfas's monochromatic tree-cover conjecture.

The challenge is `RyserOddExtensions`, also at `/opt/openai-math/challenges/RyserOddExtensions.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

namespace RyserCoveringCounterexample

abbrev Hypergraph (Vertex : Type*) := Finset (Finset Vertex)

variable {Vertex : Type*} [DecidableEq Vertex]

def IsCover (hypergraph : Hypergraph Vertex) (cover : Finset Vertex) : Prop :=
  ∀ edge ∈ hypergraph, ∃ vertex ∈ cover, vertex ∈ edge

def Intersecting (hypergraph : Hypergraph Vertex) : Prop :=
  ∀ edge ∈ hypergraph, ∀ other ∈ hypergraph, edge ≠ other → (edge ∩ other).Nonempty

attribute [-instance] instDecidablePairwiseCoeFinsetOfDecidableEqOfDecidableRel in
def matchings (hypergraph : Hypergraph Vertex) : Finset (Hypergraph Vertex) := by
  classical
  exact hypergraph.powerset.filter fun matching =>
    (matching : Set (Finset Vertex)).Pairwise Disjoint

def matchingNumber (hypergraph : Hypergraph Vertex) : ℕ :=
  (matchings hypergraph).sup Finset.card

def coverCardinalities (hypergraph : Hypergraph Vertex) : Set ℕ :=
  {size | ∃ cover : Finset Vertex, IsCover hypergraph cover ∧ cover.card = size}

def coverNumber (hypergraph : Hypergraph Vertex) : ℕ := sInf (coverCardinalities hypergraph)

def Uniform (rank : ℕ) (hypergraph : Hypergraph Vertex) : Prop :=
  ∀ edge ∈ hypergraph, edge.card = rank

def PartiteUniform {Index : Type*} (part : Vertex → Index)
    (hypergraph : Hypergraph Vertex) : Prop :=
  ∀ edge ∈ hypergraph, ∀ index : Index,
    ∃! vertex : Vertex, vertex ∈ edge ∧ part vertex = index

def RPartiteUniform (rank : ℕ) (hypergraph : Hypergraph Vertex) : Prop :=
  ∃ part : Vertex → Fin rank, PartiteUniform part hypergraph

end RyserCoveringCounterexample

namespace RyserOdd

open RyserCoveringCounterexample

def Specification.ExplicitFailureAt (rank : ℕ) : Prop :=
  ∃ (Vertex : Type) (finiteVertices : Fintype Vertex) (decidableVertices : DecidableEq Vertex),
    letI : Fintype Vertex := finiteVertices
    letI : DecidableEq Vertex := decidableVertices
    ∃ hypergraph : RyserCoveringCounterexample.Hypergraph Vertex,
      0 < rank ∧ hypergraph.Nonempty ∧ RPartiteUniform rank hypergraph ∧
        Uniform rank hypergraph ∧ Intersecting hypergraph ∧
        (∃ cover : Finset Vertex, IsCover hypergraph cover) ∧
        matchingNumber hypergraph = 1 ∧ coverNumber hypergraph = rank ∧
        (rank - 1) * matchingNumber hypergraph < coverNumber hypergraph

theorem eventualOddFailures_and_infinite :
    (∃ primeThreshold : ℕ, ∀ prime : ℕ, primeThreshold ≤ prime →
      prime.Prime → prime % 3 = 2 →
      ∃ degreeThreshold : ℕ, 3 ≤ degreeThreshold ∧
        ∀ degree : ℕ, degreeThreshold ≤ degree → Odd degree →
          Specification.ExplicitFailureAt (prime ^ degree + 1)) ∧
    Set.Infinite {rank : ℕ | Specification.ExplicitFailureAt rank} := by
  sorry

end RyserOdd

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/RyserOddExtensions.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.RyserOdd.eventualOddFailures_and_infinite` must keep exactly the statement shown above: same names,
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
