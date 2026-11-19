# openai/math challenge `LipschitzHilbert` (family 083)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 083 of the release, *Stein's conjecture for Hilbert transforms along Lipschitz directions*
(Real and complex analysis). The family as a whole: Proves a uniform strong $L^2$ bound for the planar Hilbert transform along any Lipschitz unit vector field, at integration lengths bounded by an absolute multiple of its reciprocal Lipschitz constant. The estimate is uniform over inner truncations and yields an $L^2$-bounded principal-value operator, establishing Stein's weak-type conjecture at this short scale.

The challenge is `LipschitzHilbert`, also at `/opt/openai-math/challenges/LipschitzHilbert.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

/- Use the normed-field structure on ℂ for real scalar multiplication. -/
attribute [-instance] instCommCStarAlgebraComplex

open MeasureTheory Set
open scoped ENNReal NNReal

namespace LipschitzHilbert

abbrev Plane := EuclideanSpace ℝ (Fin 2)
abbrev DirectionPlane := EuclideanSpace ℝ (Fin 2)

def sample (v : DirectionPlane → DirectionPlane) (t : ℝ) (x : DirectionPlane) :
    DirectionPlane := x - t • v x

/-- The symmetrized form of the hard-truncated directional integral. -/
def shortTransform (v : DirectionPlane → DirectionPlane) (ε a : ℝ)
    (f : DirectionPlane → ℂ) (x : DirectionPlane) : ℂ :=
  ∫ t in ε..a, t⁻¹ • (f (sample v t x) - f (sample v (-t) x))

def directionalKernel (v : DirectionPlane → DirectionPlane)
    (f : DirectionPlane → ℂ) (x : DirectionPlane) (t : ℝ) : ℂ :=
  t⁻¹ • f (sample v t x)

/-- The two hard-cutoff intervals in the directional Hilbert transform. -/
def twoSidedTruncation (v : DirectionPlane → DirectionPlane) (ε a : ℝ)
    (f : DirectionPlane → ℂ) (x : DirectionPlane) : ℂ :=
  (∫ t in -a..-ε, directionalKernel v f x t) +
    ∫ t in ε..a, directionalKernel v f x t

/-- The symmetric quotient extended continuously at zero for smooth inputs. -/
def smoothPrincipalValue (v : DirectionPlane → DirectionPlane) (a : ℝ)
    (f : DirectionPlane → ℂ) (x : DirectionPlane) : ℂ :=
  let g := fun t : ℝ => f (sample v t x)-f (sample v (-t) x)
  ∫ t in (0:ℝ)..a, Function.update (fun t => t⁻¹ • g t) 0 (deriv g 0) t

attribute [instance] instCommCStarAlgebraComplex

def ShortHilbertConclusion (a : ℝ) (C : ℝ≥0) : Prop :=
  ∀ v : Plane → Plane, LipschitzWith 1 v → (∀ x, ‖v x‖=1) →
    (∀ epsilon : ℝ, 0<epsilon → epsilon<a → ∀ f : SchwartzMap Plane ℂ,
      eLpNorm (twoSidedTruncation v epsilon a f) 2 volume≤C*eLpNorm f 2 volume) ∧
    (∀ f : SchwartzMap Plane ℂ,
      eLpNorm (smoothPrincipalValue v a f) 2 volume≤C*eLpNorm f 2 volume) ∧
    (∀ f : SchwartzMap Plane ℂ, ∀ level : ℝ≥0∞, level≠0 → level≠∞ →
      volume {x | level<‖smoothPrincipalValue v a f x‖ₑ}≤
        level⁻¹^2*((C:ℝ≥0∞)*eLpNorm f 2 volume)^2) ∧
    (∀ epsilon : ℝ, 0<epsilon → epsilon<a →
      ∃ T : Lp ℂ 2 (volume : Measure Plane) →L[ℂ] Lp ℂ 2 volume,
        ‖T‖≤C ∧ ∀ f : SchwartzMap Plane ℂ,
          (T (f.toLp 2 volume) : Plane → ℂ)=ᵐ[volume] twoSidedTruncation v epsilon a f) ∧
    (∃ T : Lp ℂ 2 (volume : Measure Plane) →L[ℂ] Lp ℂ 2 volume,
      ‖T‖≤C ∧ ∀ f : SchwartzMap Plane ℂ,
        (T (f.toLp 2 volume) : Plane → ℂ)=ᵐ[volume] smoothPrincipalValue v a f)

/-- Uniform hard truncation, principal-value and weak-(2,2) estimates,
with bounded L² extensions for all Lipschitz unit vector fields. -/
theorem main :
    ∃ a : ℝ, a∈Ioo 0 (1/2) ∧ ∃ C : ℝ≥0, 0<C ∧ ShortHilbertConclusion a C := by
  sorry

/-- The same uniform estimate at the reciprocal-Lipschitz truncation scale. -/
theorem uniform_truncation :
    ∃ C : ℝ, 0<C ∧ ∀ K : ℝ≥0, 0<K → ∀ epsilon R : ℝ,
      0<epsilon → epsilon≤R → R≤1/(1000000*(K:ℝ)) →
      ∀ v : Plane → Plane, LipschitzWith K v → (∀ x, ‖v x‖=1) →
      ∀ f : SchwartzMap Plane ℂ,
        eLpNorm (shortTransform v epsilon R f) 2 volume≤ENNReal.ofReal (C*‖f.toLp 2 volume‖) := by
  sorry

end LipschitzHilbert

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/LipschitzHilbert.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorems `OAI.LipschitzHilbert.main`, `OAI.LipschitzHilbert.uniform_truncation` must keep exactly the statement shown above: same names,
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
