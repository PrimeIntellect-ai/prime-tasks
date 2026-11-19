# openai/math challenge `SymmetricMahlerEquality` (family 087)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 087 of the release, *The Mahler conjectures and symplectic width*
(Convex and metric geometry). The family as a whole: Resolves the symmetric and nonsymmetric geometric Mahler conjectures in every dimension, with Hanner polytopes and simplices as the respective volume-product minimizers and all equality cases classified. The corresponding sharp functional Mahler inequalities also hold. For $n\ge2$, every symmetric polar product $K\times K^\circ$ in dimension $2n$ has Gromov width $4$.

The challenge is `SymmetricMahlerEquality`, also at `/opt/openai-math/challenges/SymmetricMahlerEquality.lean`:

```lean
import Mathlib

namespace OAI

namespace SymmetricMahler

section

open Real Complex Set Finset
variable {I : Type*} [Fintype I]

def coordinatePolar (K : Set (I → ℝ)) : Set (I → ℝ) :=
  {p | ∀ v ∈ K, (∑ i, p i*v i) ≤ 1}

end

noncomputable section

open Set MeasureTheory Metric

def hannerProduct {k l : ℕ} (A : Set (Fin k → ℝ)) (B : Set (Fin l → ℝ)) :
    Set (Fin (k + l) → ℝ) :=
  {z | ∃ x ∈ A, ∃ y ∈ B, z = Fin.append x y}

def hannerJoin {k l : ℕ} (A : Set (Fin k → ℝ)) (B : Set (Fin l → ℝ)) :
    Set (Fin (k + l) → ℝ) :=
  convexHull ℝ
    (((fun x : Fin k → ℝ => Fin.append x 0) '' A) ∪
      ((fun y : Fin l → ℝ => Fin.append 0 y) '' B))

inductive IsHanner : {n : ℕ} → Set (Fin n → ℝ) → Prop
  | interval (a : ℝ) (ha : 0 < a) :
      IsHanner (Icc (fun _ : Fin 1 => -a) (fun _ : Fin 1 => a))
  | product {k l : ℕ} {A : Set (Fin k → ℝ)} {B : Set (Fin l → ℝ)}
      (hA : IsHanner A) (hB : IsHanner B) : IsHanner (hannerProduct A B)
  | join {k l : ℕ} {A : Set (Fin k → ℝ)} {B : Set (Fin l → ℝ)}
      (hA : IsHanner A) (hB : IsHanner B) : IsHanner (hannerJoin A B)

def IsLinearHanner {n : ℕ} (K : Set (Fin n → ℝ)) : Prop :=
  ∃ H : Set (Fin n → ℝ), IsHanner H ∧
    ∃ T : (Fin n → ℝ) ≃ₗ[ℝ] (Fin n → ℝ), K = T '' H

theorem symmetric_mahler_equality {n : ℕ} (hn : 1 ≤ n)
    {K : Set (Fin n → ℝ)} (hK : IsCompact K) (hconv : Convex ℝ K)
    (hsym : ∀ x ∈ K, -x ∈ K) (hint : (interior K).Nonempty) :
    ((volume K).toReal * (volume (coordinatePolar K)).toReal =
      (4 : ℝ)^n / (Nat.factorial n : ℝ)) ↔ IsLinearHanner K := by
  sorry

end

end SymmetricMahler

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/SymmetricMahlerEquality.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.SymmetricMahler.symmetric_mahler_equality` must keep exactly the statement shown above: same names,
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
