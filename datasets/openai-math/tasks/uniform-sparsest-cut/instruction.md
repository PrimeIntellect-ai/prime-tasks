# openai/math challenge `UniformSparsestCut` (family 117)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 117 of the release, *Uniform sparsest cut: hardness and semidefinite gaps*
(Theoretical computer science). The family as a whole: Proves that approximating Uniform Sparsest Cut within any fixed constant factor is NP-hard, even with nonnegative rational capacities and unit demands. The Goemans–Linial semidefinite relaxation also has integrality gaps of order at least $\sqrt{\log n}/(\log\log n)^3$, approaching the square-root-logarithmic upper bound.

The challenge is `UniformSparsestCut`, also at `/opt/openai-math/challenges/UniformSparsestCut.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

open scoped BigOperators

namespace UniformSparsestCut

structure Capacity (n : ℕ) where
  cap : Fin n → Fin n → ℝ
  nonneg : ∀ i j, 0 ≤ cap i j
  symm : ∀ i j, cap i j = cap j i
  diagonal : ∀ i, cap i i = 0

def pairSum {n : ℕ} (f : Fin n → Fin n → ℝ) : ℝ :=
  ∑ i, ∑ j, if i < j then f i j else 0

noncomputable def cutRatio {n : ℕ} (C : Capacity n) (B : Finset (Fin n)) : ℝ :=
  (∑ i ∈ B, ∑ j ∈ Bᶜ, C.cap i j) /
    ((B.card : ℝ) * ((n : ℝ) - (B.card : ℝ)))

noncomputable def OPT {n : ℕ} (C : Capacity n) : ℝ :=
  sInf {r | ∃ B : Finset (Fin n), B.Nonempty ∧ B ≠ Finset.univ ∧ r = cutRatio C B}

def NegativeType {n : ℕ} (d : Fin n → Fin n → ℝ) : Prop :=
  (∃ x : Fin n → EuclideanSpace ℝ (Fin n), ∀ i j, d i j = ‖x i - x j‖ ^ 2) ∧
  ∀ i j k, d i k ≤ d i j + d j k

def Feasible {n : ℕ} (d : Fin n → Fin n → ℝ) : Prop :=
  NegativeType d ∧ pairSum d = 1

noncomputable def glValue {n : ℕ} (C : Capacity n) : ℝ :=
  sInf {r | ∃ d : Fin n → Fin n → ℝ, Feasible d ∧
    r = pairSum (fun i j => C.cap i j * d i j)}

open Filter

theorem mainGap :
    ∃ c : ℝ, 0 < c ∧
      ∃ n : ℕ → ℕ, ∃ C : (j : ℕ) → Capacity (n j),
        (∀ j, 2 ≤ n j) ∧
        Tendsto n atTop atTop ∧
        (∀ j, 0 < glValue (C j)) ∧
        ∀ᶠ j in atTop,
          c * Real.sqrt (Real.log (n j : ℝ)) / (Real.log (Real.log (n j : ℝ))) ^ 3 ≤
            OPT (C j) / glValue (C j) := by
  sorry

end UniformSparsestCut

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/UniformSparsestCut.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.UniformSparsestCut.mainGap` must keep exactly the statement shown above: same names,
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
