# openai/math challenge `BipartiteCrossing` (family 165)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 165 of the release, *Exact crossing numbers of complete and complete bipartite graphs*
(Combinatorics). The family as a whole: Resolves the Harary–Hill conjecture and Turan's brickyard problem in the Zarankiewicz formulation, determining the crossing numbers of every complete and complete bipartite graph. The result proves the optimality of the classical drawings among all plane drawings with continuous edge arcs.

The challenge is `BipartiteCrossing`, also at `/opt/openai-math/challenges/BipartiteCrossing.lean`:

```lean
import Mathlib.Topology.Path
import Mathlib.Topology.OpenPartialHomeomorph.Defs
import Mathlib.Topology.Instances.Real.Lemmas
import Mathlib.Data.Set.Finite.Basic
import Mathlib.Data.Finset.Attr
import Mathlib.Tactic.Common
import Mathlib.Tactic.Finiteness.Attr
import Mathlib.Tactic.SetLike
import Mathlib.Util.CompileInductive

namespace OAI

noncomputable section

namespace Zarankiewicz

def axisPairs (r : ℕ) : ℕ := (r/2) * ((r-1)/2)


abbrev Plane := ℝ × ℝ
abbrev BipartiteVertex (m n : ℕ) := Fin m ⊕ Fin n
abbrev BipartiteEdge (m n : ℕ) := Fin m × Fin n

structure ContinuousDrawing (m n : ℕ) where
  vertex : BipartiteVertex m n → Plane
  vertex_injective : Function.Injective vertex
  edge : ∀ e : BipartiteEdge m n, Path (vertex (.inl e.1)) (vertex (.inr e.2))
  edge_injective : ∀ e, Function.Injective (edge e)
  interior_avoids_vertices : ∀ e t, t ∈ Set.Ioo (0 : unitInterval) 1 →
    ∀ v, edge e t ≠ vertex v

def edgeInterior {m n : ℕ} (D : ContinuousDrawing m n) (e : BipartiteEdge m n) : Set Plane :=
  D.edge e '' Set.Ioo (0 : unitInterval) 1

def ProperCrossing (A B : Set Plane) (x : Plane) : Prop :=
  ∃ chart : OpenPartialHomeomorph Plane Plane,
    x ∈ chart.source ∧ chart x = (0,0) ∧
    chart '' (chart.source ∩ A) = chart.target ∩ {y | y.2 = 0} ∧
    chart '' (chart.source ∩ B) = chart.target ∩ {y | y.1 = 0}

def crossingPoints {m n : ℕ} (D : ContinuousDrawing m n) : Set Plane :=
  {x | ∃ e f : BipartiteEdge m n, e ≠ f ∧ x ∈ edgeInterior D e ∧ x ∈ edgeInterior D f}

structure AdmissibleDrawing (m n : ℕ) extends ContinuousDrawing m n where
  crossings_finite : (crossingPoints toContinuousDrawing).Finite
  crossings_proper : ∀ e f, e ≠ f → ∀ x,
    x ∈ edgeInterior toContinuousDrawing e → x ∈ edgeInterior toContinuousDrawing f →
    ProperCrossing (edgeInterior toContinuousDrawing e) (edgeInterior toContinuousDrawing f) x
  no_triples : ∀ e f g, e ≠ f → e ≠ g → f ≠ g →
    edgeInterior toContinuousDrawing e ∩ edgeInterior toContinuousDrawing f ∩
      edgeInterior toContinuousDrawing g = ∅

def crossingCount {m n : ℕ} (D : AdmissibleDrawing m n) : ℕ := D.crossings_finite.toFinset.card

def MainTarget : Prop :=
  ∀ m n : ℕ, 0 < m → 0 < n →
    (∃ D : AdmissibleDrawing m n, crossingCount D = axisPairs m * axisPairs n) ∧
    (∀ D : AdmissibleDrawing m n, axisPairs m * axisPairs n ≤ crossingCount D)

theorem mainTarget_proof : MainTarget := by
  sorry

end Zarankiewicz

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/BipartiteCrossing.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Zarankiewicz.mainTarget_proof` must keep exactly the statement shown above: same names,
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
