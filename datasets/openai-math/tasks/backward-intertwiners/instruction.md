# openai/math challenge `BackwardIntertwiners` (family 293)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 293 of the release, *A counterexample to the hyperinvariant-subspace problem*
(Operator algebras). The family as a whole: Constructs a nonzero norm-quasinilpotent operator on every infinite-dimensional separable complex Hilbert space with no nonzero proper closed subspace invariant under every commuting operator. The construction also gives operators with no nontrivial invariant projection in the hyperfinite type $\mathrm{II}_1$ factor.

The challenge is `BackwardIntertwiners`, also at `/opt/openai-math/challenges/BackwardIntertwiners.lean`:

```lean
import Mathlib

namespace OAI

namespace Hyperinvariant233
open Filter
open scoped Topology
universe u
variable {H : Type u} [NormedAddCommGroup H] [InnerProductSpace ℂ H] [CompleteSpace H]

def commutant (T : H →L[ℂ] H) : Subalgebra ℂ (H →L[ℂ] H) :=
  Subalgebra.centralizer ℂ ({T} : Set (H →L[ℂ] H))

def TransitiveCommutant (T : H →L[ℂ] H) : Prop :=
  ∀ K : Submodule ℂ H, IsClosed (K : Set H) →
    (∀ A : H →L[ℂ] H, A * T = T * A → ∀ x ∈ K, A x ∈ K) →
    K = ⊥ ∨ K = ⊤

@[instance_reducible]
def strongOperatorTopology : TopologicalSpace (H →L[ℂ] H) :=
  TopologicalSpace.induced (fun A : H →L[ℂ] H => (fun x : H => A x)) inferInstance

def FullClaim : Prop :=
  ∃ T : H →L[ℂ] H, T ≠ 0 ∧
    Tendsto (fun n : ℕ => ‖T ^ n‖ ^ (1 / (n : ℝ))) atTop (𝓝 0) ∧
    TransitiveCommutant T ∧ commutant T ≠ ⊤ ∧
    @IsClosed (H →L[ℂ] H) strongOperatorTopology (commutant T : Set (H →L[ℂ] H))

end Hyperinvariant233

namespace BackwardIntertwiners
open Filter Topology MeasureTheory Set
noncomputable section
open scoped ENNReal

theorem direct_algebra_corollary (H : Type*) [NormedAddCommGroup H] [InnerProductSpace ℂ H]
    [CompleteSpace H] [TopologicalSpace.SeparableSpace H] (hInf : ¬FiniteDimensional ℂ H) :
    Hyperinvariant233.FullClaim (H:=H) := by
  sorry

end
end BackwardIntertwiners

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/BackwardIntertwiners.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.BackwardIntertwiners.direct_algebra_corollary` must keep exactly the statement shown above: same names,
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
