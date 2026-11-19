# openai/math challenge `ElementaryPositivity` (family 169)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 169 of the release, *The Shareshian–Wachs $e$-positivity conjecture*
(Combinatorics). The family as a whole: Resolves the elementary-positivity part of the Shareshian–Wachs conjecture: the chromatic quasisymmetric function of every natural unit interval graph has elementary-basis coefficients in $\mathbb N[q]$. The coefficients count explicitly described permutations, giving a combinatorial explanation of positivity.

The challenge is `ElementaryPositivity`, also at `/opt/openai-math/challenges/ElementaryPositivity.lean`:

```lean
import Mathlib

namespace OAI

namespace ElementaryPositivity

structure NaturalUnitIntervalGraph (n : ℕ) where
  h : Fin n → Fin n
  increasing : Monotone h
  extensive : ∀ i, i ≤ h i

namespace NaturalUnitIntervalGraph

variable {n : ℕ} (G : NaturalUnitIntervalGraph n)

def Edge (i j : Fin n) : Prop :=
  (i < j ∧ j ≤ G.h i) ∨ (j < i ∧ i ≤ G.h j)

instance (i j : Fin n) : Decidable (G.Edge i j) :=
  inferInstanceAs (Decidable ((_ ∧ _) ∨ (_ ∧ _)))

def Nondescent (σ : Equiv.Perm (Fin n)) : Prop :=
  ∀ i j : Fin n, i.val + 1 = j.val → σ j < σ i → G.Edge (σ i) (σ j)

instance (σ : Equiv.Perm (Fin n)) : Decidable (G.Nondescent σ) :=
  inferInstanceAs (Decidable (∀ i j : Fin n,
    i.val + 1 = j.val → σ j < σ i → G.Edge (σ i) (σ j)))

def graphInversions (σ : Equiv.Perm (Fin n)) : ℕ :=
  (Finset.univ.filter fun ij : Fin n × Fin n =>
    ij.1 < ij.2 ∧ σ ij.2 < σ ij.1 ∧ G.Edge (σ ij.1) (σ ij.2)).card

def Proper {r : ℕ} (f : Fin n → Fin r) : Prop :=
  ∀ i j : Fin n, G.Edge i j → f i ≠ f j

instance {r : ℕ} (f : Fin n → Fin r) : Decidable (G.Proper f) :=
  inferInstanceAs (Decidable (∀ i j : Fin n, G.Edge i j → f i ≠ f j))

def coloringAscents {r : ℕ} (f : Fin n → Fin r) : ℕ :=
  (Finset.univ.filter fun ij : Fin n × Fin n =>
    ij.1 < ij.2 ∧ G.Edge ij.1 ij.2 ∧ f ij.1 < f ij.2).card

noncomputable def chromatic (r : ℕ) : MvPolynomial (Fin r) (Polynomial ℕ) :=
  ∑ f ∈ Finset.univ.filter (G.Proper (r := r)),
    MvPolynomial.C (Polynomial.X ^ G.coloringAscents f) *
      ∏ i : Fin n, MvPolynomial.X (f i)

structure PermutationWitness where
  theta : {σ : Equiv.Perm (Fin n) // G.Nondescent σ} → Nat.Partition n
  expansion : ∀ r : ℕ, G.chromatic r =
    ∑ σ : {σ : Equiv.Perm (Fin n) // G.Nondescent σ},
      MvPolynomial.C (Polynomial.X ^ G.graphInversions σ.val) *
        MvPolynomial.esymmPart (Fin r) (Polynomial ℕ) (theta σ)

end NaturalUnitIntervalGraph
end ElementaryPositivity

def elementaryPositivityWitness (n : ℕ)
    (G : ElementaryPositivity.NaturalUnitIntervalGraph n) :
    G.PermutationWitness := by
  sorry

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/ElementaryPositivity.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The definition below must keep exactly the statement shown above: same names,
  namespaces, binders and types. Every definition the statements use must stay exactly as written.
  Change nothing except the proofs, and the body of `OAI.elementaryPositivityWitness`, which you must supply: its type states the claim, so any value of that type proves it.
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
