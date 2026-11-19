# openai/math challenge `GroupRingDeterminant` (family 197)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 197 of the release, *Nonsofic groups and group-ring counterexamples*
(Algebra). The family as a whole: Constructs a finitely presented torsion-free nonsofic group whose group algebra over $\mathbb F_2$ is not directly finite, disproving Kaplansky's conjecture even without torsion. Companion examples give injective nonsurjective cellular automata on all configurations, refuting Gottschalk's surjunctivity conjecture. Another counterexample is an integral group-ring matrix, invertible over the rational group ring, with Fuglede–Kadison determinant strictly between zero and one, disproving the unrestricted Determinant Conjecture.

The challenge is `GroupRingDeterminant`, also at `/opt/openai-math/challenges/GroupRingDeterminant.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open scoped BigOperators

namespace GroupRingDeterminant

/-- The Hilbert space l²(G)^n, with the product coordinates flattened. -/
abbrev Hilbert (G : Type) (n : ℕ) := lp (fun _ : Fin n × G => ℂ) 2

/-- The identity vector in component i. -/
def identityVector {G : Type} [Group G] {n : ℕ} (i : Fin n) : Hilbert G n :=
  by
    classical
    exact lp.single 2 (i, 1) 1

/-- The unnormalized matrix trace, linear in its operator argument. -/
def groupTrace {G : Type} [Group G] {n : ℕ}
    (T : Hilbert G n →L[ℂ] Hilbert G n) : ℂ :=
  ∑ i : Fin n, inner ℂ (identityVector i) (T (identityVector i))

/-- The invertible-case Fuglede--Kadison determinant.
It is used below only for invertible regular operators. -/
def fkDet {G : Type} [Group G] {n : ℕ}
    (T : Hilbert G n →L[ℂ] Hilbert G n) : ℝ :=
  Real.exp ((groupTrace (CFC.log (star T * T))).re / 2)

/-- Exact coordinate specification of the bounded left-regular operator of A. -/
def IsRegularOperator {G : Type} [Group G] {n : ℕ}
    (A : Matrix (Fin n) (Fin n) (MonoidAlgebra ℤ G))
    (T : Hilbert G n →L[ℂ] Hilbert G n) : Prop :=
  ∀ (ξ : Hilbert G n) (i : Fin n) (h : G),
    (T ξ) (i, h) = ∑ j : Fin n,
      (A i j).coeff.sum fun g z => (z : ℂ) * ξ (j, g⁻¹ * h)

/-- Coefficientwise extension from the integral to the rational group ring. -/
def rationalMatrix {G : Type} [Group G] {n : ℕ}
    (A : Matrix (Fin n) (Fin n) (MonoidAlgebra ℤ G)) :
    Matrix (Fin n) (Fin n) (MonoidAlgebra ℚ G) :=
  A.map (MonoidAlgebra.mapRingHom G (Int.castRingHom ℚ))

/-- An integral group-ring matrix with rational and bounded inverses and determinant in (0, 1). -/
def MainStatement : Prop :=
  ∃ (G : Type) (_ : Group G) (_ : Group.FG G) (n : ℕ),
    1 ≤ n ∧ ∃ (A : Matrix (Fin n) (Fin n) (MonoidAlgebra ℤ G))
      (T : Hilbert G n →L[ℂ] Hilbert G n),
      IsUnit (rationalMatrix A) ∧ IsRegularOperator A T ∧ IsUnit T ∧
        0 < fkDet T ∧ fkDet T < 1

theorem main : MainStatement := by
  sorry

end GroupRingDeterminant

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/GroupRingDeterminant.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.GroupRingDeterminant.main` must keep exactly the statement shown above: same names,
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
