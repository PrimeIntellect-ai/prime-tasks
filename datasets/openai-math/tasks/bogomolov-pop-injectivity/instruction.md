# openai/math challenge `BogomolovPopInjectivity` (family 009)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 009 of the release, *Bogomolov–Pop and Milnor $K$-theoretic reconstruction*
(Number theory). The family as a whole: Reconstructs function fields of transcendence degree at least two over algebraically closed constants from $K^{\mathrm M}_1/\ell$, $K^{\mathrm M}_2/\ell$, and their product. These data recover the perfect closure and constants when $\ell$ differs from the characteristic, and the original field and its named base in equal characteristic. Also proves Bogomolov–Pop reconstruction from abelian-by-central pro-$\ell$ Galois data away from the characteristic.

The challenge is `BogomolovPopInjectivity`, also at `/opt/openai-math/challenges/BogomolovPopInjectivity.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
namespace BogomolovPop

def proEllKernel (ell : ℕ) (G : Type*) [Group G] [TopologicalSpace G] : Subgroup G :=
  ⨅ (H : OpenNormalSubgroup G) (_ : IsPGroup ell (G ⧸ H.toSubgroup)), H.toSubgroup

instance proEllKernel_normal (ell : ℕ) (G : Type*) [Group G] [TopologicalSpace G] :
    (proEllKernel ell G).Normal := by
  unfold proEllKernel
  exact Subgroup.normal_iInf_normal fun H =>
    Subgroup.normal_iInf_normal fun _ => H.isNormal'

abbrev ProEll (ell : ℕ) (F : Type*) [Field F] :=
  Field.absoluteGaloisGroup F ⧸ proEllKernel ell (Field.absoluteGaloisGroup F)

def closedGammaThree (G : Type*) [Group G] [TopologicalSpace G] [IsTopologicalGroup G] :
    Subgroup G :=
  (⁅(commutator G).topologicalClosure, (⊤ : Subgroup G)⁆).topologicalClosure

instance closedGammaThree_normal (G : Type*) [Group G] [TopologicalSpace G]
    [IsTopologicalGroup G] : (closedGammaThree G).Normal := by
  unfold closedGammaThree
  exact Subgroup.is_normal_topologicalClosure _

abbrev PiA (ell : ℕ) (F : Type*) [Field F] := TopologicalAbelianization (ProEll ell F)

abbrev PiC (ell : ℕ) (F : Type*) [Field F] := ProEll ell F ⧸ closedGammaThree (ProEll ell F)

theorem closedGammaThree_le (G : Type*) [Group G] [TopologicalSpace G]
    [IsTopologicalGroup G] : closedGammaThree G ≤ (commutator G).topologicalClosure := by
  exact Subgroup.topologicalClosure_minimal _ (Subgroup.commutator_le_left _ _)
    (Subgroup.isClosed_topologicalClosure _)

def centralProjection (ell : ℕ) (F : Type*) [Field F] : PiC ell F →* PiA ell F :=
  QuotientGroup.map _ _ (MonoidHom.id _) (closedGammaThree_le _)

abbrev Delta (ell : ℕ) (F : Type*) [Field F] := (centralProjection ell F).ker

def sourceCommutator {G : Type*} [Group G] (x y : G) : G := x⁻¹ * y⁻¹ * x * y

def abelianLift (ell : ℕ) (F : Type*) [Field F] (x : PiA ell F) : ProEll ell F :=
  Quotient.out x

theorem abelianLift_spec (ell : ℕ) (F : Type*) [Field F] (x : PiA ell F) :
    QuotientGroup.mk' _ (abelianLift ell F x) = x := Quotient.out_eq x

def bracket (ell : ℕ) (F : Type*) [Field F] (x y : PiA ell F) : Delta ell F :=
  ⟨QuotientGroup.mk' _ (sourceCommutator (abelianLift ell F x) (abelianLift ell F y)), by
    change centralProjection ell F _ = 1
    simp only [centralProjection, sourceCommutator, map_mul, map_inv]
    simp [mul_comm]⟩

def BracketCompatible {ell : ℕ} {K L : Type*} [Field K] [Field L]
    (φ : PiA ell L ≃ₜ* PiA ell K) : Prop :=
  ∃ ψ : Delta ell L ≃ₜ* Delta ell K,
    ∀ σ τ, ψ (bracket ell L σ τ) = bracket ell K (φ σ) (φ τ)

abbrev PerfectFieldClosure (F : Type*) [Field F] := perfectClosure F (AlgebraicClosure F)

def PerfectIsom (k K l L : Type*) [Field k] [Field K] [Field l] [Field L]
    [Algebra k K] [Algebra l L] :=
  { α : PerfectFieldClosure K ≃+* PerfectFieldClosure L //
    α '' Set.range (algebraMap k (PerfectFieldClosure K)) =
      Set.range (algebraMap l (PerfectFieldClosure L)) }

def FrobeniusStep {k K l L : Type*} [Field k] [Field K] [Field l] [Field L]
    [Algebra k K] [Algebra l L] (α β : PerfectIsom k K l L) : Prop :=
  ∃ p : ℕ, p.Prime ∧ (p : L) = 0 ∧
    ∀ x : PerfectFieldClosure K, β.1 x = (α.1 x) ^ p

abbrev IsomF (k K l L : Type*) [Field k] [Field K] [Field l] [Field L]
    [Algebra k K] [Algebra l L] :=
  Quotient (Relation.EqvGen.setoid (FrobeniusStep (k := k) (K := K) (l := l) (L := L)))

abbrev IsomC (ell : ℕ) (K L : Type*) [Field K] [Field L] :=
  {φ : PiA ell L ≃ₜ* PiA ell K // BracketCompatible φ}

def ScalarStep {ell : ℕ} [Fact ell.Prime] {K L : Type*} [Field K] [Field L]
    (φ χ : IsomC ell K L) : Prop :=
  ∃ u : (PadicInt ell)ˣ, ∀ x : PiA ell L,
    Filter.Tendsto (fun n : ℕ => (φ.1 x) ^ PadicInt.appr (u : PadicInt ell) n)
      Filter.atTop (nhds (χ.1 x))

abbrev IsomCUnits (ell : ℕ) [Fact ell.Prime] (K L : Type*) [Field K] [Field L] :=
  Quotient (Relation.EqvGen.setoid (ScalarStep (ell := ell) (K := K) (L := L)))

def absoluteToPiA (ell : ℕ) (F : Type*) [Field F] :
    Field.absoluteGaloisGroup F →* PiA ell F :=
  (QuotientGroup.mk' _).comp (QuotientGroup.mk' _)

def absoluteAction {F : Type*} [Field F] (σ : Field.absoluteGaloisGroup F)
    (x : AlgebraicClosure F) : AlgebraicClosure F := by
  change AlgebraicClosure F ≃ₐ[F] AlgebraicClosure F at σ
  exact σ x

def PullbackGraph {ell : ℕ} {k K l L : Type*}
    [Field k] [Field K] [Field l] [Field L] [Algebra k K] [Algebra l L]
    (α : PerfectIsom k K l L) (φ : IsomC ell K L) : Prop :=
  ∃ β : AlgebraicClosure K ≃+* AlgebraicClosure L,
    (∀ x : PerfectFieldClosure K, β x = ((α.1 x : PerfectFieldClosure L) :
      AlgebraicClosure L)) ∧
    ∀ σ : Field.absoluteGaloisGroup L, ∃ τ : Field.absoluteGaloisGroup K,
      (∀ x : AlgebraicClosure K,
        β (absoluteAction τ x) = absoluteAction σ (β x)) ∧
      φ.1 (absoluteToPiA ell L σ) = absoluteToPiA ell K τ

def PhiGraph {ell : ℕ} [Fact ell.Prime] {k K l L : Type*}
    [Field k] [Field K] [Field l] [Field L] [Algebra k K] [Algebra l L]
    (a : IsomF k K l L) (b : IsomCUnits ell K L) : Prop :=
  ∃ α : PerfectIsom k K l L, ∃ φ : IsomC ell K L,
    Quotient.mk _ α = a ∧ Quotient.mk _ φ = b ∧ PullbackGraph α φ

theorem main_graph_injective (ell : ℕ) [Fact ell.Prime]
    (k K l L : Type*) [Field k] [Field K] [Field l] [Field L]
    [IsAlgClosed k] [IsAlgClosed l] [Algebra k K] [Algebra l L]
    [Algebra.EssFiniteType k K] [Algebra.EssFiniteType l L]
    (hk : (ell : k) ≠ 0) (hl : (ell : l) ≠ 0)
    (hK : 2 ≤ Algebra.trdeg k K) (hL : 2 ≤ Algebra.trdeg l L) :
    ∀ (a a' : IsomF k K l L) (b : IsomCUnits ell K L),
      PhiGraph a b → PhiGraph a' b → a = a'  := by
  sorry

end BogomolovPop

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/BogomolovPopInjectivity.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.BogomolovPop.main_graph_injective` must keep exactly the statement shown above: same names,
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
