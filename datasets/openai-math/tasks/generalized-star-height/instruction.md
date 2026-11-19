# openai/math challenge `GeneralizedStarHeight` (family 134)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 134 of the release, *Generalized star height at most three*
(Theoretical computer science). The family as a whole: Every regular language over a finite alphabet has a generalized regular expression with at most three nested Kleene stars, allowing union, concatenation and complement over the same alphabet. This establishes an absolute bound independent of automaton size, resolving the uniform-boundedness version of the generalized star-height problem.

The challenge is `GeneralizedStarHeight`, also at `/opt/openai-math/challenges/GeneralizedStarHeight.lean`:

```lean
import Mathlib

namespace OAI

namespace GeneralizedStarHeight

universe u

inductive Expression (Alphabet : Type u) : Type u
  | zero : Expression Alphabet
  | one : Expression Alphabet
  | letter : Alphabet → Expression Alphabet
  | union : Expression Alphabet → Expression Alphabet → Expression Alphabet
  | concat : Expression Alphabet → Expression Alphabet → Expression Alphabet
  | compl : Expression Alphabet → Expression Alphabet
  | star : Expression Alphabet → Expression Alphabet

namespace Expression

open scoped Computability

def language {Alphabet : Type u} : Expression Alphabet → Language Alphabet
  | .zero => 0
  | .one => 1
  | .letter a => {[a]}
  | .union P Q => P.language + Q.language
  | .concat P Q => P.language * Q.language
  | .compl P => P.languageᶜ
  | .star P => P.language∗

def height {Alphabet : Type u} : Expression Alphabet → ℕ
  | .zero | .one | .letter _ => 0
  | .union P Q | .concat P Q => max P.height Q.height
  | .compl P => P.height
  | .star P => 1 + P.height

end Expression

def HasHeightAtMost {Alphabet : Type u} (L : Language Alphabet) (n : ℕ) : Prop :=
  ∃ P : Expression Alphabet, P.language = L ∧ P.height ≤ n

theorem main {Alphabet : Type u} [Finite Alphabet] (L : Language Alphabet) (hL : L.IsRegular) :
    HasHeightAtMost L 3 := by
  sorry

end GeneralizedStarHeight

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/GeneralizedStarHeight.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.GeneralizedStarHeight.main` must keep exactly the statement shown above: same names,
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
