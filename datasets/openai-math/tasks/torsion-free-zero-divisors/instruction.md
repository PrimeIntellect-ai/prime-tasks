# openai/math challenge `TorsionFreeZeroDivisors` (family 196)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 196 of the release, *A counterexample to Kaplansky's zero-divisor conjecture*
(Algebra). The family as a whole: Constructs a finitely presented torsion-free group $G$ whose group algebra $\mathbb F_2[G]$ has nonzero zero divisors, disproving Kaplansky's zero-divisor conjecture. The group has a finite two-dimensional classifying space.

The challenge is `TorsionFreeZeroDivisors`, also at `/opt/openai-math/challenges/TorsionFreeZeroDivisors.lean`:

```lean
import Mathlib

namespace OAI

namespace TorsionFreeZeroDivisors

/-- Ordinary group torsion-freeness, without requiring uniqueness of all roots. -/
def TorsionFree (G : Type) [Group G] : Prop :=
  ∀ (g : G) (n : ℕ), 0 < n → g ^ n = 1 → g = 1

/-- A connected finite Hausdorff 2-dimensional CW K(G,1). -/
def HasFiniteTwoDimensionalClassifyingSpace (G : Type) [Group G] : Prop :=
  ∃ (X : Type) (topX : TopologicalSpace X),
    letI : TopologicalSpace X := topX
    ∃ (_hausdorff : T2Space X) (_connected : PathConnectedSpace X)
      (cw : Topology.CWComplex (Set.univ : Set X)),
      letI : Topology.CWComplex (Set.univ : Set X) := cw
      Topology.CWComplex.Finite (Set.univ : Set X) ∧
      (∀ n : ℕ, 2 < n → IsEmpty (Topology.CWComplex.cell (Set.univ : Set X) n)) ∧
      Nonempty (Topology.CWComplex.cell (Set.univ : Set X) 2) ∧
      ∃ (x : X), Nonempty (G ≃* FundamentalGroup X x) ∧
        ∃ (E : Type) (topE : TopologicalSpace E),
          letI : TopologicalSpace E := topE
          ContractibleSpace E ∧
          ∃ p : E → X, IsCoveringMap p ∧ Function.Surjective p

/-- The entire main theorem, including its "Moreover" clause. -/
def MainTheorem : Prop :=
  ∃ (G : Type) (inst : Group G),
    letI : Group G := inst
    Group.IsFinitelyPresented G ∧ TorsionFree G ∧
    HasFiniteTwoDimensionalClassifyingSpace G ∧
    ∃ α β : MonoidAlgebra (ZMod 2) G, α ≠ 0 ∧ β ≠ 0 ∧ α * β = 0

theorem main : MainTheorem := by
  sorry

end TorsionFreeZeroDivisors

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/TorsionFreeZeroDivisors.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.TorsionFreeZeroDivisors.main` must keep exactly the statement shown above: same names,
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
