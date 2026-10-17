# openai/math challenge `GaussianInformation` (family 140)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 140 of the release, *Memory–sample lower bounds for noiseless Gaussian regression*
(Theoretical computer science). The family as a whole: For fixed $A>0$, a one-pass learner with $Ad^2$ persistent bits needs $\Omega_A(d\log(1/\epsilon))$ noiseless Gaussian samples to recover a unit vector to angular error $0<\epsilon\le1/10$ with probability $2/3$, uniformly in accuracy for large $d$. Computation and randomized updates are unrestricted, but output uses only the terminal state, stopping index and fresh randomness.

The challenge is `GaussianInformation`, also at `/opt/openai-math/challenges/GaussianInformation.lean`:

```lean
import Mathlib

namespace OAI


open MeasureTheory ProbabilityTheory Set
open scoped BigOperators ENNReal

namespace RepeatedLocalization

abbrev Coordinate (n : ℕ) := Fin n → ℝ
abbrev GaussianBlock (n : ℕ) := Fin (n / 16) → Fin (n + 1) → ℝ
abbrev Label (n : ℕ) := Fin (n / 16) → ℝ
abbrev History (N t : ℕ) := Fin t → Fin N
abbrev Cell (n : ℕ) := Σ J : ℕ, Fin n → Fin (2 ^ J)

instance cellMeasurableSpace (n : ℕ) : MeasurableSpace (Cell n) := ⊤

noncomputable def initialCube (n : ℕ) : Set (Coordinate n) :=
  Set.pi Set.univ (fun _ => Set.Ico (-1 / (2 * Real.sqrt n)) (1 / (2 * Real.sqrt n)))

noncomputable def cubePrior (n : ℕ) : Measure (Coordinate n) :=
  ProbabilityTheory.cond volume (initialCube n)

noncomputable def chart {n : ℕ} (z : Coordinate n) : Fin (n + 1) → ℝ :=
  Fin.lastCases (Real.sqrt (1 - ∑ a, (z a) ^ 2)) z

noncomputable def cellSet {n : ℕ} (Q : Cell n) : Set (Coordinate n) :=
  {z | ∀ a, -1 / (2 * Real.sqrt n) + (Q.2 a : ℝ) / (Real.sqrt n * (2 : ℝ) ^ Q.1) ≤ z a ∧
    z a < -1 / (2 * Real.sqrt n) + ((Q.2 a : ℝ) + 1) / (Real.sqrt n * (2 : ℝ) ^ Q.1)}

def rootCell (n : ℕ) : Cell n := ⟨0, fun _ => 0⟩

noncomputable def gaussianBlockLaw (n : ℕ) : Measure (GaussianBlock n) :=
  Measure.pi (fun _ => Measure.pi (fun _ => gaussianReal 0 1))

noncomputable def exactLabel {n : ℕ} (X : GaussianBlock n) (z : Coordinate n) : Label n :=
  fun row => ∑ a, X row a * chart z a

structure BlockRule (n N : ℕ) where
  prob : (GaussianBlock n × Label n) → Fin N → ℝ
  measurable_prob : ∀ w, Measurable (fun data => prob data w)
  nonneg : ∀ data w, 0 ≤ prob data w
  sum_one : ∀ data, ∑ w, prob data w = 1

abbrev Rules (n N t : ℕ) := ∀ i : Fin t, History N i.val → BlockRule n N

def past {N t : ℕ} (w : History N t) (i : Fin t) : History N i.val :=
  fun j => w ⟨j.val, Nat.lt_trans j.isLt i.isLt⟩

def through {N t : ℕ} (w : History N t) (i : Fin t) : History N (i.val + 1) :=
  fun j => w ⟨j.val, Nat.lt_of_lt_of_le j.isLt i.isLt⟩

noncomputable def blockProbability {n N : ℕ} (rule : BlockRule n N)
    (z : Coordinate n) (w : Fin N) : ℝ :=
  ∫ X, rule.prob (X, exactLabel X z) w ∂gaussianBlockLaw n

noncomputable def historyLikelihood {n N t : ℕ} (rules : Rules n N t)
    (z : Coordinate n) (w : History N t) : ℝ :=
  ∏ i, blockProbability (rules i (past w i)) z (w i)

noncomputable def experimentLaw {n N t : ℕ} (rules : Rules n N t) :
    Measure (Coordinate n × History N t) :=
  ∑ w : History N t,
    ((cubePrior n).withDensity (fun z => ENNReal.ofReal (historyLikelihood rules z w))).map
      (fun z => (z, w))

abbrev Disclosure (n N t : ℕ) := ∀ i : Fin t, Coordinate n → History N (i.val + 1) → Cell n

def ValidDisclosure {n N t : ℕ} (Q : Disclosure n N t) : Prop :=
  (∀ i, Measurable (fun zh : Coordinate n × History N (i.val + 1) => Q i zh.1 zh.2)) ∧
  (∀ i, (Set.range (fun zh : Coordinate n × History N (i.val + 1) => Q i zh.1 zh.2)).Finite) ∧
  (∀ z ∈ initialCube n, ∀ w : History N t, ∀ i,
    z ∈ cellSet (Q i z (through w i)) ∧ cellSet (Q i z (through w i)) ⊆ initialCube n) ∧
  (∀ z ∈ initialCube n, ∀ w : History N t, ∀ i j : Fin t, i ≤ j →
    cellSet (Q j z (through w j)) ⊆ cellSet (Q i z (through w i)))

noncomputable def transcriptMap {n N t : ℕ} (Q : Disclosure n N t)
    (zw : Coordinate n × History N t) : Coordinate n × (History N t × (Fin t → Cell n)) :=
  (zw.1, (zw.2, fun i => Q i zw.1 (through zw.2 i)))

noncomputable def augmentedLaw {n N t : ℕ} (rules : Rules n N t) (Q : Disclosure n N t) :=
  (experimentLaw rules).map (transcriptMap Q)

noncomputable def mutualInformation {α β : Type*} [MeasurableSpace α] [MeasurableSpace β]
    (μ : Measure (α × β)) : ℝ≥0∞ :=
  InformationTheory.klDiv μ ((μ.map Prod.fst).prod (μ.map Prod.snd))

noncomputable def finalLevel {n N t : ℕ} (Q : Disclosure n N t)
    (zw : Coordinate n × History N t) : ℕ :=
  if ht : 0 < t then
    let i : Fin t := ⟨t - 1, by omega⟩
    (Q i zw.1 (through zw.2 i)).1
  else 0

def MainStatement : Prop :=
  ∃ c : ℝ, 0 < c ∧ ∃ n₀ : ℕ, ∀ C₀ : ℝ, 0 < C₀ →
    ∃ C : ℝ, 0 < C ∧ ∀ (n N t : ℕ), n₀ ≤ n → 1 ≤ N → ∀ rules : Rules n N t,
      (2 / (n / 8 : ℕ) + Real.exp (-c * (n / 16 : ℕ))) * Real.log N ≤ C₀ * (n + 1) →
      ∃ Q : Disclosure n N t, ValidDisclosure Q ∧
        mutualInformation (augmentedLaw rules Q) ≤ ENNReal.ofReal (C * (n + 1) * t) ∧
        (∫ zw, (finalLevel Q zw : ℝ) ∂experimentLaw rules) ≤ C * t

theorem repeated_localization : MainStatement := by
  sorry

end RepeatedLocalization


open MeasureTheory Metric
open scoped ENNReal
namespace AllScaleInverseVolume
local instance namedAtLeastTwoTwo : Nat.AtLeastTwo 2 := ⟨Nat.le_refl 2⟩

abbrev Ambient (d : ℕ) := EuclideanSpace ℝ (Fin d)

noncomputable local instance ambientSub (d : ℕ) : Sub (Ambient d) where
  sub vector other := WithLp.toLp (2 : ℝ≥0∞)
    (WithLp.ofLp (p := (2 : ℝ≥0∞)) vector - WithLp.ofLp (p := (2 : ℝ≥0∞)) other)

noncomputable local instance ambientInner (d : ℕ) : Inner ℝ (Ambient d) where
  inner vector other := ∑ coordinate : Fin d,
    inner ℝ (WithLp.ofLp (p := (2 : ℝ≥0∞)) vector coordinate)
      (WithLp.ofLp (p := (2 : ℝ≥0∞)) other coordinate)

noncomputable def gramVolume {d k : ℕ} (u : Ambient d) (z : Fin k → Ambient d) : ℝ :=
  Real.sqrt (Matrix.gram ℝ (fun i => z i-u)).det
noncomputable def inverseVolume {d : ℕ} (u : Ambient d) (z : Fin (d/100) → Ambient d) : ℝ≥0∞ :=
  ((ENNReal.ofReal (gramVolume u z))⁻¹)^(d/100)
def BallBound {d : ℕ} (ν : Measure (Ambient d)) : Prop :=
  ∀ (x : Ambient d) (r : ℝ), 0 < r →
    ν (ball x r) ≤ ENNReal.ofReal (r^(((d:ℝ)-1)/2))
def InverseVolumeStatement : Prop :=
  ∃ C : ℝ, 0 < C ∧ ∃ d₀ : ℕ, ∀ d : ℕ, d₀ ≤ d →
    ∀ ν : Measure (Ambient d), IsProbabilityMeasure ν → BallBound ν →
      ∀ u : Ambient d, (∫⁻ z,inverseVolume u z ∂Measure.pi (fun _ : Fin (d/100) => ν)) ≤
        ENNReal.ofReal (Real.exp (C*d*(d/100:ℕ)))
theorem inverse_volume_without_support : InverseVolumeStatement := by
  sorry
end AllScaleInverseVolume


open MeasureTheory ProbabilityTheory Metric Set
open scoped ENNReal
namespace KernelPotential
local instance namedAtLeastTwoTwo : Nat.AtLeastTwo 2 := ⟨Nat.le_refl 2⟩

abbrev Ambient (d : ℕ) := EuclideanSpace ℝ (Fin d)
abbrev Rows (d : ℕ) := Fin (d/16) → Fin d → ℝ
noncomputable def radial {d : ℕ} (x : Ambient d) : Ambient d := ‖x‖⁻¹ • x
noncomputable def sphereProbability (d : ℕ) : Measure (Ambient d) :=
  ((volume (ball (0 : Ambient d) 1))⁻¹ • volume.restrict (ball (0 : Ambient d) 1)).map radial
noncomputable def J {d : ℕ} (ν : Measure (Ambient d)) (s : Ambient d) : ℝ≥0∞ :=
  ∫⁻ u,((ENNReal.ofReal ‖u-s‖)⁻¹)^(2*(d/16)) ∂ν
noncomputable def B {d : ℕ} (ν : Measure (Ambient d)) : ℝ :=
  ∫ s, Real.log ((J ν s).toReal) ∂ν
noncomputable def Phi {d : ℕ} (ν : Measure (Ambient d)) : ℝ :=
  (InformationTheory.klDiv ν (sphereProbability d)).toReal - B ν

def BoundedDensity {d : ℕ} (ν : Measure (Ambient d)) : Prop :=
  ∃ H : ℝ, 0 < H ∧ ν ≤ ENNReal.ofReal H • sphereProbability d

noncomputable def rowLaw (d : ℕ) : Measure (Rows d) :=
  Measure.pi (fun _ : Fin (d/16) => Measure.pi (fun _ : Fin d => gaussianReal 0 1))
noncomputable def labels {d : ℕ} (a : Rows d) (s : Ambient d) : Fin (d/16) → ℝ :=
  fun i => ∑ j,a i j*s j
structure BlockRule (d N : ℕ) where
  prob : (Fin N × (Rows d × (Fin (d/16) → ℝ))) → Fin N → ℝ
  measurable_prob : ∀ w, Measurable (fun x => prob x w)
  nonneg_prob : ∀ x w, 0 ≤ prob x w
  sum_prob : ∀ x, ∑ w,prob x w=1

noncomputable def outgoingLaw {d N : ℕ} (μ : Measure (Ambient d × Fin N))
    (rule : BlockRule d N) : Measure (Ambient d × Fin N) :=
  ∑ w : Fin N, ((μ.prod (rowLaw d)).withDensity (fun x =>
    ENNReal.ofReal (rule.prob (x.1.2,x.2,labels x.2 x.1.1) w))).map (fun x => (x.1.1,w))
noncomputable def component {d N : ℕ} (μ : Measure (Ambient d × Fin N)) (v : Fin N) :
    Measure (Ambient d) := (μ.restrict {x|x.2=v}).map Prod.fst
noncomputable def posterior {d N : ℕ} (μ : Measure (Ambient d × Fin N)) (v : Fin N) :
    Measure (Ambient d) := (component μ v univ)⁻¹ • component μ v
noncomputable def averagePhi {d N : ℕ} (μ : Measure (Ambient d × Fin N)) : ℝ :=
  ∑ v : Fin N, (component μ v univ).toReal * Phi (posterior μ v)

def CoercivityStatement : Prop :=
  ∃ C : ℝ, 0 < C ∧ ∃ d₀ : ℕ, ∀ d : ℕ, d₀ ≤ d →
    (∀ ν : Measure (Ambient d), IsProbabilityMeasure ν → BoundedDensity ν →
      (1/2:ℝ)*(InformationTheory.klDiv ν (sphereProbability d)).toReal-C*d ≤ Phi ν) ∧
    Phi (sphereProbability d) ≤ (2*(d/16):ℕ)*Real.log 2 ∧
    (∀ (q : ℕ) (w : Fin q → ℝ), (∀ i,0 ≤ w i) → (∑ i,w i)=1 →
      ∀ ν : Fin q → Measure (Ambient d), (∀ i,IsProbabilityMeasure (ν i)) →
      (∀ i,BoundedDensity (ν i)) →
      Phi (∑ i,ENNReal.ofReal (w i) • ν i) ≤ ∑ i,w i*Phi (ν i))

def DriftStatement : Prop :=
  ∃ C : ℝ, 0 < C ∧ ∃ d₀ : ℕ, ∀ d : ℕ, d₀ ≤ d → ∀ N : ℕ, 1 ≤ N →
    Real.log N ≤ (d:ℝ)^2 → ∀ μ : Measure (Ambient d × Fin N), IsProbabilityMeasure μ →
    μ.map Prod.fst=sphereProbability d → ∀ rule : BlockRule d N,
      averagePhi (outgoingLaw μ rule) ≤ averagePhi μ+C*d

theorem kernel_coercivity : CoercivityStatement := by sorry
theorem actual_row_drift : DriftStatement := by sorry
end KernelPotential

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/GaussianInformation.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorems `OAI.RepeatedLocalization.repeated_localization`, `OAI.AllScaleInverseVolume.inverse_volume_without_support`, `OAI.KernelPotential.kernel_coercivity`, `OAI.KernelPotential.actual_row_drift` must keep exactly the statement shown above: same names,
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
