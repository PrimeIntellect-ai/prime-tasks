# openai/math challenge `DuttaDomain` (family 194)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 194 of the release, *Lech's multiplicity conjecture*
(Algebra). The family as a whole: Proves $e(R)\le e(S)$ for every flat local homomorphism of nonzero Noetherian local rings, where $e$ is Hilbert–Samuel multiplicity. This resolves Lech's conjecture in every dimension and characteristic.

The challenge is `DuttaDomain`, also at `/opt/openai-math/challenges/DuttaDomain.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
namespace Lech
noncomputable def dimension (A : Type*) [CommRing A] : ℕ :=
  (WithBot.unbotD 0 (ringKrullDim A)).toNat

noncomputable def colength (A : Type*) [CommRing A] [IsLocalRing A]
    (N : ℕ) : ℕ :=
  (Module.length A (A ⧸ (IsLocalRing.maximalIdeal A) ^ N)).toNat

noncomputable def normalizedColength (A : Type*) [CommRing A] [IsLocalRing A]
    (N : ℕ) : ℝ :=
  (Nat.factorial (dimension A) : ℝ) * (colength A N : ℝ) /
    (N : ℝ) ^ dimension A

noncomputable def multiplicity (A : Type*) [CommRing A] [IsLocalRing A] : ℝ :=
  Filter.limUnder Filter.atTop (normalizedColength A)
end Lech


 

noncomputable section
namespace Lech
open CategoryTheory CategoryTheory.Limits HomologicalComplex Filter
open scoped Topology
universe u
variable (R : Type u) [CommRing R] [IsNoetherianRing R] [IsLocalRing R]

 
structure IsShortComplex (F : CochainComplex (ModuleCat.{u} R) ℤ) : Prop where
  term_free : ∀ i, Module.Free R (F.X i)
  term_finite : ∀ i, Module.Finite R (F.X i)
  bounded : ∀ i, i < -(dimension R : ℤ) ∨ 0 < i → IsZero (F.X i)
  homology_finite_length : ∀ i, IsFiniteLength R (F.homology i)
  homology_zero_nonzero : ¬ IsZero (F.homology 0)

 

def frobeniusComplex (p : ℕ) [Fact p.Prime] [CharP R p] (n : ℕ)
    (F : CochainComplex (ModuleCat.{u} R) ℤ) : CochainComplex (ModuleCat.{u} R) ℤ :=
  ((ModuleCat.extendScalars (iterateFrobenius R p n)).mapHomologicalComplex (.up ℤ)).obj F

 
def shortEuler (F : CochainComplex (ModuleCat.{u} R) ℤ) : ℝ :=
  ∑ i∈Finset.range (dimension R+1),(-1:ℝ)^i*
    ((Module.length R (F.homology (-(i:ℤ)))).toNat : ℝ)

def duttaSequence (p : ℕ) [Fact p.Prime] [CharP R p]
    (F : CochainComplex (ModuleCat.{u} R) ℤ) (n : ℕ) : ℝ :=
  (p:ℝ)^(-(n*dimension R : ℤ)) * shortEuler R (frobeniusComplex R p n F)

def duttaMultiplicity (p : ℕ) [Fact p.Prime] [CharP R p]
    (F : CochainComplex (ModuleCat.{u} R) ℤ) : ℝ :=
  limUnder atTop (duttaSequence R p F)

 

def DuttaDomainClaim : Prop :=
  ∀ (D : Type u) [CommRing D] [IsNoetherianRing D] [IsLocalRing D] [IsDomain D]
    [IsAdicComplete (IsLocalRing.maximalIdeal D) D]
    (p : ℕ) [Fact p.Prime] [CharP D p]
    (F : CochainComplex (ModuleCat.{u} D) ℤ), IsShortComplex D F →
      (∀ n i,IsFiniteLength D ((frobeniusComplex D p n F).homology i)) ∧
      Tendsto (duttaSequence D p F) atTop (𝓝 (duttaMultiplicity D p F)) ∧
      multiplicity D ≤ duttaMultiplicity D p F
end Lech

namespace Lech
universe u
theorem dutta_domain : DuttaDomainClaim.{u} := by
  sorry
end Lech

end
end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/DuttaDomain.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Lech.dutta_domain` must keep exactly the statement shown above: same names,
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
