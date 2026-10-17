# openai/math challenge `ArtinCAT0` (family 254)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 254 of the release, *Classifying spaces and geometric obstructions for Artin groups*
(Group theory). The family as a whole: The Salvetti complex of every finite-rank Artin group is aspherical, proving the Artin $K(\pi,1)$ conjecture. Arbitrary intersections of its parabolic subgroups are parabolic, proving the Parabolic Intersection Conjecture. An explicit Artin group admits no proper cocompact isometric action on any nonempty proper CAT$(0)$ space.

The challenge is `ArtinCAT0`, also at `/opt/openai-math/challenges/ArtinCAT0.lean`:

```lean
import Mathlib

namespace OAI

namespace ArtinCAT0

universe uS uG uX

abbrev Letters := Fin 116
abbrev Label := WithTop ℕ

def blockLetter (b : Fin 3) (i : Fin 39) : Letters :=
  if h₀ : i.val = 0 then ⟨b.val, by omega⟩
  else if h₁ : i.val = 1 then ⟨(b.val + 1) % 3, by omega⟩
  else ⟨5 + 37 * b.val + (i.val - 2), by omega⟩

def Adjacent (s t : Letters) : Prop :=
  ∃ (b : Fin 3) (i j : Fin 39), s = blockLetter b i ∧ t = blockLetter b j ∧
    (i.val + 1 = j.val ∨ j.val + 1 = i.val)

def Distant (s t : Letters) : Prop :=
  ∃ (b : Fin 3) (i j : Fin 39), s = blockLetter b i ∧ t = blockLetter b j ∧
    (i.val + 2 ≤ j.val ∨ j.val + 2 ≤ i.val)

def Sentinel (s t : Letters) : Prop :=
  ((s.val = 3 ∨ s.val = 4) ∧ t.val < 3) ∨
  ((t.val = 3 ∨ t.val = 4) ∧ s.val < 3)

noncomputable def explicitMatrix (s t : Letters) : Label := by
  classical
  exact if s = t then 1 else if Adjacent s t then 3
    else if Distant s t ∨ Sentinel s t then 2 else ⊤

def alternating {S : Type uS} (s t : S) : ℕ → FreeGroup S
  | 0 => 1
  | n + 1 => FreeGroup.of s * alternating t s n

def artinRelators {S : Type uS} (M : S → S → Label) : Set (FreeGroup S) :=
  {w | ∃ (s t : S) (n : ℕ), M s t = (n : Label) ∧
    w = alternating s t n * (alternating t s n)⁻¹}

abbrev ArtinGroup {S : Type uS} (M : S → S → Label) := PresentedGroup (artinRelators M)

def Segment {X : Type uX} [MetricSpace X] (x y : X) (γ : ℝ → X) : Prop :=
  γ 0 = x ∧ γ 1 = y ∧
    ∀ s ∈ Set.Icc (0 : ℝ) 1, ∀ t ∈ Set.Icc (0 : ℝ) 1,
      dist (γ s) (γ t) = |s - t| * dist x y

def CAT0 (X : Type uX) [MetricSpace X] : Prop :=
  (∀ x y : X, ∃ γ : ℝ → X, Segment x y γ) ∧
  ∀ (x y z : X) (γ η : ℝ → X), Segment x y γ → Segment x z η →
    ∀ t ∈ Set.Icc (0 : ℝ) 1, ∀ u ∈ Set.Icc (0 : ℝ) 1,
      dist (γ t) (η u) ^ 2 ≤
        (t ^ 2 - t * u) * dist x y ^ 2 +
        (u ^ 2 - t * u) * dist x z ^ 2 + t * u * dist y z ^ 2

def GeometricAction (G : Type uG) (X : Type uX) [Group G] [MetricSpace X] [MulAction G X] : Prop :=
  CAT0 X ∧
  (∀ g : G, Isometry (fun x : X => g • x)) ∧
  (∀ K : Set X, IsCompact K → {g : G | ((fun x : X => g • x) '' K ∩ K).Nonempty}.Finite) ∧
  ∃ K : Set X, IsCompact K ∧ ∀ x : X, ∃ g : G, ∃ k ∈ K, g • k = x

universe u

theorem main :
    (∀ s t : Letters, explicitMatrix s t = explicitMatrix t s) ∧
    (∀ s : Letters, explicitMatrix s s = 1) ∧
    (∀ s t : Letters, s ≠ t →
      explicitMatrix s t = 2 ∨ explicitMatrix s t = 3 ∨ explicitMatrix s t = ⊤) ∧
    (∀ (X : Type u) [MetricSpace X] [ProperSpace X] [Nonempty X]
      [MulAction (ArtinGroup explicitMatrix) X],
      ¬ GeometricAction (ArtinGroup explicitMatrix) X) := by
  sorry

end ArtinCAT0

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/ArtinCAT0.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.ArtinCAT0.main` must keep exactly the statement shown above: same names,
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
