# openai/math challenge `DirectionalBallisticity` (family 220)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 220 of the release, *Directional zero–one laws and ballisticity in random environments*
(Probability and statistical mechanics). The family as a whole: On $\mathbb Z^d$, $d\ge3$, directional escape has probability zero or one for iid strictly elliptic nearest-neighbor environments, and for stationary ergodic finite-range-dependent environments under uniform ellipticity. In iid uniformly elliptic environments with $d\ge2$, almost-sure directional transience implies a deterministic limiting velocity with positive projection in that direction, resolving the ballisticity conjecture.

The challenge is `DirectionalBallisticity`, also at `/opt/openai-math/challenges/DirectionalBallisticity.lean`:

```lean
import Mathlib

namespace OAI

open MeasureTheory ProbabilityTheory Filter
open scoped ENNReal NNReal BigOperators Topology

namespace DirectionalTransience

abbrev Lattice (d : ℕ) := Fin d → ℤ
abbrev Direction (d : ℕ) := Fin d × Bool
abbrev Vector (d : ℕ) := Fin d → ℝ
abbrev Row (d : ℕ) := {p : Direction d → ℝ≥0 // ∑ e, p e = 1}
abbrev Environment (d : ℕ) := Lattice d → Row d
abbrev State (d : ℕ) := Environment d × Lattice d
abbrev Path (d : ℕ) := ℕ → Lattice d

def step {d : ℕ} (e : Direction d) : Lattice d :=
  fun i => if i = e.1 then (if e.2 then 1 else -1) else 0

noncomputable def environmentLaw {d : ℕ} (ν : Measure (Row d)) :
    Measure (Environment d) := Measure.infinitePi (fun _ => ν)

def UniformElliptic {d : ℕ} (ν : Measure (Row d)) : Prop :=
  ∃ κ : ℝ≥0, 0 < κ ∧ ∀ᵐ p ∂ν, ∀ e, κ ≤ p.1 e

lemma measurable_current_row {d : ℕ} :
    Measurable (fun z : State d => z.1 z.2) := by
  apply measurable_from_prod_countable_left
  intro x
  exact measurable_pi_apply x

noncomputable def transition {d : ℕ} : Kernel (State d) (State d) where
  toFun z := ∑ e : Direction d,
    ((z.1 z.2).1 e : ℝ≥0∞) • Measure.dirac (z.1, z.2 + step e)
  measurable' := by
    apply Measure.measurable_of_measurable_coe
    intro s hs
    simp only [Measure.finsetSum_apply, Measure.smul_apply, smul_eq_mul]
    apply Finset.measurable_fun_sum
    intro e _
    apply Measurable.mul
    · exact (measurable_pi_apply e |>.comp
        (measurable_subtype_coe.comp measurable_current_row)).coe_nnreal_ennreal
    · exact (Measure.measurable_coe hs).comp
        (Measure.measurable_dirac.comp (measurable_fst.prodMk
          (measurable_snd.add_const (step e))))

instance transition_markov {d : ℕ} : IsMarkovKernel (transition (d := d)) where
  isProbabilityMeasure z := by
    constructor
    change (∑ e : Direction d,
      ((z.1 z.2).1 e : ℝ≥0∞) • Measure.dirac (z.1, z.2 + step e)) Set.univ = 1
    simp only [Measure.finsetSum_apply, Measure.smul_apply, Measure.dirac_apply_of_mem
      (Set.mem_univ _), smul_eq_mul, mul_one]
    rw [← ENNReal.ofNNReal_finsetSum, (z.1 z.2).2]
    rfl

noncomputable def historyTransition {d : ℕ} (n : ℕ) :
    Kernel ((i : Finset.Iic n) → State d) (State d) where
  toFun z := transition (z ⟨n, Finset.mem_Iic.mpr le_rfl⟩)
  measurable' := transition.measurable.comp (measurable_pi_apply _)

instance historyTransition_markov {d : ℕ} (n : ℕ) :
    IsMarkovKernel (historyTransition (d := d) n) where
  isProbabilityMeasure _ := transition_markov.isProbabilityMeasure _

noncomputable def initialLaw {d : ℕ} (ν : Measure (Row d)) : Measure (State d) :=
  (environmentLaw ν).map (fun ω => (ω, (0 : Lattice d)))

noncomputable def annealedLaw {d : ℕ} (ν : Measure (Row d)) : Measure (Path d) :=
  (@Kernel.trajMeasure (fun _ => State d) _ (initialLaw ν) (historyTransition (d := d)) _).map
    (fun z n => (z n).2)

def dot {d : ℕ} (v ℓ : Vector d) : ℝ := ∑ i, v i * ℓ i

def realPosition {d : ℕ} (x : Lattice d) : Vector d := fun i => (x i : ℝ)

def DirectionallyTransient {d : ℕ} (ν : Measure (Row d)) (ℓ : Vector d) : Prop :=
  ∀ᵐ X ∂annealedLaw ν,
    Tendsto (fun n => dot (realPosition (X n)) ℓ) atTop atTop

def HasVelocity {d : ℕ} (ν : Measure (Row d)) (v : Vector d) : Prop :=
  ∀ᵐ X ∂annealedLaw ν,
    Tendsto (fun n : ℕ => (fun i => (X n i : ℝ) / (n : ℝ))) atTop (𝓝 v)

open scoped ENNReal NNReal Classical Topology BigOperators

def MainStatement : Prop :=
  ∀ (d : ℕ), 2 ≤ d → ∀ (ν : Measure (Row d)), IsProbabilityMeasure ν →
    UniformElliptic ν → ∀ (ℓ : Vector d), dot ℓ ℓ = 1 →
    DirectionallyTransient ν ℓ →
    ∃ v : Vector d, 0 < dot v ℓ ∧ HasVelocity ν v

theorem directional_transience_implies_ballisticity : MainStatement := by
  sorry

end DirectionalTransience

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/DirectionalBallisticity.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.DirectionalTransience.directional_transience_implies_ballisticity` must keep exactly the statement shown above: same names,
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
