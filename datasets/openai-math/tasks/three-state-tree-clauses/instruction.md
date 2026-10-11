# openai/math challenge `ThreeStateTreeClauses` (family 229)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 229 of the release, *Sharp three- and four-state reconstruction thresholds*
(Probability and statistical mechanics). The family as a whole: Proves the exact reconstruction threshold $d\lambda^2>1$, with nonreconstruction at equality, for three-state symmetric and four-state ferromagnetic broadcasting on regular trees ($d\ge2$) and observed Poisson trees (mean $d>1$ and $d>0$, respectively), with Poisson advantage averaged without conditioning on survival. The three-state theorem allows both signs of $\lambda$ and gives the exact weak-recovery threshold for the symmetric three-community stochastic block model.

The challenge is `ThreeStateTreeClauses`, also at `/opt/openai-math/challenges/ThreeStateTreeClauses.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open scoped BigOperators ENNReal NNReal
open Filter

namespace ThreeState.TreeClauses

abbrev Spin := Fin 3

def Admissible (lam : ℝ) : Prop := -(1 / 2 : ℝ) ≤ lam ∧ lam ≤ 1

def channelWeight (lam : ℝ) (i j : Spin) : ℝ :=
  if i = j then (1 + 2 * lam) / 3 else (1 - lam) / 3

lemma channelWeight_nonneg {lam : ℝ} (hlam : Admissible lam) (i j : Spin) :
    0 ≤ channelWeight lam i j := by
  unfold channelWeight
  split_ifs <;> dsimp [Admissible] at hlam <;> linarith [hlam.1, hlam.2]

lemma channelWeight_sum (lam : ℝ) (i : Spin) : ∑ j, channelWeight lam i j = 1 := by
  fin_cases i <;> simp [channelWeight, Fin.sum_univ_three] <;> ring

def channel (lam : ℝ) (hlam : Admissible lam) (i : Spin) : PMF Spin :=
  PMF.ofFintype (fun j ↦ ENNReal.ofReal (channelWeight lam i j)) (by
    rw [← ENNReal.ofReal_sum_of_nonneg (fun j _ ↦ channelWeight_nonneg hlam i j),
      channelWeight_sum]
    norm_num)

def Observation : ℕ → Type
  | 0 => Spin
  | n + 1 => Multiset (Observation n)

def iidList {α : Type} (p : PMF α) : ℕ → PMF (List α)
  | 0 => PMF.pure []
  | n + 1 => p.bind fun x ↦ (iidList p n).map (List.cons x)

def observationLaw (lam : ℝ) (hlam : Admissible lam) (offspring : PMF ℕ) :
    (ℓ : ℕ) → Spin → PMF (Observation ℓ)
  | 0, i => PMF.pure i
  | ℓ + 1, i => offspring.bind fun n ↦
      (iidList ((channel lam hlam i).bind (observationLaw lam hlam offspring ℓ)) n).map
        (fun xs ↦ (xs : Multiset (Observation ℓ)))

def jointWeight (lam : ℝ) (hlam : Admissible lam) (offspring : PMF ℕ)
    (ℓ : ℕ) (i : Spin) (o : Observation ℓ) : ℝ≥0∞ :=
  (1 / 3 : ℝ≥0∞) * observationLaw lam hlam offspring ℓ i o

def marginalWeight (lam : ℝ) (hlam : Admissible lam) (offspring : PMF ℕ)
    (ℓ : ℕ) (o : Observation ℓ) : ℝ≥0∞ :=
  ∑ i, jointWeight lam hlam offspring ℓ i o

def posterior (lam : ℝ) (hlam : Admissible lam) (offspring : PMF ℕ)
    (ℓ : ℕ) (o : Observation ℓ) (i : Spin) : ℝ :=
  (jointWeight lam hlam offspring ℓ i o / marginalWeight lam hlam offspring ℓ o).toReal

def advantage (lam : ℝ) (hlam : Admissible lam) (offspring : PMF ℕ) (ℓ : ℕ) : ℝ :=
  ∑' o : Observation ℓ, (marginalWeight lam hlam offspring ℓ o).toReal *
    ((∑ i : Spin, |posterior lam hlam offspring ℓ o i - (1 / 3 : ℝ)|) / 2)

def Reconstructs (lam : ℝ) (hlam : Admissible lam) (offspring : PMF ℕ) : Prop :=
  ∃ a : ℝ, 0 < a ∧ Tendsto (advantage lam hlam offspring) atTop (nhds a)

namespace Probability

def poissonWeight (rate : ℝ) (count : ℕ) : ℝ :=
  Real.exp (-rate) * rate ^ count / (count.factorial : ℝ)

lemma poissonWeight_nonneg {rate : ℝ} (hrate : 0 ≤ rate) (count : ℕ) :
    0 ≤ poissonWeight rate count := by
  unfold poissonWeight
  positivity

lemma poissonWeight_mass (rate : ℝ≥0) : HasSum (poissonWeight rate) 1 :=
  ProbabilityTheory.hasSum_one_poissonMeasure rate

def _root_.OAI.ThreeState.TreeClauses.poissonPMF (rate : ℝ≥0) : PMF ℕ := by
  refine ⟨fun count ↦ ENNReal.ofReal (poissonWeight rate count), ?_⟩
  apply ENNReal.hasSum_coe.mpr
  rw [← Real.toNNReal_one]
  exact (poissonWeight_mass rate).toNNReal (poissonWeight_nonneg rate.coe_nonneg)

end Probability

end ThreeState.TreeClauses

open scoped Topology
namespace ThreeState.TreeClauses.Tree

theorem regular_reconstructs_above_KS (b : ℕ) (lam : ℝ) (hlam : Admissible lam)
    (hKS : 1 < (b:ℝ)*lam^2) : Reconstructs lam hlam (PMF.pure b) := by
  sorry

theorem poisson_reconstructs_above_KS (d : ℝ≥0) (lam : ℝ) (hlam : Admissible lam)
    (hKS : 1 < (d:ℝ)*lam^2) : Reconstructs lam hlam (poissonPMF d) := by
  sorry

end ThreeState.TreeClauses.Tree

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/ThreeStateTreeClauses.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorems `OAI.ThreeState.TreeClauses.Tree.regular_reconstructs_above_KS`, `OAI.ThreeState.TreeClauses.Tree.poisson_reconstructs_above_KS` must keep exactly the statement shown above: same names,
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
