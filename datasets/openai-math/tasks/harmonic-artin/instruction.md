# openai/math challenge `HarmonicArtin` (family 254)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 254 of the release, *Classifying spaces and geometric obstructions for Artin groups*
(Group theory). The family as a whole: The Salvetti complex of every finite-rank Artin group is aspherical, proving the Artin $K(\pi,1)$ conjecture. Arbitrary intersections of its parabolic subgroups are parabolic, proving the Parabolic Intersection Conjecture. An explicit Artin group admits no proper cocompact isometric action on any nonempty proper CAT$(0)$ space.

The challenge is `HarmonicArtin`, also at `/opt/openai-math/challenges/HarmonicArtin.lean`:

```lean
import Mathlib

namespace OAI

namespace HarmonicArtin

universe u

variable {S : Type u}

def alternating (s t : S) : ℕ → FreeGroup S
  | 0 => 1
  | n + 1 => FreeGroup.of s * alternating t s n

def braidRelators (M : CoxeterMatrix S) : Set (FreeGroup S) :=
  Set.range fun st : S × S =>
    alternating st.1 st.2 (M st.1 st.2) *
      (alternating st.2 st.1 (M st.1 st.2))⁻¹

abbrev Artin (M : CoxeterMatrix S) := PresentedGroup (braidRelators M)

def generator (M : CoxeterMatrix S) (s : S) : Artin M := PresentedGroup.of s

def coxeterParabolic (M : CoxeterMatrix S) (T : Set S) : Subgroup M.Group :=
  Subgroup.closure (M.simple '' T)

def IsSpherical (M : CoxeterMatrix S) (T : Set S) : Prop :=
  Finite (coxeterParabolic M T)

abbrev SphericalType (M : CoxeterMatrix S) := {T : Set S // IsSpherical M T}

abbrev LiftedCell (M : CoxeterMatrix S) := Artin M × SphericalType M

def wordArtin (M : CoxeterMatrix S) (w : List S) : Artin M :=
  (w.map (generator M)).prod

def wordCoxeter (M : CoxeterMatrix S) (w : List S) : M.Group :=
  (w.map M.simple).prod

def LiftedFace (M : CoxeterMatrix S) (a b : LiftedCell M) : Prop :=
  a.2.1 ⊆ b.2.1 ∧ ∃ w : List S,
    (∀ s ∈ w, s ∈ b.2.1) ∧
    M.toCoxeterSystem.length (wordCoxeter M w) = w.length ∧
    (∀ v : coxeterParabolic M a.2.1,
      M.toCoxeterSystem.length (wordCoxeter M w) ≤
        M.toCoxeterSystem.length (wordCoxeter M w * v)) ∧
    a.1 = b.1 * wordArtin M w

instance (M : CoxeterMatrix S) : Preorder (LiftedCell M) where
  le := Relation.ReflTransGen (LiftedFace M)
  le_refl _ := Relation.ReflTransGen.refl
  le_trans _ _ _ := Relation.ReflTransGen.trans

noncomputable def SalvettiCover (M : CoxeterMatrix S) : TopCat :=
  SSet.toTop.obj (CategoryTheory.nerve (LiftedCell M))

/-- The full lifted spherical-cell realization is contractible for every
Coxeter matrix with finitely many standard generators. -/
theorem salvetti_cover_contractible [Finite S] (M : CoxeterMatrix S) :
    ContractibleSpace (SalvettiCover M) := by
  sorry

end HarmonicArtin

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/HarmonicArtin.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.HarmonicArtin.salvetti_cover_contractible` must keep exactly the statement shown above: same names,
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
