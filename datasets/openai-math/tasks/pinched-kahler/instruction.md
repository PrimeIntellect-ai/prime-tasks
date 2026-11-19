# openai/math challenge `PinchedKahler` (family 359)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 359 of the release, *Negative Kahler curvature without bounded holomorphic coordinates*
(Differential geometry). The family as a whole: Constructs a contractible domain in $\mathbb C^3$ with a complete negatively pinched Kahler metric but no bounded holomorphic coordinates, disproving bounded-domain uniformization in this setting. A higher-dimensional example has sectional curvature at most $-1$ and only constant bounded holomorphic functions; its curvature is not bounded below.

The challenge is `PinchedKahler`, also at `/opt/openai-math/challenges/PinchedKahler.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

open Set Filter Topology
open scoped ContDiff

namespace PinchedHartogs

abbrev Base := EuclideanSpace ℂ (Fin 2)
abbrev Ambient := Base × ℂ
abbrev Target := Fin 3 → ℂ

def ball : Set Base := {z | ‖z‖ < 1}

def hartogs (φ : Base → ℝ) : Set Ambient :=
  {p | p.1 ∈ ball ∧ Real.exp (φ p.1) * ‖p.2‖ ^ 2 < 1}

def noMinorant (φ : Base → ℝ) : Prop :=
  ¬ ∃ (H : Base → ℂ) (C : ℝ), AnalyticOnNhd ℂ H ball ∧
    ∀ z ∈ ball, (H z).re ≤ C + 4 * Real.log (1 / (1 - ‖z‖)) + φ z

def coordVector (j : Fin 3) : Ambient :=
  ![(EuclideanSpace.single 0 1, 0), (EuclideanSpace.single 1 1, 0), (0, 1)] j

def jacobian (F : Ambient → Target) (p : Ambient) : Matrix (Fin 3) (Fin 3) ℂ :=
  fun i j ↦ (fderiv ℂ F p (coordVector j)) i

open scoped Matrix.Norms.Elementwise

abbrev CMatrix := Matrix (Fin 3) (Fin 3) ℂ
abbrev CurvatureTensor := Fin 3 → Fin 3 → Fin 3 → Fin 3 → ℂ

def coordinates (u : Ambient) : Fin 3 → ℂ := ![u.1 0, u.1 1, u.2]

def dz (f : Ambient → ℂ) (p : Ambient) (j : Fin 3) : ℂ :=
  (fderiv ℝ f p (coordVector j) - Complex.I * fderiv ℝ f p (Complex.I • coordVector j)) / 2

def dbar (f : Ambient → ℂ) (p : Ambient) (j : Fin 3) : ℂ :=
  (fderiv ℝ f p (coordVector j) + Complex.I * fderiv ℝ f p (Complex.I • coordVector j)) / 2

def hermitianValue (h : CMatrix) (u v : Ambient) : ℂ :=
  ∑ i, ∑ j, h i j * coordinates u i * star (coordinates v j)

def realArea (h : CMatrix) (u v : Ambient) : ℝ :=
  (hermitianValue h u u).re * (hermitianValue h v v).re - (hermitianValue h u v).re ^ 2

def tensorValue (R : CurvatureTensor) (u v w y : Ambient) : ℂ :=
  ∑ a, ∑ b, ∑ c, ∑ d,
    R a b c d * coordinates u a * star (coordinates v b) * coordinates w c * star (coordinates y d)

def curvature (g : Ambient → CMatrix) (p : Ambient) : CurvatureTensor := fun a b c d ↦
  -dbar (fun q ↦ dz (fun r ↦ g r c d) q a) p b +
    ∑ e, ∑ k, (g p)⁻¹ e k * dz (fun q ↦ g q c e) p a * dbar (fun q ↦ g q k d) p b

def sectional (g : Ambient → CMatrix) (p u v : Ambient) : ℝ :=
  ((tensorValue (curvature g p) u u v v).re - (tensorValue (curvature g p) u v u v).re) /
    (2 * realArea (g p) u v)

def IsKahlerMetric (M : Set Ambient) (g : Ambient → CMatrix) : Prop :=
  ContDiffOn ℝ ∞ g M ∧
  (∀ p ∈ M, ∀ i j, g p i j = star (g p j i)) ∧
  (∀ p ∈ M, ∀ u : Ambient, u ≠ 0 → 0 < (hermitianValue (g p) u u).re) ∧
  (∀ p ∈ M, ∀ i j k, dz (fun q ↦ g q k j) p i = dz (fun q ↦ g q i j) p k)

def christoffel (g : Ambient → CMatrix) (p : Ambient) (k a c : Fin 3) : ℂ :=
  ∑ e, (g p)⁻¹ e k * dz (fun q ↦ g q c e) p a

def GeodesicallyComplete (M : Set Ambient) (g : Ambient → CMatrix) : Prop :=
  ∀ p ∈ M, ∀ v : Ambient, ∃ γ : ℝ → Ambient,
    ContDiff ℝ ∞ γ ∧ (∀ t, γ t ∈ M) ∧ γ 0 = p ∧ deriv γ 0 = v ∧
      ∀ t k, coordinates (deriv (deriv γ) t) k +
        ∑ a, ∑ c, christoffel g (γ t) k a c * coordinates (deriv γ t) a *
          coordinates (deriv γ t) c = 0

def IsNegativelyPinched (M : Set Ambient) (g : Ambient → CMatrix) (A B : ℝ) : Prop :=
  0 < A ∧ A ≤ B ∧ ∀ p ∈ M, ∀ u v : Ambient, LinearIndependent ℝ ![u, v] →
    -B ≤ sectional g p u v ∧ sectional g p u v ≤ -A

def NoBoundedCoordinates (M : Set Ambient) : Prop :=
  ∀ F : Ambient → Target, AnalyticOnNhd ℂ F M →
    (∃ B : ℝ, ∀ p ∈ M, ∀ i, ‖F p i‖ ≤ B) →
      ¬ ∀ p ∈ M, (jacobian F p).det ≠ 0

def BiholomorphicToBoundedDomain (M : Set Ambient) : Prop :=
  ∃ N : Set Ambient, IsOpen N ∧ Bornology.IsBounded N ∧
    ∃ F G : Ambient → Ambient, AnalyticOnNhd ℂ F M ∧ AnalyticOnNhd ℂ G N ∧
      MapsTo F M N ∧ MapsTo G N M ∧ (∀ p ∈ M, G (F p) = p) ∧ (∀ q ∈ N, F (G q) = q)

def MainTheorem : Prop :=
  ∃ (M : Set Ambient) (g : Ambient → CMatrix) (A B : ℝ),
    IsOpen M ∧ M.Nonempty ∧ ContractibleSpace M ∧ IsKahlerMetric M g ∧
      GeodesicallyComplete M g ∧ IsNegativelyPinched M g A B ∧
      NoBoundedCoordinates M ∧ ¬ BiholomorphicToBoundedDomain M

def psi (z : Base) : ℝ := -Real.log (1 - ‖z‖ ^ 2)
def metricPotential (φ : Base → ℝ) (lam : ℝ) (p : Ambient) : ℝ :=
  lam * psi p.1 - Real.log (1 - Real.exp (φ p.1) * ‖p.2‖ ^ 2)

def complexHessian (f : Ambient → ℝ) (p : Ambient) : CMatrix :=
  fun i j ↦ dz (fun q ↦ dbar (fun r ↦ (f r : ℂ)) q j) p i

def hartogsMetric (φ : Base → ℝ) (lam : ℝ) : Ambient → CMatrix :=
  complexHessian (metricPotential φ lam)

def dzBase (f : Base → ℂ) (z : Base) (i : Fin 2) : ℂ :=
  (fderiv ℝ f z (EuclideanSpace.single i 1) -
    Complex.I * fderiv ℝ f z (Complex.I • EuclideanSpace.single i 1)) / 2

def dbarBase (f : Base → ℂ) (z : Base) (i : Fin 2) : ℂ :=
  (fderiv ℝ f z (EuclideanSpace.single i 1) +
    Complex.I * fderiv ℝ f z (Complex.I • EuclideanSpace.single i 1)) / 2

def baseHessian (φ : Base → ℝ) (z : Base) : Matrix (Fin 2) (Fin 2) ℂ :=
  fun i j ↦ dzBase (fun q ↦ dbarBase (fun r ↦ (φ r : ℂ)) q j) z i

def centeredChart (r : ℝ) (U : Base ≃ₗᵢ[ℂ] Base) (ζ : Base) : Base :=
  U (WithLp.toLp 2 ![((r : ℂ) + ζ 0) / (1 + (r : ℂ) * ζ 0),
    ((Real.sqrt (1 - r ^ 2) : ℝ) : ℂ) * ζ 1 / (1 + (r : ℂ) * ζ 0)])

def ChartControl (φ : Base → ℝ) (c C : ℝ) : Prop :=
  ∀ r : ℝ, 0 ≤ r → r < 1 → ∀ U : Base ≃ₗᵢ[ℂ] Base, ∀ v : Base,
    c * ‖v‖ ^ 2 ≤ (∑ i, ∑ j, baseHessian (φ ∘ centeredChart r U) 0 i j * v i * star (v j)).re ∧
    (∑ i, ∑ j, baseHessian (φ ∘ centeredChart r U) 0 i j * v i * star (v j)).re ≤ C * ‖v‖ ^ 2

def ChartJets (φ : Base → ℝ) (C : ℝ) : Prop :=
  ∀ r : ℝ, 0 ≤ r → r < 1 → ∀ U : Base ≃ₗᵢ[ℂ] Base, ∀ i j k l : Fin 2,
    ‖dzBase (fun z ↦ baseHessian (φ ∘ centeredChart r U) z i j) 0 k‖ +
    ‖dbarBase (fun z ↦ baseHessian (φ ∘ centeredChart r U) z i j) 0 l‖ +
    ‖dzBase (fun z ↦ dbarBase (fun q ↦ baseHessian (φ ∘ centeredChart r U) q i j) z l) 0 k‖ ≤ C

def ControlledPotential : Prop :=
  ∃ φ : Base → ℝ, ∃ C : ℝ, ContDiffOn ℝ ∞ φ ball ∧
    ChartControl φ 1 C ∧ ChartJets φ C ∧ noMinorant φ

def MetricTransfer : Prop :=
  ∀ c C : ℝ, 0 < c → c ≤ C → ∃ lam0 : ℝ, 0 < lam0 ∧
    ∀ φ : Base → ℝ, ContDiffOn ℝ ∞ φ ball → ChartControl φ c C → ChartJets φ C →
      ∀ lam : ℝ, lam0 ≤ lam → ContractibleSpace (hartogs φ) ∧
        IsKahlerMetric (hartogs φ) (hartogsMetric φ lam) ∧
        GeodesicallyComplete (hartogs φ) (hartogsMetric φ lam) ∧
        ∃ A B : ℝ, IsNegativelyPinched (hartogs φ) (hartogsMetric φ lam) A B

theorem main_theorem : MainTheorem := by
  sorry

theorem controlled_potential : ControlledPotential := by
  sorry

theorem metric_transfer : MetricTransfer := by
  sorry

end PinchedHartogs

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/PinchedKahler.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorems `OAI.PinchedHartogs.main_theorem`, `OAI.PinchedHartogs.controlled_potential`, `OAI.PinchedHartogs.metric_transfer` must keep exactly the statement shown above: same names,
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
