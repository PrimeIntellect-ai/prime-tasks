# openai/math challenge `MatchingEntropyBounds` (family 113)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 113 of the release, *Approximate counting and the perfect-matching entropy conjecture*
(Theoretical computer science). The family as a whole: Gives a fully polynomial randomized approximation scheme for counting perfect matchings in arbitrary finite simple graphs, with exact detection of zero counts. Also proves the perfect-matching entropy conjecture of Anari, Oveis Gharan, and Vinzant, bounding the maximum entropy of a matching law at every feasible edge-marginal vector in a loopless labelled multigraph, including boundary points.

The challenge is `MatchingEntropyBounds`, also at `/opt/openai-math/challenges/MatchingEntropyBounds.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

open scoped BigOperators Topology
open Filter

universe uV uE uIndex uι

namespace MatchingEntropyBounds

structure LooplessGraph (V : Type uV) (E : Type uE) where
  left : E → V
  right : E → V
  loopless : ∀ e, left e ≠ right e

variable {V : Type uV} {E : Type uE}
  [Fintype V] [Fintype E] [DecidableEq V] [DecidableEq E]

namespace LooplessGraph

def Incident (G : LooplessGraph V E) (v : V) (e : E) : Prop :=
  G.left e = v ∨ G.right e = v

instance incidentDecidable (G : LooplessGraph V E) (v : V) (e : E) :
    Decidable (G.Incident v e) := inferInstanceAs (Decidable (G.left e = v ∨ G.right e = v))

def IsPerfectMatching (G : LooplessGraph V E) (M : Finset E) : Prop :=
  ∀ v, ∃! e, e ∈ M ∧ G.Incident v e

abbrev Matching (G : LooplessGraph V E) := {M : Finset E // G.IsPerfectMatching M}

instance matchingFintype (G : LooplessGraph V E) : Fintype G.Matching :=
  Fintype.ofFinite _

def indicator (G : LooplessGraph V E) (M : G.Matching) (e : E) : ℝ :=
  if e ∈ M.val then 1 else 0

def polytope (G : LooplessGraph V E) : Set (E → ℝ) :=
  convexHull ℝ (Set.range G.indicator)

def mean (G : LooplessGraph V E) (p : G.Matching → ℝ) (e : E) : ℝ :=
  ∑ M, p M * G.indicator M e

end LooplessGraph

def probabilitySimplex (Index : Type uIndex) [Fintype Index] : Set (Index → ℝ) :=
  {weights | (∀ index, 0 ≤ weights index) ∧ ∑ index, weights index = 1}

def LooplessGraph.feasibleLaws (G : LooplessGraph V E) (y : E → ℝ) : Set (G.Matching → ℝ) :=
  {p | p ∈ probabilitySimplex G.Matching ∧ G.mean p = y}

def entropy {ι : Type uι} [Fintype ι] (p : ι → ℝ) : ℝ :=
  ∑ i, Real.negMulLog (p i)

def maxMatchingEntropy (G : LooplessGraph V E) (y : E → ℝ) : ℝ :=
  sSup (entropy '' G.feasibleLaws y)

namespace Refined

def complementEntropy (x : E → ℝ) : ℝ := entropy (fun e => 1 - x e)

end Refined

open Module Matrix

variable {V : Type uV} {E : Type uE} [Fintype V] [Fintype E] [DecidableEq V] [DecidableEq E]

open LooplessGraph

theorem Refined.pointwise_entropy (G : LooplessGraph V E) (m : ℕ)
    (hm : 0 < m) (hV : Fintype.card V = 2 * m) (hPM : Nonempty G.Matching)
    (x : E → ℝ) (hx : x ∈ G.polytope) :
    entropy x - (2 - 2 / (m : ℝ)) * complementEntropy x ≤ maxMatchingEntropy G x ∧
      maxMatchingEntropy G x ≤ entropy x := by
  sorry

end MatchingEntropyBounds

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/MatchingEntropyBounds.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.MatchingEntropyBounds.Refined.pointwise_entropy` must keep exactly the statement shown above: same names,
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
