# openai/math challenge `CompleteCrossing` (family 165)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 165 of the release, *Exact crossing numbers of complete and complete bipartite graphs*
(Combinatorics). The family as a whole: Resolves the Harary–Hill conjecture and Turan's brickyard problem in the Zarankiewicz formulation, determining the crossing numbers of every complete and complete bipartite graph. The result proves the optimality of the classical drawings among all plane drawings with continuous edge arcs.

The challenge is `CompleteCrossing`, also at `/opt/openai-math/challenges/CompleteCrossing.lean`:

```lean
import Mathlib.Data.Set.Card
import Mathlib.Order.Lattice.Nat
import Mathlib.Topology.Instances.Real.Lemmas
import Mathlib.Topology.OpenPartialHomeomorph.Defs
import Mathlib.Topology.Path

namespace OAI

noncomputable section

namespace Paper170

abbrev Plane := ℝ × ℝ

structure Graph (Vertex Edge : Type) where
  src : Edge → Vertex
  dst : Edge → Vertex
  loopless : ∀ edge, src edge ≠ dst edge
  simple : ∀ edge other, ((src edge = src other ∧ dst edge = dst other) ∨
    (src edge = dst other ∧ dst edge = src other)) → edge = other

abbrev CompleteEdge (order : ℕ) := {pair : Fin order × Fin order // pair.1 < pair.2}

def completeGraph (order : ℕ) : Graph (Fin order) (CompleteEdge order) where
  src edge := edge.val.1
  dst edge := edge.val.2
  loopless edge := ne_of_lt edge.property
  simple edge other same := by
    rcases same with same | reversed
    · exact Subtype.ext (Prod.ext same.1 same.2)
    · have increasing := edge.property
      have other_increasing := other.property
      rw [reversed.1, reversed.2] at increasing
      exact (lt_asymm increasing other_increasing).elim

variable {Vertex Edge : Type}

structure ContinuousDrawing (graph : Graph Vertex Edge) where
  vertex : Vertex → Plane
  vertex_injective : Function.Injective vertex
  edge : ∀ edge : Edge, Path (vertex (graph.src edge)) (vertex (graph.dst edge))
  edge_injective : ∀ selected, Function.Injective (edge selected)
  interior_avoids_vertices : ∀ selected time, time ∈ Set.Ioo (0 : unitInterval) 1 →
    ∀ other, edge selected time ≠ vertex other

variable {graph : Graph Vertex Edge}

def edgeInterior (drawing : ContinuousDrawing graph) (edge : Edge) : Set Plane :=
  drawing.edge edge '' Set.Ioo (0 : unitInterval) 1

structure ProperCrossing (first second : Set Plane) (point : Plane) : Prop where
  chart_exists : ∃ chart : OpenPartialHomeomorph Plane Plane,
    point ∈ chart.source ∧ chart point = (0, 0) ∧
    chart '' (chart.source ∩ first) = chart.target ∩ {image | image.2 = 0} ∧
    chart '' (chart.source ∩ second) = chart.target ∩ {image | image.1 = 0}

def crossingPoints (drawing : ContinuousDrawing graph) : Set Plane :=
  {point | ∃ edge other : Edge, edge ≠ other ∧
    point ∈ edgeInterior drawing edge ∧ point ∈ edgeInterior drawing other}

structure AdmissibleDrawing (graph : Graph Vertex Edge) extends ContinuousDrawing graph where
  crossings_finite : (crossingPoints toContinuousDrawing).Finite
  crossings_proper : ∀ edge other, edge ≠ other → ∀ point,
    point ∈ edgeInterior toContinuousDrawing edge →
    point ∈ edgeInterior toContinuousDrawing other →
    ProperCrossing (edgeInterior toContinuousDrawing edge)
      (edgeInterior toContinuousDrawing other) point
  no_triples : ∀ first second third, first ≠ second → first ≠ third → second ≠ third →
    edgeInterior toContinuousDrawing first ∩ edgeInterior toContinuousDrawing second ∩
      edgeInterior toContinuousDrawing third = ∅

def crossingCount (drawing : AdmissibleDrawing graph) : ℕ :=
  drawing.crossings_finite.toFinset.card

def ordinaryCrossingNumber (graph : Graph Vertex Edge) : ℕ :=
  sInf (Set.range (@crossingCount Vertex Edge graph))

def hill (order : ℕ) : ℕ :=
  (order / 2 * ((order - 1) / 2) * ((order - 2) / 2) * ((order - 3) / 2)) / 4

theorem complete_graph_crossing_number (order : ℕ) (at_least_three : 3 ≤ order) :
    ordinaryCrossingNumber (completeGraph order) = hill order := by
  sorry

end Paper170

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/CompleteCrossing.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Paper170.complete_graph_crossing_number` must keep exactly the statement shown above: same names,
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
