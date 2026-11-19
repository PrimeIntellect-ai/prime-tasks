# openai/math challenge `HeilbronnTriangle` (family 191)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 191 of the release, *A power improvement in the Heilbronn triangle problem*
(Combinatorics). The family as a whole: For every sufficiently large $n$, constructs $n$ points in the unit square such that every triangle has area at least $n^{-2+c}$ for one absolute $c>0$. This disproves the conjectured almost-$n^{-2}$ upper bound in Heilbronn's triangle problem, which asks how large the smallest determined triangle can be.

The challenge is `HeilbronnTriangle`, also at `/opt/openai-math/challenges/HeilbronnTriangle.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

namespace Problem355

abbrev Point := ℝ × ℝ

def triangleArea (p q r : Point) : ℝ :=
  abs ((q.1 - p.1) * (r.2 - p.2) - (q.2 - p.2) * (r.1 - p.1)) / 2

def pointInUnitSquare (p : Point) : Prop :=
  0 ≤ p.1 ∧ p.1 ≤ 1 ∧ 0 ≤ p.2 ∧ p.2 ≤ 1

def pointsInUnitSquare (P : Finset Point) : Prop := by
  classical
  exact ∀ p, p ∈ P → pointInUnitSquare p

def triangleAreasAtLeast (P : Finset Point) (a : ℝ) : Prop := by
  classical
  exact ∀ p, p ∈ P → ∀ q, q ∈ P → ∀ r, r ∈ P →
    p ≠ q → p ≠ r → q ≠ r → a ≤ triangleArea p q r

def hasTriangleAreaAtMost (P : Finset Point) (a : ℝ) : Prop := by
  classical
  exact ∃ p, p ∈ P ∧ ∃ q, q ∈ P ∧ ∃ r, r ∈ P ∧
    p ≠ q ∧ p ≠ r ∧ q ≠ r ∧ triangleArea p q r ≤ a

def heilbronnD : ℕ := 41

def heilbronnM : ℕ := Nat.choose (4 * heilbronnD - 1) heilbronnD

def heilbronnT : ℕ := Nat.choose heilbronnM 3

def heilbronnK : ℕ := heilbronnT ^ 2 + 1

def heilbronnExponent : ℝ :=
  1 / (100000 * (heilbronnK : ℝ))

def eventualAlmostUpperBound (epsilon : ℝ) : Prop :=
  ∃ C : ℝ, 0 < C ∧ ∃ n0 : ℕ, ∀ n : ℕ, n0 ≤ n → 3 ≤ n →
    ∀ P : Finset Point, P.card = n → pointsInUnitSquare P →
      hasTriangleAreaAtMost P
        (C * Real.rpow (n : ℝ) (-2 + epsilon))

attribute [local irreducible] Problem355.heilbronnT
  Problem355.heilbronnM

theorem heilbronn_power_lower_bound :
    0 < heilbronnExponent ∧ ∃ n : ℕ → ℕ, ∃ P : ℕ → Finset Point,
      Filter.Tendsto n Filter.atTop Filter.atTop ∧ ∀ j : ℕ,
        3 ≤ n j ∧ (P j).card = n j ∧ pointsInUnitSquare (P j) ∧
        triangleAreasAtLeast (P j)
          (Real.rpow (n j : ℝ) (-2 + heilbronnExponent)) := by
  sorry

theorem almost_n_minus_two_refuted :
    0 < heilbronnExponent / 2 ∧
      ¬ eventualAlmostUpperBound (heilbronnExponent / 2) := by
  sorry

end Problem355

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/HeilbronnTriangle.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorems `OAI.Problem355.heilbronn_power_lower_bound`, `OAI.Problem355.almost_n_minus_two_refuted` must keep exactly the statement shown above: same names,
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
