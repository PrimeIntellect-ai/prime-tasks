# openai/math challenge `Superstring` (family 128)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 128 of the release, *A factor-two approximation for shortest common superstring*
(Theoretical computer science). The family as a whole: Gives a deterministic polynomial-time algorithm constructing a common superstring of length at most twice the optimum for every finite family of explicitly represented strings. The running time is polynomial in the full encoded input length, including symbol labels.

The challenge is `Superstring`, also at `/opt/openai-math/challenges/Superstring.lean`:

```lean
import Mathlib

namespace OAI

namespace Superstring

abbrev Symbol := List Bool
abbrev Word := List Symbol
abbrev Instance := List Word

/-- Prefix markers encode the list spine, including its final boundary. -/
def encodeList {α : Type} (enc : α → List Bool) : List α → List Bool
  | [] => [true]
  | a :: as => false :: (enc a ++ encodeList enc as)

def encodeSymbol : Symbol → List Bool := encodeList (fun b => [b])
def encodeWord : Word → List Bool := encodeList encodeSymbol
def encodeInstance : Instance → List Bool := encodeList encodeWord

/-- Ordinary contiguous substring containment, including the empty word. -/
def IsCommonSuperstring (S : Instance) (T : Word) : Prop :=
  ∀ s ∈ S, s <:+: T

/-- The optimum in symbols, not in bits. -/
noncomputable def opt (S : Instance) : ℕ :=
  sInf {n : ℕ | ∃ T : Word, IsCommonSuperstring S T ∧ T.length = n}

/-- A deterministic finite-stack-machine implementation, with a polynomial bound
on bit-level running time in the explicitly encoded input length. -/
def HasPolynomialImplementation (f : Instance → Word) : Prop :=
  ∃ M : Turing.TM2ComputableInPolyTime encodeInstance encodeWord f,
    ∀ k : M.tm.K, Finite (M.tm.Γ k)

/-- The deterministic algorithm with its exact finite-alphabet bit-machine
certificate, contiguous coverage, and factor-two bound in symbols. -/
theorem main : ∃ f : Instance → Word,
    HasPolynomialImplementation f ∧
    ∀ S, IsCommonSuperstring S (f S) ∧ (f S).length ≤ 2 * opt S := by
  sorry

end Superstring

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/Superstring.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Superstring.main` must keep exactly the statement shown above: same names,
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
