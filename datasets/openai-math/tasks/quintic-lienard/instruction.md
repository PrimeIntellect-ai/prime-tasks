# openai/math challenge `QuinticLienard` (family 143)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 143 of the release, *Uniform limit-cycle bounds in Hilbert's sixteenth problem*
(Dynamical systems and ergodic theory). The family as a whole: Resolves the uniform boundedness assertion in Hilbert's sixteenth problem: the number of isolated periodic orbits of a real planar polynomial vector field is bounded by a finite constant depending only on its degree. For classical quintic Lienard systems, the exact maximum is two limit cycles.

The challenge is `QuinticLienard`, also at `/opt/openai-math/challenges/QuinticLienard.lean`:

```lean
import Mathlib

namespace OAI

namespace QuinticLienard

abbrev Plane := ℝ × ℝ

def vectorField (F : Polynomial ℝ) (z : Plane) : Plane :=
  (z.2 - F.eval z.1, -z.1)

def IsSolution (F : Polynomial ℝ) (z : ℝ → Plane) : Prop :=
  ∀ t : ℝ, HasDerivAt z (vectorField F (z t)) t

def IsPeriodicOrbit (F : Polynomial ℝ) (C : Set Plane) : Prop :=
  ∃ (z : ℝ → Plane) (T : ℝ),
    IsSolution F z ∧ 0 < T ∧ Function.Periodic z T ∧
    (∃ s t : ℝ, z s ≠ z t) ∧ C = Set.range z

def IsLimitCycle (F : Polynomial ℝ) (C : Set Plane) : Prop :=
  IsPeriodicOrbit F C ∧
    ∃ U : Set Plane, IsOpen U ∧ C ⊆ U ∧
      ∀ C' : Set Plane, IsPeriodicOrbit F C' → C' ⊆ U → C' = C

open scoped Topology NNReal ContDiff Manifold
open Filter Set
open Set Filter Metric MeasureTheory
open scoped Topology NNReal ContDiff
open scoped Topology ENNReal
open Set Filter MeasureTheory
open Set Filter Asymptotics
open Set Filter Metric
open scoped Topology NNReal
open scoped Topology
open scoped Topology ContDiff
open Set Filter
open scoped Topology ContDiff NNReal

theorem main :
    (∀ F : Polynomial ℝ, F.degree ≤ 5 → {C : Set Plane | IsLimitCycle F C}.encard ≤ 2) ∧
    (∃ F : Polynomial ℝ, F.degree ≤ 5 ∧ {C : Set Plane | IsLimitCycle F C}.encard = 2) := by
  sorry

end QuinticLienard

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/QuinticLienard.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.QuinticLienard.main` must keep exactly the statement shown above: same names,
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
