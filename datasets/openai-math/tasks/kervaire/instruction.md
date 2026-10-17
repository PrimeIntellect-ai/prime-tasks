# openai/math challenge `Kervaire` (family 256)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 256 of the release, *Howie's conjecture on equations over groups*
(Group theory). The family as a whole: Proves that every finite system of equations over an arbitrary group whose exponent-sum matrix has full row rank over $\mathbb Q$ has a simultaneous solution in an overgroup, resolving Howie's conjecture. The coefficient group embeds in the presented quotient. A companion proves Kervaire's conjecture: adjoining one generator and one relation cannot trivialize a nontrivial group.

The challenge is `Kervaire`, also at `/opt/openai-math/challenges/Kervaire.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

namespace Kervaire

universe u

abbrev WordGroup (A : Type u) [Group A] := Monoid.Coprod A (Multiplicative ℤ)

def exponentSum {A : Type u} [Group A] (w : WordGroup A) : ℤ :=
  Multiplicative.toAdd (Monoid.Coprod.snd w)

def Unimodular {A : Type u} [Group A] (w : WordGroup A) : Prop :=
  exponentSum w = 1 ∨ exponentSum w = -1

def relatorClosure {A : Type u} [Group A] (w : WordGroup A) : Subgroup (WordGroup A) :=
  Subgroup.normalClosure ({w} : Set (WordGroup A))

instance {A : Type u} [Group A] (w : WordGroup A) : (relatorClosure w).Normal :=
  inferInstanceAs (Subgroup.normalClosure ({w} : Set (WordGroup A))).Normal

abbrev RelatorQuotient {A : Type u} [Group A] (w : WordGroup A) :=
  WordGroup A ⧸ relatorClosure w

def coefficientMap {A : Type u} [Group A] (w : WordGroup A) : A →* RelatorQuotient w :=
  (QuotientGroup.mk' (relatorClosure w)).comp Monoid.Coprod.inl

theorem coefficient_injective (A : Type u) [Group A] (w : WordGroup A)
    (hw : Unimodular w) : Function.Injective (coefficientMap w) := by
  sorry

end Kervaire

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/Kervaire.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Kervaire.coefficient_injective` must keep exactly the statement shown above: same names,
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
