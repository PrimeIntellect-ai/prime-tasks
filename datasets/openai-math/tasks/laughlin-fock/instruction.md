# openai/math challenge `LaughlinFock` (family 269)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 269 of the release, *The Laughlin gap and stability under scalar disorder*
(Mathematical physics). The family as a whole: Proves the fermionic Laughlin spectral-gap conjecture for the full $V_1$ interaction at filling $1/3$ on the round sphere. The unique ground state remains uniformly gapped under sufficiently weak bounded real scalar one-body potentials projected to the lowest Landau level. Both the gap and disorder threshold are uniform over all sufficiently large particle numbers and all normalized potential profiles.

The challenge is `LaughlinFock`, also at `/opt/openai-math/challenges/LaughlinFock.lean`:

```lean
import Mathlib

namespace OAI

/-! The spherical V₁ Hamiltonian inequality on the full fermionic Fock space. -/

noncomputable section

namespace Laughlin

noncomputable def pairCoefficient (Q p : ℕ) (x y : Fin (Q+1)) : ℝ :=
  if x.val + y.val = p+1 then
    ((x.val : ℝ) - (y.val : ℝ)) *
      Real.sqrt (((Q.descFactorial x.val : ℝ) * (Q.descFactorial y.val : ℝ) *
        (p.factorial : ℝ)) /
        ((Q : ℝ) * ((2*Q-2).descFactorial p : ℝ) *
          (x.val.factorial : ℝ) * (y.val.factorial : ℝ))) / Real.sqrt 2
  else 0

end Laughlin

run_cmd Lean.modifyEnv fun environment => Lean.Meta.auxLemmasExt.setState environment {}

namespace LaughlinFock

open scoped BigOperators Matrix ComplexConjugate ComplexOrder

abbrev Orbital (Q : ℕ) := Fin (Q + 1)
abbrev Occupation (Q : ℕ) := Finset (Orbital Q)
abbrev FockMatrix (Q : ℕ) := Matrix (Occupation Q) (Occupation Q) ℂ

def tensorPairCoefficient (Q p : ℕ) (i j : Orbital Q) : ℝ :=
  _root_.OAI.Laughlin.pairCoefficient Q p i j

def pairCoefficient (Q p : ℕ) (i j : Orbital Q) : ℝ :=
  Real.sqrt 2 * tensorPairCoefficient Q p i j

def annihilator (Q : ℕ) (j : Orbital Q) : FockMatrix Q := fun A B =>
  if j ∈ B ∧ A = B.erase j then
    (-1 : ℂ) ^ (B.filter (fun i => i < j)).card
  else 0

def pairAnnihilator (Q p : ℕ) : FockMatrix Q :=
  ∑ i : Orbital Q, ∑ j : Orbital Q,
    if i < j then
      (pairCoefficient Q p i j : ℂ) • (annihilator Q j * annihilator Q i)
    else 0

def hamiltonian (Q : ℕ) : FockMatrix Q :=
  ∑ p ∈ Finset.range (2 * Q - 1),
    (pairAnnihilator Q p)ᴴ * pairAnnihilator Q p

def gammaStar : ℝ := 4616733319001 / 10 ^ 14

def FockInequality (Q : ℕ) (γ : ℝ) : Prop :=
  (hamiltonian Q * hamiltonian Q - γ • hamiltonian Q).PosSemidef

theorem thm_fock (γ : ℝ) (hγ : 0 < γ) (hγStar : γ < gammaStar) :
    ∃ Qγ : ℤ, 1 ≤ Qγ ∧ ∀ Q : ℤ, Qγ ≤ Q → FockInequality Q.toNat γ := by
  sorry

end LaughlinFock

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/LaughlinFock.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.LaughlinFock.thm_fock` must keep exactly the statement shown above: same names,
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
