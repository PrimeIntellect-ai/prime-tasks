# openai/math challenge `ThreeStateSupercritical` (family 229)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 229 of the release, *Sharp three- and four-state reconstruction thresholds*
(Probability and statistical mechanics). The family as a whole: Proves the exact reconstruction threshold $d\lambda^2>1$, with nonreconstruction at equality, for three-state symmetric and four-state ferromagnetic broadcasting on regular trees ($d\ge2$) and observed Poisson trees (mean $d>1$ and $d>0$, respectively), with Poisson advantage averaged without conditioning on survival. The three-state theorem allows both signs of $\lambda$ and gives the exact weak-recovery threshold for the symmetric three-community stochastic block model.

The challenge is `ThreeStateSupercritical`, also at `/opt/openai-math/challenges/ThreeStateSupercritical.lean`:

```lean
import Mathlib

namespace OAI

namespace ThreeState

abbrev Spin := Fin 3

 
def Admissible (lam : ℝ) : Prop := -(1 / 2 : ℝ) ≤ lam ∧ lam ≤ 1

 
noncomputable def channel (lam : ℝ) (i j : Spin) : ℝ :=
  if i = j then (1 + 2 * lam) / 3 else (1 - lam) / 3

 

def Observation : ℕ → Type
  | 0 => Spin
  | n + 1 => Multiset (Observation n)

theorem channel_nonneg {lam : ℝ} (h : Admissible lam) (i j : Spin) :
    0 ≤ channel lam i j := by
  unfold channel
  split_ifs
  · dsimp [Admissible] at h
    linarith [h.1]
  · dsimp [Admissible] at h
    linarith [h.2]

theorem channel_sum (lam : ℝ) (i : Spin) : ∑ j, channel lam i j = 1 := by
  fin_cases i <;> simp [channel, Fin.sum_univ_succ] <;> ring

noncomputable def channelPMF (lam : ℝ) (h : Admissible lam) (i : Spin) : PMF Spin :=
  PMF.ofFintype (fun j => ENNReal.ofReal (channel lam i j)) (by
    rw [← ENNReal.ofReal_sum_of_nonneg (fun j _ => channel_nonneg h i j)]
    simp [channel_sum])

 
noncomputable def iidList {α : Type*} (p : PMF α) : ℕ → PMF (List α)
  | 0 => PMF.pure []
  | n + 1 => p.bind fun a => (iidList p n).map (List.cons a)

 

noncomputable def observedLaw (offspring : PMF ℕ) (lam : ℝ) (h : Admissible lam) :
    (n : ℕ) → Spin → PMF (Observation n)
  | 0, i => PMF.pure i
  | n + 1, i => offspring.bind fun k =>
      (iidList ((channelPMF lam h i).bind (observedLaw offspring lam h n)) k).map
        (fun xs : List (Observation n) => (xs : Multiset (Observation n)))

noncomputable def uniformSpin : PMF Spin := PMF.ofFintype (fun _ => 1 / 3) (by
  simp
  exact ENNReal.mul_inv_cancel (by norm_num) (by finiteness))

 
noncomputable def marginal {α : Type*} (law : Spin → PMF α) : PMF α :=
  uniformSpin.bind law

 
noncomputable def posterior {α : Type*} (law : Spin → PMF α) (y : α) (i : Spin) : ℝ :=
  if marginal law y = 0 then 1 / 3
  else (law i y).toReal / (3 * (marginal law y).toReal)

 

noncomputable def advantage {α : Type*} (law : Spin → PMF α) : ℝ :=
  ∑' y, (marginal law y).toReal *
    ((∑ i : Spin, |posterior law y i - 1 / 3|) / 2)

noncomputable def regularLaw (b : ℕ) (lam : ℝ) (h : Admissible lam) (n : ℕ) :=
  observedLaw (PMF.pure b) lam h n

 
noncomputable def poissonOffspring (d : ℝ) (hd : 0 ≤ d) : PMF ℕ := by
  refine ⟨fun k => ENNReal.ofReal (Real.exp (-d) * d ^ k / (k.factorial : ℝ)), ?_⟩
  apply ENNReal.hasSum_coe.2
  have hsum : HasSum (fun k : ℕ => Real.exp (-d) * d ^ k / (k.factorial : ℝ)) 1 :=
    ProbabilityTheory.hasSum_one_poissonMeasure ⟨d, hd⟩
  simpa using hsum.toNNReal (fun k => by positivity)

noncomputable def poissonLaw (d : ℝ) (hd : 0 ≤ d) (lam : ℝ)
    (h : Admissible lam) (n : ℕ) :=
  observedLaw (poissonOffspring d hd) lam h n

noncomputable def regularAdvantage (b : ℕ) (lam : ℝ) (h : Admissible lam) (n : ℕ) : ℝ :=
  advantage (regularLaw b lam h n)

noncomputable def poissonAdvantage (d : ℝ) (hd : 1 < d) (lam : ℝ)
    (h : Admissible lam) (n : ℕ) : ℝ :=
  advantage (poissonLaw d (le_trans (by norm_num) hd.le) lam h n)

 
def Reconstructs (a : ℕ → ℝ) : Prop :=
  ∃ L : ℝ, 0 < L ∧ Filter.Tendsto a Filter.atTop (nhds L)

theorem regular_supercritical (b : ℕ) (hb : 2 ≤ b) (lam : ℝ) (h : Admissible lam)
    (hcrit : 1 < (b : ℝ) * lam ^ 2) : Reconstructs (regularAdvantage b lam h) := by
  sorry

theorem poisson_supercritical (d : ℝ) (hd : 1 < d) (lam : ℝ) (h : Admissible lam)
    (hcrit : 1 < d * lam ^ 2) : Reconstructs (poissonAdvantage d hd lam h) := by
  sorry

end ThreeState

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/ThreeStateSupercritical.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorems `OAI.ThreeState.regular_supercritical`, `OAI.ThreeState.poisson_supercritical` must keep exactly the statement shown above: same names,
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
