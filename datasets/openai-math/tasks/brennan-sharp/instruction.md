# openai/math challenge `BrennanSharp` (family 072)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 072 of the release, *Brennan's conjecture and a counterexample to Kraetzer's prediction*
(Real and complex analysis). The family as a whole: Proves Brennan's conjecture: for every conformal bijection $\phi$ from a simply connected plane domain onto the disk, $|\phi'|^s$ is area-integrable for $4/3<s<4$. The sharp universal integral-means identity is $B_{\mathcal S}(t)=|t|-1$ for $t\le-2$. A strict bound $B_b(-1)<1/4$ for bounded univalent functions disproves Kraetzer's prediction at that parameter.

The challenge is `BrennanSharp`, also at `/opt/openai-math/challenges/BrennanSharp.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open Set MeasureTheory Filter
open scoped Topology ENNReal
namespace Brennan

def disk : Set ℂ := Metric.ball 0 1

def UnivalentOn (f : ℂ → ℂ) (U : Set ℂ) : Prop :=
  DifferentiableOn ℂ f U ∧ Set.InjOn f U

def Schlicht (f : ℂ → ℂ) : Prop :=
  UnivalentOn f disk ∧ f 0 = 0 ∧ deriv f 0 = 1

def koebeMap (z : ℂ) : ℂ := z/(1-z)^2

namespace Sharp

def koebeDomain : Set ℂ := koebeMap '' disk

def koebeInverse : ℂ → ℂ := Function.invFunOn koebeMap disk

def areaMoment (f : ℂ → ℂ) (U : Set ℂ) (t : ℝ) : ℝ≥0∞ :=
  ∫⁻ z in U, ENNReal.ofReal (‖deriv f z‖ ^ t) ∂volume

def SharpEndpointStatement : Prop :=
  Schlicht koebeMap ∧
  areaMoment koebeMap disk (-2) = ⊤ ∧
  areaMoment koebeMap disk (2 / 3) = ⊤ ∧
  ¬ IntegrableOn (fun z => ‖deriv koebeInverse z‖ ^ (4 : ℝ)) koebeDomain volume ∧
  ¬ IntegrableOn (fun z => ‖deriv koebeInverse z‖ ^ (4 / 3 : ℝ)) koebeDomain volume

theorem sharp_endpoints : SharpEndpointStatement := by
  sorry

end Sharp
end Brennan

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/BrennanSharp.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Brennan.Sharp.sharp_endpoints` must keep exactly the statement shown above: same names,
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
