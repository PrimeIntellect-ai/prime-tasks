# openai/math challenge `PartialPermutation` (family 238)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 238 of the release, *Optimal logarithmic mixing of the Thorp shuffle*
(Probability and statistical mechanics). The family as a whole: Proves that the Thorp shuffle randomizes $N=2^d$ labeled cards in $\Theta(\log N)$ physical shuffles, settling its optimal mixing order for power-of-two deck sizes. Convergence is in total variation from the worst initial ordering and concerns the entire permutation, not just individual card positions.

The challenge is `PartialPermutation`, also at `/opt/openai-math/challenges/PartialPermutation.lean`:

```lean
import Mathlib

namespace OAI

open scoped Classical BigOperators ComplexConjugate MonoidAlgebra
namespace PartialPermutation
noncomputable section

def IsUnitary {G V : Type*} [Group G] [NormedAddCommGroup V]
    [InnerProductSpace ℂ V] (ρ : Representation ℂ G V) : Prop :=
  ∀ g x y, inner ℂ (ρ g x) (ρ g y) = inner ℂ x y

section
variable {V : Type*} [NormedAddCommGroup V] [InnerProductSpace ℂ V]
    [FiniteDimensional ℂ V]
def hsNormSq (A : Module.End ℂ V) : ℝ :=
  (LinearMap.trace ℂ V (LinearMap.adjoint A * A)).re

end

def complexFourier {G V : Type*} [Group G] [Fintype G] [AddCommGroup V] [Module ℂ V]
    (ρ : Representation ℂ G V) (f : G → ℂ) : Module.End ℂ V := ∑ g, f g • ρ g

section
variable {G V : Type*} [Group G] [Fintype G] [AddCommGroup V] [Module ℂ V]
    [FiniteDimensional ℂ V] (ρ : Representation ℂ G V)
noncomputable def componentSimple (c : isotypicComponents ℂ[G] ρ.asModule) :
    Submodule ℂ[G] ρ.asModule := c.property.choose

instance components_finite : Finite (isotypicComponents ℂ[G] ρ.asModule) := by
  let : IsNoetherian ℂ[G] ρ.asModule := isNoetherian_of_tower ℂ inferInstance
  infer_instance

end

section
variable (G : Type*) [Group G] [Fintype G]
def regularRep : Representation ℂ G (EuclideanSpace ℂ G) where
  toFun g :=
    { toFun := fun f => WithLp.toLp 2 (fun h => f (g⁻¹ * h))
      map_add' := by intros; rfl
      map_smul' := by intros; rfl }
  map_one' := by ext f h; simp
  map_mul' := by
    intro x y
    ext f h
    change f ((x * y)⁻¹ * h) = f (y⁻¹ * (x⁻¹ * h))
    simp [mul_assoc]

end

section
variable {G : Type*} [Group G] [Fintype G]
abbrev IrreducibleIndex (G : Type*) [Group G] [Fintype G] :=
  isotypicComponents ℂ[G] (regularRep G).asModule

noncomputable instance irreducibleIndex_fintype : Fintype (IrreducibleIndex G) :=
  Fintype.ofFinite _

abbrev irreducibleSpace (c : IrreducibleIndex G) :=
  (Subrepresentation.ofSubmodule' (componentSimple (regularRep G) c)).toSubmodule

abbrev irreducibleDegree (c : IrreducibleIndex G) := Module.finrank ℂ (irreducibleSpace c)

end

def mass {G : Type*} [Fintype G] (f : G → ℝ) : ℝ := ∑ g, f g

def LeftCosetCap {G : Type*} [Group G] [Fintype G]
    (f : G → ℝ) (H : Subgroup G) (B : ℝ) : Prop :=
  by classical exact ∀ g, ∑ h : H, f (g * h) ≤ B / H.index

def blockSubgroup {X : Type*} (M : Set X) : Subgroup (Equiv.Perm X) where
  carrier := {g | ∀ x, x ∉ M → g x = x}
  one_mem' := by simp
  mul_mem' := by
    intro g h hg hh x hx
    simp only [Set.mem_ofPred_eq] at hg hh ⊢
    simp [Equiv.Perm.mul_apply, hh x hx, hg x hx]
  inv_mem' := by
    intro g hg x hx
    exact ((Equiv.eq_symm_apply g).mpr (hg x hx)).symm

def inverseDegreeSum (G : Type*) [Group G] [Fintype G] (u : ℝ) : ℝ :=
  ∑ c : IrreducibleIndex G, (irreducibleDegree c : ℝ)^(-u)

def symmetricInverseDegreeSum (n : ℕ) (u : ℝ) : ℝ :=
  inverseDegreeSum (Equiv.Perm (Fin n)) u

def symmetricDegreeConstant (u : ℝ) : ℝ :=
  sSup {x : ℝ | ∃ n : ℕ, 1 ≤ n ∧ x = symmetricInverseDegreeSum n u}

def ComplementaryCosetsFiniteStatement : Prop :=
  ∀ (X : Type*) [Fintype X] [DecidableEq X] (b : ℕ) (_ : 0 < b) (M : Fin b → Set X),
    (∀ i, (M i).Nonempty) →
    Pairwise (fun i j => Disjoint (M i) (M j)) → (⋃ i, M i) = Set.univ →
    ∀ (V : Type) [NormedAddCommGroup V] [InnerProductSpace ℂ V]
      [FiniteDimensional ℂ V] (ρ : Representation ℂ (Equiv.Perm X) V),
      Representation.IsIrreducible ρ → IsUnitary ρ →
      ∀ (f : Equiv.Perm X → ℝ) (B u : ℝ),
      (∀ g, 0 ≤ f g) → mass f ≤ 1 → 0 < u →
      (∀ i, LeftCosetCap f (blockSubgroup (M i)) B) →
      (hsNormSq (complexFourier ρ (fun g => f g)) ≤
        b * B * symmetricDegreeConstant u *
          (Module.finrank ℂ V : ℝ)^(-1+(u+2)/(b : ℝ))) ∧
      (‖LinearMap.toContinuousLinearMap (complexFourier ρ (fun g => f g))‖^2 ≤
        b * B * symmetricDegreeConstant u *
          (Module.finrank ℂ V : ℝ)^(-1+(u+2)/(b : ℝ)))

theorem complementaryCosets_finite : ComplementaryCosetsFiniteStatement := by
  sorry

end
end PartialPermutation

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/PartialPermutation.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.PartialPermutation.complementaryCosets_finite` must keep exactly the statement shown above: same names,
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
