# openai/math challenge `FiniteCongruenceGraph` (family 206)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 206 of the release, *Finite lattice representation: counterexamples and undecidability*
(Algebra). The family as a whole: Some finite lattices are not congruence lattices of any finite algebra, answering the finite lattice representation problem negatively. Moreover, no algorithm decides whether a finite lattice has such a representation, or whether it is a full subgroup interval of a finite group.

The challenge is `FiniteCongruenceGraph`, also at `/opt/openai-math/challenges/FiniteCongruenceGraph.lean`:

```lean
import Mathlib.Data.Finset.Lattice.Fold
import Mathlib.Data.Fintype.Defs
import Mathlib.Data.Setoid.Basic
import Mathlib.Order.Hom.Basic

namespace OAI

namespace FiniteCongruence

structure Algebra (Carrier : Type) where
  numOps : ℕ
  arity : Fin numOps → ℕ
  op : (index : Fin numOps) → (Fin (arity index) → Carrier) → Carrier

def Compatible {Carrier : Type} (alg : Algebra Carrier) (rel : Setoid Carrier) : Prop :=
  ∀ (index : Fin alg.numOps) (left right : Fin (alg.arity index) → Carrier),
    (∀ coord, rel (left coord) (right coord)) → rel (alg.op index left) (alg.op index right)

def Congruence {Carrier : Type} (alg : Algebra Carrier) :=
  {rel : Setoid Carrier // Compatible alg rel}

instance {Carrier : Type} (alg : Algebra Carrier) : PartialOrder (Congruence alg) :=
  inferInstanceAs (PartialOrder {rel : Setoid Carrier // Compatible alg rel})

def Representable (Lat : Type) [PartialOrder Lat] : Prop :=
  ∃ size : ℕ, 0 < size ∧ ∃ alg : Algebra (Fin size), Nonempty (Lat ≃o Congruence alg)

def Admissible {Lat Carrier : Type} [LE Lat] (color : Carrier → Carrier → Lat)
    (placement : Carrier → Carrier) : Prop :=
  ∀ left right, color (placement left) (placement right) ≤ color left right

def Marked {Lat Carrier : Type} [LE Lat] (color : Carrier → Carrier → Lat)
    (seeds : Finset (Carrier × Carrier)) (left right : Carrier) : Prop :=
  ∃ placement : Carrier → Carrier, Admissible color placement ∧
    ∃ edge ∈ seeds, placement edge.1 = left ∧ placement edge.2 = right

def Connected {Lat Carrier : Type} [LE Lat] (color : Carrier → Carrier → Lat)
    (seeds : Finset (Carrier × Carrier)) (left right : Carrier) : Prop :=
  Relation.EqvGen (Marked color seeds) left right

def IsGraphWitness {Lat Carrier : Type} [Lattice Lat] [OrderBot Lat]
    (color : Carrier → Carrier → Lat) : Prop :=
  (∀ left right, color left right = color right left) ∧
  (∀ left right, color left right = ⊥ ↔ left = right) ∧
  (∀ left right middle, color left right ≤ color left middle ⊔ color middle right) ∧
  (∀ lower upper : Lat, ¬ lower ≤ upper →
    ∃ left right, color left right ≤ lower ∧ ¬ color left right ≤ upper) ∧
  (∀ seeds : Finset (Carrier × Carrier), seeds.Nonempty → ∀ left right,
    color left right ≤ seeds.sup (fun edge => color edge.1 edge.2) →
      Connected color seeds left right)

def HasGraphWitness (Lat : Type) [Lattice Lat] [OrderBot Lat] : Prop :=
  ∃ size : ℕ, 0 < size ∧ ∃ color : Fin size → Fin size → Lat, IsGraphWitness color

/-- A finite lattice is representable as the full congruence lattice of a nonempty finite
algebra exactly when it has a finite nonempty colored-graph witness. -/
theorem graph_criterion (Lat : Type) [Fintype Lat] [Lattice Lat] [OrderBot Lat] :
    Representable Lat ↔ HasGraphWitness Lat := by
  sorry

end FiniteCongruence

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/FiniteCongruenceGraph.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.FiniteCongruence.graph_criterion` must keep exactly the statement shown above: same names,
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
