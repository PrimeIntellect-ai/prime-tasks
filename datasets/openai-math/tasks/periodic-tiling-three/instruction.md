# openai/math challenge `PeriodicTilingThree` (family 155)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 155 of the release, *A counterexample to periodic tiling in dimension three*
(Combinatorics). The family as a whole: Constructs a finite translational tile in $\mathbb Z^3$ that tiles space but admits no fully periodic tiling, disproving the periodic tiling conjecture in the smallest possible lattice dimension. Its unit-cube thickening gives the same counterexample in $\mathbb R^3$, even with arbitrary real translation vectors.

The challenge is `PeriodicTilingThree`, also at `/opt/openai-math/challenges/PeriodicTilingThree.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

universe u

namespace PeriodicTilingThree

abbrev Lattice (d : ℕ) := Fin d → ℤ

variable {G : Type u} [AddCommGroup G]

def Tiles (F : Finset G) (A : Set G) : Prop :=
  Function.Bijective (fun p : ↥F × A => (p.1 : G) + (p.2 : G))

def Period (A : Set G) (v : G) : Prop :=
  ∀ x : G, x + v ∈ A ↔ x ∈ A

def FullyPeriodic (A : Set G) : Prop :=
  ∃ P : AddSubgroup G, P.FiniteIndex ∧ ∀ v ∈ P, Period A v

open MeasureTheory

abbrev Space (d : ℕ) := Fin d → ℝ

def castLattice {d : ℕ} : Lattice d →+ Space d where
  toFun z i := (z i : ℝ)
  map_zero' := by ext i; simp
  map_add' z w := by ext i; simp

def unitCube (d : ℕ) : Set (Space d) := Set.Icc 0 1

def Thickening {d : ℕ} (F : Finset (Lattice d)) : Set (Space d) :=
  {x | ∃ z ∈ F, x - castLattice z ∈ unitCube d}

def AETiles {d : ℕ} (Ω A : Set (Space d)) : Prop :=
  ∀ᵐ x ∂volume, ∃! a : A, x - (a : Space d) ∈ Ω

def latticeOfBasis {d : ℕ} (b : Module.Basis (Fin d) ℝ (Space d)) :
    AddSubgroup (Space d) := (Submodule.span ℤ (Set.range b)).toAddSubgroup

def EuclideanFullyPeriodic {d : ℕ} (A : Set (Space d)) : Prop :=
  ∃ b : Module.Basis (Fin d) ℝ (Space d), ∀ v ∈ latticeOfBasis b, Period A v

def HasTileWithoutPeriodicComplement (d : ℕ) : Prop :=
  ∃ T : Finset (Lattice d), T.Nonempty ∧
    (∃ A : Set (Lattice d), Tiles T A) ∧
    ∀ A : Set (Lattice d), Tiles T A → ¬ FullyPeriodic A

theorem periodic_tiling_counterexample_and_minimality :
    (∃ T : Finset (Lattice 3), T.Nonempty ∧
      (∃ A : Set (Lattice 3), Tiles T A) ∧
      (∀ A : Set (Lattice 3), Tiles T A → ¬ FullyPeriodic A) ∧
      (∃ A : Set (Space 3), AETiles (Thickening T) A) ∧
      (∀ A : Set (Space 3),
        AETiles (Thickening T) A → ¬ EuclideanFullyPeriodic A)) ∧
    IsLeast {d : ℕ | HasTileWithoutPeriodicComplement d} 3 := by
  sorry

end PeriodicTilingThree

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/PeriodicTilingThree.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.PeriodicTilingThree.periodic_tiling_counterexample_and_minimality` must keep exactly the statement shown above: same names,
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
