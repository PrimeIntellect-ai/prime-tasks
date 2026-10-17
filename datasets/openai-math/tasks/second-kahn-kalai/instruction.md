# openai/math challenge `SecondKahnKalai` (family 176)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 176 of the release, *The second Kahn–Kalai conjecture*
(Combinatorics). The family as a whole: Proves the second Kahn–Kalai conjecture: for every finite simple graph $H$ with $h\ge1$ edges and at most $n$ vertices, its appearance threshold in $G(n,p)$ is at most $C p_{\mathrm E}(n,H)(1+\log_2 h)$, with universal $C$. Here $p_{\mathrm E}$ is the least density at which every subgraph of $H$ has expected copy count at least $1/2$.

The challenge is `SecondKahnKalai`, also at `/opt/openai-math/challenges/SecondKahnKalai.lean`:

```lean
import Mathlib.Data.Fintype.Powerset
import Mathlib.Basic.Real.Basic
import Mathlib.Algebra.BigOperators.Ring.Finset
import Mathlib.Combinatorics.SimpleGraph.Copy
import Mathlib.Analysis.SpecialFunctions.Log.Basic

namespace OAI

noncomputable section

universe u

namespace LeanBlast.SecondKahnKalai

def bernoulliWeight {X : Type u} [Fintype X] [DecidableEq X]
    (p : ℝ) (W : Finset X) : ℝ :=
  ∏ x, if x ∈ W then p else 1 - p

def bernoulliExpectation {X : Type u} [Fintype X] [DecidableEq X]
    (p : ℝ) (f : Finset X → ℝ) : ℝ :=
  ∑ W, bernoulliWeight p W * f W

def bernoulliProbability {X : Type u} [Fintype X] [DecidableEq X]
    (p : ℝ) (P : Finset X → Prop) : ℝ := by
  classical
  exact ∑ W, if P W then bernoulliWeight p W else 0

/-- The unordered non-loop edges of the complete graph on `n` vertices. -/
abbrev Edge (n : ℕ) := {e : Sym2 (Fin n) // ¬e.IsDiag}

/-- A set of edges, interpreted as an ordinary graph on all `n` vertices. -/
def graphOfEdges {n : ℕ} (W : Finset (Edge n)) : SimpleGraph (Fin n) :=
  SimpleGraph.fromEdgeSet (Subtype.val '' (W : Set (Edge n)))

/-- The number of unordered edges, each counted once. -/
def edgeCount {V : Type u} (H : SimpleGraph V) : ℕ := Nat.card H.edgeSet

/-- Expected number of actual unlabelled non-induced copies in `G(n,p)`. -/
def expectedCopies {V : Type u} (n : ℕ) (p : ℝ) (H : SimpleGraph V) : ℝ :=
  bernoulliExpectation p (fun W : Finset (Edge n) =>
    ((graphOfEdges W).copyCount H : ℝ))

/-- Probability that `G(n,p)` contains at least one non-induced copy. -/
def containmentProbability {V : Type u} (n : ℕ) (p : ℝ)
    (H : SimpleGraph V) : ℝ :=
  bernoulliProbability p (fun W : Finset (Edge n) =>
    0 < (graphOfEdges W).copyCount H)

def criticalThreshold {V : Type u} (n : ℕ) (H : SimpleGraph V) : ℝ :=
  sInf {p : ℝ | p ∈ Set.Icc 0 1 ∧ (1 / 2 : ℝ) ≤ containmentProbability n p H}

def expectationThreshold {V : Type u} (n : ℕ) (H : SimpleGraph V) : ℝ :=
  sInf {p : ℝ | p ∈ Set.Icc 0 1 ∧
    ∀ F : H.Subgraph, (1 / 2 : ℝ) ≤ expectedCopies n p F.coe}

def logTwo (x : ℝ) : ℝ := Real.log x / Real.log 2

def SecondKahnKalaiBounds {V : Type u} (n : ℕ) (H : SimpleGraph V) : Prop :=
  criticalThreshold n H ≤
      min 1 (2048 * Real.exp 50 * expectationThreshold n H *
        (1 + logTwo (edgeCount H : ℝ))) ∧
    criticalThreshold n H ≤
      6144 * Real.exp 50 * expectationThreshold n H * logTwo (n : ℝ)

theorem secondKahnKalaiBounds (n : ℕ) (V : Type u) [Fintype V]
    (H : SimpleGraph V) (hn : 2 ≤ n) (hcard : Fintype.card V ≤ n)
    (hedge : 1 ≤ edgeCount H) : SecondKahnKalaiBounds n H := by
  sorry

end LeanBlast.SecondKahnKalai

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/SecondKahnKalai.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.LeanBlast.SecondKahnKalai.secondKahnKalaiBounds` must keep exactly the statement shown above: same names,
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
