# openai/math challenge `BallPackingNecessity` (family 343)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 343 of the release, *Sharp symplectic ball-packing criteria in higher dimensions*
(Differential geometry). The family as a whole: Resolves the Siegel–Yao conjecture for arbitrary capacities in every dimension $2n\ge6$. Finitely many closed symplectic balls of capacities $R_1,\ldots,R_k$ embed disjointly into an open ball of capacity $R$ exactly when $\sum_iR_i^n<R^n$ and $R_i+R_j<R$ for every distinct pair $i,j$.

The challenge is `BallPackingNecessity`, also at `/opt/openai-math/challenges/BallPackingNecessity.lean`:

```lean
import Mathlib

namespace OAI

namespace HigherDimensionalBallPacking
open scoped ContDiff

abbrev Phase (n : ℕ) := Fin n → ℂ

noncomputable def capacity {n : ℕ} (z : Phase n) : ℝ :=
  Real.pi * ∑ j, Complex.normSq (z j)

def closedBall (n : ℕ) (r : ℝ) : Set (Phase n) := {z | capacity z ≤ r}

def openBall (n : ℕ) (r : ℝ) : Set (Phase n) := {z | capacity z < r}

noncomputable def standardForm {n : ℕ} (u v : Phase n) : ℝ :=
  ∑ j, ((u j).re * (v j).im - (u j).im * (v j).re)

 
def SymplecticOn {n : ℕ} (U : Set (Phase n)) (f : Phase n → Phase n) : Prop :=
  IsOpen U ∧ ContDiffOn ℝ ∞ f U ∧
    Topology.IsEmbedding (fun x : U => f x) ∧
    ∀ x ∈ U, ∀ u v : Phase n,
      standardForm (fderiv ℝ f x u) (fderiv ℝ f x v) = standardForm u v

 
def HasPacking (n k : ℕ) (R : ℝ) (r : Fin k → ℝ) : Prop :=
  ∃ (U : Fin k → Set (Phase n)) (f : Fin k → Phase n → Phase n),
    (∀ i, closedBall n (r i) ⊆ U i ∧ SymplecticOn (U i) (f i) ∧
      Set.MapsTo (f i) (closedBall n (r i)) (openBall n R)) ∧
    (∀ i j, i ≠ j →
      Disjoint (f i '' closedBall n (r i)) (f j '' closedBall n (r j)))

def PackingInequalities (n k : ℕ) (R : ℝ) (r : Fin k → ℝ) : Prop :=
  (∑ i, r i ^ n) < R ^ n ∧ ∀ i j, i ≠ j → r i + r j < R

theorem packing_necessity (n k : ℕ) (hn : 3 ≤ n) (hk : 1 ≤ k)
    (R : ℝ) (r : Fin k → ℝ) (hR : 0 < R) (hr : ∀ i, 0 < r i)
    (hp : HasPacking n k R r) : PackingInequalities n k R r := by
  sorry

end HigherDimensionalBallPacking

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/BallPackingNecessity.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.HigherDimensionalBallPacking.packing_necessity` must keep exactly the statement shown above: same names,
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
