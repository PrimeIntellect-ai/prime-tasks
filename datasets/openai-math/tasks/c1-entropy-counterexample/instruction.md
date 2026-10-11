# openai/math challenge `C1EntropyCounterexample` (family 151)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 151 of the release, *A $C^1$ counterexample to Shub’s entropy conjecture*
(Dynamical systems and ergodic theory). The family as a whole: Constructs a noninvertible $C^1$ self-map of a compact smooth manifold with zero topological entropy but eigenvalue $2$ on second homology. This disproves the homological entropy lower bound for general $C^1$ self-maps: homological growth need not force positive orbit complexity.

The challenge is `C1EntropyCounterexample`, also at `/opt/openai-math/challenges/C1EntropyCounterexample.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

open CategoryTheory

namespace Problem340

abbrev ClockAmbient := EuclideanSpace ℝ (Fin 2)

abbrev SphereAmbient := EuclideanSpace ℝ (Fin 3)

abbrev StandardClock := Metric.sphere (0 : ClockAmbient) (1 : ℝ)

abbrev StandardSphere2 := Metric.sphere (0 : SphereAmbient) (1 : ℝ)

abbrev CounterexampleManifold (q : ℕ) :=
  StandardClock × (Fin (q + 1) → StandardSphere2)

abbrev CounterexampleAmbient (q : ℕ) :=
  ClockAmbient × (Fin (q + 1) → SphereAmbient)

def standardEmbedding (q : ℕ) :
    CounterexampleManifold q → CounterexampleAmbient q :=
  fun x => (x.1.1, fun i => (x.2 i).1)

def IsC1SelfMap (q : ℕ) (f : CounterexampleManifold q → CounterexampleManifold q) : Prop :=
  Continuous f ∧
    ∀ x : CounterexampleManifold q,
      ∃ U : Set (CounterexampleAmbient q),
        IsOpen U ∧ standardEmbedding q x ∈ U ∧
          ∃ F : CounterexampleAmbient q → CounterexampleAmbient q,
            ContDiffOn ℝ 1 F U ∧
              ∀ y : CounterexampleManifold q,
                standardEmbedding q y ∈ U →
                  standardEmbedding q (f y) = F (standardEmbedding q y)

def continuousMapOf {X Y : Type} [TopologicalSpace X] [TopologicalSpace Y]
    (f : X → Y) (hf : Continuous f) : ContinuousMap X Y :=
  ⟨f, hf⟩

abbrev RealSingularHomology (n : ℕ) (X : Type) [TopologicalSpace X] :=
  (((AlgebraicTopology.singularHomologyFunctor (ModuleCat ℝ) n).obj
    (ModuleCat.of ℝ ℝ)).obj (TopCat.of X))

def realHomologyMap {X Y : Type} [TopologicalSpace X] [TopologicalSpace Y]
    (n : ℕ) (f : X → Y) (hf : Continuous f) :
    RealSingularHomology n X →ₗ[ℝ] RealSingularHomology n Y :=
  (((AlgebraicTopology.singularHomologyFunctor (ModuleCat ℝ) n).obj
    (ModuleCat.of ℝ ℝ)).map
      (TopCat.ofHom (continuousMapOf f hf))).hom

def totalRealHomologySpectralRadius {X : Type} [TopologicalSpace X]
    (f : X → X) (hf : Continuous f) : ℝ :=
  sSup {r : ℝ |
    ∃ n : ℕ, ∃ a b : ℝ,
      ∃ u v : RealSingularHomology n X,
        (u ≠ 0 ∨ v ≠ 0) ∧
        realHomologyMap n f hf u = a • u - b • v ∧
        realHomologyMap n f hf v = b • u + a • v ∧
        r = Real.sqrt (a ^ 2 + b ^ 2)}

theorem exists_C1_entropy_counterexample :
    ∃ q : ℕ, 0 < q ∧ ∃ f : CounterexampleManifold q → CounterexampleManifold q, ∃ hf : IsC1SelfMap q f, Dynamics.coverEntropy f (Set.univ : Set (CounterexampleManifold q)) = (0 : EReal) ∧ (∃ v : RealSingularHomology 2 (CounterexampleManifold q), v ≠ 0 ∧ realHomologyMap 2 f hf.1 v = (2 : ℝ) • v) ∧ 0 < Real.log (2 : ℝ) ∧ Real.log (2 : ℝ) ≤ Real.log (totalRealHomologySpectralRadius f hf.1) ∧ ¬ Function.Bijective f ∧ 5 ≤ 2 * q + 3 := by
  sorry

end Problem340

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/C1EntropyCounterexample.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Problem340.exists_C1_entropy_counterexample` must keep exactly the statement shown above: same names,
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
