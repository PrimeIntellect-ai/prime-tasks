# openai/math challenge `CoulombIonization` (family 263)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 263 of the release, *The ionization and generalized ionization conjectures*
(Mathematical physics). The family as a whole: For the full nonrelativistic Coulomb model with two electron spin states, proves that a molecule with $M$ fixed nuclei of charges at least one and total charge $Z$ strictly binds at most $Z+CM$ electrons. Neutral-atom first ionization energies and radii containing all but an expected half-electron have universal positive upper and lower bounds. The energy cost of removing $m$ electrons has Thomas–Fermi asymptotics as $m\to\infty$ and $Z/m\to\infty$; neutral-atom outer radii have the corresponding iterated-limit asymptotics, taking $Z\to\infty$ first.

The challenge is `CoulombIonization`, also at `/opt/openai-math/challenges/CoulombIonization.lean`:

```lean
import Mathlib

namespace OAI

open MeasureTheory Filter
open scoped Topology BigOperators ContDiff

noncomputable section
namespace CoulombAtom

abbrev Space := EuclideanSpace ℝ (Fin 3)
abbrev Configuration (N : ℕ) := Fin N → Space
abbrev Spins (N : ℕ) := Fin N → Fin 2

structure FormVector (N : ℕ) where
  value : Spins N → Configuration N → ℂ
  gradient : Spins N → Fin N → Fin 3 → Configuration N → ℂ

def direction {N : ℕ} (i : Fin N) (a : Fin 3) : Configuration N :=
  Pi.single i (EuclideanSpace.single a 1)

def FormAdmissible {N : ℕ} (ψ : FormVector N) : Prop :=
  (∀ s, MemLp (ψ.value s) 2) ∧
  (∀ s i a, MemLp (ψ.gradient s i a) 2) ∧
  (∀ s i a (φ : Configuration N → ℝ),
    ContDiff ℝ ∞ φ → HasCompactSupport φ →
    (∫ x, ψ.value s x * Complex.ofReal (lineDeriv ℝ φ x (direction i a))) =
      -(∫ x, ψ.gradient s i a x * (φ x : ℂ))) ∧
  (∀ (π : Equiv.Perm (Fin N)) s, ∀ᵐ x,
    ψ.value (s ∘ π) (x ∘ π) =
      (((Equiv.Perm.sign π : ℤ) : ℂ) * ψ.value s x)) ∧
  (∑ s : Spins N, ∫ x, ‖ψ.value s x‖ ^ 2) = 1 ∧
  (∀ s i, Integrable (fun x => ‖ψ.value s x‖ ^ 2 / ‖x i‖)) ∧
  (∀ s i j, i ≠ j →
    Integrable (fun x => ‖ψ.value s x‖ ^ 2 / ‖x i - x j‖))

def formEnergy {N : ℕ} (Z : ℝ) (ψ : FormVector N) : ℝ :=
  (1 / 2 : ℝ) *
      (∑ s : Spins N, ∑ i : Fin N, ∑ a : Fin 3,
        (∫ x, ‖ψ.gradient s i a x‖ ^ 2)) -
    Z * (∑ s : Spins N, ∑ i : Fin N,
      (∫ x, ‖ψ.value s x‖ ^ 2 / ‖x i‖)) +
    (∑ s : Spins N, ∑ i : Fin N, ∑ j : Fin N,
      if i < j then (∫ x, ‖ψ.value s x‖ ^ 2 / ‖x i - x j‖) else 0)

def energy (Z : ℝ) (N : ℕ) : ℝ :=
  if N = 0 then 0 else sInf {e | ∃ ψ : FormVector N,
    FormAdmissible ψ ∧ formEnergy Z ψ = e}

def ionization (m Z : ℕ) : ℝ :=
  energy Z (Z - m) - energy Z Z

def tfKinetic : ℝ := (3 / 10 : ℝ) * (3 * Real.pi ^ 2) ^ (2 / 3 : ℝ)

def directIntegrand (ρ : Space → ℝ) (p : Space × Space) : ℝ :=
  ρ p.1 * ρ p.2 / ‖p.1 - p.2‖

def TFAdmissible (M : ℝ) (ρ : Space → ℝ) : Prop :=
  (∀ᵐ x, 0 ≤ ρ x) ∧ Integrable ρ ∧ (∫ x, ρ x) = M ∧
  Integrable (fun x => ρ x ^ (5 / 3 : ℝ)) ∧
  Integrable (fun x => ρ x / ‖x‖) ∧ Integrable (directIntegrand ρ)

def tfFunctional (Z : ℝ) (ρ : Space → ℝ) : ℝ :=
  tfKinetic * (∫ x, ρ x ^ (5 / 3 : ℝ)) - Z * (∫ x, ρ x / ‖x‖) +
    (1 / 2 : ℝ) * ∫ p, directIntegrand ρ p

def tfEnergy (Z M : ℝ) : ℝ :=
  sInf {e | ∃ ρ : Space → ℝ, TFAdmissible M ρ ∧ tfFunctional Z ρ = e}

def tfIonization (m Z : ℝ) : ℝ := tfEnergy Z (Z - m) - tfEnergy Z Z

def TFCharacterization (a : ℝ) : Prop :=
  ∀ m : ℝ, 0 < m →
    Tendsto (tfIonization m) atTop (𝓝 (a * m ^ (7 / 3 : ℝ)))

def JointLimit (a : ℝ) : Prop :=
  ∀ m Z : ℕ → ℕ, (∀ j, 1 ≤ m j ∧ m j < Z j) →
    Tendsto m atTop atTop →
    Tendsto (fun j => (Z j : ℝ) / (m j : ℝ)) atTop atTop →
    Tendsto (fun j => ionization (m j) (Z j) / (m j : ℝ) ^ (7 / 3 : ℝ))
      atTop (𝓝 a)

def IteratedLimits (a : ℝ) : Prop :=
  Tendsto (fun m : ℕ => (limsup (ionization m) atTop) / (m : ℝ) ^ (7 / 3 : ℝ))
    atTop (𝓝 a) ∧
  Tendsto (fun m : ℕ => (liminf (ionization m) atTop) / (m : ℝ) ^ (7 / 3 : ℝ))
    atTop (𝓝 a)

def MainStatement : Prop :=
  ∃ a : ℝ, 0 < a ∧ TFCharacterization a ∧ JointLimit a ∧ IteratedLimits a

theorem generalized_ionization : MainStatement := by
  sorry

end CoulombAtom

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/CoulombIonization.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.CoulombAtom.generalized_ionization` must keep exactly the statement shown above: same names,
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
