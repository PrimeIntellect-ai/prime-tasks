# openai/math challenge `SharpLogRamsey` (family 170)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 170 of the release, *Sharp logarithmic exponents for off-diagonal Ramsey numbers*
(Combinatorics). The family as a whole: For every fixed integer $s\ge5$, proves $r(s,t)=t^{s-1}/(\log t)^{s-2+o(1)}$ as $t\to\infty$, determining the logarithmic exponent and matching the classical upper bound at that scale. Here $r(s,t)$ is the least number of vertices forcing an $s$-clique or a $t$-vertex independent set.

The challenge is `SharpLogRamsey`, also at `/opt/openai-math/challenges/SharpLogRamsey.lean`:

```lean
import Mathlib

namespace OAI

namespace SharpLogRamsey

/-- Every graph has an s-clique or an independent set of size t. -/
def RamseyProperty (s t N : ℕ) : Prop :=
  ∀ G : SimpleGraph (Fin N),
    (∃ A : Finset (Fin N), G.IsNClique s A) ∨
    (∃ B : Finset (Fin N), Gᶜ.IsNClique t B)

noncomputable def ramsey (s t : ℕ) : ℕ := sInf {N | RamseyProperty s t N}

/-- The upper-bound constant is chosen independently of epsilon. -/
def MainBounds (s : ℕ) : Prop :=
  ∃ C : ℝ, 0 < C ∧ ∀ ε : ℝ, 0 < ε →
    ∃ t₀ : ℕ, ∀ t : ℕ, t₀ ≤ t →
      (t : ℝ) ^ (s - 1) / Real.rpow (Real.log (t : ℝ)) ((s - 2 : ℕ) + ε)
        ≤ (ramsey s t : ℝ) ∧
      (ramsey s t : ℝ) ≤ C * (t : ℝ) ^ (s - 1) /
        (Real.log (t : ℝ)) ^ (s - 2)

/-- The logarithmic exponent converges along all natural orders. -/
def MainLimit (s : ℕ) : Prop :=
  Filter.Tendsto
    (fun t : ℕ =>
      (((s - 1 : ℕ) : ℝ) * Real.log (t : ℝ) - Real.log (ramsey s t : ℝ)) /
        Real.log (Real.log (t : ℝ)))
    Filter.atTop (nhds ((s - 2 : ℕ) : ℝ))

theorem main (s : ℕ) (hs : 6 ≤ s) : MainBounds s ∧ MainLimit s := by
  sorry

end SharpLogRamsey

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/SharpLogRamsey.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.SharpLogRamsey.main` must keep exactly the statement shown above: same names,
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
