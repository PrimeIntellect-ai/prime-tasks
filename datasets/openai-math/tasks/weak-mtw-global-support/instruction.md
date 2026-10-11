# openai/math challenge `WeakMTWGlobalSupport` (family 360)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 360 of the release, *Villani’s convexity conjecture and regular optimal transport*
(Differential geometry). The family as a whole: On every closed connected Riemannian manifold of dimension at least two satisfying weak Ma–Trudinger–Wang curvature, all tangent injectivity domains are convex, resolving Villani’s conjecture in this setting. For squared-distance transport between measurable probability densities bounded above and away from zero, the optimal map and its inverse are Holder continuous.

The challenge is `WeakMTWGlobalSupport`, also at `/opt/openai-math/challenges/WeakMTWGlobalSupport.lean`:

```lean
import Mathlib

namespace OAI

namespace WeakMTWGlobalSupport

open scoped Manifold ContDiff Topology
open Set Filter Manifold Bundle

namespace WeakMTW

noncomputable section

abbrev Model (n : ℕ) := EuclideanSpace ℝ (Fin n)
abbrev model (n : ℕ) := 𝓘(ℝ, Model n)

variable {n : ℕ} {M : Type*} [MetricSpace M] [ChartedSpace (Model n) M]
  [IsManifold (model n) ∞ M]
  [RiemannianBundle (fun x : M => TangentSpace (model n) x)]
  [IsContMDiffRiemannianBundle (model n) ∞ (Model n)
    (fun x : M => TangentSpace (model n) x)]
  [IsRiemannianManifold (model n) M]

def CompleteGeodesicWithInitialData (x : M) (v : TangentSpace (model n) x)
    (γ : ℝ → M) : Prop :=
  ContMDiff 𝓘(ℝ, ℝ) (model n) ∞ γ ∧
  ∃ h : γ 0 = x,
    (h ▸ mfderiv 𝓘(ℝ, ℝ) (model n) γ 0 (1 : ℝ)) = v ∧
    ∀ t : ℝ, ∃ ε : ℝ, 0 < ε ∧
      ∀ s ∈ Metric.ball t ε, ∀ r ∈ Metric.ball t ε,
        dist (γ s) (γ r) = ‖v‖ * |s - r|

def ExpEndpoint (x : M) (v : TangentSpace (model n) x) (y : M) : Prop :=
  ∃ γ : ℝ → M, CompleteGeodesicWithInitialData x v γ ∧ γ 1 = y

noncomputable def exp (x : M) (v : TangentSpace (model n) x) : M :=
  by
    classical
    exact if h : ∃ y, ExpEndpoint x v y then Classical.choose h else x

def injectivityDomain (x : M) : Set (TangentSpace (model n) x) :=
  {v | ∃ a : ℝ, 1 < a ∧ dist x (exp x (a • v)) = a * ‖v‖}

def cost (x y : M) : ℝ := dist x y ^ 2 / 2

noncomputable def mtw (x : M) (v ξ η : TangentSpace (model n) x) : ℝ :=
  -(3 / 2 : ℝ) * deriv (fun s : ℝ =>
    deriv (fun s' : ℝ => deriv (fun t : ℝ =>
      deriv (fun t' : ℝ => cost (exp x (t' • ξ)) (exp x (v + s' • η))) t) 0) s) 0

def HasWeakMTW : Prop :=
  ∀ (x : M) (v : TangentSpace (model n) x), v ∈ injectivityDomain x →
    ∀ ξ η : TangentSpace (model n) x, inner ℝ ξ η = 0 → 0 ≤ mtw x v ξ η

def MainConvexity : Prop :=
  ∀ x : M, Convex ℝ (injectivityDomain (n := n) x)

end

end WeakMTW

/-- Weak MTW implies linear convexity of every open tangent injectivity domain. -/
theorem current_main_convexity
    {n : ℕ} (hn : 2 ≤ n) {M : Type*}
    [MetricSpace M] [ChartedSpace (WeakMTW.Model n) M]
    [IsManifold (WeakMTW.model n) ∞ M]
    [CompactSpace M] [ConnectedSpace M]
    [RiemannianBundle (fun x : M => TangentSpace (WeakMTW.model n) x)]
    [IsContMDiffRiemannianBundle (WeakMTW.model n) ∞ (WeakMTW.Model n)
      (fun x : M => TangentSpace (WeakMTW.model n) x)]
    [IsRiemannianManifold (WeakMTW.model n) M]
    (hmtw : WeakMTW.HasWeakMTW (n := n) (M := M)) :
    WeakMTW.MainConvexity (n := n) (M := M) :=
  by
    sorry

end WeakMTWGlobalSupport

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/WeakMTWGlobalSupport.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.WeakMTWGlobalSupport.current_main_convexity` must keep exactly the statement shown above: same names,
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
