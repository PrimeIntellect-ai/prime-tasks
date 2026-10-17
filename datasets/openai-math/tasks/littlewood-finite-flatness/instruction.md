# openai/math challenge `LittlewoodFiniteFlatness` (family 076)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 076 of the release, *Ultraflat real Littlewood polynomials*
(Real and complex analysis). The family as a whole: Constructs polynomials with $N$ consecutive coefficients in $\{-1,1\}$ whose modulus is $(1+o(1))\sqrt N$ uniformly on the entire unit circle, for every sufficiently large integer length $N$. Thus real Littlewood polynomials are ultraflat, including at the real endpoints. Their binary merit factors tend to infinity, disproving Turyn's bounded-merit-factor conjecture.

The challenge is `LittlewoodFiniteFlatness`, also at `/opt/openai-math/challenges/LittlewoodFiniteFlatness.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open MeasureTheory Filter Complex
open scoped BigOperators Topology ComplexConjugate

namespace AsymptoticallyMinimalLittlewoodFiniteFlatness

/-- The consecutive-degree polynomial of a real coefficient family. -/
def littlewoodValue {N : ℕ} (ε : Fin N → ℝ) (z : ℂ) : ℂ :=
  ∑ k : Fin N, (ε k : ℂ) * z ^ (k : ℕ)

/-- Every coefficient is a real sign. -/
def IsRealSigning {N : ℕ} (ε : Fin N → ℝ) : Prop :=
  ∀ k, ε k = -1 ∨ ε k = 1

def MainStatement : Prop :=
  ∃ ε : (N : ℕ) → Fin N → ℝ,
    (∀ N : ℕ, IsRealSigning (ε N)) ∧
    ∀ p : ℝ, 0 < p →
      Filter.Tendsto
        (fun N : ℕ =>
          ∫ t : UnitAddCircle,
            Real.rpow
              |‖littlewoodValue (ε N) (fourier (1 : ℤ) t)‖ /
                  Real.sqrt (N : ℝ) - 1|
              p
            ∂AddCircle.haarAddCircle)
        Filter.atTop (𝓝 (0 : ℝ))

/-- One all-length real-sign family for every finite positive real exponent. -/
theorem main : MainStatement := by
  sorry

end AsymptoticallyMinimalLittlewoodFiniteFlatness

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/LittlewoodFiniteFlatness.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.AsymptoticallyMinimalLittlewoodFiniteFlatness.main` must keep exactly the statement shown above: same names,
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
