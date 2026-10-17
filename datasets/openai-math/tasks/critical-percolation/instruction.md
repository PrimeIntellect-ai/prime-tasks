# openai/math challenge `CriticalPercolation` (family 213)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 213 of the release, *No infinite critical clusters on quasi-transitive graphs*
(Probability and statistical mechanics). The family as a whole: Resolves the Benjamini–Schramm criticality conjecture for bond percolation on every infinite connected locally finite quasi-transitive graph with $p_c<1$: at the critical probability, there is almost surely no infinite cluster. The family also establishes this conclusion for both nearest-neighbor bond and site percolation on $\mathbb Z^3$.

The challenge is `CriticalPercolation`, also at `/opt/openai-math/challenges/CriticalPercolation.lean`:

```lean
import Mathlib

namespace OAI

open Set MeasureTheory ProbabilityTheory

namespace CriticalPercolation

/-- An undirected graph with labelled bonds, including loops and parallel bonds. -/
structure BondGraph (V E : Type*) where
  ends : E → Sym2 V

namespace BondGraph
variable {V E : Type*} (G : BondGraph V E)

/-- The graph of retained bonds. `fromEdgeSet` discards loops. -/
def openGraph (ω : Set E) : SimpleGraph V :=
  SimpleGraph.fromEdgeSet (G.ends '' ω)

/-- The underlying connectivity graph with every bond retained. -/
def fullGraph : SimpleGraph V := G.openGraph Set.univ

/-- Local finiteness counts bonds, not just distinct neighbors. -/
def LocallyFinite : Prop := ∀ v : V, {e : E | v ∈ G.ends e}.Finite

/-- Automorphisms preserve the vertex and bond structure, including multiplicities. -/
structure Aut where
  vertex : V ≃ V
  edge : E ≃ E
  preserves : ∀ e, G.ends (edge e) = Sym2.map vertex (G.ends e)

/-- Finitely many vertex orbits under the full automorphism group. -/
def QuasiTransitive : Prop :=
  ∃ S : Set V, S.Finite ∧ ∀ v : V, ∃ s ∈ S, ∃ φ : G.Aut, φ.vertex s = v

/-- Finite open paths, including the path of length zero, define the open cluster. -/
def cluster (ω : Set E) (v : V) : Set V := {w | (G.openGraph ω).Reachable v w}

/-- The event that at least one open cluster is infinite. -/
def percolates : Set (Set E) := {ω | ∃ v : V, (G.cluster ω v).Infinite}

/-- Independent retention with parameter `p ∈ [0,1]` of each labelled bond. -/
noncomputable def law (_G : BondGraph V E) (p : unitInterval) : Measure (Set E) :=
  ProbabilityTheory.setBernoulli Set.univ p

/-- The infimum of parameters with positive probability of an infinite cluster. -/
noncomputable def criticalProbability : unitInterval :=
  sInf {p : unitInterval | 0 < G.law p G.percolates}

/-- Critical Bernoulli bond percolation has no infinite cluster when the critical
probability is below one. -/
theorem no_percolation_at_criticality [Infinite V]
    (hconnected : G.fullGraph.Connected)
    (hlocal : G.LocallyFinite)
    (hquasi : G.QuasiTransitive)
    (hpc : G.criticalProbability < 1) :
    G.law G.criticalProbability G.percolates = 0 := by
  sorry

end BondGraph
end CriticalPercolation

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/CriticalPercolation.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.CriticalPercolation.BondGraph.no_percolation_at_criticality` must keep exactly the statement shown above: same names,
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
