# openai/math challenge `VlasovMaxwell` (family 362)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 362 of the release, *Global smoothness for relativistic Vlasov–Maxwell*
(Partial differential equations). The family as a whole: Proves large-data global existence and uniqueness for the three-dimensional, one-species relativistic Vlasov–Maxwell system. Smooth admissible initial data may be arbitrary provided the particle density is compactly supported and the electromagnetic fields have finite energy and bounded derivatives of every order; the solution remains smooth on every finite time interval.

The challenge is `VlasovMaxwell`, also at `/opt/openai-math/challenges/VlasovMaxwell.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open MeasureTheory Set
open scoped ContDiff
namespace RVM

abbrev Vec := EuclideanSpace ℝ (Fin 3)
abbrev Phase := Vec × Vec
abbrev Particle := ℝ × Phase → ℝ
abbrev Field := ℝ × Vec → Vec

def q (v : Vec) : ℝ := Real.sqrt (1 + ‖v‖ ^ 2)
def velocity (v : Vec) : Vec := (q v)⁻¹ • v

def basis (i : Fin 3) : Vec := WithLp.toLp 2 (Pi.single i (1 : ℝ))
def dot (a b : Vec) : ℝ := ∑ i : Fin 3, a i * b i
def cross (a b : Vec) : Vec := WithLp.toLp 2
  ![a 1 * b 2 - a 2 * b 1, a 2 * b 0 - a 0 * b 2,
    a 0 * b 1 - a 1 * b 0]

def spatialPartial (g : Vec → ℝ) (x : Vec) (i : Fin 3) : ℝ :=
  fderiv ℝ g x (basis i)
def divergence (F : Vec → Vec) (x : Vec) : ℝ :=
  ∑ i : Fin 3, spatialPartial (fun y => F y i) x i

def curl (F : Vec → Vec) (x : Vec) : Vec := WithLp.toLp 2
  ![spatialPartial (fun y => F y 2) x 1 - spatialPartial (fun y => F y 1) x 2,
    spatialPartial (fun y => F y 0) x 2 - spatialPartial (fun y => F y 2) x 0,
    spatialPartial (fun y => F y 1) x 0 - spatialPartial (fun y => F y 0) x 1]

def rho (g : Phase → ℝ) (x : Vec) : ℝ := ∫ v : Vec, g (x, v)
def current (g : Phase → ℝ) (x : Vec) : Vec :=
  ∫ v : Vec, g (x, v) • velocity v

structure Datum where
  f₀ : Phase → ℝ
  E₀ : Vec → Vec
  B₀ : Vec → Vec

def BoundedSmooth (F : Vec → Vec) : Prop :=
  ContDiff ℝ ∞ F ∧ ∀ n : ℕ, ∃ C : ℝ, ∀ x : Vec,
    ‖iteratedFDeriv ℝ n F x‖ ≤ C

def Admissible (d : Datum) : Prop :=
  ContDiff ℝ ∞ d.f₀ ∧ HasCompactSupport d.f₀ ∧ (∀ z, 0 ≤ d.f₀ z) ∧
  BoundedSmooth d.E₀ ∧ BoundedSmooth d.B₀ ∧
  MemLp d.E₀ 2 volume ∧ MemLp d.B₀ 2 volume ∧
  (∀ x, divergence d.E₀ x = rho d.f₀ x) ∧
  (∀ x, divergence d.B₀ x = 0)

structure Solution where
  f : Particle
  E : Field
  B : Field

def particleHalfSpace : Set (ℝ × Phase) := {z | 0 ≤ z.1}
def fieldHalfSpace : Set (ℝ × Vec) := {z | 0 ≤ z.1}
def particleSlab (T : ℝ) : Set (ℝ × Phase) := {z | z.1 ∈ Icc 0 T}
def fieldSlab (T : ℝ) : Set (ℝ × Vec) := {z | z.1 ∈ Icc 0 T}

def TimeContinuousL2 (F : Field) : Prop :=
  ∃ F₂ : ℝ → Lp Vec 2 (volume : Measure Vec),
    ContinuousOn F₂ (Ici 0) ∧
    ∀ t, 0 ≤ t → (F₂ t : Vec → Vec) =ᵐ[volume] (fun x => F (t, x))

def Equations (s : Solution) : Prop := ∀ t, 0 ≤ t →
  (∀ x v,
    derivWithin (fun t' => s.f (t', x, v)) (Ici 0) t +
    (∑ i : Fin 3, velocity v i * spatialPartial (fun y => s.f (t, y, v)) x i) +
    (∑ i : Fin 3, (s.E (t, x) + cross (velocity v) (s.B (t, x))) i *
      spatialPartial (fun v' => s.f (t, x, v')) v i) = 0) ∧
  (∀ x, derivWithin (fun t' => s.E (t', x)) (Ici 0) t -
    curl (fun y => s.B (t, y)) x = -current (fun z => s.f (t, z)) x) ∧
  (∀ x, derivWithin (fun t' => s.B (t', x)) (Ici 0) t +
    curl (fun y => s.E (t, y)) x = 0) ∧
  (∀ x, divergence (fun y => s.E (t, y)) x = rho (fun z => s.f (t, z)) x) ∧
  (∀ x, divergence (fun y => s.B (t, y)) x = 0)

def CompactOnFiniteHorizons (s : Solution) : Prop :=
  ∀ T : ℝ, 0 ≤ T → ∃ K : Set Phase, IsCompact K ∧
    ∀ t ∈ Icc 0 T, tsupport (fun z => s.f (t, z)) ⊆ K

def Classical (d : Datum) (s : Solution) : Prop :=
  ContDiffOn ℝ 1 s.f particleHalfSpace ∧
  ContDiffOn ℝ 1 s.E fieldHalfSpace ∧ ContDiffOn ℝ 1 s.B fieldHalfSpace ∧
  (∀ t, 0 ≤ t → ∀ z, 0 ≤ s.f (t, z)) ∧
  TimeContinuousL2 s.E ∧ TimeContinuousL2 s.B ∧
  CompactOnFiniteHorizons s ∧ Equations s ∧
  (∀ z, s.f (0, z) = d.f₀ z) ∧
  (∀ x, s.E (0, x) = d.E₀ x) ∧ (∀ x, s.B (0, x) = d.B₀ x)

def SmoothOnFiniteHorizons (s : Solution) : Prop := ∀ T : ℝ, 0 ≤ T →
  ContDiffOn ℝ ∞ s.f (particleSlab T) ∧
  ContDiffOn ℝ ∞ s.E (fieldSlab T) ∧ ContDiffOn ℝ ∞ s.B (fieldSlab T)

def SameNonnegativeTime (s s' : Solution) : Prop := ∀ t, 0 ≤ t →
  (∀ z, s.f (t, z) = s'.f (t, z)) ∧
  (∀ x, s.E (t, x) = s'.E (t, x)) ∧ (∀ x, s.B (t, x) = s'.B (t, x))

theorem global_classical_solution (d : Datum) (hd : Admissible d) :
    ∃ s : Solution, Classical d s ∧ SmoothOnFiniteHorizons s ∧
      ∀ s' : Solution, Classical d s' → SameNonnegativeTime s s' := by
  sorry

end RVM

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/VlasovMaxwell.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.RVM.global_classical_solution` must keep exactly the statement shown above: same names,
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
