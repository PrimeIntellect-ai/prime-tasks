# openai/math challenge `DixmierAllDiscrete` (family 251)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 251 of the release, *Amenability, unitarizability, and Ulam stability*
(Group theory). The family as a whole: Resolves Dixmier's problem for all discrete groups: amenability is equivalent to every uniformly bounded Hilbert-space representation being similar to a unitary representation. For countable discrete groups, amenability is also equivalent to strong Ulam stability: sufficiently accurate unitary approximate representations are uniformly close in operator norm to genuine representations on the same, possibly infinite-dimensional, Hilbert space.

The challenge is `DixmierAllDiscrete`, also at `/opt/openai-math/challenges/DixmierAllDiscrete.lean`:

```lean
import Mathlib.Analysis.InnerProductSpace.LinearMap
import Mathlib.Topology.ContinuousMap.Bounded.Normed
import Mathlib.Topology.Instances.Discrete

namespace OAI

noncomputable section
universe u v
namespace Dixmier
open scoped BoundedContinuousFunction

def leftTranslate {G : Type u} [Group G] [TopologicalSpace G]
    [DiscreteTopology G] (g : G) (f : G →ᵇ ℂ) : G →ᵇ ℂ :=
  f.compContinuous ⟨fun x => g⁻¹ * x, continuous_of_discreteTopology⟩

def Amenable (G : Type u) [Group G] [TopologicalSpace G]
    [DiscreteTopology G] : Prop :=
  ∃ m : (G →ᵇ ℂ) →ₗ[ℂ] ℂ,
    m (BoundedContinuousFunction.const G 1) = 1 ∧
    (∀ f : G →ᵇ ℂ, (∀ x, 0 ≤ (f x).re ∧ (f x).im = 0) →
      0 ≤ (m f).re ∧ (m f).im = 0) ∧
    ∀ (g : G) (f : G →ᵇ ℂ), m (leftTranslate g f) = m f

def SimilarToUnitary {G : Type u} [Group G]
    {H : Type v} [NormedAddCommGroup H] [InnerProductSpace ℂ H]
    (π : G →* (H →L[ℂ] H)) : Prop :=
  ∃ S : H ≃L[ℂ] H, ∀ (g : G) (x : H), ‖S (π g (S.symm x))‖ = ‖x‖

def Unitarizable (G : Type u) [Group G] : Prop :=
  ∀ (H : Type v) [NormedAddCommGroup H] [InnerProductSpace ℂ H]
    [CompleteSpace H] (π : G →* (H →L[ℂ] H)),
    (∃ C : ℝ, ∀ g, ‖π g‖ ≤ C) → SimilarToUnitary π

def CurrentMainTheorem : Prop :=
  ∀ (G : Type u) [Group G] [TopologicalSpace G] [DiscreteTopology G],
    (Amenable G ↔ Unitarizable.{u, max u v} G) ∧
    ∀ (ε : ℝ), 0 < ε → ¬ Amenable G →
      ∃ (H : Type (max u v)) (_ : NormedAddCommGroup H) (_ : InnerProductSpace ℂ H)
        (_ : CompleteSpace H) (π : G →* (H →L[ℂ] H)),
        (Countable G → TopologicalSpace.SeparableSpace H) ∧
        (∀ g, ‖π g‖ ≤ 1 + ε) ∧ ¬ SimilarToUnitary π

theorem current_main_theorem : CurrentMainTheorem.{u,v} := by
  sorry

end Dixmier
end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/DixmierAllDiscrete.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Dixmier.current_main_theorem` must keep exactly the statement shown above: same names,
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
