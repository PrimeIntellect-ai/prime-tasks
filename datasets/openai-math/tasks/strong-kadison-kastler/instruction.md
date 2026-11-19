# openai/math challenge `StrongKadisonKastler` (family 289)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 289 of the release, *The strong Kadison–Kastler conjecture*
(Operator algebras). The family as a whole: Proves that sufficiently close unital von Neumann algebras on the same Hilbert space are conjugate by a unitary arbitrarily close to the identity, with a universal tolerance in the operator-norm distance between unit balls. Counterexamples show that near-identity conjugacy fails for one-sided near inclusions, and that arbitrarily close norm-separable $C^*$-algebras need not be ambiently unitarily conjugate.

The challenge is `StrongKadisonKastler`, also at `/opt/openai-math/challenges/StrongKadisonKastler.lean`:

```lean
import Mathlib

namespace OAI

/-! Theorem 1.1 of *Universal strong Kadison–Kastler stability*:
one tolerance gives small unitary conjugacies on every complex Hilbert space. -/

namespace KadisonKastler

noncomputable section

universe u

variable {H : Type u} [NormedAddCommGroup H] [InnerProductSpace ℂ H] [CompleteSpace H]

def unitBall (M : VonNeumannAlgebra H) : Set (H →L[ℂ] H) :=
  {x | x ∈ M ∧ ‖x‖ ≤ 1}

noncomputable def kkDistance (M N : VonNeumannAlgebra H) : ℝ :=
  Metric.hausdorffDist (unitBall M) (unitBall N)

def unitaryConj (v : unitary (H →L[ℂ] H)) (x : H →L[ℂ] H) : H →L[ℂ] H :=
  (v : H →L[ℂ] H) * x * star (v : H →L[ℂ] H)

def Conjugates (v : unitary (H →L[ℂ] H)) (M N : VonNeumannAlgebra H) : Prop :=
  unitaryConj v '' (M : Set (H →L[ℂ] H)) = (N : Set (H →L[ℂ] H))

def NearConjugacy (M N : VonNeumannAlgebra H) (ε : ℝ) : Prop :=
  ∃ v : unitary (H →L[ℂ] H), Conjugates v M N ∧ ‖(v : H →L[ℂ] H) - 1‖ < ε

def UniversalStrongStability : Prop :=
  ∀ ε : ℝ, 0 < ε → ∃ δ : ℝ, 0 < δ ∧
    ∀ (H : Type u) [NormedAddCommGroup H] [InnerProductSpace ℂ H] [CompleteSpace H],
      ∀ M N : VonNeumannAlgebra H,
        kkDistance M N < δ → NearConjugacy M N ε

theorem universal_strong_stability : UniversalStrongStability.{u} := by
  sorry

end

end KadisonKastler

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/StrongKadisonKastler.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.KadisonKastler.universal_strong_stability` must keep exactly the statement shown above: same names,
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
