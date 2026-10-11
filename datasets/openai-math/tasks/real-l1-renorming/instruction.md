# openai/math challenge `RealL1Renorming` (family 330)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 330 of the release, *A negative answer to Kalton's Lipschitz-free approximation question*
(Functional analysis). The family as a whole: Constructs a countable uniformly discrete metric space whose real Lipschitz-free Banach space has the approximation property but not the bounded approximation property, answering Kalton's question negatively. Finite-rank operators approximate the identity on every compact set, but their norms cannot share a finite bound.

The challenge is `RealL1Renorming`, also at `/opt/openai-math/challenges/RealL1Renorming.lean`:

```lean
import Mathlib.Analysis.Normed.Lp.lpSpace
import Mathlib.Analysis.Normed.Operator.Basic
import Mathlib.RingTheory.Finiteness.Defs

namespace OAI

noncomputable section

/-!
# Quantitative renorming of real ℓ¹ with fixed vector-space operations
-/

open scoped BigOperators ENNReal

namespace DiscreteFree

variable {M : Type*} [MetricSpace M]

def HasBAP (X : Type*) [NormedAddCommGroup X] [NormedSpace ℝ X] (Λ : ℝ) : Prop :=
  ∀ C : Set X, IsCompact C → ∀ ε : ℝ, 0 < ε →
    ∃ T : X →L[ℝ] X, Module.Finite ℝ (LinearMap.range T.toLinearMap) ∧
      ‖T‖ ≤ Λ ∧ ∃ η : ℝ, η < ε ∧ ∀ u ∈ C, ‖T u - u‖ ≤ η

def blockBound (p : ℕ) : ℝ := 300 * (p : ℝ)^2 + 150 * (p : ℝ) + 5

open scoped BigOperators ENNReal

def RealL1 : Type := lp (fun _ : ℕ => ℝ) (1 : ENNReal)

noncomputable instance : NormedAddCommGroup RealL1 :=
  inferInstanceAs (NormedAddCommGroup (lp (fun _ : ℕ => ℝ) (1 : ENNReal)))

noncomputable instance : NormedSpace ℝ RealL1 :=
  inferInstanceAs (NormedSpace ℝ (lp (fun _ : ℕ => ℝ) (1 : ENNReal)))

def RealL1RenormingStatement : Prop :=
  ∀ p : ℕ, 1 ≤ p → ∃ N : AddGroupNorm RealL1,
    (∀ (r : ℝ) (c : RealL1), N (r • c) = |r| * N c) ∧
    (∀ c : RealL1, (1 / 2 : ℝ) * ‖c‖ ≤ N c ∧ N c ≤ blockBound p * ‖c‖) ∧
    (let m : Module ℝ RealL1 := inferInstance
     letI : NormedAddCommGroup RealL1 := N.toNormedAddCommGroup
     ∃ s : NormedSpace ℝ RealL1, s.toModule = m ∧
       letI := s
       CompleteSpace RealL1 ∧
       HasBAP RealL1 (2 * blockBound p) ∧ ¬ HasBAP RealL1 (p : ℝ) ∧
         (p = 1 → ¬ HasBAP RealL1 1))

theorem real_l1_quantitative_renorming : RealL1RenormingStatement := by
  sorry

end DiscreteFree

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/RealL1Renorming.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.DiscreteFree.real_l1_quantitative_renorming` must keep exactly the statement shown above: same names,
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
