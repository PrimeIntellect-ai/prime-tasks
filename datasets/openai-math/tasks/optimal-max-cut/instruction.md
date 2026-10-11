# openai/math challenge `OptimalMaxCut` (family 102)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 102 of the release, *The Unique Games Conjecture and optimal approximation thresholds*
(Theoretical computer science). The family as a whole: Proves Khot's Unique Games Conjecture. Independent direct reductions also establish NP-hardness, on unweighted graphs, of approximation beyond the Goemans–Williamson ratio for Max-Cut, below factor two for Vertex Cover, and within any fixed constant factor for Min-UnCut and directed feedback vertex set. These direct proofs use established PCP and Label Cover hardness results.

The challenge is `OptimalMaxCut`, also at `/opt/openai-math/challenges/OptimalMaxCut.lean`:

```lean
import Mathlib

namespace OAI

namespace MaxCutGames.BinaryFormula

structure Literal where
  name : Nat
  positive : Bool
  deriving DecidableEq

def Literal.eval (literal : Literal) (assignment : Nat → Bool) : Bool :=
  if literal.positive then assignment literal.name else !(assignment literal.name)

abbrev Clause := Vector Literal 3

def Clause.eval (clause : Clause) (assignment : Nat → Bool) : Bool :=
  (clause[0].eval assignment || clause[1].eval assignment) || clause[2].eval assignment

/-- An ordinary conjunction of three-slot clauses with sparse variable names.
Repeated names and repeated literals are permitted in every clause. -/
structure Formula where
  clauses : List Clause

def Formula.Satisfiable (F : Formula) : Prop :=
  ∃ assignment : Nat → Bool, ∀ clause ∈ F.clauses, clause.eval assignment = true

end MaxCutGames.BinaryFormula

namespace MaxCutGames.BinaryEncoding

open BinaryFormula

def bitsValue : List Bool → Nat
  | [] => 0
  | b :: bits => Nat.bit b (bitsValue bits)

/-- Prefix-free framing on the two-symbol input alphabet. -/
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

/-- Equality with the canonical digits rejects alternate padded encodings. -/
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

/-- Fuel bounds the number of clause iterations, not the size of any name. -/
def parseClauses : Nat → List Bool → Option (List Clause × List Bool)
  | 0, _ => none
  | _ + 1, false :: rest => some ([], rest)
  | fuel + 1, true :: input => do
      let (clause, input) ← parseClause input
      let (clauses, rest) ← parseClauses fuel input
      return (clause :: clauses, rest)
  | _ + 1, [] => none

def decodeFormula (input : List Bool) : Option Formula := do
  let (clauses, rest) ← parseClauses (input.length + 1) input
  if rest = [] then some ⟨clauses⟩ else none

end MaxCutGames.BinaryEncoding

namespace OptimalMaxCut

open scoped BigOperators

/-- The exact Goemans–Williamson ratio, as an infimum over -1 ≤ ρ < 1. -/
noncomputable def alphaGW : ℝ :=
  sInf ((fun ρ : ℝ => 2 * Real.arccos ρ / (Real.pi * (1 - ρ))) ''
    Set.Ico (-1 : ℝ) 1)

/-- The ordinary binary 3SAT language, including rejection of malformed words. -/
def binary3SAT (input : List Bool) : Prop :=
  ∃ formula, MaxCutGames.BinaryEncoding.decodeFormula input = some formula ∧
    formula.Satisfiable

/-- A finite simple unweighted graph with its full Boolean adjacency table. -/
structure Graph where
  vertices : ℕ
  adj : Fin vertices → Fin vertices → Bool
  symmetric : ∀ u v, adj u v = adj v u
  loopless : ∀ u, adj u u = false

/-- Each unordered distinct edge crossing the cut is counted exactly once. -/
def Graph.cutSize (G : Graph) (cut : Fin G.vertices → Bool) : ℕ :=
  ∑ u : Fin G.vertices, ∑ v : Fin G.vertices,
    if u < v ∧ G.adj u v = true ∧ cut u ≠ cut v then 1 else 0

/-- The maximum over all Boolean cuts of the finite vertex set. -/
def Graph.maxCut (G : Graph) : ℕ :=
  (Finset.univ.image G.cutSize).sup id

/-- The positive integer scale Q is part of the output. It need not equal the
number of graph edges. -/
structure ScaledGraph where
  graph : Graph
  scale : ℕ
  scale_pos : 0 < scale

/-- Canonical delimited binary vertex count and scale, followed by the full
adjacency table in lexicographic order. -/
def ScaledGraph.bits (G : ScaledGraph) : List Bool :=
  MaxCutGames.BinaryEncoding.nameBits G.graph.vertices ++
  MaxCutGames.BinaryEncoding.nameBits G.scale ++
  (List.finRange G.graph.vertices).flatMap (fun u =>
    (List.finRange G.graph.vertices).map (fun v => G.graph.adj u v))

/-- The rational gap bounds and the finite machine are fixed before the input.
The bounds compare the maximum cut divided by the positive output scale. -/
structure GapReduction (α : ℝ) where
  yesBound : ℚ
  noBound : ℚ
  yes_pos : 0 < yesBound
  no_nonneg : 0 ≤ noBound
  gap : (noBound : ℝ) < α * (yesBound : ℝ)
  construct : List Bool → ScaledGraph
  computation : Turing.TM2ComputableInPolyTime (id : List Bool → List Bool)
    ScaledGraph.bits construct
  finiteAlphabet : ∀ k, Finite (computation.tm.Γ k)
  completeness : ∀ input, binary3SAT input →
    (yesBound : ℝ) ≤ ((construct input).graph.maxCut : ℝ) / (construct input).scale
  soundness : ∀ input, ¬ binary3SAT input →
    ((construct input).graph.maxCut : ℝ) / (construct input).scale ≤ (noBound : ℝ)

def MainStatement : Prop :=
  ∀ α : ℝ, alphaGW < α → α ≤ 1 → Nonempty (GapReduction α)

end OptimalMaxCut

theorem OptimalMaxCut.main : OptimalMaxCut.MainStatement := by
  sorry

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/OptimalMaxCut.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.OptimalMaxCut.main` must keep exactly the statement shown above: same names,
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
