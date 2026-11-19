# openai/math challenge `KLInvariance` (family 168)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 168 of the release, *Combinatorial invariance of Kazhdan–Lusztig polynomials*
(Combinatorics). The family as a whole: Resolves the full combinatorial invariance conjecture: isomorphic Bruhat intervals in arbitrary Coxeter systems have identical equal-parameter Kazhdan–Lusztig polynomials. Thus the abstract order of the interval determines the polynomial, even across different Coxeter systems.

The challenge is `KLInvariance`, also at `/opt/openai-math/challenges/KLInvariance.lean`:

```lean
import Mathlib

namespace OAI

namespace KLInvariance

open Polynomial

universe u v u' v'

variable {B : Type u} {W : Type v} [Group W] {M : CoxeterMatrix B}

/-- An upward edge in the *strong* Bruhat graph, with left reflection labels. -/
def BruhatStep (cs : CoxeterSystem M W) (x y : W) : Prop :=
  cs.length x < cs.length y ∧ ∃ t : W, cs.IsReflection t ∧ y = t * x

/-- The actual strong Bruhat order, not the weak order. -/
def BruhatLE (cs : CoxeterSystem M W) : W → W → Prop :=
  Relation.ReflTransGen (BruhatStep cs)

/-- The unlabelled interval, including both endpoints. -/
def Interval (cs : CoxeterSystem M W) (u b : W) :=
  {x : W // BruhatLE cs u x ∧ BruhatLE cs x b}

instance intervalOrder (cs : CoxeterSystem M W) (u b : W) :
    PartialOrder (Interval cs u b) where
  le left right := BruhatLE cs left.val right.val
  le_refl _ := Relation.ReflTransGen.refl
  le_trans _ _ _ forward backward := forward.trans backward
  le_antisymm left right forward backward := by
    apply Subtype.ext
    have length_mono : ∀ {lower upper : W}, BruhatLE cs lower upper →
        cs.length lower ≤ cs.length upper := by
      intro lower upper relation
      induction relation using Relation.ReflTransGen.head_induction_on with
      | refl => exact le_rfl
      | head step _ rest => exact le_trans step.1.le rest
    by_contra distinct
    rcases forward.cases_head with same | ⟨middle, step, rest⟩
    · exact distinct same
    · exact (not_lt_of_ge (length_mono backward))
        (lt_of_lt_of_le step.1 (length_mono rest))

/-- `d(x,y)` in the manuscript, used only for comparable endpoints. -/
noncomputable def rankDifference (cs : CoxeterSystem M W) (x y : W) : ℕ :=
  cs.length y - cs.length x

abbrev PolynomialFamilies (W : Type v) := (W → W → ℤ[X]) × (W → W → ℤ[X])

/-- Exact equal-parameter normalization in the introduction.
The first family is R and the second is P.  `reflect d p` is `q^d p(q⁻¹)`
when `p.natDegree ≤ d`, which follows here from the degree bound (or the
diagonal normalization). The sum is over the real Bruhat interval;
its finiteness is a separate theorem, not a different definition of order. -/
structure NormalizedKL (cs : CoxeterSystem M W) (RP : PolynomialFamilies W) : Prop where
  R_diagonal : ∀ x, RP.1 x x = 1
  R_zero : ∀ x y, ¬ BruhatLE cs x y → RP.1 x y = 0
  R_recursion : ∀ x y i, cs.length (cs.simple i * y) < cs.length y →
    RP.1 x y =
      if cs.length (cs.simple i * x) < cs.length x then
        RP.1 (cs.simple i * x) (cs.simple i * y)
      else
        (X - 1) * RP.1 x (cs.simple i * y) +
          X * RP.1 (cs.simple i * x) (cs.simple i * y)
  P_diagonal : ∀ x, RP.2 x x = 1
  P_zero : ∀ x y, ¬ BruhatLE cs x y → RP.2 x y = 0
  P_degree : ∀ x y, BruhatLE cs x y → x ≠ y →
    2 * (RP.2 x y).natDegree < rankDifference cs x y
  reciprocity : ∀ x y, BruhatLE cs x y →
    reflect (rankDifference cs x y) (RP.2 x y) =
      ∑ᶠ z : Interval cs x y, RP.1 x z.val * RP.2 z.val y

/-- The polynomial families selected by their equal-parameter normalization. -/
noncomputable def klFamilies (cs : CoxeterSystem M W) : PolynomialFamilies W :=
  Classical.epsilon (NormalizedKL cs)

noncomputable def klPolynomial (cs : CoxeterSystem M W) (x y : W) : ℤ[X] :=
  (klFamilies cs).2 x y

end KLInvariance

namespace KLInvariance

universe u v u' v'

variable {B : Type u} {W : Type v} [Group W] {M : CoxeterMatrix B}

theorem combinatorial_invariance
    {B' : Type u'} {W' : Type v'} [Group W'] {M' : CoxeterMatrix B'}
    (cs : CoxeterSystem M W) (cs' : CoxeterSystem M' W')
    {u b : W} {u' b' : W'}
    (hub : BruhatLE cs u b) (hub' : BruhatLE cs' u' b')
    (ι : Interval cs u b ≃o Interval cs' u' b') :
    klPolynomial cs u b = klPolynomial cs' u' b' := by
  sorry

end KLInvariance

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/KLInvariance.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.KLInvariance.combinatorial_invariance` must keep exactly the statement shown above: same names,
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
