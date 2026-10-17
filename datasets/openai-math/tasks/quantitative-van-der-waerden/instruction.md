# openai/math challenge `QuantitativeVanDerWaerden` (family 160)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 160 of the release, *Superexponential van der Waerden numbers*
(Combinatorics). The family as a whole: Resolves Erd\H{o}s's superexponential-growth question for van der Waerden numbers. If $W_r(k)$ is the least interval length forcing a monochromatic $k$-term progression in every $r$-coloring, then $W_r(k)>k^{ck\lfloor\log_2 r\rfloor}$ for an absolute $c>0$, all $r\ge2$ and sufficiently large $k$, uniformly in $r$. In particular, $W_r(k)^{1/k}\to\infty$ for each fixed $r$.

The challenge is `QuantitativeVanDerWaerden`, also at `/opt/openai-math/challenges/QuantitativeVanDerWaerden.lean`:

```lean
import Mathlib

namespace OAI

universe u

namespace QuantitativeVanDerWaerden

def MonoAP {α : Type u} (c : ℕ → α) (k a d : ℕ) : Prop :=
  ∀ j < k, c (a + j * d) = c a

def HasMonoAP {α : Type u} (c : ℕ → α) (k N : ℕ) : Prop :=
  ∃ a d, 0 < d ∧ a + (k - 1) * d < N ∧ MonoAP c k a d

def IsRamsey (α : Type u) (k N : ℕ) : Prop :=
  ∀ c : ℕ → α, HasMonoAP c k N

/-- The least positive Ramsey interval size. Statements about its Ramsey
property require a finiteness proof; no such proof is built into this definition. -/
noncomputable def W (r k : ℕ) : ℕ :=
  sInf {N : ℕ | 0 < N ∧ IsRamsey (Fin r) k N}

open Filter

/-- An absolute quantitative lower bound, uniform over all color counts. -/
theorem uniform_lower_bound :
    ∃ K : ℕ, ∀ k ≥ K, ∀ r ≥ 2,
      (k : ℝ) ^ ((1 / 100000 : ℝ) * k * (Nat.log 2 r : ℝ)) < (W r k : ℝ) := by
  sorry

end QuantitativeVanDerWaerden

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/QuantitativeVanDerWaerden.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.QuantitativeVanDerWaerden.uniform_lower_bound` must keep exactly the statement shown above: same names,
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
