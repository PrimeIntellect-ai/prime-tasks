# openai/math challenge `ContinuumTransition` (family 228)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 228 of the release, *Continuum phase transitions for radial pair potentials*
(Probability and statistical mechanics). The family as a whole: Constructs stable distance-dependent pair interactions for three-dimensional classical particles with a first-order phase transition: the canonical free energy has a derivative jump at one inverse temperature throughout an open density interval. One potential has a divergent repulsive core; another is bounded and continuous with an integrable power-law tail, realizing the type of transition sought in Simon's continuum problem.

The challenge is `ContinuumTransition`, also at `/opt/openai-math/challenges/ContinuumTransition.lean`:

```lean
import Mathlib

namespace OAI

open scoped Topology BigOperators ENNReal
open Filter MeasureTheory Set

namespace ContinuumTemperature

abbrev Space := EuclideanSpace ℝ (Fin 3)

noncomputable def radialPotential (φ : ℝ → ℝ) (x : Space) : EReal :=
  if x = 0 then ⊤ else (φ ‖x‖ : EReal)

noncomputable def energy (φ : ℝ → ℝ) {N : ℕ} (x : Fin N → Space) : EReal :=
  ∑ i : Fin N, ∑ j ∈ Finset.univ.filter (fun j : Fin N => i < j),
    radialPotential φ (x i - x j)

def Admissible (φ : ℝ → ℝ) : Prop :=
  Measurable (radialPotential φ) ∧
  (∀ a b : ℝ, 0 < a → a ≤ b →
    BddAbove (φ '' Icc a b) ∧ BddBelow (φ '' Icc a b)) ∧
  Tendsto φ (𝓝[>] (0 : ℝ)) atTop ∧
  (∃ r₁ r₂ a : ℝ, 0 < r₁ ∧ r₁ < r₂ ∧ 0 < a ∧
    ∀ r ∈ Icc r₁ r₂, φ r ≤ -a) ∧
  (∃ R : ℝ, 0 < R ∧ IntegrableOn (fun r : ℝ => r ^ 2 * |φ r|) (Ioi R)) ∧
  (∃ B : ℝ, ∀ (N : ℕ) (x : Fin N → Space),
    ((-B * (N : ℝ) : ℝ) : EReal) ≤ energy φ x)

def cube (L : ℝ) : Set Space :=
  {x | ∀ i, x i ∈ Icc (-L / 2) (L / 2)}

noncomputable def boltzmann (φ : ℝ → ℝ) (β : ℝ) {N : ℕ}
    (x : Fin N → Space) : ℝ :=
  if energy φ x = ⊤ then 0 else Real.exp (-β * (energy φ x).toReal)

noncomputable def partition (φ : ℝ → ℝ) (β L : ℝ) (N : ℕ) : ℝ :=
  if N = 0 then 1 else
    (1 / (N.factorial : ℝ)) *
      ∫ x in {x : Fin N → Space | ∀ i, x i ∈ cube L}, boltzmann φ β x

def HasCanonicalFreeEnergy (φ : ℝ → ℝ) (f : ℝ → ℝ → ℝ) : Prop :=
  ∀ β ρ : ℝ, 0 < β → 0 < ρ →
    Tendsto (fun L : ℝ => L⁻¹ ^ 3 * Real.log (partition φ β L ⌊ρ * L ^ 3⌋₊))
      atTop (𝓝 (-β * f β ρ))

def MainStatement : Prop :=
  ∃ (φ : ℝ → ℝ) (f : ℝ → ℝ → ℝ) (I : Set ℝ) (βc : ℝ),
    Admissible φ ∧
    Asymptotics.IsLittleO atTop φ (fun r : ℝ => r ^ (-3 : ℤ)) ∧
    HasCanonicalFreeEnergy φ f ∧
    IsOpen I ∧ OrdConnected I ∧ I.Nonempty ∧ I ⊆ Ioi 0 ∧
    βc ∈ Ioo (1 / 2 : ℝ) (3 / 2 : ℝ) ∧
    ∀ ρ ∈ I, ∃ dminus dplus : ℝ,
      HasDerivWithinAt (fun β => f β ρ) dminus (Iic βc) βc ∧
      HasDerivWithinAt (fun β => f β ρ) dplus (Ici βc) βc ∧
      dplus < dminus

theorem main_theorem : MainStatement := by
  sorry

end ContinuumTemperature

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/ContinuumTransition.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.ContinuumTemperature.main_theorem` must keep exactly the statement shown above: same names,
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
