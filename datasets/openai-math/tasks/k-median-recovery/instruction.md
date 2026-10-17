# openai/math challenge `KMedianRecovery` (family 125)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 125 of the release, *The approximation threshold for metric $k$-median*
(Theoretical computer science). The family as a whole: Gives a deterministic polynomial-time $(1+2/e+\varepsilon)$-approximation for finite rational metric $k$-median with specified candidate facilities, for every fixed $\varepsilon>0$. Assuming $P\ne NP$, the optimal infimum approximation factor is $1+2/e$.

The challenge is `KMedianRecovery`, also at `/opt/openai-math/challenges/KMedianRecovery.lean`:

```lean
import Mathlib

namespace OAI

namespace MetricKMedianRecovery

structure RationalMetricInput where
  pointCount : ℕ
  distance : Fin pointCount → Fin pointCount → ℚ
  clients : Finset (Fin pointCount)
  facilities : Finset (Fin pointCount)
  budget : ℕ
  facilities_nonempty : facilities.Nonempty
  budget_pos : 0 < budget
  covered : clients ∪ facilities = Finset.univ
  distance_nonneg : ∀ x y, 0 ≤ distance x y
  distance_self : ∀ x, distance x x = 0
  distance_symm : ∀ x y, distance x y = distance y x
  distance_triangle : ∀ x y z, distance x z ≤ distance x y + distance y z

namespace RationalMetricInput

def size (I : RationalMetricInput) : ℕ := I.clients.card + I.facilities.card

def Feasible (I : RationalMetricInput) (S : Finset (Fin I.pointCount)) : Prop :=
  S ⊆ I.facilities ∧ S.card ≤ I.budget ∧ (I.clients.Nonempty → S.Nonempty)

def cost (I : RationalMetricInput) (S : Finset (Fin I.pointCount)) : ℚ :=
  if hS : S.Nonempty then ∑ p ∈ I.clients, S.inf' hS (I.distance p) else 0

def comparisonSets (I : RationalMetricInput) : Finset (Finset (Fin I.pointCount)) :=
  I.facilities.powerset.filter (fun S => S.Nonempty ∧ S.card ≤ I.budget)

lemma comparisonSets_nonempty (I : RationalMetricInput) : I.comparisonSets.Nonempty := by
  obtain ⟨i, hi⟩ := I.facilities_nonempty
  refine ⟨{i}, ?_⟩
  simp only [comparisonSets, Finset.mem_filter, Finset.mem_powerset,
    Finset.singleton_subset_iff, Finset.singleton_nonempty, Finset.card_singleton, true_and]
  exact ⟨hi, I.budget_pos⟩

def optimum (I : RationalMetricInput) : ℚ :=
  I.comparisonSets.inf' I.comparisonSets_nonempty I.cost

def natBits (n : ℕ) : List Bool :=
  List.replicate (Nat.bits n).length true ++ [false] ++ Nat.bits n

def rationalBits (r : ℚ) : List Bool :=
  [decide (r < 0)] ++ natBits r.num.natAbs ++ natBits r.den

def bits (I : RationalMetricInput) : List Bool :=
  natBits I.pointCount ++ natBits I.budget ++
    List.ofFn (fun i : Fin I.pointCount => decide (i ∈ I.clients)) ++
    List.ofFn (fun i : Fin I.pointCount => decide (i ∈ I.facilities)) ++
    (List.ofFn (fun i : Fin I.pointCount =>
      (List.ofFn (fun j : Fin I.pointCount => rationalBits (I.distance i j))).flatten)).flatten

def decodeOutput (I : RationalMetricInput) (out : List Bool) : Finset (Fin I.pointCount) :=
  I.facilities.filter (fun i => out[i.val]?.getD false = true)

end RationalMetricInput

def pairBits (p : List Bool × List Bool) : List Bool :=
  p.1.flatMap (fun b => [true, b]) ++ [false] ++ p.2

structure BinaryRandomizedAlgorithm where
  randomBits : Polynomial ℕ
  run : List Bool × List Bool → List Bool
  computation : Turing.TM2ComputableInPolyTime pairBits id run
  finiteWorkAlphabet : ∀ k : computation.tm.K, Finite (computation.tm.Γ k)

namespace BinaryRandomizedAlgorithm

def bitCount (A : BinaryRandomizedAlgorithm) (I : RationalMetricInput) : ℕ :=
  A.randomBits.eval I.bits.length

abbrev Seed (A : BinaryRandomizedAlgorithm) (I : RationalMetricInput) :=
  Fin (A.bitCount I) → Bool

def output (A : BinaryRandomizedAlgorithm) (I : RationalMetricInput) (s : A.Seed I) :
    Finset (Fin I.pointCount) :=
  I.decodeOutput (A.run (I.bits, List.ofFn s))

noncomputable def successProbability (A : BinaryRandomizedAlgorithm) (I : RationalMetricInput)
    (bound : ℝ) : ℝ := by
  classical
  exact ((Finset.univ.filter (fun s : A.Seed I => (I.cost (A.output I s) : ℝ) ≤ bound)).card : ℝ) /
    2 ^ (A.bitCount I)

noncomputable def expectedCost (A : BinaryRandomizedAlgorithm) (I : RationalMetricInput) : ℝ :=
  (∑ s : A.Seed I, (I.cost (A.output I s) : ℝ)) / 2 ^ (A.bitCount I)

end BinaryRandomizedAlgorithm

def globalApplicationClaim : Prop :=
  ∃ σ : ℝ, 0 < σ ∧ ∀ a : ℝ, 0 < a → ∃ A : BinaryRandomizedAlgorithm,
    (∀ (I : RationalMetricInput) (s : A.Seed I), I.Feasible (A.output I s)) ∧
    (∀ I : RationalMetricInput,
      1 - Real.rpow ((I.size : ℝ) + 2) (-a) ≤
        A.successProbability I ((2 - σ) * (I.optimum : ℝ))) ∧
    (∀ I : RationalMetricInput, A.expectedCost I ≤ (2 - σ) * (I.optimum : ℝ))

theorem global_application : globalApplicationClaim := by
  sorry

end MetricKMedianRecovery

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/KMedianRecovery.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.MetricKMedianRecovery.global_application` must keep exactly the statement shown above: same names,
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
