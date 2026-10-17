# openai/math challenge `LipschitzEquivalence` (family 324)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 324 of the release, *Lipschitz equivalence without linear isomorphism*
(Functional analysis). The family as a whole: Constructs separable real Banach spaces that are globally bi-Lipschitz equivalent but not linearly isomorphic, resolving the separable Lipschitz-isomorphism problem negatively. Thus even the complete metric structure up to bi-Lipschitz equivalence does not determine a separable Banach space's linear isomorphism class.

The challenge is `LipschitzEquivalence`, also at `/opt/openai-math/challenges/LipschitzEquivalence.lean`:

```lean
import Mathlib

namespace OAI

universe uE uF

noncomputable section
namespace LipschitzCounterexample

abbrev RealL2 := lp (fun _ : ℕ => ℝ) 2
abbrev C0L2 := ZeroAtInftyContinuousMap ℕ RealL2

structure SeparableRealBanach where
  Carrier : Type
  [normedAddCommGroup : NormedAddCommGroup Carrier]
  [normedSpace : NormedSpace ℝ Carrier]
  [completeSpace : CompleteSpace Carrier]
  [separableSpace : TopologicalSpace.SeparableSpace Carrier]

attribute [instance] SeparableRealBanach.normedAddCommGroup
  SeparableRealBanach.normedSpace SeparableRealBanach.completeSpace
  SeparableRealBanach.separableSpace

def ContainsLinearCopy (E : Type uE) (F : Type uF) [NormedAddCommGroup E] [NormedSpace ℝ E]
    [NormedAddCommGroup F] [NormedSpace ℝ F] : Prop :=
  ∃ (T : E →L[ℝ] F) (a : ℝ), 0 < a ∧ ∀ x : E, a * ‖x‖ ≤ ‖T x‖

def MainClaim : Prop :=
  ∃ X Y : SeparableRealBanach,
    ∃ Ψ : X.Carrier ≃ Y.Carrier,
      (∀ s t : X.Carrier,
        (4 / 21 : ℝ) * ‖s - t‖ ≤ ‖Ψ s - Ψ t‖ ∧
        ‖Ψ s - Ψ t‖ ≤ (76 / 25 : ℝ) * ‖s - t‖) ∧
      IsEmpty (X.Carrier ≃L[ℝ] Y.Carrier) ∧
      Nonempty (C0L2 →ₗᵢ[ℝ] X.Carrier) ∧
      ¬ ContainsLinearCopy C0L2 Y.Carrier

theorem main : MainClaim := by
  sorry

end LipschitzCounterexample
end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/LipschitzEquivalence.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.LipschitzCounterexample.main` must keep exactly the statement shown above: same names,
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
