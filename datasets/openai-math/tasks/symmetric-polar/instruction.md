# openai/math challenge `SymmetricPolar` (family 087)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 087 of the release, *The Mahler conjectures and symplectic width*
(Convex and metric geometry). The family as a whole: Resolves the symmetric and nonsymmetric geometric Mahler conjectures in every dimension, with Hanner polytopes and simplices as the respective volume-product minimizers and all equality cases classified. The corresponding sharp functional Mahler inequalities also hold. For $n\ge2$, every symmetric polar product $K\times K^\circ$ in dimension $2n$ has Gromov width $4$.

The challenge is `SymmetricPolar`, also at `/opt/openai-math/challenges/SymmetricPolar.lean`:

```lean
import Mathlib

namespace OAI

open Set
open scoped ContDiff ENNReal

namespace SymmetricPolar

abbrev Position (n : ℕ) := EuclideanSpace ℝ (Fin n)
abbrev Phase (n : ℕ) := Position n × Position n

def IsSymmetricConvexBody {n : ℕ} (K : Set (Position n)) : Prop :=
  IsCompact K ∧ Convex ℝ K ∧ (interior K).Nonempty ∧
    ∀ x, x ∈ K ↔ -x ∈ K

def polar {n : ℕ} (K : Set (Position n)) : Set (Position n) :=
  {p | ∀ q ∈ K, inner (𝕜 := ℝ) q p ≤ 1}

def polarProduct {n : ℕ} (K : Set (Position n)) : Set (Phase n) :=
  interior K ×ˢ interior (polar K)

def capacityBall (n : ℕ) (c : ℝ) : Set (Phase n) :=
  {z | Real.pi * (‖z.1‖ ^ 2 + ‖z.2‖ ^ 2) < c}

noncomputable def omega0 {n : ℕ} (v w : Phase n) : ℝ :=
  inner (𝕜 := ℝ) v.1 w.2 - inner (𝕜 := ℝ) w.1 v.2

def HasSymplecticEmbedding {n : ℕ} (U V : Set (Phase n)) : Prop :=
  ∃ e : Phase n → Phase n,
    ContDiffOn ℝ ∞ e U ∧
    Topology.IsEmbedding (fun z : U => e z) ∧
    MapsTo e U V ∧
    ∀ z ∈ U, ∀ v w : Phase n,
      omega0 (fderiv ℝ e z v) (fderiv ℝ e z w) = omega0 v w

noncomputable def gromovWidth {n : ℕ} (U : Set (Phase n)) : ℝ≥0∞ :=
  sSup (ENNReal.ofReal '' {c : ℝ | 0 < c ∧ HasSymplecticEmbedding (capacityBall n c) U})

theorem symmetric_polar_main {n : ℕ} (hn : 2 ≤ n)
    (K : Set (Position n)) (hK : IsSymmetricConvexBody K) :
    gromovWidth (polarProduct K) = 4 ∧
      ∀ c : ℝ, 0 < c → c < 4 →
        HasSymplecticEmbedding (capacityBall n c) (polarProduct K) := by
  sorry

end SymmetricPolar

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/SymmetricPolar.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.SymmetricPolar.symmetric_polar_main` must keep exactly the statement shown above: same names,
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
