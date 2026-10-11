# openai/math challenge `GotsmanLinial` (family 127)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 127 of the release, *The asymptotic Gotsman–Linial conjecture*
(Theoretical computer science). The family as a whole: Proves that a degree-at-most-$d$ polynomial threshold function on the uniform $n$-dimensional Boolean cube has average sensitivity at most $8d\sqrt n$, uniformly for $1\le d\le n$. Average sensitivity counts expected output changes under single-bit flips. This establishes the asymptotic Gotsman–Linial conjecture, allowing polynomial zeros with $\operatorname{sign}(0)=1$.

The challenge is `GotsmanLinial`, also at `/opt/openai-math/challenges/GotsmanLinial.lean`:

```lean
import Mathlib.Algebra.MvPolynomial.Degrees
import Mathlib.Algebra.BigOperators.Field
import Mathlib.Data.Fintype.BigOperators
import Mathlib.Analysis.Real.Sqrt
import Mathlib.Tactic.NormNum

namespace OAI

open scoped BigOperators

namespace LeanBlast.GotsmanLinial

abbrev Cube (n : ℕ) := Fin n → Bool

def cubeCoord {n : ℕ} (x : Cube n) (i : Fin n) : ℝ :=
  if x i then 1 else -1

def flip {n : ℕ} (i : Fin n) (x : Cube n) : Cube n :=
  Function.update x i (!(x i))

noncomputable def thresholdSign (t : ℝ) : ℝ :=
  if 0 ≤ t then 1 else -1

noncomputable def sensitiveVertices {n : ℕ} (f : Cube n → ℝ) (i : Fin n) :
    Finset (Cube n) := by
  classical
  exact Finset.univ.filter fun x => f x ≠ f (flip i x)

noncomputable def averageSensitivity {n : ℕ} (f : Cube n → ℝ) : ℝ :=
  ∑ i : Fin n, ((sensitiveVertices f i).card : ℝ) / (2 : ℝ) ^ n

def IsMultilinear {n : ℕ} (p : MvPolynomial (Fin n) ℝ) : Prop :=
  ∀ m ∈ p.support, ∀ i : Fin n, m i ≤ 1

noncomputable def polynomialValue {n : ℕ} (p : MvPolynomial (Fin n) ℝ)
    (x : Cube n) : ℝ :=
  MvPolynomial.eval (cubeCoord x) p

noncomputable def polynomialThreshold {n : ℕ} (p : MvPolynomial (Fin n) ℝ) :
    Cube n → ℝ :=
  fun x => thresholdSign (polynomialValue p x)

def GotsmanLinialStatement : Prop :=
  ∀ (n d : ℕ), 1 ≤ n → 1 ≤ d → d ≤ n →
    ∀ p : MvPolynomial (Fin n) ℝ,
      IsMultilinear p → p.totalDegree ≤ d →
        averageSensitivity (polynomialThreshold p) ≤ 8 * (d : ℝ) * Real.sqrt (n : ℝ)

theorem gotsmanLinialStatement : GotsmanLinialStatement := by
  sorry

end LeanBlast.GotsmanLinial

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/GotsmanLinial.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.LeanBlast.GotsmanLinial.gotsmanLinialStatement` must keep exactly the statement shown above: same names,
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
