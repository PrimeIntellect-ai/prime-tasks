# openai/math challenge `ExactFourier` (family 130)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 130 of the release, *Fourier transforms below $n\log n$*
(Theoretical computer science). The family as a whole: Gives a deterministic length-$n$ discrete Fourier transform algorithm using $O(n(\log n)^{1-\delta})$ operations for every $n$, with explicit $\delta=10^{-13}$. The model uses exact complex arithmetic, unrestricted coefficients and a supplied root of unity, and counts scalar preparation and logarithmic-word indexing.

The challenge is `ExactFourier`, also at `/opt/openai-math/challenges/ExactFourier.lean`:

```lean
import Mathlib

namespace OAI

/-!
Scalar circuits for exact discrete Fourier transforms.
No bounds on predetermined complex coefficients, reuse, storage, or conditioning.
-/

namespace ExactFourier

/-- One charged scalar gate, referencing only available values. -/
inductive Gate (w : ℕ) where
  | add (i j : Fin w)
  | sub (i j : Fin w)
  | scale (c : ℂ) (i : Fin w)

def Gate.eval {w : ℕ} (v : Fin w → ℂ) : Gate w → ℂ
  | .add i j => v i + v j
  | .sub i j => v i - v j
  | .scale c i => c * v i

/-- A topologically ordered scalar DAG; available values are never consumed. -/
inductive Program (n : ℕ) : ℕ → Type where
  | nil : Program n 0
  | step {k : ℕ} (p : Program n k) (g : Gate (n + 1 + k)) : Program n (k + 1)

def Program.eval {n : ℕ} : {k : ℕ} → Program n k → (Fin n → ℂ) →
    (Fin (n + 1 + k) → ℂ)
  | 0, .nil, x => Fin.snoc x 0
  | _ + 1, .step p g, x =>
      let v := p.eval x
      Fin.snoc v (g.eval v)

/-- Outputs name available values, so permutations and arbitrary fanout are uncharged. -/
structure Circuit (n : ℕ) where
  size : ℕ
  program : Program n size
  outputs : Fin n → Fin (n + 1 + size)

def Circuit.eval {n : ℕ} (C : Circuit n) (x : Fin n → ℂ) : Fin n → ℂ :=
  fun i => C.program.eval x (C.outputs i)

noncomputable def zeta (n : ℕ) : ℂ := Complex.exp (2 * Real.pi * Complex.I / (n : ℂ))
noncomputable def fourierMatrix (n : ℕ) : Matrix (Fin n) (Fin n) ℂ :=
  fun j k => zeta n ^ (j.val * k.val)

def Circuit.Computes {n : ℕ} (C : Circuit n) (A : Matrix (Fin n) (Fin n) ℂ) : Prop :=
  ∀ x, C.eval x = A.mulVec x

/-- The precise quantified formulation of source theorem `thm:main`. -/
def MainStatement : Prop :=
  ∀ c : ℝ, 0 < c → ∀ N₀ : ℕ, 2 ≤ N₀ → ∃ n : ℕ, N₀ ≤ n ∧
    ∃ C : Circuit n, C.Computes (fourierMatrix n) ∧
      (C.size : ℝ) < c * (n : ℝ) * Real.logb 2 (n : ℝ)

theorem main_theorem : MainStatement := by
  sorry

end ExactFourier

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/ExactFourier.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.ExactFourier.main_theorem` must keep exactly the statement shown above: same names,
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
