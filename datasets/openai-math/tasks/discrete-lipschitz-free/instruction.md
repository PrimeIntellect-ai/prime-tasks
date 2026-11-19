# openai/math challenge `DiscreteLipschitzFree` (family 330)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 330 of the release, *A negative answer to Kalton's Lipschitz-free approximation question*
(Functional analysis). The family as a whole: Constructs a countable uniformly discrete metric space whose real Lipschitz-free Banach space has the approximation property but not the bounded approximation property, answering Kalton's question negatively. Finite-rank operators approximate the identity on every compact set, but their norms cannot share a finite bound.

The challenge is `DiscreteLipschitzFree`, also at `/opt/openai-math/challenges/DiscreteLipschitzFree.lean`:

```lean
import Mathlib

namespace OAI

/-!
# Real Lipschitz-free spaces and approximation properties
-/

noncomputable section
open scoped BigOperators ENNReal

namespace DiscreteFree

variable {M : Type*} [MetricSpace M]

def lipSubmodule (o : M) : Submodule ℝ (M → ℝ) where
  carrier := {f | f o = 0 ∧ ∃ C : ℝ, 0 ≤ C ∧
    ∀ x y, |f x - f y| ≤ C * dist x y}
  zero_mem' := by
    refine ⟨rfl, 0, le_rfl, ?_⟩
    intro x y
    simp
  add_mem' := by
    rintro f g ⟨hfo, C, hC, hf⟩ ⟨hgo, D, hD, hg⟩
    refine ⟨by simpa using congrArg₂ (· + ·) hfo hgo,
      C + D, add_nonneg hC hD, ?_⟩
    intro x y
    change |f x + g x - (f y + g y)| ≤ (C + D) * dist x y
    calc
      _ = |(f x - f y) + (g x - g y)| := by ring_nf
      _ ≤ |f x - f y| + |g x - g y| := abs_add_le _ _
      _ ≤ C * dist x y + D * dist x y := add_le_add (hf x y) (hg x y)
      _ = _ := by ring
  smul_mem' := by
    rintro c f ⟨hfo, C, hC, hf⟩
    refine ⟨by simp [hfo], |c| * C, mul_nonneg (abs_nonneg c) hC, ?_⟩
    intro x y
    change |c * f x - c * f y| ≤ (|c| * C) * dist x y
    calc
      _ = |c| * |f x - f y| := by rw [← mul_sub, abs_mul]
      _ ≤ |c| * (C * dist x y) := mul_le_mul_of_nonneg_left (hf x y) (abs_nonneg c)
      _ = _ := by ring

def Lip0 (o : M) := ↥(lipSubmodule o)

namespace Lip0

variable {o : M}

instance : AddCommGroup (Lip0 o) := inferInstanceAs (AddCommGroup ↥(lipSubmodule o))
instance : Module ℝ (Lip0 o) := inferInstanceAs (Module ℝ ↥(lipSubmodule o))

instance : CoeFun (Lip0 o) (fun _ => M → ℝ) := ⟨fun f => f.val⟩

def slope (o : M) : Lip0 o →ₗ[ℝ] lp (fun _ : M × M => ℝ) ∞ where
  toFun f := ⟨fun z : M × M => (f z.1 - f z.2) / dist z.1 z.2, by
    obtain ⟨C, hC, hf⟩ := f.property.2
    apply memℓp_infty
    refine ⟨C, ?_⟩
    rintro r ⟨⟨x, y⟩, rfl⟩
    change ‖(f x - f y) / dist x y‖ ≤ C
    rw [Real.norm_eq_abs, abs_div, abs_of_nonneg dist_nonneg]
    by_cases hxy : x = y
    · simp [hxy, hC]
    · exact (div_le_iff₀ (dist_pos.mpr hxy)).2 (hf x y)⟩
  map_add' f g := by
    apply lp.ext
    funext z
    change ((f z.1 + g z.1) - (f z.2 + g z.2)) / dist z.1 z.2 =
      (f z.1 - f z.2) / dist z.1 z.2 + (g z.1 - g z.2) / dist z.1 z.2
    ring
  map_smul' c f := by
    apply lp.ext
    funext z
    change (c * f z.1 - c * f z.2) / dist z.1 z.2 =
      c * ((f z.1 - f z.2) / dist z.1 z.2)
    ring

instance (o : M) : NormedAddCommGroup (Lip0 o) :=
  NormedAddCommGroup.induced _ _ (slope o).toAddMonoidHom (by
    intro f g h
    apply Subtype.ext
    funext x
    have hx := congrArg (fun q : lp (fun _ : M × M => ℝ) ∞ => q (x, o)) h
    change (f x - f o) / dist x o = (g x - g o) / dist x o at hx
    rw [f.property.1, g.property.1, sub_zero, sub_zero] at hx
    by_cases hxo : x = o
    · rw [hxo, f.property.1, g.property.1]
    · exact (div_left_inj' (ne_of_gt (dist_pos.mpr hxo))).mp hx)

instance (o : M) : NormedSpace ℝ (Lip0 o) :=
  NormedSpace.induced ℝ _ _ (slope o)

end Lip0

def evaluation (o x : M) : (Lip0 o →L[ℝ] ℝ) :=
  LinearMap.mkContinuous
    ({ toFun := fun f : Lip0 o => f x
       map_add' := fun _ _ => rfl
       map_smul' := fun _ _ => rfl } : Lip0 o →ₗ[ℝ] ℝ)
    (dist x o) (fun f => by
      change ‖f x‖ ≤ dist x o * ‖f‖
      rw [mul_comm]
      have hx := lp.norm_apply_le_norm (by simp : (∞ : ℝ≥0∞) ≠ 0)
        (Lip0.slope o f) (x, o)
      change ‖(f x - f o) / dist x o‖ ≤ ‖f‖ at hx
      rw [f.property.1, sub_zero, norm_div, Real.norm_of_nonneg dist_nonneg] at hx
      by_cases hxo : x = o
      · rw [hxo, f.property.1, norm_zero, dist_self, mul_zero]
      · exact (div_le_iff₀ (dist_pos.mpr hxo)).mp hx)

def freeSubmodule (o : M) : Submodule ℝ ((Lip0 o →L[ℝ] ℝ)) :=
  (Submodule.span ℝ (Set.range (evaluation o))).topologicalClosure

def FreeSpace (o : M) := ↥(freeSubmodule o)

instance (o : M) : NormedAddCommGroup (FreeSpace o) :=
  inferInstanceAs (NormedAddCommGroup ↥(freeSubmodule o))

instance (o : M) : NormedSpace ℝ (FreeSpace o) :=
  inferInstanceAs (NormedSpace ℝ ↥(freeSubmodule o))

def delta (o x : M) : FreeSpace o :=
  ⟨evaluation o x, Submodule.le_topologicalClosure _
    (Submodule.subset_span ⟨x, rfl⟩)⟩

def HasAP (X : Type*) [NormedAddCommGroup X] [NormedSpace ℝ X] : Prop :=
  ∀ C : Set X, IsCompact C → ∀ ε : ℝ, 0 < ε →
    ∃ T : X →L[ℝ] X, Module.Finite ℝ (LinearMap.range T.toLinearMap) ∧
      ∃ η : ℝ, η < ε ∧ ∀ u ∈ C, ‖T u - u‖ ≤ η

def HasBAP (X : Type*) [NormedAddCommGroup X] [NormedSpace ℝ X] (Λ : ℝ) : Prop :=
  ∀ C : Set X, IsCompact C → ∀ ε : ℝ, 0 < ε →
    ∃ T : X →L[ℝ] X, Module.Finite ℝ (LinearMap.range T.toLinearMap) ∧
      ‖T‖ ≤ Λ ∧ ∃ η : ℝ, η < ε ∧ ∀ u ∈ C, ‖T u - u‖ ≤ η

def blockBound (p : ℕ) : ℝ := 300 * (p : ℝ)^2 + 150 * (p : ℝ) + 5

def BlockStatement : Prop :=
  ∀ p : ℕ, 1 ≤ p → ∃ (M : Type) (d : MetricSpace M) (o : M),
    letI := d
    Countable M ∧ (∀ x y : M, x ≠ y → 1 ≤ dist x y) ∧
      (∀ x y : M, dist x y ≤ blockBound p) ∧
      ∃ A : Finset M, o ∈ A ∧ ∀ T : FreeSpace o →L[ℝ] FreeSpace o,
        Module.Finite ℝ (LinearMap.range T.toLinearMap) → ‖T‖ ≤ (p : ℝ) →
          ∃ a ∈ A, (1 / 2 : ℝ) ≤ ‖T (delta o a) - delta o a‖

def MainStatement : Prop :=
  ∃ (M : Type) (d : MetricSpace M) (o : M),
    letI := d
    Countable M ∧ (∀ x y : M, x ≠ y → 1 ≤ dist x y) ∧
      (¬ Bornology.IsBounded (Set.univ : Set M)) ∧
      (¬ ProperSpace M) ∧ HasAP (FreeSpace o) ∧
      ∀ Λ : ℝ, 1 ≤ Λ → ¬ HasBAP (FreeSpace o) Λ

theorem source_endpoints : BlockStatement ∧ MainStatement := by
  sorry

end DiscreteFree

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/DiscreteLipschitzFree.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.DiscreteFree.source_endpoints` must keep exactly the statement shown above: same names,
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
