# openai/math challenge `BarnetteHamiltonian` (family 180)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 180 of the release, *Barnette's Hamiltonian-cycle conjecture*
(Combinatorics). The family as a whole: Proves that every finite simple cubic bipartite planar $3$-vertex-connected graph has a Hamiltonian cycle, resolving Barnette's conjecture. Equivalently, every three-edge path in a finite simple cubic $3$-vertex-connected bipartite Pfaffian graph lies in a Hamiltonian cycle.

The challenge is `BarnetteHamiltonian`, also at `/opt/openai-math/challenges/BarnetteHamiltonian.lean`:

```lean
import Mathlib

namespace OAI

namespace Barnette

universe u

/-- A topological plane drawing of a simple graph, with no crossings. -/
structure PlaneEmbedding {V : Type u} (G : SimpleGraph V) where
  point : V → ℝ × ℝ
  point_injective : Function.Injective point
  arc : ∀ (v w : V), G.Adj v w → Path (point v) (point w)
  arc_injective : ∀ (v w : V) (h : G.Adj v w),
    Function.Injective (arc v w h)
  arc_reverse : ∀ (v w : V) (h : G.Adj v w),
    arc w v h.symm = (arc v w h).symm
  arc_avoids_vertices : ∀ (v w : V) (h : G.Adj v w)
    (t : unitInterval) (z : V),
    arc v w h t = point z →
      (t = 0 ∧ z = v) ∨ (t = 1 ∧ z = w)
  interiors_disjoint : ∀ (v w x y : V) (h : G.Adj v w) (k : G.Adj x y)
    (t s : unitInterval),
    t ≠ 0 → t ≠ 1 → s ≠ 0 → s ≠ 1 →
    arc v w h t = arc x y k s →
      (v = x ∧ w = y) ∨ (v = y ∧ w = x)

/-- Planarity means existence of a crossing-free topological plane embedding. -/
def Planar {V : Type u} (G : SimpleGraph V) : Prop :=
  Nonempty (PlaneEmbedding G)

/-- Deleting any set of at most two vertices leaves a connected graph of order at least two. -/
def ThreeVertexConnected {V : Type u} [Fintype V] (G : SimpleGraph V) : Prop :=
  4 ≤ Fintype.card V ∧
    ∀ S : Finset V, S.card ≤ 2 → (G.induce {v | v ∉ S}).Connected

/-- A single spanning cycle, not a possibly disconnected spanning 2-factor. -/
def HasHamiltonianCycle {V : Type u} [DecidableEq V] (G : SimpleGraph V) : Prop :=
  ∃ v : V, ∃ p : G.Walk v v, p.IsHamiltonianCycle

/-- Cubic bipartite three-vertex-connected plane graphs have a Hamiltonian cycle. -/
def MainStatement : Prop :=
  ∀ (V : Type u) [Fintype V] [DecidableEq V] (G : SimpleGraph V)
    [DecidableRel G.Adj],
    G.IsRegularOfDegree 3 → G.IsBipartite → Planar G →
      ThreeVertexConnected G → HasHamiltonianCycle G

theorem main : MainStatement.{u} := by
  sorry

end Barnette

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/BarnetteHamiltonian.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Barnette.main` must keep exactly the statement shown above: same names,
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
