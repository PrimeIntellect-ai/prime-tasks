# openai/math challenge `Laughlin` (family 269)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 269 of the release, *The Laughlin gap and stability under scalar disorder*
(Mathematical physics). The family as a whole: Proves the fermionic Laughlin spectral-gap conjecture for the full $V_1$ interaction at filling $1/3$ on the round sphere. The unique ground state remains uniformly gapped under sufficiently weak bounded real scalar one-body potentials projected to the lowest Landau level. Both the gap and disorder threshold are uniform over all sufficiently large particle numbers and all normalized potential profiles.

The challenge is `Laughlin`, also at `/opt/openai-math/challenges/Laughlin.lean`:

```lean
import Mathlib

namespace OAI

namespace Laughlin
open scoped BigOperators

abbrev Configuration (N Q : ℕ) := Fin N → Fin (Q+1)
abbrev State (N Q : ℕ) := Configuration N Q → ℂ

def Antisymmetric {N Q : ℕ} (ψ : State N Q) : Prop :=
  ∀ (i j : Fin N), i ≠ j → ∀ a, ψ (a ∘ Equiv.swap i j) = -ψ a

noncomputable def pairCoefficient (Q p : ℕ) (x y : Fin (Q+1)) : ℝ :=
  if x.val + y.val = p+1 then
    ((x.val : ℝ) - (y.val : ℝ)) *
      Real.sqrt (((Q.descFactorial x.val : ℝ) * (Q.descFactorial y.val : ℝ) *
        (p.factorial : ℝ)) /
        ((Q : ℝ) * ((2*Q-2).descFactorial p : ℝ) *
          (x.val.factorial : ℝ) * (y.val.factorial : ℝ))) / Real.sqrt 2
  else 0

noncomputable def pairAmplitude {N Q : ℕ} (ψ : State N Q)
    (i j : Fin N) (p : ℕ) (a : Configuration N Q) : ℂ :=
  ∑ x : Fin (Q+1), ∑ y : Fin (Q+1),
    (pairCoefficient Q p x y : ℂ) * ψ (Function.update (Function.update a i x) j y)

noncomputable def energy {N Q : ℕ} (ψ : State N Q) : ℝ :=
  ∑ i : Fin N, ∑ j : Fin N, if i < j then
    ∑ p ∈ Finset.range (2*Q-1), ∑ a : Configuration N Q,
      if a i = 0 ∧ a j = 0 then ‖pairAmplitude ψ i j p a‖ ^ 2 else 0
  else 0

abbrev SpinorVariables (N : ℕ) := Fin N × Bool

noncomputable def bracket {N : ℕ} (i j : Fin N) : MvPolynomial (SpinorVariables N) ℂ :=
  MvPolynomial.X (i,false) * MvPolynomial.X (j,true) -
    MvPolynomial.X (j,false) * MvPolynomial.X (i,true)

noncomputable def laughlinPolynomial (N : ℕ) : MvPolynomial (SpinorVariables N) ℂ :=
  ∏ i : Fin N, ∏ j : Fin N, if i < j then bracket i j ^ 3 else 1

noncomputable def monomialExponent {N Q : ℕ} (a : Configuration N Q) : SpinorVariables N →₀ ℕ :=
  Finsupp.onFinset Finset.univ
    (fun ib => if ib.2 then (a ib.1).val else Q - (a ib.1).val)
    (by intro; simp)

noncomputable def laughlinVector (N Q : ℕ) : State N Q := fun a =>
  (laughlinPolynomial N).coeff (monomialExponent a) /
    ((∏ i : Fin N, Real.sqrt (Nat.choose Q (a i).val : ℝ) : ℝ) : ℂ)

noncomputable def distanceToLaughlinSq {N Q : ℕ} (ψ : State N Q) : ℝ :=
  sInf (Set.range (fun c : ℂ => ∑ a : Configuration N Q,
    ‖ψ a - c * laughlinVector N Q a‖ ^ 2))

def MainTarget : Prop :=
  ∃ N₀ : ℕ, 2 ≤ N₀ ∧ ∀ N : ℕ, N₀ ≤ N →
    ∀ ψ : State N (3*(N-1)), Antisymmetric ψ →
      (1/100 : ℝ) * distanceToLaughlinSq ψ ≤ energy ψ

theorem mainTarget_proved : MainTarget := by
  sorry

end Laughlin

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/Laughlin.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Laughlin.mainTarget_proved` must keep exactly the statement shown above: same names,
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
