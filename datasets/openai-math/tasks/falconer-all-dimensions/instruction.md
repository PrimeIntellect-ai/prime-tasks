# openai/math challenge `FalconerAllDimensions` (family 073)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 073 of the release, *The Falconer distance conjecture*
(Real and complex analysis). The family as a whole: Resolves the Falconer distance conjecture in every dimension $d\ge2$: every compact set $E\subset\mathbb R^d$ with Hausdorff dimension greater than $d/2$ determines a set of Euclidean distances of positive Lebesgue measure.

The challenge is `FalconerAllDimensions`, also at `/opt/openai-math/challenges/FalconerAllDimensions.lean`:

```lean
import Mathlib

namespace OAI

namespace Falconer
open MeasureTheory
open scoped ENNReal

/-- A compact subset of Euclidean space with Hausdorff dimension greater than
half the ambient dimension determines a distance set of positive Lebesgue measure. -/
theorem falconer_distance_conjecture :
    ∀ (d : ℕ), 2 ≤ d → ∀ E : Set (EuclideanSpace ℝ (Fin d)), IsCompact E →
      (d : ℝ≥0∞) / 2 < dimH E →
        0 < volume {r : ℝ | ∃ x ∈ E, ∃ y ∈ E, dist x y = r} := by
  sorry

end Falconer

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/FalconerAllDimensions.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Falconer.falconer_distance_conjecture` must keep exactly the statement shown above: same names,
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
