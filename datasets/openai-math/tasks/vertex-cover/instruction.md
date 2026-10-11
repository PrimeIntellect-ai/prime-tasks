# openai/math challenge `VertexCover` (family 102)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 102 of the release, *The Unique Games Conjecture and optimal approximation thresholds*
(Theoretical computer science). The family as a whole: Proves Khot's Unique Games Conjecture. Independent direct reductions also establish NP-hardness, on unweighted graphs, of approximation beyond the Goemans–Williamson ratio for Max-Cut, below factor two for Vertex Cover, and within any fixed constant factor for Min-UnCut and directed feedback vertex set. These direct proofs use established PCP and Label Cover hardness results.

The challenge is `VertexCover`, also at `/opt/openai-math/challenges/VertexCover.lean`:

```lean
import Mathlib

namespace OAI

namespace UniqueGames.BinaryFormula

structure Literal where
  name : Nat
  positive : Bool
  deriving DecidableEq

def Literal.eval (literal : Literal) (assignment : Nat → Bool) : Bool :=
  if literal.positive then assignment literal.name else !(assignment literal.name)

abbrev Clause := Vector Literal 3

def Clause.eval (clause : Clause) (assignment : Nat → Bool) : Bool :=
  (clause[0].eval assignment || clause[1].eval assignment) || clause[2].eval assignment

structure Formula where
  clauses : List Clause

def Formula.Satisfiable (F : Formula) : Prop :=
  ∃ assignment : Nat → Bool, ∀ clause ∈ F.clauses, clause.eval assignment = true

end UniqueGames.BinaryFormula

namespace UniqueGames.BinaryEncoding

open BinaryFormula

def bitsValue : List Bool → Nat
  | [] => 0
  | b :: bits => Nat.bit b (bitsValue bits)

def frame : List Bool → List Bool
  | [] => [false]
  | b :: bits => true :: b :: frame bits

def parseFrame : List Bool → Option (List Bool × List Bool)
  | false :: rest => some ([], rest)
  | true :: b :: rest => do
      let (bits, trailing) ← parseFrame rest
      return (b :: bits, trailing)
  | _ => none

def nameBits (name : Nat) : List Bool := frame name.bits

def parseName (input : List Bool) : Option (Nat × List Bool) := do
  let (digits, rest) ← parseFrame input
  let name := bitsValue digits
  if digits = name.bits then some (name, rest) else none

def parseLiteral : List Bool → Option (Literal × List Bool)
  | sign :: input => do
      let (name, rest) ← parseName input
      return (⟨name, sign⟩, rest)
  | [] => none

def parseClause (input : List Bool) : Option (Clause × List Bool) := do
  let (a, input) ← parseLiteral input
  let (b, input) ← parseLiteral input
  let (c, rest) ← parseLiteral input
  return (#v[a, b, c], rest)

def parseClauses : Nat → List Bool → Option (List Clause × List Bool)
  | 0, _ => none
  | _fuel + 1, false :: rest => some ([], rest)
  | fuel + 1, true :: input => do
      let (clause, input) ← parseClause input
      let (clauses, rest) ← parseClauses fuel input
      return (clause :: clauses, rest)
  | _ + 1, [] => none

def decodeFormula (input : List Bool) : Option Formula := do
  let (clauses, rest) ← parseClauses (input.length + 1) input
  if rest = [] then some ⟨clauses⟩ else none

end UniqueGames.BinaryEncoding

namespace VertexCover

def ThreeSAT (input : List Bool) : Prop :=
  ∃ formula, UniqueGames.BinaryEncoding.decodeFormula input = some formula ∧
    formula.Satisfiable

structure ExplicitGraph where
  n : ℕ
  edges : List (Fin n × Fin n)
  increasing : ∀ e ∈ edges, e.1 < e.2
  nodup : edges.Nodup

namespace ExplicitGraph

def Cover (G : ExplicitGraph) (S : Finset (Fin G.n)) : Prop :=
  ∀ e ∈ G.edges, e.1 ∈ S ∨ e.2 ∈ S

instance (G : ExplicitGraph) (S : Finset (Fin G.n)) : Decidable (G.Cover S) :=
  inferInstanceAs (Decidable (∀ e ∈ G.edges, e.1 ∈ S ∨ e.2 ∈ S))

noncomputable def coverNumber (G : ExplicitGraph) : ℕ :=
  Nat.find (show ∃ k : ℕ, ∃ S : Finset (Fin G.n), G.Cover S ∧ S.card = k from
    ⟨G.n, Finset.univ, by simp [Cover], by simp⟩)

def bits (G : ExplicitGraph) : List Bool :=
  let names := [G.n] ++ List.range G.n ++ [G.edges.length] ++
    G.edges.flatMap (fun e => [e.1.val, e.2.val])
  names.flatMap UniqueGames.BinaryEncoding.nameBits

end ExplicitGraph

def FiniteAlphabet (M : Turing.FinTM2) : Prop := ∀ k, Finite (M.Γ k)

structure GapReduction (m : ℕ) where
  construct : List Bool → ExplicitGraph
  computation : Turing.TM2ComputableInPolyTime (id : List Bool → List Bool)
    ExplicitGraph.bits construct
  finiteAlphabet : FiniteAlphabet computation.tm
  completeness : ∀ input, ThreeSAT input →
    ((construct input).coverNumber : ℝ) <
      (1 / 2 + 1 / (m : ℝ)) * (construct input).n
  soundness : ∀ input, ¬ ThreeSAT input →
    (1 - 1 / (m : ℝ)) * (construct input).n <
      ((construct input).coverNumber : ℝ)

def natListBits (L : List ℕ) : List Bool :=
  (L.length :: L).flatMap UniqueGames.BinaryEncoding.nameBits

structure Approximation (α : ℝ) where
  run : ExplicitGraph → List ℕ
  computation : Turing.TM2ComputableInPolyTime ExplicitGraph.bits natListBits run
  finiteAlphabet : FiniteAlphabet computation.tm
  nodup : ∀ G, (run G).Nodup
  vertices : ∀ G, ∀ v ∈ run G, v < G.n
  covers : ∀ G, ∀ e ∈ G.edges, e.1.val ∈ run G ∨ e.2.val ∈ run G
  quality : ∀ G, ((run G).length : ℝ) ≤ α * (G.coverNumber : ℝ)

structure ThreeSATDecision where
  run : List Bool → Bool
  computation : Turing.TM2ComputableInPolyTime (id : List Bool → List Bool)
    (fun b : Bool => [b]) run
  finiteAlphabet : FiniteAlphabet computation.tm
  correct : ∀ input, run input = true ↔ ThreeSAT input

theorem explicit_cover_gap (m : ℕ) (hm : 4 ≤ m) : Nonempty (GapReduction m) := by
  sorry

theorem every_fixed_factor_below_two (α : ℝ) (hα : 1 ≤ α) (hα2 : α < 2)
    (algorithm : Approximation α) : Nonempty ThreeSATDecision := by
  sorry

end VertexCover

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/VertexCover.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorems `OAI.VertexCover.explicit_cover_gap`, `OAI.VertexCover.every_fixed_factor_below_two` must keep exactly the statement shown above: same names,
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
