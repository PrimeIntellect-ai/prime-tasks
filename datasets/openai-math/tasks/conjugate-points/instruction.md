# openai/math challenge `ConjugatePoints` (family 358)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 358 of the release, *A three-manifold with no conjugate points and no nonpositively curved metric*
(Differential geometry). The family as a whole: Constructs a closed connected orientable smooth three-manifold that admits a metric without conjugate points but no metric of nonpositive sectional curvature. This answers negatively, already in dimension three, whether the first metric-existence property implies the second.

The challenge is `ConjugatePoints`, also at `/opt/openai-math/challenges/ConjugatePoints.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open Set Manifold Bundle
open scoped ContDiff

namespace ThreeManifold

abbrev E3 := Fin 3 → ℝ
abbrev I3 := 𝓘(ℝ, E3)

variable {M : Type} [TopologicalSpace M] [ChartedSpace E3 M]

def OrientedAtlas : Prop :=
  ∀ (c d : OpenPartialHomeomorph M E3), c ∈ atlas E3 M → d ∈ atlas E3 M →
    ∀ x ∈ c.target, c.symm x ∈ d.source →
      0 < LinearMap.det (fderiv ℝ (d ∘ c.symm) x).toLinearMap

variable [IsManifold I3 ∞ M]

abbrev SmoothMetric (M : Type) [TopologicalSpace M] [ChartedSpace E3 M]
    [IsManifold I3 ∞ M] :=
  ContMDiffRiemannianMetric I3 ∞ E3 (fun x : M => TangentSpace I3 x)

def basisVector (i : Fin 3) : E3 := Pi.single i 1

def metricMatrix (g : SmoothMetric M) (c : OpenPartialHomeomorph M E3) (x : E3) :
    Matrix (Fin 3) (Fin 3) ℝ :=
  fun i j => g.inner (c.symm x)
    (mfderiv I3 I3 c.symm x (basisVector i))
    (mfderiv I3 I3 c.symm x (basisVector j))

def coordPartial (f : E3 → ℝ) (x : E3) (i : Fin 3) : ℝ :=
  fderiv ℝ f x (basisVector i)

def christoffel (g : SmoothMetric M) (c : OpenPartialHomeomorph M E3)
    (x : E3) (i j k : Fin 3) : ℝ :=
  (1 / 2 : ℝ) * ∑ l : Fin 3, (metricMatrix g c x)⁻¹ i l *
    (coordPartial (fun y => metricMatrix g c y l k) x j +
     coordPartial (fun y => metricMatrix g c y l j) x k -
     coordPartial (fun y => metricMatrix g c y j k) x l)

def connectionTerm (g : SmoothMetric M) (c : OpenPartialHomeomorph M E3)
    (x u v : E3) : E3 :=
  fun i => ∑ j : Fin 3, ∑ k : Fin 3, christoffel g c x i j k * u j * v k

def curvatureCoefficient (g : SmoothMetric M) (c : OpenPartialHomeomorph M E3)
    (x : E3) (l k i j : Fin 3) : ℝ :=
  coordPartial (fun y => christoffel g c y l j k) x i -
  coordPartial (fun y => christoffel g c y l i k) x j +
    ∑ a : Fin 3, (christoffel g c x l i a * christoffel g c x a j k -
      christoffel g c x l j a * christoffel g c x a i k)

def curvatureTerm (g : SmoothMetric M) (c : OpenPartialHomeomorph M E3)
    (x u v w : E3) : E3 :=
  fun l => ∑ k : Fin 3, ∑ i : Fin 3, ∑ j : Fin 3,
    curvatureCoefficient g c x l k i j * w k * u i * v j

def NonpositiveSectionalCurvature (g : SmoothMetric M) : Prop :=
  ∀ (c : OpenPartialHomeomorph M E3), c ∈ atlas E3 M →
    ∀ x ∈ c.target, ∀ u v : E3,
      (∑ i : Fin 3, ∑ j : Fin 3,
        metricMatrix g c x i j * curvatureTerm g c x u v v i * u j) ≤ 0

def alongDerivative (g : SmoothMetric M) (c : OpenPartialHomeomorph M E3)
    (x w : ℝ → E3) (s : ℝ) : E3 :=
  deriv w s + connectionTerm g c (x s) (deriv x s) (w s)

def IsGeodesicOn (g : SmoothMetric M) (γ : ℝ → M) (U : Set ℝ) : Prop :=
  ContMDiffOn 𝓘(ℝ, ℝ) I3 ∞ γ U ∧
    ∀ (c : OpenPartialHomeomorph M E3), c ∈ atlas E3 M →
      ∀ s ∈ U, γ s ∈ c.source →
        alongDerivative g c (c ∘ γ) (deriv (c ∘ γ)) s = 0

def fieldCoordinates (γ : ℝ → M) (J : ∀ s, TangentSpace I3 (γ s))
    (c : OpenPartialHomeomorph M E3) (s : ℝ) : E3 :=
  mfderiv I3 I3 c (γ s) (J s)

def IsJacobiFieldOn (g : SmoothMetric M) (γ : ℝ → M)
    (J : ∀ s, TangentSpace I3 (γ s)) (U : Set ℝ) : Prop :=
  ∀ (c : OpenPartialHomeomorph M E3), c ∈ atlas E3 M →
    ContDiffOn ℝ ∞ (fieldCoordinates γ J c) (U ∩ γ ⁻¹' c.source) ∧
    ∀ s ∈ U, γ s ∈ c.source →
      alongDerivative g c (c ∘ γ)
        (alongDerivative g c (c ∘ γ) (fieldCoordinates γ J c)) s +
      curvatureTerm g c (c (γ s)) (fieldCoordinates γ J c s)
        (deriv (c ∘ γ) s) (deriv (c ∘ γ) s) = 0

def NoConjugatePoints (g : SmoothMetric M) : Prop :=
  ∀ (U : Set ℝ), IsOpen U → OrdConnected U →
    ∀ (γ : ℝ → M), IsGeodesicOn g γ U →
      ∀ (J : ∀ s, TangentSpace I3 (γ s)), IsJacobiFieldOn g γ J U →
        ∀ a ∈ U, ∀ b ∈ U, a ≠ b → J a = 0 → J b = 0 → ∀ s ∈ U, J s = 0

def MainStatement : Prop :=
  ∃ (M : Type) (top : TopologicalSpace M),
    letI := top
    ∃ (_ : T2Space M) (_ : SecondCountableTopology M) (_ : CompactSpace M)
      (_ : ConnectedSpace M) (charts : ChartedSpace E3 M),
      letI := charts
      ∃ (smooth : IsManifold I3 ∞ M),
        letI := smooth
        OrientedAtlas (M := M) ∧
          (∃ g : SmoothMetric M, NoConjugatePoints g) ∧
          ¬ ∃ g : SmoothMetric M, NonpositiveSectionalCurvature g

theorem main_theorem : MainStatement := by
  sorry

end ThreeManifold

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/ConjugatePoints.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.ThreeManifold.main_theorem` must keep exactly the statement shown above: same names,
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
