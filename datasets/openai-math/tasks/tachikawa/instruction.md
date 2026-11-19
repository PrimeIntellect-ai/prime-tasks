# openai/math challenge `Tachikawa` (family 199)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 199 of the release, *Counterexamples to conjectures of Auslander–Reiten, Tachikawa, and Nakayama*
(Algebra). The family as a whole: Constructs finite-dimensional algebras over a characteristic-two rational-function field that disprove the Auslander–Reiten and Gorenstein-projective conjectures, and Tachikawa's second conjecture. An associated endomorphism algebra also disproves the classical, generalized and strong Nakayama conjectures, the Auslander–Gorenstein conjecture, and the Wakamatsu tilting conjecture. The counterexamples persist under every extension of the base field.

The challenge is `Tachikawa`, also at `/opt/openai-math/challenges/Tachikawa.lean`:

```lean
import Mathlib

namespace OAI

namespace Tachikawa

noncomputable section

abbrev k := FractionRing (MvPolynomial (Fin 3) (ZMod 2))

def SymmetricOver (K A : Type) [Field K] [Ring A] [Algebra K A] : Prop :=
  ∃ e : A ≃ₗ[K] Module.Dual K A,
    (∀ a b c : A, e (a * b) c = e b (c * a)) ∧
    (∀ a b c : A, e (a * b) c = e a (b * c))

def Counterexample : Prop :=
  ∃ (A : Type) (rA : Ring A),
    letI := rA
    ∃ (aA : Algebra k A),
      letI := aA
      Module.Finite k A ∧ SymmetricOver k A ∧
      ∃ (M : Type) (gM : AddCommGroup M),
        letI := gM
        ∃ (mA : Module A M) (mk : Module k M),
          letI := mA
          letI := mk
          IsScalarTower k A M ∧ Module.Finite k M ∧
          ¬ Module.Projective A M ∧
          ∀ n : ℕ, 0 < n →
            Subsingleton (CategoryTheory.Abelian.Ext (ModuleCat.of A M) (ModuleCat.of A M) n)

theorem main_theorem : Counterexample := by
  sorry

end

end Tachikawa

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/Tachikawa.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Tachikawa.main_theorem` must keep exactly the statement shown above: same names,
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
