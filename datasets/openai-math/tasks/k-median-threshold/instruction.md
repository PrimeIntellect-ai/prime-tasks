# openai/math challenge `KMedianThreshold` (family 125)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 125 of the release, *The approximation threshold for metric $k$-median*
(Theoretical computer science). The family as a whole: Gives a deterministic polynomial-time $(1+2/e+\varepsilon)$-approximation for finite rational metric $k$-median with specified candidate facilities, for every fixed $\varepsilon>0$. Assuming $P\ne NP$, the optimal infimum approximation factor is $1+2/e$.

The challenge is `KMedianThreshold`, also at `/opt/openai-math/challenges/KMedianThreshold.lean`:

```lean
import Mathlib

namespace OAI

section
section
namespace MetricKMedian

structure Instance where
  n : ℕ
  distance : Fin n → Fin n → ℚ
  clients : Finset (Fin n)
  facilities : Finset (Fin n)
  k : ℕ
  distance_nonneg : ∀ i j, 0 ≤ distance i j
  distance_eq_zero : ∀ i j, distance i j = 0 ↔ i = j
  distance_symm : ∀ i j, distance i j = distance j i
  distance_triangle : ∀ i j h, distance i h ≤ distance i j + distance j h
  k_pos : 1 ≤ k
  k_le : k ≤ facilities.card

def encodeNat (n : ℕ) : List Bool :=
  List.replicate n.bits.length true ++ [false] ++ n.bits

def encodeRat (q : ℚ) : List Bool :=
  [decide (q.num < 0)] ++ encodeNat q.num.natAbs ++ encodeNat q.den

def encodeInstance (I : Instance) : List Bool :=
  encodeNat I.n ++ encodeNat I.k ++
    List.ofFn (fun i : Fin I.n => decide (i ∈ I.clients)) ++
    List.ofFn (fun i : Fin I.n => decide (i ∈ I.facilities)) ++
    (List.ofFn (fun i : Fin I.n =>
      (List.ofFn (fun j : Fin I.n => encodeRat (I.distance i j))).flatten)).flatten

noncomputable def nearest (I : Instance) (j : Fin I.n) (S : Finset (Fin I.n)) : ℝ :=
  if h : S.Nonempty then
    (S.image (fun i => (I.distance j i : ℝ))).min' (h.image _)
  else 0

noncomputable def cost (I : Instance) (S : Finset (Fin I.n)) : ℝ :=
  ∑ j ∈ I.clients, nearest I j S

def feasibleSets (I : Instance) : Finset (Finset (Fin I.n)) :=
  I.facilities.powerset.filter (fun S => S.Nonempty ∧ S.card ≤ I.k)

noncomputable def optimum (I : Instance) : ℝ :=
  if h : (feasibleSets I).Nonempty then
    ((feasibleSets I).image (cost I)).min' (h.image _)
  else 0

def Correct (epsilon : ℝ) (I : Instance) (output : List Bool) : Prop :=
  ∃ S : Finset (Fin I.n), S ⊆ I.facilities ∧ S.Nonempty ∧ S.card ≤ I.k ∧
    output = List.ofFn (fun i : Fin I.n => decide (i ∈ S)) ∧
    cost I S ≤ (1 + 2 / Real.exp 1 + epsilon) * optimum I

end MetricKMedian
end
end

namespace MetricKMedian
namespace Complexity
/-- Polynomial-time computation with every physical work alphabet finite. -/
def FinitePolyTime {α β : Type} (ea : α → List Bool) (eb : β → List Bool)
    (f : α → β) : Prop :=
  ∃ p : Turing.TM2ComputableInPolyTime ea eb f,
    ∀ k : p.tm.K, Finite (p.tm.Γ k)

abbrev Word := List Bool
abbrev Language := Set Word

def encodeBit (b : Bool) : Word := [b]

def encodePair (x : Word × Word) : Word :=
  encodeNat x.1.length ++ x.1 ++ x.2

def P : Set Language := {L | ∃ decideL : Word → Bool,
  FinitePolyTime id encodeBit decideL ∧ ∀ x, decideL x = true ↔ x ∈ L}

def NP : Set Language := {L | ∃ (verify : Word × Word → Bool) (p : Polynomial ℕ),
  FinitePolyTime encodePair encodeBit verify ∧
  ∀ x, x ∈ L ↔ ∃ w : Word, w.length ≤ p.eval x.length ∧ verify (x, w) = true}

/-- Separation of deterministic polynomial time from finite-verifier nondeterministic polynomial time. -/
def PNeNP : Prop := P ≠ NP

end Complexity
/-- An actual nonempty feasible facility set, encoded by its membership mask. -/
def FactorCorrect (α : ℝ) (I : Instance) (output : List Bool) : Prop :=
  ∃ S : Finset (Fin I.n), S ⊆ I.facilities ∧ S.Nonempty ∧ S.card ≤ I.k ∧
    output = List.ofFn (fun i : Fin I.n => decide (i ∈ S)) ∧
    cost I S ≤ α * optimum I

/-- Deterministic polynomial-time approximation factors for arbitrary specified clients and facilities. -/
def approximationFactors : Set ℝ := {α | ∃ algorithm : Instance → List Bool,
  Complexity.FinitePolyTime encodeInstance id algorithm ∧
  ∀ I, FactorCorrect α I (algorithm I)}

end MetricKMedian

namespace MetricKMedian
/-- The deterministic approximation threshold is an infimum; its attainment is not asserted. -/
theorem threshold (h : Complexity.PNeNP) :
    sInf approximationFactors=1+2/Real.exp 1 := by
  sorry
end MetricKMedian

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/KMedianThreshold.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.MetricKMedian.threshold` must keep exactly the statement shown above: same names,
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
