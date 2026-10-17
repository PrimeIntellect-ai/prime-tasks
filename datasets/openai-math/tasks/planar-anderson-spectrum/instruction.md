# openai/math challenge `PlanarAndersonSpectrum` (family 261)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 261 of the release, *Localization and delocalization in the Anderson model*
(Mathematical physics). The family as a whole: Resolves the predicted spectral contrast for the lattice Anderson model with independent uniform site potentials. In dimension two, every positive disorder strength gives almost surely pure-point spectrum. In every fixed dimension $d\ge3$, sufficiently weak positive disorder gives purely absolutely continuous spectrum on a fixed open interval with nonzero spectral weight.

The challenge is `PlanarAndersonSpectrum`, also at `/opt/openai-math/challenges/PlanarAndersonSpectrum.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open MeasureTheory
open scoped ENNReal

namespace PlanarAnderson

abbrev Site := ℤ × ℤ
abbrev Configuration := Site → ℝ
abbrev Hilbert := lp (fun _ : Site => ℂ) 2

def disorderLaw (h : ℝ) : Measure Configuration :=
  Measure.infinitePi (fun _ : Site => ProbabilityTheory.cond volume (Set.Icc (-h) h))

def IsAndersonOperator (v : Configuration) (H : Hilbert →L[ℂ] Hilbert) : Prop :=
  ∀ (u : Hilbert) (x : Site),
    (H u) x = u (x.1 + 1, x.2) + u (x.1 - 1, x.2) +
      u (x.1, x.2 + 1) + u (x.1, x.2 - 1) + (v x : ℂ) * u x

def spectralInterval (h : ℝ) : Set ℂ :=
  {z | z.im = 0 ∧ -4 - h ≤ z.re ∧ z.re ≤ 4 + h}

theorem anderson_spectrum_ae {h : ℝ} (hh : 0 < h) :
    ∀ᵐ v ∂disorderLaw h, ∃ H : Hilbert →L[ℂ] Hilbert,
      IsAndersonOperator v H ∧ IsSelfAdjoint H ∧ spectrum ℂ H = spectralInterval h := by
  sorry

end PlanarAnderson

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/PlanarAndersonSpectrum.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.PlanarAnderson.anderson_spectrum_ae` must keep exactly the statement shown above: same names,
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
