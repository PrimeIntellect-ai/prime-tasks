# openai/math challenge `IsometricImmersion` (family 334)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 334 of the release, *A smooth surface metric with no local immersion in $\mathbb R^3$*
(Differential geometry). The family as a whole: Constructs a smooth positive-definite metric on $(-1,1)^2$ for which no neighborhood of the origin admits a smooth isometric immersion into $\mathbb R^3$. This answers the unrestricted smooth local isometric realization problem for surfaces negatively, even after shrinking the neighborhood.

The challenge is `IsometricImmersion`, also at `/opt/openai-math/challenges/IsometricImmersion.lean`:

```lean
import Mathlib.Analysis.InnerProductSpace.Calculus
import Mathlib.LinearAlgebra.Matrix.PosDef
import Mathlib.LinearAlgebra.Matrix.NonsingularInverse
import Mathlib.Geometry.Manifold.ContMDiff.NormedSpace
import Mathlib.Geometry.Manifold.MFDeriv.FDeriv

namespace OAI

noncomputable section
open Set TopologicalSpace
open scoped ContDiff Topology Manifold Matrix

namespace SmoothLocal.Geometry

abbrev Coord := Fin 2 → ℝ

abbrev Ambient := EuclideanSpace ℝ (Fin 3)

def square : Set Coord := {p | ∀ i, p i ∈ Set.Ioo (-1 : ℝ) 1}

def LocalSmoothPositive (U : Opens Coord)
    (g : U → Matrix (Fin 2) (Fin 2) ℝ) : Prop :=
  (∀ i j, ContMDiff 𝓘(ℝ, Coord) 𝓘(ℝ, ℝ) ∞ (fun p => g p i j)) ∧
    ∀ p, (g p).PosDef

end SmoothLocal.Geometry

namespace SmoothLocal.ODE
open SmoothLocal.Geometry

theorem coordinate_square_isOpen : IsOpen square := by
  have heq : square = ⋂ i : Fin 2,
      (fun p : Coord => p i) ⁻¹' Ioo (-1 : ℝ) 1 := by
    ext p
    simp [square]
  rw [heq]
  exact isOpen_iInter_of_finite (fun i => isOpen_Ioo.preimage (continuous_apply i))

end SmoothLocal.ODE

namespace SmoothLocal.Geometry

def coordinateSquareOpen : Opens Coord :=
  ⟨square, SmoothLocal.ODE.coordinate_square_isOpen⟩

theorem exists_local_metric_without_local_immersion :
    ∃ g : coordinateSquareOpen → Matrix (Fin 2) (Fin 2) ℝ,
      LocalSmoothPositive coordinateSquareOpen g ∧
      ∀ U : Opens Coord, ∀ hUS : (U : Set Coord) ⊆ square,
        (0 : Coord) ∈ U → ∀ F : U → Ambient,
          ¬ (ContMDiff 𝓘(ℝ, Coord) 𝓘(ℝ, Ambient) ∞ F ∧
            ∀ p : U, ∀ v w : Coord,
              (inner ℝ : Ambient → Ambient → ℝ) (mfderiv 𝓘(ℝ, Coord) 𝓘(ℝ, Ambient) F p v)
                (mfderiv 𝓘(ℝ, Coord) 𝓘(ℝ, Ambient) F p w) =
                  v ⬝ᵥ (g ⟨p, hUS p.property⟩ *ᵥ w)) := by
  sorry

end SmoothLocal.Geometry

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/IsometricImmersion.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.SmoothLocal.Geometry.exists_local_metric_without_local_immersion` must keep exactly the statement shown above: same names,
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
