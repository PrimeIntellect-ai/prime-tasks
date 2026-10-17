# openai/math challenge `C0Absorption` (family 324)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 324 of the release, *Lipschitz equivalence without linear isomorphism*
(Functional analysis). The family as a whole: Constructs separable real Banach spaces that are globally bi-Lipschitz equivalent but not linearly isomorphic, resolving the separable Lipschitz-isomorphism problem negatively. Thus even the complete metric structure up to bi-Lipschitz equivalence does not determine a separable Banach space's linear isomorphism class.

The challenge is `C0Absorption`, also at `/opt/openai-math/challenges/C0Absorption.lean`:

```lean
import Mathlib

namespace OAI

namespace C0Absorption

open scoped ZeroAtInfty

abbrev C0 := C₀(ℕ, ℝ)

def BiLip {X Y : Type*} [MetricSpace X] [MetricSpace Y] (f : X → Y) : Prop :=
  ∃ c C : ℝ, 0 < c ∧ c ≤ C ∧
    ∀ x y, c * dist x y ≤ dist (f x) (f y) ∧ dist (f x) (f y) ≤ C * dist x y

def NoLinearC0 (Z : Type*) [NormedAddCommGroup Z] [NormedSpace ℝ Z] : Prop :=
  ∀ T : C0 →L[ℝ] Z, ¬ ∃ c : ℝ, 0 < c ∧ ∀ x, c * ‖x‖ ≤ ‖T x‖

def MetricUniversal (Z : Type*) [MetricSpace Z] : Prop :=
  ∀ (M : Type) [MetricSpace M] [TopologicalSpace.SeparableSpace M],
    ∃ f : M → Z, BiLip f

def MainConclusion : Prop :=
  ∃ (Z : Type) (_ : NormedAddCommGroup Z) (_ : NormedSpace ℝ Z),
    CompleteSpace Z ∧ TopologicalSpace.SeparableSpace Z ∧ NoLinearC0 Z ∧
    (∃ F : Z × C0 → Z, Function.Surjective F ∧ BiLip F) ∧
    (∃ f : C0 → Z, BiLip f) ∧ MetricUniversal Z ∧
    ¬ Nonempty ((Z × C0) ≃L[ℝ] Z)

theorem main_result : MainConclusion := by sorry

end C0Absorption

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/C0Absorption.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.C0Absorption.main_result` must keep exactly the statement shown above: same names,
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
