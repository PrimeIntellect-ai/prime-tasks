# openai/math challenge `KServer` (family 110)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 110 of the release, *Optimal-order randomized $k$-server on arbitrary metrics*
(Theoretical computer science). The family as a whole: Establishes a randomized competitive ratio $O(\log^2(k+1))$ for $k$-server on every metric space, matching the worst-case lower-bound order. One policy serves every finite oblivious request sequence, including on infinite unbounded metrics. On finite rational metrics, a uniform implementation has polynomial preprocessing and per-request bit cost in the input length and $\log(t+1)$ at request $t$, with a finite instance-dependent additive movement constant.

The challenge is `KServer`, also at `/opt/openai-math/challenges/KServer.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

open scoped BigOperators

namespace KServer

universe u

abbrev Configuration (k : ℕ) (X : Type u) := Fin k → X

def LabelDistribution (k : ℕ) :=
  {probability : Fin k → ℝ //
    (∀ label, 0 ≤ probability label) ∧ ∑ label, probability label = 1}

abbrev Policy (k : ℕ) (X : Type u) :=
  List (X × Fin k) → X → LabelDistribution k

def serve {k : ℕ} {X : Type u} (s : Configuration k X)
    (label : Fin k) (request : X) : Configuration k X :=
  Function.update s label request

def serviceCost {k : ℕ} {X : Type u} [MetricSpace X]
    (s : Configuration k X) : (requests : List X) → (Fin requests.length → Fin k) → ℝ
  | [], _ => 0
  | request :: requests, labels =>
      dist (s (labels 0)) request +
        serviceCost (serve s (labels 0) request) requests (fun index => labels index.succ)

def pathProbability {k : ℕ} {X : Type u} (A : Policy k X)
    (history : List (X × Fin k)) :
    (requests : List X) → (Fin requests.length → Fin k) → ℝ
  | [], _ => 1
  | request :: requests, labels =>
      (A history request).val (labels 0) *
        pathProbability A (history ++ [(request, labels 0)]) requests
          (fun index => labels index.succ)

def expectedCost {k : ℕ} {X : Type u} [MetricSpace X]
    (A : Policy k X) (s : Configuration k X) (requests : List X) : ℝ :=
  ∑ labels : Fin requests.length → Fin k,
    pathProbability A [] requests labels * serviceCost s requests labels

def optimalCost {k : ℕ} {X : Type u} [MetricSpace X]
    (s : Configuration k X) (requests : List X) : ℝ :=
  sInf (Set.range (serviceCost s requests))

def MainStatement : Prop :=
  ∃ C : ℝ, 0 < C ∧ ∀ (k : ℕ), 2 ≤ k →
    ∀ (X : Type u) (_ : MetricSpace X),
      (∃ embedding : Fin (k + 1) → X, Function.Injective embedding) →
      ∀ s : Configuration k X,
        ∃ A : Policy k X, ∃ B : ℝ,
          0 ≤ B ∧ (Function.Injective s → B = 0) ∧
          ∀ requests : List X,
            expectedCost A s requests ≤
              C * (Real.log (k + 1)) ^ 2 * optimalCost s requests + B

theorem main_theorem : MainStatement.{u} := by
  sorry

end KServer

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/KServer.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.KServer.main_theorem` must keep exactly the statement shown above: same names,
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
