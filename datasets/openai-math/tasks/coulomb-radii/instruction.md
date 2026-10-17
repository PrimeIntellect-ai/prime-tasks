# openai/math challenge `CoulombRadii` (family 263)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 263 of the release, *The ionization and generalized ionization conjectures*
(Mathematical physics). The family as a whole: For the full nonrelativistic Coulomb model with two electron spin states, proves that a molecule with $M$ fixed nuclei of charges at least one and total charge $Z$ strictly binds at most $Z+CM$ electrons. Neutral-atom first ionization energies and radii containing all but an expected half-electron have universal positive upper and lower bounds. The energy cost of removing $m$ electrons has Thomas–Fermi asymptotics as $m\to\infty$ and $Z/m\to\infty$; neutral-atom outer radii have the corresponding iterated-limit asymptotics, taking $Z\to\infty$ first.

The challenge is `CoulombRadii`, also at `/opt/openai-math/challenges/CoulombRadii.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

open MeasureTheory Filter
open scoped BigOperators Topology ContDiff

namespace NeutralAtom

abbrev Position := EuclideanSpace ℝ (Fin 3)
abbrev Configuration (n : ℕ) := Fin n → Position
abbrev Spins (n : ℕ) := Fin n → Fin 2
abbrev Wavefunction (n : ℕ) := Spins n → Configuration n → ℂ
abbrev Gradient (n : ℕ) := Spins n → Fin n → Fin 3 → Configuration n → ℂ

def coordinateDirection {n : ℕ} (i : Fin n) (a : Fin 3) : Configuration n :=
  Pi.single i (EuclideanSpace.single a 1)

def HasWeakGradient {n : ℕ} (ψ : Wavefunction n) (g : Gradient n) : Prop :=
  ∀ σ i a (φ : Configuration n → ℝ), ContDiff ℝ ∞ φ → HasCompactSupport φ →
    (∫ x, (fderiv ℝ φ x (coordinateDirection i a) : ℂ) * ψ σ x) =
      -(∫ x, (φ x : ℂ) * g σ i a x)

def IsAntisymmetric {n : ℕ} (ψ : Wavefunction n) : Prop :=
  ∀ (p : Equiv.Perm (Fin n)) (σ : Spins n),
    (fun x : Configuration n => ψ (σ ∘ p) (x ∘ p)) =ᵐ[volume]
      (fun x => (((Equiv.Perm.sign p : ℤ) : ℂ)) * ψ σ x)

def FormDomain {n : ℕ} (ψ : Wavefunction n) (g : Gradient n) : Prop :=
  IsAntisymmetric ψ ∧ HasWeakGradient ψ g ∧
  (∀ σ, MemLp (ψ σ) 2 volume) ∧
  (∀ σ i a, MemLp (g σ i a) 2 volume) ∧
  (∀ σ i, Integrable (fun x : Configuration n => ‖x i‖⁻¹ * ‖ψ σ x‖ ^ 2)) ∧
  (∀ σ i j, i < j →
    Integrable (fun x : Configuration n => ‖x i - x j‖⁻¹ * ‖ψ σ x‖ ^ 2))

def normSquared {n : ℕ} (ψ : Wavefunction n) : ℝ :=
  ∑ σ : Spins n, ∫ x : Configuration n, ‖ψ σ x‖ ^ 2

def coulombPotential {n : ℕ} (Z : ℕ) (x : Configuration n) : ℝ :=
  -(Z : ℝ) * (∑ i : Fin n, ‖x i‖⁻¹) +
    ∑ i : Fin n, ∑ j ∈ Finset.univ.filter (fun j : Fin n => i < j), ‖x i - x j‖⁻¹

def energy {n : ℕ} (Z : ℕ) (ψ : Wavefunction n) (g : Gradient n) : ℝ :=
  (1 / 2 : ℝ) * (∑ σ : Spins n, ∑ i : Fin n, ∑ a : Fin 3,
    ∫ x : Configuration n, ‖g σ i a x‖ ^ 2) +
  ∑ σ : Spins n, ∫ x : Configuration n, coulombPotential Z x * ‖ψ σ x‖ ^ 2

def IsNormalizedGroundState (Z : ℕ) (ψ : Wavefunction Z) : Prop :=
  ∃ g : Gradient Z, FormDomain ψ g ∧ normSquared ψ = 1 ∧
    ∀ (χ : Wavefunction Z) (h : Gradient Z),
      FormDomain χ h → normSquared χ = 1 → energy Z ψ g ≤ energy Z χ h

def density {N : ℕ} (ψ : Wavefunction (N + 1)) (x : Position) : ℝ :=
  (N + 1 : ℝ) * ∑ σ : Spins (N + 1),
    ∫ y : Configuration N, ‖ψ σ (Fin.cons x y)‖ ^ 2

def exteriorMass {N : ℕ} (ψ : Wavefunction (N + 1)) (r : ℝ) : ℝ :=
  ∫ x in {x : Position | r < ‖x‖}, density ψ x

def radius {N : ℕ} (ψ : Wavefunction (N + 1)) (m : ℕ) : ℝ :=
  sInf {r : ℝ | 0 ≤ r ∧ exteriorMass ψ r ≤ (m : ℝ)}

def bTF : ℝ := (81 * Real.pi ^ 2 / 2) ^ (1 / 3 : ℝ)

def largeCharge (m : ℕ) : Filter ℕ :=
  atTop ⊓ Filter.principal {N : ℕ | m < N + 1}

def upperRadius (Ψ : ∀ N : ℕ, Wavefunction (N + 1)) (m : ℕ) : EReal :=
  Filter.limsup (fun N : ℕ => (radius (Ψ N) m : EReal)) (largeCharge m)

def lowerRadius (Ψ : ∀ N : ℕ, Wavefunction (N + 1)) (m : ℕ) : EReal :=
  Filter.liminf (fun N : ℕ => (radius (Ψ N) m : EReal)) (largeCharge m)

theorem generalized_outer_radii
    (Ψ : ∀ N : ℕ, Wavefunction (N + 1))
    (hΨ : ∀ N : ℕ, IsNormalizedGroundState (N + 1) (Ψ N)) :
    Tendsto (fun m : ℕ => (((m : ℝ) ^ (1 / 3 : ℝ) : ℝ) : EReal) * upperRadius Ψ m)
      atTop (𝓝 (bTF : EReal)) ∧
    Tendsto (fun m : ℕ => (((m : ℝ) ^ (1 / 3 : ℝ) : ℝ) : EReal) * lowerRadius Ψ m)
      atTop (𝓝 (bTF : EReal)) := by
  sorry

end NeutralAtom
end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/CoulombRadii.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.NeutralAtom.generalized_outer_radii` must keep exactly the statement shown above: same names,
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
