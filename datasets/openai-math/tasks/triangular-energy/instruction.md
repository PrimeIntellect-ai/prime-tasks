# openai/math challenge `TriangularEnergy` (family 090)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 090 of the release, *Universal optimality of the triangular lattice*
(Convex and metric geometry). The family as a whole: Proves that the triangular lattice minimizes the lower limit of energy per particle for every nonnegative completely monotone potential of squared distance among locally finite planar configurations of centered-disk density one. It also minimizes unit-background renormalized Riesz energies for $0<s<2$ and Coulomb energy, resolving Sandier–Serfaty and the two-dimensional Brauchart–Hardin–Saff conjecture on the linear term of optimal spherical logarithmic energy.

The challenge is `TriangularEnergy`, also at `/opt/openai-math/challenges/TriangularEnergy.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open scoped BigOperators Topology ENNReal
open Classical Filter

namespace TriangularUniversal

abbrev Plane := EuclideanSpace ℝ (Fin 2)

def LocallyFinite (C : Set Plane) : Prop :=
  ∀ R : ℝ, (C ∩ Metric.closedBall (0 : Plane) R).Finite

def diskPoints (C : Set Plane) (R : ℝ) : Finset Plane :=
  if h : (C ∩ Metric.closedBall (0 : Plane) R).Finite then h.toFinset else ∅

def diskCount (C : Set Plane) (R : ℝ) : ℕ := (diskPoints C R).card

def DensityOne (C : Set Plane) : Prop :=
  Tendsto (fun R : ℝ => (diskCount C R : ℝ) / (Real.pi * R ^ 2))
    atTop (𝓝 1)

def AdmissiblePotential (g : ℝ → ℝ) : Prop :=
  ContDiffOn ℝ (⊤ : ℕ∞) g (Set.Ioi 0) ∧
  (∀ t : ℝ, 0 < t → 0 ≤ g t) ∧
  ∀ (r : ℕ) (t : ℝ), 0 < t → 0 ≤ (-1 : ℝ) ^ r * iteratedDeriv r g t

def diskEnergy (g : ℝ → ℝ) (C : Set Plane) (R : ℝ) : ℝ≥0∞ :=
  (diskCount C R : ℝ≥0∞)⁻¹ *
    ∑ x ∈ diskPoints C R, ∑ y ∈ (diskPoints C R).erase x,
      ENNReal.ofReal (g (‖x - y‖ ^ 2))

def energy (g : ℝ → ℝ) (C : Set Plane) : ℝ≥0∞ :=
  Filter.liminf (diskEnergy g C) atTop

end TriangularUniversal

namespace AtomicTriangular

abbrev Plane := EuclideanSpace ℝ (Fin 2)

def b : ℝ := Real.sqrt 3 / 2

def triangularPoint (jk : ℤ × ℤ) : Plane :=
  (Real.sqrt b)⁻¹ •
    (EuclideanSpace.single 0 ((jk.1 : ℝ) + (jk.2 : ℝ) / 2) +
      EuclideanSpace.single 1 ((jk.2 : ℝ) * b))

def A : Set Plane := Set.range triangularPoint

abbrev LocallyFinite := TriangularUniversal.LocallyFinite
abbrev diskPoints := TriangularUniversal.diskPoints
abbrev diskCount := TriangularUniversal.diskCount
abbrev DensityOne := TriangularUniversal.DensityOne
abbrev AdmissiblePotential := TriangularUniversal.AdmissiblePotential
abbrev diskEnergy := TriangularUniversal.diskEnergy
abbrev energy := TriangularUniversal.energy

/-- The full nonzero-lattice energy, allowing a divergent series. -/
def latticeEnergy (g : ℝ → ℝ) : ℝ≥0∞ :=
  ∑' a : {x : Plane // x ∈ A ∧ x ≠ 0}, ENNReal.ofReal (g (‖a.val‖ ^ 2))

/-- Universal energy minimality for smooth completely monotone potentials, with attainment. -/
theorem universal_energy_minimum (g : ℝ → ℝ) (C : Set Plane)
    (hg : AdmissiblePotential g) (hC : LocallyFinite C) (hd : DensityOne C) :
    latticeEnergy g ≤ energy g C ∧ latticeEnergy g = energy g A := by
  sorry

end AtomicTriangular
end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/TriangularEnergy.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.AtomicTriangular.universal_energy_minimum` must keep exactly the statement shown above: same names,
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
