# openai/math challenge `IndependentSets` (family 106)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 106 of the release, *Hardness of coloring three-colorable graphs*
(Theoretical computer science). The family as a whole: It is NP-hard to color a three-colorable graph using any fixed number $c\ge3$ of colors. More strongly, for every fixed $0<\delta<1/3$, a deterministic polynomial-time reduction from $3$SAT produces simple unweighted graphs that are three-colorable in the satisfiable case and have no independent set of size $\delta n$ otherwise, where $n$ is the number of vertices.

The challenge is `IndependentSets`, also at `/opt/openai-math/challenges/IndependentSets.lean`:

```lean
import Mathlib

namespace OAI

namespace LargeIndependentSets

structure Literal where
  name : ℕ
  positive : Bool
  deriving DecidableEq

structure Formula where
  clauses : List (List Literal)
  width : ∀ C ∈ clauses, C.length ≤ 3

def Formula.Satisfiable (φ : Formula) : Prop :=
  ∃ assignment : ℕ → Bool, ∀ C ∈ φ.clauses,
    ∃ l ∈ C, assignment l.name = l.positive

/-- Binary framing: `true,b` for a payload bit and `false` as terminator. -/
def frame : List Bool → List Bool
  | [] => [false]
  | b :: bs => true :: b :: frame bs

def nameBits (n : ℕ) : List Bool := frame n.bits

def literalBits (l : Literal) : List Bool := l.positive :: nameBits l.name

def clauseBits (C : List Literal) : List Bool :=
  nameBits C.length ++ C.flatMap literalBits

def formulaBits (φ : Formula) : List Bool :=
  nameBits φ.clauses.length ++ φ.clauses.flatMap clauseBits

/-- A nonempty, finite, simple, undirected, unweighted graph. -/
structure Graph where
  vertices : ℕ
  nonempty : 0 < vertices
  adj : Fin vertices → Fin vertices → Bool
  symm : ∀ u v, adj u v = adj v u
  loopless : ∀ u, adj u u = false

def Graph.Independent (G : Graph) (S : Finset (Fin G.vertices)) : Prop :=
  ∀ u ∈ S, ∀ v ∈ S, u ≠ v → G.adj u v = false

instance (G : Graph) (S : Finset (Fin G.vertices)) : Decidable (G.Independent S) :=
  inferInstanceAs (Decidable (∀ u ∈ S, ∀ v ∈ S, u ≠ v → G.adj u v = false))

def Graph.independenceNumber (G : Graph) : ℕ :=
  ((Finset.univ : Finset (Fin G.vertices)).powerset.filter G.Independent).sup Finset.card

def Graph.ThreeColorable (G : Graph) : Prop :=
  ∃ color : Fin G.vertices → Fin 3,
    ∀ u v, G.adj u v = true → color u ≠ color v

/-- Full explicit adjacency matrix, row-major, with binary vertex count. -/
def graphBits (G : Graph) : List Bool :=
  nameBits G.vertices ++ (List.finRange G.vertices).flatMap
    (fun u => (List.finRange G.vertices).map (G.adj u))

open scoped Classical
noncomputable section

/-- Polynomial-time graph reduction with a real independence-ratio threshold. -/
structure RealGraphReduction (δ : ℝ) where
  reduce : List Bool → Graph
  computation : Turing.TM2ComputableInPolyTime (id : List Bool → List Bool) graphBits reduce
  finiteAlphabets : ∀ k : computation.tm.K, Finite (computation.tm.Γ k)
  outputBound : Polynomial ℕ
  outputSize : ∀ b, (graphBits (reduce b)).length ≤ outputBound.eval b.length
  completeness : ∀ φ : Formula, φ.Satisfiable → (reduce (formulaBits φ)).ThreeColorable
  soundness : ∀ φ : Formula, ¬φ.Satisfiable →
    ((reduce (formulaBits φ)).independenceNumber : ℝ) <
      δ * (reduce (formulaBits φ)).vertices

/-- Real-threshold graph reduction with explicit binary runtime and output-size bounds. -/
theorem mainTheoremReal :
    ∀ δ : ℝ, 0 < δ → δ < 1 / 3 → Nonempty (RealGraphReduction δ) := by
  sorry

end
end LargeIndependentSets

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/IndependentSets.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.LargeIndependentSets.mainTheoremReal` must keep exactly the statement shown above: same names,
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
