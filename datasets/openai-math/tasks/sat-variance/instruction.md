# openai/math challenge `SATVariance` (family 235)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 235 of the release, *Random-SAT thresholds, sharp variance and computability*
(Probability and statistical mechanics). The family as a whole: For random $k$-SAT with independent uniformly signed proper clauses sampled with replacement, proves finite positive limiting thresholds and hitting-time variance $\Theta_k(n)$ for every fixed $k\ge3$, and computability of the 3-SAT threshold. We credit Gaia Carenini with priority for resolving the threshold-existence conjecture in her concurrent \href{https://eccc.weizmann.ac.il/report/2026/229/}{ECCC TR26-229}, made public October 5, 2026; this family supplies another proof and the sharper variance and computability results.

The challenge is `SATVariance`, also at `/opt/openai-math/challenges/SATVariance.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

open MeasureTheory ProbabilityTheory

namespace RandomKSAT

abbrev Assignment (n : ℕ) := Fin n → Bool

def Clause (n k : ℕ) :=
  (s : {s : Finset (Fin n) // s.card = k}) × (s.1 → Bool)

instance clauseFintype (n k : ℕ) : Fintype (Clause n k) := by
  classical
  unfold Clause
  infer_instance

instance clauseMeasurableSpace (n k : ℕ) : MeasurableSpace (Clause n k) := ⊤

instance clauseMeasurableSingletonClass (n k : ℕ) :
    MeasurableSingletonClass (Clause n k) := ⟨fun _ => trivial⟩

def Satisfies {n k : ℕ} (c : Clause n k) (a : Assignment n) : Prop :=
  ∃ v : c.1.1, a v = c.2 v

abbrev Stream (n k : ℕ) := ℕ → Clause n k

def clauseLaw (n k : ℕ) : Measure (Clause n k) := uniformOn Set.univ

def streamLaw (n k : ℕ) : Measure (Stream n k) :=
  Measure.infinitePi (fun _ : ℕ => clauseLaw n k)

def PrefixSAT {n k : ℕ} (ω : Stream n k) (m : ℕ) : Prop :=
  ∃ a : Assignment n, ∀ i < m, Satisfies (ω i) a

def firstFailure {n k : ℕ} (ω : Stream n k) : ℕ∞ :=
  sInf ((fun m : ℕ => (m : ℕ∞)) '' {m | ¬ PrefixSAT ω m})

def H {n k : ℕ} (ω : Stream n k) : ℝ := (firstFailure ω).toNat

def cap (n : ℕ) (B : ℝ) : ℕ := ⌊B * n⌋₊

def T {n k : ℕ} (B : ℝ) (ω : Stream n k) : ℝ :=
  (min (firstFailure ω) (cap n B : ℕ∞)).toNat

def ell (k n : ℕ) : ℝ :=
  if k = 3 then Real.log (Real.exp 1 * n) else 1

def U (k : ℕ) : ℝ := Real.log 2 / (-Real.log (1 - ((2 : ℝ) ^ k)⁻¹))

theorem variance_main (k : ℕ) (hk : 3 ≤ k) :
    (∃ C : ℝ, 0 ≤ C ∧ ∀ n : ℕ, k ≤ n →
      variance (H : Stream n k → ℝ) (streamLaw n k) ≤ C * n * ell k n) ∧
    (∀ B : ℝ, 0 < B → ∃ C : ℝ, 0 ≤ C ∧ ∀ n : ℕ, k ≤ n →
      variance (T B : Stream n k → ℝ) (streamLaw n k) ≤ C * n * ell k n) ∧
    (∃ c : ℝ, 0 < c ∧
      (∃ N : ℕ, ∀ n : ℕ, N ≤ n → k ≤ n →
        c * n ≤ variance (H : Stream n k → ℝ) (streamLaw n k)) ∧
      (∀ B : ℝ, U k < B → ∃ N : ℕ, ∀ n : ℕ, N ≤ n → k ≤ n →
        c * n ≤ variance (T B : Stream n k → ℝ) (streamLaw n k))) := by
  sorry

end RandomKSAT

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/SATVariance.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.RandomKSAT.variance_main` must keep exactly the statement shown above: same names,
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
