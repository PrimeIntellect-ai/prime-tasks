# openai/math challenge `ProjectionCounterexample` (family 088)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 088 of the release, *Petty's projection-volume conjecture and simplex counterexamples*
(Convex and metric geometry). The family as a whole: Proves Petty's projection-volume conjecture in the remaining dimensions $n\ge4$: ellipsoids uniquely minimize projection-body volume at fixed body volume. Also establishes the full Lutwak–Petty projection inequalities. In contrast, products of simplices exceed Brannen's proposed simplex maximum for normalized projection-body volume by an exponential factor in every sufficiently large dimension.

The challenge is `ProjectionCounterexample`, also at `/opt/openai-math/challenges/ProjectionCounterexample.lean`:

```lean
import Mathlib.Analysis.Convex.Hull
import Mathlib.Analysis.InnerProductSpace.PiL2
import Mathlib.Analysis.InnerProductSpace.Projection.Basic
import Mathlib.Geometry.Euclidean.Volume.Measure

namespace OAI

noncomputable section

open Set MeasureTheory
open scoped RealInnerProductSpace

namespace ProjectionCounterexample

abbrev E (d : ℕ) := EuclideanSpace ℝ (Fin d)

def simplex (d : ℕ) : Set (E d) :=
  convexHull ℝ (insert 0 (range fun i : Fin d => EuclideanSpace.single i (1 : ℝ)))

def IsConvexBody {d : ℕ} (P : Set (E d)) : Prop :=
  IsCompact P ∧ Convex ℝ P ∧ (interior P).Nonempty

def project {d : ℕ} (u : E d) : E d →L[ℝ] E d :=
  (ℝ ∙ u)ᗮ.starProjection

def projectionVolume {d : ℕ} (P : Set (E d)) (u : E d) : ℝ :=
  (Measure.euclideanHausdorffMeasure (d - 1) (project u '' P)).toReal

def projectionBody {d : ℕ} (P : Set (E d)) : Set (E d) :=
  {x | ∀ u : E d, ‖u‖ = 1 → ⟪u, x⟫ ≤ projectionVolume P u}

def bodyVolume {d : ℕ} (P : Set (E d)) : ℝ := (volume P).toReal

def ratio {d : ℕ} (P : Set (E d)) : ℝ :=
  bodyVolume (projectionBody P) / bodyVolume P ^ (d - 1)

theorem universal_simplex_upper_bound_false :
    ¬ (∀ P : Set (E 20), IsConvexBody P → ratio P ≤ ratio (simplex 20)) := by
  sorry

end ProjectionCounterexample

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/ProjectionCounterexample.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.ProjectionCounterexample.universal_simplex_upper_bound_false` must keep exactly the statement shown above: same names,
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
