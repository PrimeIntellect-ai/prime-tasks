# openai/math challenge `PowerFreeValues` (family 020)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 020 of the release, *Squarefree quartics and power-free polynomial values*
(Number theory). The family as a whole: Proves the squarefree-values conjecture for irreducible integer quartics with no fixed prime-square divisor: squarefree values on positive integers have the predicted positive Euler-product density. More generally, establishes the $(d-2)$-power-free density for irreducible integer polynomials of degrees four through eight under the necessary local condition; together with Browning's higher-degree theorem, this covers every $d\ge4$.

The challenge is `PowerFreeValues`, also at `/opt/openai-math/challenges/PowerFreeValues.lean`:

```lean
import Mathlib

namespace OAI



open Filter Asymptotics
open scoped Topology

namespace QuarticPowerFree

def PowerFree (k : ℕ) (a : ℤ) : Prop :=
  ∀ p : ℕ, p.Prime → ¬ (p : ℤ) ^ k ∣ a

def rho (f : Polynomial ℤ) (q : ℕ) : ℕ :=
  ((Finset.range q).filter fun a : ℕ => (q : ℤ) ∣ f.eval (a : ℤ)).card

noncomputable def count (f : Polynomial ℤ) (k : ℕ) (X : ℝ) : ℕ := by
  classical
  exact ((Finset.Icc 1 ⌊X⌋₊).filter fun n : ℕ => PowerFree k (f.eval (n : ℤ))).card

def LocallyAdmissible (f : Polynomial ℤ) (k : ℕ) : Prop :=
  ∀ p : ℕ, p.Prime → rho f (p ^ k) < p ^ k

noncomputable def localFactor (f : Polynomial ℤ) (k : ℕ) (p : Nat.Primes) : ℝ :=
  1 - (rho f (p.val ^ k) : ℝ) / (p.val : ℝ) ^ k

noncomputable def densityConstant (f : Polynomial ℤ) (k : ℕ) : ℝ :=
  ∏' p : Nat.Primes, localFactor f k p

def DensityStatement (f : Polynomial ℤ) (k : ℕ) : Prop :=
  Multipliable (localFactor f k) ∧
  0 < densityConstant f k ∧
  (fun X : ℝ => (count f k X : ℝ) - densityConstant f k * X) =o[atTop]
    (fun X : ℝ => X)

theorem allDegrees (f : Polynomial ℤ)
    (hirr : Irreducible (f.map (Int.castRingHom ℚ)))
    (hdeglo : 4 ≤ f.natDegree)
    (hlocal : LocallyAdmissible f (f.natDegree - 2)) :
    DensityStatement f (f.natDegree - 2) := by
  sorry

end QuarticPowerFree

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/PowerFreeValues.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.QuarticPowerFree.allDegrees` must keep exactly the statement shown above: same names,
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
