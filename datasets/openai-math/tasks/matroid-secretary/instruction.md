# openai/math challenge `MatroidSecretary` (family 111)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 111 of the release, *One-sample matroid prophet inequalities against an almighty adversary*
(Theoretical computer science). The family as a whole: For every finite matroid known in advance, gives a distribution-independent online rule using one independent sample per element and earning a universal constant fraction of the expected offline optimum. Values are independent and nonnegative, with finite expected optimum. The guarantee holds even when the arrival-order adversary sees all samples, values, and the rule's entire random seed; no polynomial-time implementation is asserted.

The challenge is `MatroidSecretary`, also at `/opt/openai-math/challenges/MatroidSecretary.lean`:

```lean
import Mathlib

namespace OAI

/-!
# Matroid selection against an almighty adversary

The three guarantees concern one independent sample per label, a hidden fixed
weight vector, and a uniformly sampled observation prefix. The rule and its
finite seed law are fixed before the input weights or value distributions.
-/

open scoped BigOperators

section

open MeasureTheory ProbabilityTheory
open scoped BigOperators

namespace MatroidProphet

abbrev Weights (n : ℕ) := Fin n → ℝ
abbrev Seed (bits : ℕ) := Fin bits → Bool
abbrev ArrivalOrder (n : ℕ) := Equiv.Perm (Fin n)
instance arrivalOrderMeasurableSpace (n : ℕ) : MeasurableSpace (ArrivalOrder n) := ⊤

abbrev History (n : ℕ) (k : Fin n) := Fin (k.val + 1) → Fin n × ℝ

structure OnlineRule (n bits : ℕ) where
  decide : (k : Fin n) → Seed bits → Weights n → History n k → Bool
  measurable_decide : ∀ k, Measurable
    (fun x : Seed bits × (Weights n × History n k) => decide k x.1 x.2.1 x.2.2)

def prefixIndex {n : ℕ} (k : Fin n) (j : Fin (k.val + 1)) : Fin n :=
  ⟨j.val, Nat.lt_of_lt_of_le j.isLt (Nat.succ_le_of_lt k.isLt)⟩

def history {n : ℕ} (v : Weights n) (π : ArrivalOrder n) (k : Fin n) : History n k :=
  fun j => let e := π (prefixIndex k j); (e, v e)

def decisionAt {n bits : ℕ} (A : OnlineRule n bits) (r : Seed bits)
    (s v : Weights n) (π : ArrivalOrder n) (k : Fin n) : Bool :=
  A.decide k r s (history v π k)

noncomputable def acceptedThrough {n bits : ℕ} (A : OnlineRule n bits) (r : Seed bits)
    (s v : Weights n) (π : ArrivalOrder n) (t : ℕ) : Finset (Fin n) := by
  classical
  exact Finset.univ.filter fun e =>
    (π.symm e).val < t ∧ decisionAt A r s v π (π.symm e) = true

noncomputable def accepted {n bits : ℕ} (A : OnlineRule n bits) (r : Seed bits)
    (s v : Weights n) (π : ArrivalOrder n) : Finset (Fin n) :=
  acceptedThrough A r s v π n

noncomputable def reward {n bits : ℕ} (A : OnlineRule n bits) (r : Seed bits)
    (s v : Weights n) (π : ArrivalOrder n) : ℝ :=
  ∑ e ∈ accepted A r s v π, v e

noncomputable def optimum {n : ℕ} (M : Matroid (Fin n)) (v : Weights n) : ℝ := by
  classical
  exact Finset.univ.sup' Finset.univ_nonempty
    (fun I : Finset (Fin n) => if M.Indep (I : Set (Fin n)) then ∑ e ∈ I, v e else 0)

def Feasible {n bits : ℕ} (M : Matroid (Fin n)) (A : OnlineRule n bits) : Prop :=
  ∀ (r : Seed bits) (s v : Weights n) (π : ArrivalOrder n) (t : ℕ),
    (∀ e, 0 ≤ s e) → (∀ e, 0 ≤ v e) →
    M.Indep (acceptedThrough A r s v π t : Set (Fin n))

def pairedCoordinates.{u} {n : ℕ} {Ω : Type u} (S V : Ω → Weights n)
    (i : Fin n × Bool) : Ω → ℝ :=
  if i.2 then fun ω => S ω i.1 else fun ω => V ω i.1

def OneSampleChallenge.{u} : Prop :=
  ∀ (n : ℕ) (M : Matroid (Fin n)), M.E = Set.univ →
    ∃ (bits : ℕ) (ν : Measure (Seed bits)), IsProbabilityMeasure ν ∧
    ∃ (A : OnlineRule n bits), Feasible M A ∧
      ∀ {Ω : Type u} [MeasurableSpace Ω] (μ : Measure Ω) [IsProbabilityMeasure μ]
        (S V : Ω → Weights n) (R : Ω → Seed bits),
        Measurable S → Measurable V → Measurable R →
        (∀ᵐ ω ∂μ, ∀ e, 0 ≤ S ω e) →
        (∀ᵐ ω ∂μ, ∀ e, 0 ≤ V ω e) →
        iIndepFun (pairedCoordinates S V) μ →
        (∀ e, Measure.map (fun ω => S ω e) μ = Measure.map (fun ω => V ω e) μ) →
        IndepFun (fun ω => (S ω, V ω)) R μ →
        Measure.map R μ = ν →
        Integrable (fun ω => optimum M (V ω)) μ →
        ∀ (π : Ω → ArrivalOrder n), Measurable π →
          Integrable (fun ω => reward A (R ω) (S ω) (V ω) (π ω)) μ ∧
          ((2 : ℝ) ^ 310)⁻¹ * (∫ ω, optimum M (V ω) ∂μ) ≤
            ∫ ω, reward A (R ω) (S ω) (V ω) (π ω) ∂μ

end MatroidProphet

end

section

open MeasureTheory
open scoped BigOperators

namespace MatroidProphet

instance arrivalOrderMeasurableSingletonClass (n : ℕ) :
    MeasurableSingletonClass (ArrivalOrder n) := ⟨fun _ => trivial⟩

structure HiddenRule (n bits : ℕ) where
  mask : Seed bits → Finset (Fin n)
  core : OnlineRule n bits

noncomputable def observed {n bits : ℕ} (A : HiddenRule n bits) (r : Seed bits)
    (w : Weights n) : Weights n := by
  classical
  exact fun e => if e ∈ A.mask r then w e else 0

noncomputable def hiddenAcceptedThrough {n bits : ℕ} (A : HiddenRule n bits)
    (r : Seed bits) (w : Weights n) (π : ArrivalOrder n) (t : ℕ) : Finset (Fin n) :=
  acceptedThrough A.core r (observed A r w) w π t \ A.mask r

noncomputable def hiddenReward {n bits : ℕ} (A : HiddenRule n bits)
    (r : Seed bits) (w : Weights n) (π : ArrivalOrder n) : ℝ :=
  ∑ e ∈ hiddenAcceptedThrough A r w π n, w e

noncomputable def hiddenWorstReward {n bits : ℕ} (A : HiddenRule n bits)
    (w : Weights n) (r : Seed bits) : ℝ := by
  classical
  exact Finset.univ.inf' Finset.univ_nonempty (hiddenReward A r w)

end MatroidProphet

end

section

open MeasureTheory ProbabilityTheory

namespace MatroidProphet

def HiddenVectorChallenge : Prop :=
  ∀ (n : ℕ) (M : Matroid (Fin n)), M.E = Set.univ →
    ∃ (bits : ℕ) (ν : Measure (Seed bits)), IsProbabilityMeasure ν ∧
    ∃ (A : HiddenRule n bits),
      (∀ (w : Weights n), (∀ e, 0 ≤ w e) →
        ∀ (r : Seed bits) (π : ArrivalOrder n) (t : ℕ),
          M.Indep (hiddenAcceptedThrough A r w π t : Set (Fin n))) ∧
      ∀ (w : Weights n), (∀ e, 0 ≤ w e) →
        ((2 : ℝ) ^ 293)⁻¹ * optimum M w ≤
          ∫ r, hiddenWorstReward A w r ∂ν

end MatroidProphet

end

section

open MeasureTheory

namespace MatroidProphet

structure SecretaryRule (n : ℕ) (Q : Type*) [MeasurableSpace Q] where
  prefixLength : Q → Fin (n + 1)
  measurable_prefixLength : Measurable prefixLength
  decide : (k : Fin n) → Q → History n k → Bool
  measurable_decide : ∀ k, Measurable
    (fun x : Q × History n k => decide k x.1 x.2)

def SamePrefix {n : ℕ} (K : ℕ) (σ π : ArrivalOrder n) : Prop :=
  ∀ k : Fin n, k.val < K → σ k = π k

def secretaryDecisionAt {n : ℕ} {Q : Type*} [MeasurableSpace Q]
    (A : SecretaryRule n Q) (q : Q) (w : Weights n) (π : ArrivalOrder n)
    (k : Fin n) : Bool :=
  if k.val < (A.prefixLength q).val then false else A.decide k q (history w π k)

noncomputable def secretaryAcceptedThrough {n : ℕ} {Q : Type*} [MeasurableSpace Q]
    (A : SecretaryRule n Q) (q : Q) (w : Weights n) (π : ArrivalOrder n)
    (t : ℕ) : Finset (Fin n) := by
  classical
  exact Finset.univ.filter fun e =>
    (π.symm e).val < t ∧ secretaryDecisionAt A q w π (π.symm e) = true

noncomputable def secretaryReward {n : ℕ} {Q : Type*} [MeasurableSpace Q]
    (A : SecretaryRule n Q) (q : Q) (w : Weights n) (π : ArrivalOrder n) : ℝ :=
  ∑ e ∈ secretaryAcceptedThrough A q w π n, w e

def SecretaryFeasible {n : ℕ} {Q : Type*} [MeasurableSpace Q]
    (M : Matroid (Fin n)) (A : SecretaryRule n Q) : Prop :=
  ∀ (q : Q) (w : Weights n), (∀ e, 0 ≤ w e) →
    ∀ (π : ArrivalOrder n) (t : ℕ),
      M.Indep (secretaryAcceptedThrough A q w π t : Set (Fin n))

end MatroidProphet

end

section

namespace MatroidProphet.Secretary

open MeasureTheory

noncomputable def uniformArrivalLaw (n : ℕ) : Measure (ArrivalOrder n) :=
  (PMF.uniformOfFintype (ArrivalOrder n)).toMeasure

end MatroidProphet.Secretary

end

section

open MeasureTheory ProbabilityTheory

namespace MatroidProphet

def SecretaryChallenge.{u} : Prop :=
  ∀ (n : ℕ) (M : Matroid (Fin n)), M.E = Set.univ →
    ∃ (q : ℕ) (ν : Measure (Fin q)), IsProbabilityMeasure ν ∧
    ∃ (A : SecretaryRule n (Fin q)), SecretaryFeasible M A ∧
      ∀ (w : Weights n), (∀ e, 0 ≤ w e) →
      ∀ {Ω : Type u} [MeasurableSpace Ω] (μ : Measure Ω) [IsProbabilityMeasure μ]
        (Q : Ω → Fin q) (σ π : Ω → ArrivalOrder n),
        Measurable Q → Measurable σ → Measurable π →
        Measure.map Q μ = ν →
        Measure.map σ μ = Secretary.uniformArrivalLaw n →
        IndepFun Q σ μ →
        (∀ᵐ ω ∂μ, SamePrefix (A.prefixLength (Q ω)).val (σ ω) (π ω)) →
        Integrable (fun ω => secretaryReward A (Q ω) w (π ω)) μ ∧
          ((2 : ℝ) ^ 293)⁻¹ * optimum M w ≤
            ∫ ω, secretaryReward A (Q ω) w (π ω) ∂μ

end MatroidProphet

end

namespace MatroidProphet.Assigned

theorem one_sample.{u} : MatroidProphet.OneSampleChallenge.{u} := by
  sorry

theorem hidden_vector : MatroidProphet.HiddenVectorChallenge := by
  sorry

theorem secretary.{u} : MatroidProphet.SecretaryChallenge.{u} := by
  sorry

end MatroidProphet.Assigned

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/MatroidSecretary.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorems `OAI.MatroidProphet.Assigned.one_sample`, `OAI.MatroidProphet.Assigned.hidden_vector`, `OAI.MatroidProphet.Assigned.secretary` must keep exactly the statement shown above: same names,
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
