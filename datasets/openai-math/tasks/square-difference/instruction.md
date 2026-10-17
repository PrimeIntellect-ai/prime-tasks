# openai/math challenge `SquareDifference` (family 182)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 182 of the release, *Power savings for polynomial-difference-free sets*
(Combinatorics). The family as a whole: For every fixed intersective integer polynomial $h$ of degree $k\ge2$ with positive leading coefficient, proves that a subset of $\{1,\ldots,N\}$ avoiding nonzero values $h(1),h(2),\ldots$ as differences has size $O_h(N^{1-c_k})$, with $c_k>0$ depending only on degree. Here intersective means having a root modulo every modulus. For prime arguments, a power saving also holds when $h$ has a unit root modulo every modulus, with exponent allowed to depend on $h$.

The challenge is `SquareDifference`, also at `/opt/openai-math/challenges/SquareDifference.lean`:

```lean
import Mathlib

namespace OAI

namespace SquareDifference

def IsSquareDifferenceFree (A : Finset ℤ) : Prop :=
  ∀ a ∈ A, ∀ b ∈ A, ∀ m : ℕ, 1 ≤ m → a - b ≠ (m : ℤ) ^ 2

theorem power_saving :
    ∃ c C : ℝ, 0 < c ∧ ∀ N : ℕ, 1 ≤ N → ∀ A : Finset ℤ,
      A ⊆ Finset.Icc 1 (N : ℤ) → SquareDifference.IsSquareDifferenceFree A →
        (A.card : ℝ) ≤ C * (N : ℝ) ^ (1 - c) := by
  sorry

end SquareDifference

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/SquareDifference.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.SquareDifference.power_saving` must keep exactly the statement shown above: same names,
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
