# openai/math challenge `Rokhlin` (family 145)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 145 of the release, *Rokhlin's multiple-mixing problem*
(Dynamical systems and ergodic theory). The family as a whole: Proves that every invertible mixing probability-preserving transformation is mixing of all finite orders, resolving Rokhlin's multiple-mixing problem for a single transformation. Correlations among any finite collection of measurable sets converge to the product of their measures whenever all pairwise time separations diverge.

The challenge is `Rokhlin`, also at `/opt/openai-math/challenges/Rokhlin.lean`:

```lean
import Mathlib

namespace OAI

open MeasureTheory Filter
open scoped BigOperators Topology

namespace Rokhlin

variable {Ω : Type*} [MeasurableSpace Ω]

def timeMap (T : Ω ≃ᵐ Ω) (n : ℤ) : Ω → Ω :=
  ⇑((T.toEquiv : Equiv.Perm Ω) ^ n)

def IsMixing (μ : Measure Ω) (T : Ω ≃ᵐ Ω) : Prop :=
  ∀ A B : Set Ω, MeasurableSet A → MeasurableSet B →
    Tendsto (fun n : ℤ => μ (A ∩ timeMap T n ⁻¹' B))
      (comap Int.natAbs atTop) (𝓝 (μ A * μ B))

def layoutTime {k : ℕ} (gaps : Fin (k - 1) → ℕ+) (i : Fin k) : ℕ :=
  ∑ j : Fin (k - 1), if j.val < i.val then (gaps j : ℕ) else 0

def MixingOfOrder (μ : Measure Ω) (T : Ω ≃ᵐ Ω) (k : ℕ) : Prop :=
  ∀ A : Fin k → Set Ω, (∀ i, MeasurableSet (A i)) →
    Tendsto
      (fun gaps : Fin (k - 1) → ℕ+ =>
        μ (⋂ i : Fin k, timeMap T (layoutTime gaps i : ℤ) ⁻¹' A i))
      atTop (𝓝 (∏ i : Fin k, μ (A i)))

theorem mixing_all_finite_orders (μ : Measure Ω) [IsProbabilityMeasure μ]
    (T : Ω ≃ᵐ Ω) (h_pres : MeasurePreserving T μ μ) (h_mix : IsMixing μ T) :
    ∀ k : ℕ, 3 ≤ k → MixingOfOrder μ T k := by
  sorry

end Rokhlin

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/Rokhlin.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Rokhlin.mixing_all_finite_orders` must keep exactly the statement shown above: same names,
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
