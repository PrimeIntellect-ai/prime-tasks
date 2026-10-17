# openai/math challenge `CycleDecomposition` (family 181)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 181 of the release, *The Erd\H{o}s–Gallai cycle-decomposition conjecture*
(Combinatorics). The family as a whole: Proves that the edges of every finite simple undirected graph on $n$ vertices can be partitioned into at most $Cn$ simple cycles and single edges, for an absolute constant $C$. This resolves the Erd\H{o}s–Gallai cycle-decomposition conjecture, bounding the number of pieces linearly even for dense graphs.

The challenge is `CycleDecomposition`, also at `/opt/openai-math/challenges/CycleDecomposition.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section


open Filter Asymptotics Real
open scoped Topology

open MeasureTheory ProbabilityTheory Finset

namespace ErdosGallai

def CycleOrSingleEdge {V : Type} (G : SimpleGraph V)
    (s : Set (Sym2 V)) : Prop :=
  (∃ (v : V) (p : G.Walk v v), p.IsCycle ∧ s = p.edgeSet) ∨
  ∃ e ∈ G.edgeSet, s = {e}

def EdgeDecomposition {V : Type} (G : SimpleGraph V) (k : ℕ) : Prop :=
  ∃ parts : Fin k → Set (Sym2 V),
    (∀ i, CycleOrSingleEdge G (parts i)) ∧
    Pairwise (fun i j => Disjoint (parts i) (parts j)) ∧
    (⋃ i, parts i) = G.edgeSet


def MainStatement : Prop :=
  ∃ C : ℝ, 0 < C ∧ ∀ (n : ℕ) (G : SimpleGraph (Fin n)),
    ∃ k : ℕ, EdgeDecomposition G k ∧ (k : ℝ) ≤ C * n

theorem erdos_gallai : MainStatement := by
  sorry

end ErdosGallai

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/CycleDecomposition.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.ErdosGallai.erdos_gallai` must keep exactly the statement shown above: same names,
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
