# openai/math challenge `DirectionalWalk` (family 220)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 220 of the release, *Directional zero–one laws and ballisticity in random environments*
(Probability and statistical mechanics). The family as a whole: On $\mathbb Z^d$, $d\ge3$, directional escape has probability zero or one for iid strictly elliptic nearest-neighbor environments, and for stationary ergodic finite-range-dependent environments under uniform ellipticity. In iid uniformly elliptic environments with $d\ge2$, almost-sure directional transience implies a deterministic limiting velocity with positive projection in that direction, resolving the ballisticity conjecture.

The challenge is `DirectionalWalk`, also at `/opt/openai-math/challenges/DirectionalWalk.lean`:

```lean
import Mathlib

namespace OAI

open MeasureTheory ProbabilityTheory Filter Preorder
open scoped ENNReal BigOperators Topology

namespace DirectionalZeroOne

abbrev Site (d : ℕ) := Fin d → ℤ
abbrev Step (d : ℕ) := Fin d × Bool

def stepVector {d : ℕ} (e : Step d) : Site d :=
  fun i => if i = e.1 then (if e.2 then 1 else -1) else 0

def Row (d : ℕ) :=
  {p : Step d → ℝ // (∀ e, p e ∈ Set.Icc (0 : ℝ) 1) ∧ ∑ e, p e = 1}

instance (d : ℕ) : MeasurableSpace (Row d) := inferInstanceAs
  (MeasurableSpace {p : Step d → ℝ //
    (∀ e, p e ∈ Set.Icc (0 : ℝ) 1) ∧ ∑ e, p e = 1})

abbrev Environment (d : ℕ) := Site d → Row d
abbrev Path (d : ℕ) := ℕ → Site d
abbrev State (d : ℕ) := Environment d × Site d

def StrictEllipticity {d : ℕ} (μ : Measure (Row d)) : Prop :=
  ∀ᵐ p ∂μ, ∀ e, 0 < p.val e

noncomputable def environmentLaw {d : ℕ} (μ : Measure (Row d))
    [IsProbabilityMeasure μ] : Measure (Environment d) :=
  Measure.infinitePi (fun _ => μ)

noncomputable def transition (d : ℕ) : Kernel (State d) (State d) where
  toFun s := ∑ e : Step d,
    ENNReal.ofReal ((s.1 s.2).val e) • Measure.dirac (s.1, s.2 + stepVector e)
  measurable' := by
    apply measurable_from_prod_countable_left
    intro x
    apply Finset.measurable_sum
    intro e he
    apply Measure.measurable_of_measurable_coe
    intro t ht
    simp only [Measure.smul_apply, smul_eq_mul]
    apply Measurable.mul
    · exact (measurable_pi_apply e |>.comp
        (measurable_subtype_coe.comp (measurable_pi_apply x))).ennreal_ofReal
    · exact (Measure.measurable_coe ht).comp
        (Measure.measurable_dirac.comp (measurable_id.prodMk measurable_const))

instance (d : ℕ) : IsMarkovKernel (transition d) where
  isProbabilityMeasure s := by
    constructor
    change (∑ e : Step d,
      ENNReal.ofReal ((s.1 s.2).val e) •
        Measure.dirac (s.1, s.2 + stepVector e)) Set.univ = 1
    simp only [Measure.finsetSum_apply, Measure.smul_apply,
      Measure.dirac_apply_of_mem (Set.mem_univ _), smul_eq_mul, mul_one]
    rw [← ENNReal.ofReal_sum_of_nonneg]
    · rw [(s.1 s.2).property.2, ENNReal.ofReal_one]
    · intro e he
      exact ((s.1 s.2).property.1 e).1

noncomputable def historyKernel (d n : ℕ) :
    Kernel ((i : Finset.Iic n) → State d) (State d) :=
  (transition d).comap (fun h => h ⟨n, Finset.mem_Iic.mpr le_rfl⟩)
    (measurable_pi_apply _)

instance (d n : ℕ) : IsMarkovKernel (historyKernel d n) := by
  unfold historyKernel
  infer_instance

noncomputable def initialLaw {d : ℕ} (μ : Measure (Row d))
    [IsProbabilityMeasure μ] (x : Site d) : Measure (State d) :=
  (environmentLaw μ).map (fun ω => (ω, x))

noncomputable def annealed {d : ℕ} (μ : Measure (Row d))
    [IsProbabilityMeasure μ] (x : Site d) : Measure (Path d) :=
  (Kernel.trajMeasure (X := fun _ => State d) (initialLaw μ x) (historyKernel d)).map
    (fun z n => (z n).2)

def escape {d : ℕ} (ℓ : Fin d → ℝ) : Set (Path d) :=
  {X | Tendsto (fun n => ∑ i, (X n i : ℝ) * ℓ i) atTop atTop}

theorem directional_zero_one (d : ℕ) (hd : 3 ≤ d)
    (μ : Measure (Row d)) [IsProbabilityMeasure μ]
    (hell : StrictEllipticity μ) (ℓ : Fin d → ℝ) (hℓ : ℓ ≠ 0) :
    annealed μ 0 (escape ℓ) = 0 ∨ annealed μ 0 (escape ℓ) = 1 := by sorry

end DirectionalZeroOne

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/DirectionalWalk.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.DirectionalZeroOne.directional_zero_one` must keep exactly the statement shown above: same names,
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
