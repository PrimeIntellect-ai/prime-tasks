# openai/math challenge `GeneralMahler` (family 087)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 087 of the release, *The Mahler conjectures and symplectic width*
(Convex and metric geometry). The family as a whole: Resolves the symmetric and nonsymmetric geometric Mahler conjectures in every dimension, with Hanner polytopes and simplices as the respective volume-product minimizers and all equality cases classified. The corresponding sharp functional Mahler inequalities also hold. For $n\ge2$, every symmetric polar product $K\times K^\circ$ in dimension $2n$ has Gromov width $4$.

The challenge is `GeneralMahler`, also at `/opt/openai-math/challenges/GeneralMahler.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

open Set MeasureTheory
open scoped RealInnerProductSpace

namespace GeneralMahler

abbrev Rn (n : ℕ) := EuclideanSpace ℝ (Fin n)

/-- The polar of a convex body translated by an interior center. -/
def polarAt {n : ℕ} (K : Set (Rn n)) (z : Rn n) : Set (Rn n) :=
  {y | ∀ x ∈ K, ⟪y, x - z⟫ ≤ 1}

/-- The volume product minimized over the interior centers of the body. -/
def volumeProduct {n : ℕ} (K : Set (EuclideanSpace ℝ (Fin n))) : ℝ :=
  sInf ((fun z => (volume K).toReal * (volume (polarAt K z)).toReal) ''
    interior K)

/-- The sharp general Mahler inequality, with equality exactly for simplices. -/
theorem general_mahler {n : ℕ} (hn : 1 ≤ n)
    (K : Set (EuclideanSpace ℝ (Fin n)))
    (hcompact : IsCompact K) (hconvex : Convex ℝ K)
    (hinterior : (interior K).Nonempty) :
    ((n : ℝ) + 1) ^ (n + 1) / (Nat.factorial n : ℝ) ^ 2 ≤ volumeProduct K ∧
      (volumeProduct K = ((n : ℝ) + 1) ^ (n + 1) / (Nat.factorial n : ℝ) ^ 2 ↔
        ∃ vertices : Fin (n + 1) → EuclideanSpace ℝ (Fin n),
          AffineIndependent ℝ vertices ∧ K = convexHull ℝ (range vertices)) := by
  sorry

end GeneralMahler

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/GeneralMahler.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.GeneralMahler.general_mahler` must keep exactly the statement shown above: same names,
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
