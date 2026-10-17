# openai/math challenge `BalancedBoxRouting` (family 376)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 376 of the release, *Universal computation in forced Navier–Stokes flows*
(Partial differential equations). The family as a whole: Constructs viscous incompressible flows starting from rest on a fixed flat three-dimensional domain that perform universal computation under smooth external forcing. A terminating compiler turns a Turing machine and input into a finite program for the force, so a designated particle reaches a fixed region exactly when the machine halts. The viscosity is fixed, positive and computable.

The challenge is `BalancedBoxRouting`, also at `/opt/openai-math/challenges/BalancedBoxRouting.lean`:

```lean
import Mathlib

namespace OAI

open scoped BigOperators ContDiff

namespace BoxTransport.Routing

abbrev Space := Fin 3 → ℝ
abbrev RationalSpace := Fin 3 → ℚ
abbrev SpaceTime := ℝ × Space
abbrev RationalSpaceTime := ℚ × RationalSpace
abbrev Field := SpaceTime → Space

abbrev Axis := Option (Fin 3)

def coordinateVector (j : Fin 3) : Space := Pi.single j 1

def coordinateDirection : Axis → SpaceTime
  | none => (1, 0)
  | some j => (0, coordinateVector j)

def realPoint (q : RationalSpace) : Space := fun j => (q j : ℝ)

def realSpaceTime (q : RationalSpaceTime) : SpaceTime := (q.1, realPoint q.2)

def realBox (c r : Space) : Set Space :=
  {x | ∀ j, |x j - c j| ≤ r j}

def solidBox (a h : RationalSpace) : Set Space :=
  realBox (realPoint a) (realPoint h)

def prescribedAffine (a b h k : RationalSpace) (x : Space) : Space :=
  fun j => (b j : ℝ) + ((k j / h j : ℚ) : ℝ) * (x j - (a j : ℝ))

noncomputable def mixedDerivative : List Axis → Field → Field
  | [], U => U
  | j :: js, U => fun p => fderiv ℝ (mixedDerivative js U) p (coordinateDirection j)

abbrev RationalCode := ℕ × ℕ × ℕ

def rationalValue (q : RationalCode) : ℚ := ((q.1 : ℚ) - q.2.1) / (q.2.2 + 1)

abbrev RationalPointCode := RationalCode × RationalCode × RationalCode × RationalCode

def codeSpaceTime (q : RationalPointCode) : SpaceTime :=
  ((rationalValue q.1 : ℝ), ![(rationalValue q.2.1 : ℝ),
    (rationalValue q.2.2.1 : ℝ), (rationalValue q.2.2.2 : ℝ)])

abbrev EvaluationRequest := List Axis × RationalPointCode × ℕ × Fin 3

def Effective (U : Field) : Prop :=
  ∃ eval : EvaluationRequest → RationalCode,
    ∃ modulus : List Axis × ℕ → ℕ,
      ∃ bound : List Axis → ℕ,
        Computable eval ∧ Computable modulus ∧ Computable bound ∧
        (∀ (ds : List Axis) (q : RationalPointCode) (n : ℕ) (p : SpaceTime),
          ‖p - codeSpaceTime q‖ ≤ ((modulus (ds, n) : ℝ) + 1)⁻¹ →
          ∀ j : Fin 3,
            |mixedDerivative ds U p j - (rationalValue (eval (ds, q, n, j)) : ℝ)| ≤
              ((n : ℝ) + 1)⁻¹) ∧
        (∀ (ds : List Axis) (p : SpaceTime) (j : Fin 3),
          |mixedDerivative ds U p j| ≤ (bound ds : ℝ))

noncomputable def spatialDivergence (U : Field) (t : ℝ) (x : Space) : ℝ :=
  ∑ j : Fin 3, (fderiv ℝ (fun y => U (t, y)) x (coordinateVector j)) j

def AdmissibleField (U : Field) : Prop :=
  ContDiff ℝ ∞ U ∧ HasCompactSupport U ∧ Effective U ∧
    (∀ t x, spatialDivergence U t x = 0) ∧
    (∀ (t : ℝ) (x : Space), t ∉ Set.Icc (1 / 4 : ℝ) (3 / 4 : ℝ) → U (t, x) = 0)

def IsGlobalFlow (U : Field) (Φ : ℝ → Space → Space) : Prop :=
  (∀ x, Φ 0 x = x) ∧
    (∀ t x, HasDerivAt (fun s => Φ s x) (U (t, Φ t x)) t) ∧
    (∀ (x : Space) (γ : ℝ → Space), γ 0 = x →
      (∀ t, HasDerivAt γ (U (t, γ t)) t) → ∀ t, γ t = Φ t x)

def Delivers {n : ℕ} (a b h k : Fin n → RationalSpace)
    (Φ : ℝ → Space → Space) : Prop :=
  ∀ i, ∃ O : Set Space, IsOpen O ∧ solidBox (a i) (h i) ⊆ O ∧
    ∀ x ∈ O, Φ 1 x = prescribedAffine (a i) (b i) (h i) (k i) x

theorem balanced_box_routing
    (n : ℕ) (a b h k : Fin n → RationalSpace)
    (hh : ∀ i j, 0 < h i j) (hk : ∀ i j, 0 < k i j)
    (ha : Pairwise fun i j => Disjoint (solidBox (a i) (h i)) (solidBox (a j) (h j)))
    (hb : Pairwise fun i j => Disjoint (solidBox (b i) (k i)) (solidBox (b j) (k j)))
    (hvol : ∀ i, ∏ j : Fin 3, k i j / h i j = 1) :
    ∃ U : Field, ∃ Φ : ℝ → Space → Space,
      AdmissibleField U ∧ IsGlobalFlow U Φ ∧ Delivers a b h k Φ := by
  sorry

end BoxTransport.Routing

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/BalancedBoxRouting.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.BoxTransport.Routing.balanced_box_routing` must keep exactly the statement shown above: same names,
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
