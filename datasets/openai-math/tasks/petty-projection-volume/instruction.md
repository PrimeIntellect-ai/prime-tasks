# openai/math challenge `PettyProjectionVolume` (family 088)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 088 of the release, *Petty's projection-volume conjecture and simplex counterexamples*
(Convex and metric geometry). The family as a whole: Proves Petty's projection-volume conjecture in the remaining dimensions $n\ge4$: ellipsoids uniquely minimize projection-body volume at fixed body volume. Also establishes the full Lutwak–Petty projection inequalities. In contrast, products of simplices exceed Brannen's proposed simplex maximum for normalized projection-body volume by an exponential factor in every sufficiently large dimension.

The challenge is `PettyProjectionVolume`, also at `/opt/openai-math/challenges/PettyProjectionVolume.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open Set MeasureTheory
open scoped RealInnerProductSpace

namespace PettyProjection

abbrev Space (n : ℕ) := EuclideanSpace ℝ (Fin n)

def IsConvexBody {n : ℕ} (K : Set (Space n)) : Prop :=
  IsCompact K ∧ Convex ℝ K ∧ (interior K).Nonempty

def unitBall (n : ℕ) : Set (Space n) := Metric.closedBall 0 1

def kappa (n : ℕ) : ℝ := volume.real (unitBall n)

def perpendicular {n : ℕ} (u : Space n) : Submodule ℝ (Space n) :=
  (Submodule.span ℝ {u})ᗮ

/-- Volume in the induced Euclidean structure on the orthogonal hyperplane. -/
def shadowVolume {n : ℕ} (K : Set (Space n)) (u : Space n) : ℝ :=
  (volume : Measure (perpendicular u)).real
    ((perpendicular u).orthogonalProjectionOnto '' K)

/-- The body with support function equal to the volumes of orthogonal shadows,
expressed as its defining intersection of supporting half-spaces. -/
def projectionBody {n : ℕ} (K : Set (Space n)) : Set (Space n) :=
  {x | ∀ u : Space n, ‖u‖ = 1 → ⟪u, x⟫ ≤ shadowVolume K u}

def projectionRatio {n : ℕ} (K : Set (Space n)) : ℝ :=
  volume.real (projectionBody K) / volume.real K ^ (n - 1)

def pettyConstant (n : ℕ) : ℝ :=
  kappa (n - 1) ^ n * kappa n ^ (2 - (n : ℤ))

def IsEllipsoid {n : ℕ} (K : Set (Space n)) : Prop :=
  ∃ (a : Space n) (T : Space n ≃ₗ[ℝ] Space n),
    K = (fun x => a + T x) '' unitBall n

/-- The exact unrestricted inequality and its global equality characterization.
-/
theorem petty_projection_volume (n : ℕ) (hn : 4 ≤ n)
    (K : Set (Space n)) (hK : IsConvexBody K) :
    pettyConstant n ≤ projectionRatio K ∧
      (projectionRatio K = pettyConstant n ↔ IsEllipsoid K) := by
  sorry

end PettyProjection
end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/PettyProjectionVolume.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.PettyProjection.petty_projection_volume` must keep exactly the statement shown above: same names,
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
